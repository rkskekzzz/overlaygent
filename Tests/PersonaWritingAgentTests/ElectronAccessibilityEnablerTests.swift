import Foundation
import XCTest
@testable import PersonaWritingAgent

final class ElectronAccessibilityEnablerTests: XCTestCase {
    func testSupportedAppsDetectRequiredBundleIDs() {
        let enabler = ElectronAccessibilityEnabler(writer: FakeAXManualAccessibilityWriter())

        XCTAssertEqual(enabler.knownElectronApp(bundleID: "com.tinyspeck.slackmacgap")?.displayName, "Slack")
        XCTAssertEqual(enabler.knownElectronApp(bundleID: "com.zoyi.channel.desk.osx")?.displayName, "ChannelTalk")
        XCTAssertEqual(enabler.knownElectronApp(bundleID: "com.hnc.Discord")?.displayName, "Discord")
        XCTAssertEqual(enabler.knownElectronApp(bundleID: "notion.id")?.displayName, "Notion Desktop")
        XCTAssertEqual(enabler.knownElectronApp(bundleID: " COM.MICROSOFT.VSCODE ")?.displayName, "VS Code")
    }

    func testEnableSetsManualAccessibilityOnProvidedApplicationElementForKnownBundle() {
        let writer = FakeAXManualAccessibilityWriter()
        let applicationElement = AXElement(FakeAXNode())
        let enabler = ElectronAccessibilityEnabler(writer: writer)

        let result = enabler.enableIfNeeded(
            bundleID: "com.tinyspeck.slackmacgap",
            processIdentifier: 1122,
            applicationElement: applicationElement
        )

        XCTAssertEqual(
            result,
            .enabled(KnownElectronApp(displayName: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"]))
        )
        XCTAssertEqual(writer.createdProcessIDs, [])
        XCTAssertEqual(writer.setRequests, [FakeAXManualAccessibilityWriter.SetRequest(enabled: true, element: applicationElement)])
    }

    func testEnableCreatesApplicationElementFromPIDWhenNoElementIsProvided() {
        let writer = FakeAXManualAccessibilityWriter()
        let createdElement = AXElement(FakeAXNode())
        writer.applicationElement = createdElement
        let enabler = ElectronAccessibilityEnabler(writer: writer)

        let result = enabler.enableIfNeeded(
            bundleID: "com.microsoft.VSCode",
            processIdentifier: 3344
        )

        XCTAssertEqual(
            result,
            .enabled(KnownElectronApp(displayName: "VS Code", bundleIDs: ["com.microsoft.VSCode"]))
        )
        XCTAssertEqual(writer.createdProcessIDs, [3344])
        XCTAssertEqual(writer.setRequests, [FakeAXManualAccessibilityWriter.SetRequest(enabled: true, element: createdElement)])
    }

    func testUnknownBundleIDSkipsWithoutAXWrite() {
        let writer = FakeAXManualAccessibilityWriter()
        let enabler = ElectronAccessibilityEnabler(writer: writer)

        let result = enabler.enableIfNeeded(
            bundleID: "com.apple.Safari",
            processIdentifier: 5566
        )

        XCTAssertEqual(result, .skippedUnknownBundleID("com.apple.Safari"))
        XCTAssertEqual(writer.createdProcessIDs, [])
        XCTAssertEqual(writer.setRequests, [])
    }

    func testKnownBundleWithoutPIDOrAppElementFailsWithoutAXWrite() {
        let writer = FakeAXManualAccessibilityWriter()
        let enabler = ElectronAccessibilityEnabler(writer: writer)

        let result = enabler.enableIfNeeded(bundleID: "com.hnc.Discord")

        XCTAssertEqual(
            result,
            .failed(
                KnownElectronApp(displayName: "Discord", bundleIDs: ["com.hnc.Discord"]),
                .missingApplicationReference
            )
        )
        XCTAssertEqual(writer.createdProcessIDs, [])
        XCTAssertEqual(writer.setRequests, [])
    }

    func testAXWriterFailureIsReturnedForKnownBundle() {
        let writer = FakeAXManualAccessibilityWriter()
        writer.setResult = .failure(
            .setAttributeFailed(
                attribute: ElectronAccessibilityEnabler.manualAccessibilityAttribute,
                code: -25205
            )
        )
        let enabler = ElectronAccessibilityEnabler(writer: writer)

        let result = enabler.enableIfNeeded(
            bundleID: "notion.id",
            processIdentifier: 7788
        )

        XCTAssertEqual(
            result,
            .failed(
                KnownElectronApp(displayName: "Notion Desktop", bundleIDs: ["notion.id"]),
                .setAttributeFailed(
                    attribute: ElectronAccessibilityEnabler.manualAccessibilityAttribute,
                    code: -25205
                )
            )
        )
        XCTAssertEqual(writer.createdProcessIDs, [7788])
        XCTAssertEqual(writer.setRequests.count, 1)
    }
}

private final class FakeAXNode: NSObject {}

private final class FakeAXManualAccessibilityWriter: AXManualAccessibilityWriting {
    struct SetRequest: Equatable {
        var enabled: Bool
        var element: AXElement
    }

    var applicationElement = AXElement(FakeAXNode())
    var setResult: Result<Void, ElectronAccessibilityEnablerError> = .success(())
    private(set) var createdProcessIDs: [pid_t] = []
    private(set) var setRequests: [SetRequest] = []

    func applicationElement(for processIdentifier: pid_t) -> AXElement {
        createdProcessIDs.append(processIdentifier)
        return applicationElement
    }

    func setManualAccessibility(
        _ enabled: Bool,
        on element: AXElement
    ) -> Result<Void, ElectronAccessibilityEnablerError> {
        setRequests.append(SetRequest(enabled: enabled, element: element))
        return setResult
    }
}
