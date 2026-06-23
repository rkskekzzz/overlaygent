import XCTest
@testable import Overlaygent

final class KnownAppCatalogTests: XCTestCase {
    func testDefaultCatalogDefinesStableKnownApps() {
        let catalog = KnownAppCatalog.defaultCatalog

        XCTAssertEqual(catalog.definitions.map(\.appID), [
            .slack,
            .channelTalk,
            .discord,
            .notion,
            .vsCode
        ])
        XCTAssertEqual(catalog.primaryBundleID(for: .slack), "com.tinyspeck.slackmacgap")
        XCTAssertEqual(catalog.primaryBundleID(for: .channelTalk), "com.zoyi.channel.desk.osx")
        XCTAssertEqual(catalog.primaryBundleID(for: .discord), "com.hnc.Discord")
        XCTAssertEqual(catalog.primaryBundleID(for: .notion), "notion.id")
        XCTAssertEqual(catalog.primaryBundleID(for: .vsCode), "com.microsoft.VSCode")
    }

    func testDefaultCatalogHasUniqueNormalizedBundleIDs() {
        let bundleKeys = KnownAppCatalog.defaultCatalog.definitions
            .flatMap(\.bundleIDs)
            .map(BundleIdentifier.lookupKey)

        XCTAssertFalse(bundleKeys.contains(""))
        XCTAssertEqual(bundleKeys.count, Set(bundleKeys).count)
    }

    func testCompatibilityRegistryMirrorsCatalogProfiles() {
        let catalog = KnownAppCatalog.defaultCatalog
        let registry = AppCompatibilityRegistry.defaultRegistry

        XCTAssertEqual(registry.knownApps, catalog.compatibilityProfiles)
    }

    func testElectronAllowlistMirrorsCatalog() {
        let expectedBundleIDs = Set(
            KnownAppCatalog.defaultCatalog.definitions
                .filter { $0.capabilities.electronAXEnableRequired }
                .flatMap(\.bundleIDs)
        )
        let actualBundleIDs = Set(KnownElectronApp.supportedApps.flatMap(\.bundleIDs))

        XCTAssertEqual(actualBundleIDs, expectedBundleIDs)
    }

    func testDefaultContextAdaptersCoverCatalogVisibleContextApps() {
        let expectedBundleIDs = KnownAppCatalog.defaultCatalog.visibleContextBundleIDs
        let actualBundleIDs = Set(
            AppContextAdapterRegistry.defaultAdapters.flatMap { adapter in
                adapter.supportedBundleIDs
            }
        )

        XCTAssertEqual(actualBundleIDs, expectedBundleIDs)
    }

    func testCatalogSourceDoesNotDependOnConcreteContextAdapters() throws {
        let sourceURL = packageRoot
            .appendingPathComponent("Sources/Overlaygent/Compatibility/KnownAppCatalog.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertFalse(source.contains("SlackContextAdapter"))
        XCTAssertFalse(source.contains("ChannelTalkContextAdapter"))
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
