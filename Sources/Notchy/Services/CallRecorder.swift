import AppKit
import AVFoundation
import Combine
import CoreMedia
import ScreenCaptureKit

/// A call recording saved on this Mac. Audio only: the microphone and Teams.
struct CallRecording: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let createdAt: Date
    let duration: TimeInterval
}

enum CallApps {
    static func isTeams(bundleIdentifier: String?, name: String?) -> Bool {
        let bundle = bundleIdentifier?.lowercased() ?? ""
        if bundle.hasPrefix("com.microsoft.teams") { return true }
        return name?.lowercased() == "microsoft teams"
    }
}

enum CallAudioMix {
    /// Sums the two tracks and keeps every sample inside -1...1.
    static func mix(mic: [Float], remote: [Float], gain: Float = 0.9) -> [Float] {
        let count = max(mic.count, remote.count)
        var out = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let left = index < mic.count ? mic[index] : 0
            let right = index < remote.count ? remote[index] : 0
            let mixed = left * gain + right * gain
            out[index] = min(1, max(-1, mixed))
        }
        return out
    }
}

enum CallRecordError: LocalizedError {
    case teamsNotFound
    case noDisplay
    case noInput
    case noAudio
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .teamsNotFound: return "Open the Teams app on this Mac first."
        case .noDisplay: return "No display is available to capture Teams audio."
        case .noInput: return "No microphone is available."
        case .noAudio: return "Nothing was captured. Check Microphone and Screen Recording, then try again."
        case .exportFailed: return "The recording could not be saved."
        }
    }
}

/// Records a Teams call the user is on: microphone plus Teams' own audio, saved as an audio file.
/// ScreenCaptureKit is what macOS allows for another app's audio, so the system recording indicator stays on.
/// Video frames are discarded.
@MainActor
final class CallRecorder: ObservableObject {
    enum Phase: Equatable { case idle, preparing, recording, saving }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var teamsRunning = false
    @Published private(set) var recordings: [CallRecording] = []
    @Published private(set) var lastError: String?
    @Published private(set) var permissionHint: PermissionsCenter.Kind?
    @Published private(set) var playingURL: URL?

    var onBegan: (() -> Void)?
    var onSaved: (() -> Void)?

    var isRecording: Bool { phase == .recording }
    var elapsedText: String { Self.format(elapsed) }

    private var capture: CallCapture?
    private var audioEngine: AVAudioEngine?
    private var clock: Timer?
    private var startedAt: Date?
    private var player: AVAudioPlayer?
    private let playback = PlaybackBox()
    private var cancellables = Set<AnyCancellable>()

