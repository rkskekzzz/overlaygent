import Foundation
import XCTest
@testable import PersonaWritingAgent

final class PermissionCoordinatorTests: XCTestCase {
    func testAccessibilityStatusUsesNonPromptingAXOptions() {
        let checker = FakeAccessibilityTrustChecker(result: false)
        let coordinator = PermissionCoordinator(trustChecker: checker)

        let state = coordinator.accessibilityStatus()

        XCTAssertEqual(state.status, .notTrusted)
        XCTAssertFalse(state.isTrusted)
        XCTAssertTrue(state.requiresUserAction)
        XCTAssertFalse(state.promptWasRequested)
        XCTAssertEqual(checker.recordedOptions, [AccessibilityPermissionPromptOptions(promptUser: false)])
    }

    func testRequestAccessibilityPermissionPromptUsesPromptingAXOptions() {
        let checker = FakeAccessibilityTrustChecker(result: true)
        let coordinator = PermissionCoordinator(trustChecker: checker)

        let state = coordinator.requestAccessibilityPermissionPrompt()

        XCTAssertEqual(state.status, .trusted)
        XCTAssertTrue(state.isTrusted)
        XCTAssertFalse(state.requiresUserAction)
        XCTAssertTrue(state.promptWasRequested)
        XCTAssertEqual(checker.recordedOptions, [AccessibilityPermissionPromptOptions(promptUser: true)])
    }

    func testPromptOptionsBuildAXTrustedCheckDictionary() {
        let options = AccessibilityPermissionPromptOptions(promptUser: true)

        XCTAssertEqual(options.dictionaryRepresentation[AccessibilityPermissionPromptOptions.promptKey], true)

        let cfDictionary = options.cfDictionary as NSDictionary
        XCTAssertEqual(cfDictionary[AccessibilityPermissionPromptOptions.promptKey] as? Bool, true)
    }

    func testAccessibilitySettingsDestinationUsesPrivacyAccessibilityPane() {
        let destination = AccessibilitySettingsDestination()

        XCTAssertEqual(
            destination.url.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        XCTAssertEqual(destination.paneName, "Privacy & Security")
        XCTAssertEqual(destination.sectionName, "Accessibility")
    }

    func testOpenAccessibilitySettingsUsesConfiguredURL() {
        let checker = FakeAccessibilityTrustChecker(result: false)
        let opener = FakeSettingsOpener(result: true)
        let url = URL(string: "x-apple.systempreferences:com.example.test?Privacy_Accessibility")!
        let destination = AccessibilitySettingsDestination(url: url)
        let coordinator = PermissionCoordinator(
            trustChecker: checker,
            settingsOpener: opener,
            settingsDestination: destination
        )

        XCTAssertTrue(coordinator.openAccessibilitySettings())
        XCTAssertEqual(opener.openedURLs, [url])
    }

    func testAccessibilityPermissionStateCodableRoundTrip() throws {
        let state = AccessibilityPermissionState(
            status: .notTrusted,
            settingsURL: AccessibilitySettingsDestination.accessibilityURL,
            promptWasRequested: false
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AccessibilityPermissionState.self, from: data)

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.diagnosticsDescription, "Accessibility permission missing")
    }
}

private final class FakeAccessibilityTrustChecker: AccessibilityTrustChecking {
    private let result: Bool
    private(set) var recordedOptions: [AccessibilityPermissionPromptOptions] = []

    init(result: Bool) {
        self.result = result
    }

    func isProcessTrusted(options: AccessibilityPermissionPromptOptions) -> Bool {
        recordedOptions.append(options)
        return result
    }
}

private final class FakeSettingsOpener: SettingsOpening {
    private let result: Bool
    private(set) var openedURLs: [URL] = []

    init(result: Bool) {
        self.result = result
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return result
    }
}
