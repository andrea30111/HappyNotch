import XCTest
@testable import Notchy

final class CallRecorderTests: XCTestCase {
    func testTeamsBundleMatchesMicrosoftTeamsOnly() {
        XCTAssertTrue(CallApps.isTeams(bundleIdentifier: "com.microsoft.teams2", name: "Microsoft Teams"))
        XCTAssertTrue(CallApps.isTeams(bundleIdentifier: "com.microsoft.teams", name: nil))
        XCTAssertTrue(CallApps.isTeams(bundleIdentifier: nil, name: "Microsoft Teams"))
        XCTAssertFalse(CallApps.isTeams(bundleIdentifier: "com.apple.MobileSMS", name: "Messages"))
        XCTAssertFalse(CallApps.isTeams(bundleIdentifier: "com.example.teamsviewer", name: "Teams Viewer"))
    }

    func testMixSumsTracksAndClamps() {
        let summed = CallAudioMix.mix(mic: [0.5, 0], remote: [0, 0.5])
        XCTAssertEqual(summed.count, 2)
        XCTAssertEqual(summed[0], 0.45, accuracy: 0.0001)
        XCTAssertEqual(summed[1], 0.45, accuracy: 0.0001)

        let clipped = CallAudioMix.mix(mic: [1, -1], remote: [1, -1])
        XCTAssertEqual(clipped, [1, -1])

        let longer = CallAudioMix.mix(mic: [0.2], remote: [])
        XCTAssertEqual(longer.count, 1)
        XCTAssertEqual(longer[0], 0.18, accuracy: 0.0001)
    }

    func testElapsedFormat() {
        XCTAssertEqual(CallRecorder.format(0), "0:00")
        XCTAssertEqual(CallRecorder.format(65), "1:05")
        XCTAssertEqual(CallRecorder.format(3661), "1:01:01")
    }
}