    init() {
        playback.onFinish = { [weak self] in self?.playingURL = nil }
        sweepPartials()
        reload()
        refreshPresence()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPresence() }
            .store(in: &cancellables)
    }

    func refreshPresence() {
        let running = NSWorkspace.shared.runningApplications.contains { app in
            CallApps.isTeams(bundleIdentifier: app.bundleIdentifier, name: app.localizedName)
        }
        if running != teamsRunning { teamsRunning = running }
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Store.callsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        recordings = urls
            .filter { ["m4a", "caf"].contains($0.pathExtension.lowercased()) }
            .compactMap { url in
                guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                let duration = Double(file.length) / file.processingFormat.sampleRate
                return CallRecording(url: url, createdAt: created, duration: duration)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func toggle() async {
        if phase == .recording {
            await stop()
        } else if phase == .idle {
            await start()
        }
    }

    func start() async {
        guard phase == .idle else { return }
        lastError = nil
        permissionHint = nil
        refreshPresence()
        guard teamsRunning else {
            lastError = CallRecordError.teamsNotFound.localizedDescription
            return
        }
        guard await Self.microphoneAllowed() else {
            lastError = "Allow Microphone for HappyNotch in System Settings › Privacy & Security."
            permissionHint = .microphone
            return
        }
        if !CGPreflightScreenCaptureAccess() {
            guard CGRequestScreenCaptureAccess() else {
                lastError = "Allow Screen Recording for HappyNotch in System Settings › Privacy & Security. If you just allowed it, quit HappyNotch and open it again."
                permissionHint = .screenRecording
                return
            }
        }

        phase = .preparing
        let session = CallCapture(directory: Store.callsDirectory)
        capture = session
        session.onInterrupted = { [weak self] message in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.lastError = message
                await self.stop()
            }
        }
        do {
            try startMicrophone(into: session)
            try await session.start()
            startedAt = Date()
            elapsed = 0
            phase = .recording
            startClock()
            onBegan?()
        } catch {
            await abandon(session)
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .idle
        }
    }

    func stop() async {
        guard phase == .recording || phase == .preparing, let session = capture else { return }
        phase = .saving
        stopClock()
        let started = startedAt ?? Date()
        stopMicrophone()
        await session.finish()
        capture = nil
        let heardTeams = session.heardRemoteAudio()
        do {
            _ = try await session.export(started: started)
            session.deletePartial()
            reload()
            onSaved?()
            if !heardTeams {
                lastError = "Saved your microphone only. Teams audio did not come through. If Screen Recording was just allowed, quit HappyNotch and open it again."
            }
        } catch {
            session.deletePartial()
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        phase = .idle
        startedAt = nil
        elapsed = 0
    }

    /// Saves an in-progress recording during quit. Safe to call when nothing is recording.
    func stopForQuit() {
        guard phase == .recording || phase == .preparing, let session = capture else { return }
        phase = .saving
        stopClock()
        let started = startedAt ?? Date()
        stopMicrophone()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            await session.finish()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        let group = DispatchSemaphore(value: 0)
        Task.detached {
            if let _ = try? await session.export(started: started) {
                session.deletePartial()
            }
            group.signal()
        }
        _ = group.wait(timeout: .now() + 20)
        phase = .idle
    }

    func togglePlayback(_ recording: CallRecording) {
        if playingURL == recording.url {
            player?.stop()
            playingURL = nil
            return
        }
        player?.stop()
        guard let next = try? AVAudioPlayer(contentsOf: recording.url) else { return }
        next.delegate = playback
        next.play()
        player = next
        playingURL = recording.url
    }

    func reveal(_ recording: CallRecording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
    }

    func delete(_ recording: CallRecording) {
        if playingURL == recording.url {
            player?.stop()
            playingURL = nil
        }
        try? FileManager.default.removeItem(at: recording.url)
        reload()
    }

    nonisolated static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func startMicrophone(into session: CallCapture) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CallRecordError.noInput }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            session.appendMicrophone(buffer)
        }
        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    private func stopMicrophone() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private func abandon(_ session: CallCapture) async {
        stopMicrophone()
        await session.finish()
        session.deletePartial()
        capture = nil
    }

    private func startClock() {
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    private func sweepPartials() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Store.callsDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.lastPathComponent.hasPrefix(".") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        default:
            return false
        }
    }
}

private final class PlaybackBox: NSObject, AVAudioPlayerDelegate {
    var onFinish: () -> Void = {}
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

/// Holds the capture stream and the two temporary tracks. Not tied to the main actor.
private final class CallCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let partial: URL
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
    private let micRing = PCMRing(capacity: 48_000 * 2 * 30)
    private let remoteRing = PCMRing(capacity: 48_000 * 2 * 30)
    private let micPump: FormatPump
    private let remotePump: FormatPump
    private let sampleQueue = DispatchQueue(label: "app.notchy.call.samples")
    private let ioQueue = DispatchQueue(label: "app.notchy.call.io")
    private var micFile: AVAudioFile?
    private var remoteFile: AVAudioFile?
    private var stream: SCStream?
    private var drain: DispatchSourceTimer?
    private let stateLock = NSLock()
    private var intentionalStop = false

    var onInterrupted: ((String) -> Void)?
    private var micURL: URL { partial.appendingPathComponent("mic.caf") }
    private var remoteURL: URL { partial.appendingPathComponent("remote.caf") }

    init(directory: URL) {
        partial = directory.appendingPathComponent(".partial-\(UUID().uuidString)", isDirectory: true)
        micPump = FormatPump(target: target)
        remotePump = FormatPump(target: target)
        super.init()
    }

