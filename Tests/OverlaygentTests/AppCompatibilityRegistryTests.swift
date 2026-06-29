import XCTest
@testable import Overlaygent

final class AppCompatibilityRegistryTests: XCTestCase {
    func testDefaultRegistryIncludesKnownBundleIDs() throws {
        let registry = AppCompatibilityRegistry.defaultRegistry

        XCTAssertEqual(try registry.profileName(forBundleID: "com.tinyspeck.slackmacgap"), "Slack")
        XCTAssertEqual(try registry.profileName(forBundleID: " com.zoyi.channel.desk.osx "), "ChannelTalk")
        XCTAssertEqual(try registry.profileName(forBundleID: "com.hnc.Discord"), "Discord")
        XCTAssertEqual(try registry.profileName(forBundleID: "notion.id"), "Notion Desktop")
        XCTAssertEqual(try registry.profileName(forBundleID: " COM.MICROSOFT.VSCODE "), "VS Code")
        XCTAssertEqual(try registry.profileName(forBundleID: "com.openai.codex"), "Codex")
        XCTAssertNil(registry.profile(forBundleID: "com.apple.TextEdit"))
    }

    func testDefaultRegistryKeepsAdapterCapabilityFlags() throws {
        let registry = AppCompatibilityRegistry.defaultRegistry
        let slack = try XCTUnwrap(registry.profile(forBundleID: SlackContextAdapter.slackBundleID))
        let channelTalk = try XCTUnwrap(registry.profile(forBundleID: ChannelTalkContextAdapter.bundleID))
        let discord = try XCTUnwrap(registry.profile(forBundleID: "com.hnc.Discord"))
        let notion = try XCTUnwrap(registry.profile(forBundleID: "notion.id"))
        let vsCode = try XCTUnwrap(registry.profile(forBundleID: "com.microsoft.VSCode"))
        let codex = try XCTUnwrap(registry.profile(forBundleID: "com.openai.codex"))

        XCTAssertEqual(slack.capabilities.visibleContextAdapterSupport, .supported)
        XCTAssertEqual(channelTalk.capabilities.visibleContextAdapterSupport, .supported)
        XCTAssertEqual(discord.capabilities.visibleContextAdapterSupport, .unsupported)
        XCTAssertEqual(notion.capabilities.visibleContextAdapterSupport, .unsupported)
        XCTAssertEqual(vsCode.capabilities.visibleContextAdapterSupport, .unsupported)
        XCTAssertEqual(codex.capabilities.visibleContextAdapterSupport, .unsupported)

        XCTAssertEqual(slack.capabilities.focusedInputRead, .supported)
        XCTAssertEqual(slack.capabilities.selectedRangeRead, .supported)
        XCTAssertEqual(slack.capabilities.boundsRead, .limited)
        XCTAssertEqual(slack.capabilities.directApply, .limited)
        XCTAssertEqual(slack.capabilities.pasteFallback, .supported)
        XCTAssertTrue(slack.capabilities.electronAXEnableRequired)
    }

    func testElectronAllowlistMirrorsCompatibilityRegistry() {
        let expectedBundleIDs = Set(
            KnownAppCatalog.defaultCatalog.definitions
                .filter(\.capabilities.electronAXEnableRequired)
                .flatMap(\.bundleIDs)
        )
        let actualBundleIDs = Set(KnownElectronApp.supportedApps.flatMap(\.bundleIDs))

        XCTAssertEqual(actualBundleIDs, expectedBundleIDs)
    }

    func testDiagnosticsSummaryRendersRedactedSafeText() {
        let summary = AppCompatibilityRegistry.defaultRegistry.diagnosticsSummary()
        let safeText = summary.safeDiagnosticsText

        XCTAssertEqual(summary.knownAppCount, 6)
        XCTAssertEqual(summary.visibleContextAdapterCount, 2)
        XCTAssertTrue(safeText.contains("Slack [com.tinyspeck.slackmacgap]"))
        XCTAssertTrue(safeText.contains("Codex [com.openai.codex]"))
        XCTAssertTrue(safeText.contains("visible_context_adapter_support=supported"))
        XCTAssertTrue(safeText.contains("electron_ax_enable_required=required"))
        XCTAssertFalse(safeText.contains("Can we deploy it after review?"))
        XCTAssertFalse(safeText.contains("sk-proj"))
        XCTAssertFalse(safeText.localizedCaseInsensitiveContains("password"))
    }

    func testDiagnosticsViewModelBuildsRegistrySummary() {
        let viewModel = DiagnosticsViewModel(registry: .defaultRegistry)

        XCTAssertEqual(viewModel.registrySummaryText, "6 known apps - 2 visible context adapters")
        XCTAssertEqual(viewModel.summary.rows.map(\.displayName), [
            "Slack",
            "ChannelTalk",
            "Discord",
            "Notion Desktop",
            "VS Code",
            "Codex"
        ])
    }
}

private extension AppCompatibilityRegistry {
    func profileName(forBundleID bundleID: String) throws -> String {
        try XCTUnwrap(profile(forBundleID: bundleID)).displayName
    }
}
