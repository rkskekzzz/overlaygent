import Foundation
import XCTest
@testable import Overlaygent

final class FocusedApplicationAccessibilityPreparerTests: XCTestCase {
    func testPreparerEnablesKnownFocusedElectronAppByPIDWithoutLoggingSuccess() {
        let application = FocusedApplicationSnapshot(
            bundleID: "com.tinyspeck.slackmacgap",
            processIdentifier: 1122
        )
        let applicationProvider = FakeFocusedApplicationProvider(application: application)
        let electronEnabler = RecordingElectronAccessibilityEnabler(
            result: .enabled(
                KnownElectronApp(displayName: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"])
            )
        )
        var logs: [String] = []
        var sleepDurations: [TimeInterval] = []
        let preparer = FocusedApplicationAccessibilityPreparer(
            applicationProvider: applicationProvider,
            electronEnabler: electronEnabler,
            logger: { logs.append($0) },
            postEnableDelay: 0.15,
            sleeper: { sleepDurations.append($0) }
        )

        preparer.prepareFocusedApplication()

        XCTAssertEqual(
            electronEnabler.targets,
            [
                ElectronAccessibilityTarget(
                    bundleID: "com.tinyspeck.slackmacgap",
                    processIdentifier: 1122
                )
            ]
        )
        XCTAssertEqual(logs, [])
        XCTAssertEqual(sleepDurations, [0.15])
    }

    func testPreparerDoesNothingWhenNoFocusedApplicationIsAvailable() {
        let applicationProvider = FakeFocusedApplicationProvider(application: nil)
        let electronEnabler = RecordingElectronAccessibilityEnabler(
            result: .skippedUnknownBundleID("com.example.Unknown")
        )
        var logs: [String] = []
        let preparer = FocusedApplicationAccessibilityPreparer(
            applicationProvider: applicationProvider,
            electronEnabler: electronEnabler,
            logger: { logs.append($0) },
            sleeper: { _ in XCTFail("Unknown apps should not sleep after preparation.") }
        )

        preparer.prepareFocusedApplication()

        XCTAssertEqual(electronEnabler.targets, [])
        XCTAssertEqual(logs, [])
    }

    func testPreparerLogsKnownElectronFailureWithoutBundleIDOrDisplayName() {
        let application = FocusedApplicationSnapshot(
            bundleID: "com.secret.InternalElectron",
            processIdentifier: 3344
        )
        let applicationProvider = FakeFocusedApplicationProvider(application: application)
        let electronEnabler = RecordingElectronAccessibilityEnabler(
            result: .failed(
                KnownElectronApp(displayName: "Secret Internal", bundleIDs: ["com.secret.InternalElectron"]),
                .setAttributeFailed(
                    attribute: ElectronAccessibilityEnabler.manualAccessibilityAttribute,
                    code: -25205
                )
            )
        )
        var logs: [String] = []
        let preparer = FocusedApplicationAccessibilityPreparer(
            applicationProvider: applicationProvider,
            electronEnabler: electronEnabler,
            logger: { logs.append($0) },
            sleeper: { _ in XCTFail("Failed preparation should not sleep.") }
        )

        preparer.prepareFocusedApplication()

        XCTAssertEqual(electronEnabler.targets.count, 1)
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs[0].contains("Electron accessibility preparation failed"))
        XCTAssertFalse(logs[0].contains("com.secret.InternalElectron"))
        XCTAssertFalse(logs[0].contains("Secret Internal"))
    }

    func testPreparerDoesNotLogUnknownApplications() {
        let application = FocusedApplicationSnapshot(
            bundleID: "com.example.Unknown",
            processIdentifier: 5566
        )
        let applicationProvider = FakeFocusedApplicationProvider(application: application)
        let electronEnabler = RecordingElectronAccessibilityEnabler(
            result: .skippedUnknownBundleID("com.example.Unknown")
        )
        var logs: [String] = []
        let preparer = FocusedApplicationAccessibilityPreparer(
            applicationProvider: applicationProvider,
            electronEnabler: electronEnabler,
            logger: { logs.append($0) },
            sleeper: { _ in XCTFail("Unknown apps should not sleep after preparation.") }
        )

        preparer.prepareFocusedApplication()

        XCTAssertEqual(electronEnabler.targets.count, 1)
        XCTAssertEqual(logs, [])
    }
}

private final class FakeFocusedApplicationProvider: FocusedApplicationProviding {
    private let application: FocusedApplicationSnapshot?

    init(application: FocusedApplicationSnapshot?) {
        self.application = application
    }

    func focusedApplication() -> FocusedApplicationSnapshot? {
        application
    }
}

private final class RecordingElectronAccessibilityEnabler: ElectronAccessibilityEnabling {
    private let result: ElectronAccessibilityEnableResult
    private(set) var targets: [ElectronAccessibilityTarget] = []

    init(result: ElectronAccessibilityEnableResult) {
        self.result = result
    }

    func enableIfNeeded(for target: ElectronAccessibilityTarget) -> ElectronAccessibilityEnableResult {
        targets.append(target)
        return result
    }
}