    func start() async throws {
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        let writing = target
        try ioQueue.sync {
            micFile = try AVAudioFile(forWriting: micURL, settings: writing.settings, commonFormat: writing.commonFormat, interleaved: writing.isInterleaved)
            remoteFile = try AVAudioFile(forWriting: remoteURL, settings: writing.settings, commonFormat: writing.commonFormat, interleaved: writing.isInterleaved)
        }
        startDraining()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let apps = content.applications.filter {
            CallApps.isTeams(bundleIdentifier: $0.bundleIdentifier, name: $0.applicationName)
        }
        guard !apps.isEmpty else { throw CallRecordError.teamsNotFound }
        let teamsWindows = content.windows.filter { window in
            guard let owner = window.owningApplication else { return false }
            return CallApps.isTeams(bundleIdentifier: owner.bundleIdentifier, name: owner.applicationName)
        }
        guard let display = content.displays.first(where: { display in
            teamsWindows.contains { $0.frame.intersects(display.frame) }
        }) ?? content.displays.first else { throw CallRecordError.noDisplay }

        let filter = SCContentFilter(display: display, including: apps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.queueDepth = 8

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func appendMicrophone(_ buffer: AVAudioPCMBuffer) {
        let samples = micPump.convert(buffer)
        guard !samples.isEmpty else { return }
        micRing.write(samples)
    }

    func finish() async {
        markStopping()
        drain?.cancel()
        drain = nil
        try? await stream?.stopCapture()
        stream = nil
        await withCheckedContinuation { continuation in
            ioQueue.async {
                self.drainRings()
                self.micFile = nil
                self.remoteFile = nil
                continuation.resume()
            }
        }
    }

    func export(started: Date) async throws -> URL {
        try await CallAudioFiles.export(mic: micURL, remote: remoteURL, into: partial.deletingLastPathComponent(), started: started)
    }

    func deletePartial() {
        try? FileManager.default.removeItem(at: partial)
    }

    func heardRemoteAudio() -> Bool {
        guard let file = try? AVAudioFile(forReading: remoteURL) else { return false }
        return file.length > 0
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(sampleBuffer),
              let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        let samples = remotePump.convert(buffer)
        guard !samples.isEmpty else { return }
        remoteRing.write(samples)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        stateLock.lock()
        let ignored = intentionalStop
        let handler = onInterrupted
        stateLock.unlock()
        guard !ignored else { return }
        handler?(error.localizedDescription)
    }

    private func markStopping() {
        stateLock.lock()
        intentionalStop = true
        stateLock.unlock()
    }

    private func startDraining() {
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + .milliseconds(40), repeating: .milliseconds(40))
        timer.setEventHandler { [weak self] in self?.drainRings() }
        timer.resume()
        drain = timer
    }

    private func drainRings() {
        write(micRing.read(max: 48_000), to: &micFile)
        write(remoteRing.read(max: 48_000), to: &remoteFile)
    }

    private func write(_ samples: [Float], to file: inout AVAudioFile?) {
        let frames = AVAudioFrameCount(samples.count / 2)
        guard frames > 0, let file, let buffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return }
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            channels[0][index] = samples[index * 2]
            channels[1][index] = samples[index * 2 + 1]
        }
        try? file.write(from: buffer)
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return nil }
        var streamDescription = basic.pointee
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}

private final class FormatPump: @unchecked Sendable {
    let target: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceKey: String?

    init(target: AVAudioFormat) {
        self.target = target
    }

    func convert(_ input: AVAudioPCMBuffer) -> [Float] {
        guard input.frameLength > 0 else { return [] }
        if input.format.commonFormat == target.commonFormat,
           input.format.sampleRate == target.sampleRate,
           input.format.channelCount == target.channelCount,
           input.format.isInterleaved == false {
            return Self.interleaved(input)
        }
        let key = "\(input.format.sampleRate)-\(input.format.channelCount)-\(input.format.commonFormat.rawValue)-\(input.format.isInterleaved)"
        if sourceKey != key {
            sourceKey = key
            converter = AVAudioConverter(from: input.format, to: target)
        }
        guard let converter else { return Self.interleaved(input) }
        let ratio = target.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: max(capacity, 1)) else { return [] }
        var error: NSError?
        var consumed = false
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil else { return [] }
        return Self.interleaved(output)
    }

    private static func interleaved(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channels = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return [] }
        var output = [Float](repeating: 0, count: frames * 2)
        if channelCount == 1 {
            for index in 0..<frames {
                output[index * 2] = channels[0][index]
                output[index * 2 + 1] = channels[0][index]
            }
        } else {
            for index in 0..<frames {
                output[index * 2] = channels[0][index]
                output[index * 2 + 1] = channels[min(1, channelCount - 1)][index]
            }
        }
        return output
    }
}

