import AVFoundation
import Speech

/// On-device dictation. Server-based recognition is only used if the user opts in.
@MainActor
final class SpeechService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var owner: String?
    @Published var lastError: String?

    var onAuthorizationPrompt: ((Bool) -> Void)?

    private let store: Store
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var handler: ((String, Bool) -> Void)?
    private var silenceTimer: Timer?
    private var recognizer: SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    init(store: Store) {
        self.store = store
    }

    var supportsOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    func isActive(owner: String) -> Bool { isRecording && self.owner == owner }

    /// Starts dictation for `owner`, or stops it if that owner is already recording.
    /// `onText` receives the running transcript and whether it is final.
    func toggle(owner: String, onText: @escaping (String, Bool) -> Void) {
        if isRecording {
            let wasOwner = self.owner == owner
            stop()
            if wasOwner { return }
        }
        onAuthorizationPrompt?(true)
        authorize { [weak self] granted in
            guard let self else { return }
            self.onAuthorizationPrompt?(false)
            guard granted else {
                self.lastError = "Allow Microphone and Speech Recognition for HappyNotch in System Settings › Privacy & Security."
                return
            }
            self.begin(owner: owner, onText: onText)
        }
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isRecording = false
        owner = nil
    }

    private func authorize(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    private func begin(owner: String, onText: @escaping (String, Bool) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            lastError = "Speech recognition isn't available right now."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else if !store.settings.allowServerSpeechRecognition {
            lastError = "On-device recognition isn't available for \(recognizer.locale.identifier). You can allow Apple's server recognition in Settings › Voice."
            return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            lastError = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }

        self.request = request
        self.handler = onText
        self.owner = owner
        isRecording = true
        lastError = nil
        armSilenceTimer(seconds: 6)

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                guard let self else { return }
                if let text { self.handler?(text, isFinal) }
                if isFinal || error != nil {
                    self.stop()
                } else if text != nil {
                    self.armSilenceTimer(seconds: 2.2)
                }
            }
        }
    }

    private func armSilenceTimer(seconds: TimeInterval) {
        silenceTimer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        RunLoop.main.add(timer, forMode: .common)
        silenceTimer = timer
    }
}