private final class PCMRing: @unchecked Sendable {
    private let capacity: Int
    private var storage: [Float]
    private var readIndex = 0
    private var writeIndex = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = max(4, capacity)
        storage = [Float](repeating: 0, count: self.capacity)
    }

    func write(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        for sample in samples {
            let next = (writeIndex + 1) % capacity
            if next == readIndex {
                readIndex = (readIndex + 2) % capacity
            }
            storage[writeIndex] = sample
            writeIndex = next
        }
    }

    func read(max: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        var available = writeIndex >= readIndex ? writeIndex - readIndex : capacity - readIndex + writeIndex
        available -= available % 2
        let count = min(max - (max % 2), available)
        var output: [Float] = []
        output.reserveCapacity(count)
        for _ in 0..<count {
            output.append(storage[readIndex])
            readIndex = (readIndex + 1) % capacity
        }
        return output
    }
}

enum CallAudioFiles {
    static func export(mic: URL, remote: URL, into directory: URL, started: Date) async throws -> URL {
        let micFrames = frameCount(mic)
        let remoteFrames = frameCount(remote)
        guard micFrames > 0 || remoteFrames > 0 else { throw CallRecordError.noAudio }

        let mixed = directory.appendingPathComponent(".mix-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: mixed) }
        if micFrames > 0, remoteFrames > 0 {
            try mix(mic: mic, remote: remote, to: mixed)
        } else {
            try FileManager.default.copyItem(at: micFrames > 0 ? mic : remote, to: mixed)
        }

        let output = directory.appendingPathComponent(fileName(started: started))
        do {
            try await encodeM4A(mixed, to: output)
            return output
        } catch {
            let fallback = output.deletingPathExtension().appendingPathExtension("caf")
            try FileManager.default.copyItem(at: mixed, to: fallback)
            return fallback
        }
    }

    static func fileName(started: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Call \(formatter.string(from: started)).m4a"
    }

    private static func frameCount(_ url: URL) -> AVAudioFramePosition {
        guard FileManager.default.fileExists(atPath: url.path), let file = try? AVAudioFile(forReading: url) else { return 0 }
        return file.length
    }

    private static func mix(mic: URL, remote: URL, to output: URL) throws {
        let micFile = try AVAudioFile(forReading: mic)
        let remoteFile = try AVAudioFile(forReading: remote)
        let format = micFile.processingFormat
        let out = try AVAudioFile(forWriting: output, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        let capacity: AVAudioFrameCount = 4096
        while true {
            guard let micBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity),
                  let remoteBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { break }
            read(micFile, into: micBuffer)
            read(remoteFile, into: remoteBuffer)
            let frames = max(micBuffer.frameLength, remoteBuffer.frameLength)
            if frames == 0 { break }
            guard let mixed = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let micChannels = micBuffer.floatChannelData,
                  let remoteChannels = remoteBuffer.floatChannelData,
                  let outChannels = mixed.floatChannelData else { break }
            mixed.frameLength = frames
            let micCount = Int(micBuffer.frameLength)
            let remoteCount = Int(remoteBuffer.frameLength)
            let channels = Int(format.channelCount)
            for channel in 0..<channels {
                var micSamples = [Float](repeating: 0, count: Int(frames))
                var remoteSamples = [Float](repeating: 0, count: Int(frames))
                for index in 0..<micCount { micSamples[index] = micChannels[channel][index] }
                for index in 0..<remoteCount { remoteSamples[index] = remoteChannels[channel][index] }
                let summed = CallAudioMix.mix(mic: micSamples, remote: remoteSamples)
                for index in 0..<Int(frames) { outChannels[channel][index] = summed[index] }
            }
            try out.write(from: mixed)
        }
    }

    private static func read(_ file: AVAudioFile, into buffer: AVAudioPCMBuffer) {
        do {
            try file.read(into: buffer)
        } catch {
            buffer.frameLength = 0
        }
    }

    private static func encodeM4A(_ source: URL, to output: URL) async throws {
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CallRecordError.exportFailed
        }
        session.outputURL = output
        session.outputFileType = .m4a
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                if session.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: session.error ?? CallRecordError.exportFailed)
                }
            }
        }
    }
}
