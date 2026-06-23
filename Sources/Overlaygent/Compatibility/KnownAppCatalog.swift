import Foundation

enum KnownAppID: String, CaseIterable, Equatable {
    case slack
    case channelTalk = "channeltalk"
    case discord
    case notion
    case vsCode = "vscode"
}

struct KnownAppDefinition: Identifiable, Equatable {
    var appID: KnownAppID
    var displayName: String
    var bundleIDs: Set<String>
    var capabilities: AppCompatibilityCapabilities

    var id: String {
        appID.rawValue
    }

    var sortedBundleIDs: [String] {
        bundleIDs.sorted()
    }

    func matches(bundleID: String) -> Bool {
        BundleIdentifier.lookupKeys(for: Array(bundleIDs))
            .contains(BundleIdentifier.lookupKey(for: bundleID))
    }
}

struct KnownAppCatalog: Equatable {
    static let defaultCatalog = KnownAppCatalog(
        definitions: [
            .slack,
            .channelTalk,
            .discord,
            .notion,
            .vsCode
        ]
    )

    var definitions: [KnownAppDefinition]

    func definition(for appID: KnownAppID) -> KnownAppDefinition? {
        definitions.first { $0.appID == appID }
    }

    func definition(forBundleID bundleID: String) -> KnownAppDefinition? {
        definitions.first { $0.matches(bundleID: bundleID) }
    }

    func bundleIDs(for appID: KnownAppID) -> Set<String> {
        definition(for: appID)?.bundleIDs ?? []
    }

    func primaryBundleID(for appID: KnownAppID) -> String? {
        definition(for: appID)?.sortedBundleIDs.first
    }

    var compatibilityProfiles: [AppCompatibilityProfile] {
        definitions.map { definition in
            AppCompatibilityProfile(
                id: definition.id,
                displayName: definition.displayName,
                bundleIDs: definition.bundleIDs,
                capabilities: definition.capabilities
            )
        }
    }

    var electronApps: [KnownElectronApp] {
        definitions
            .filter { $0.capabilities.electronAXEnableRequired }
            .map { definition in
                KnownElectronApp(
                    displayName: definition.displayName,
                    bundleIDs: Array(definition.bundleIDs)
                )
            }
    }

    var visibleContextBundleIDs: Set<String> {
        Set(
            definitions
                .filter { $0.capabilities.visibleContextAdapterSupport == .supported }
                .flatMap(\.bundleIDs)
        )
    }
}

extension KnownAppDefinition {
    static let slack = KnownAppDefinition(
        appID: .slack,
        displayName: "Slack",
        bundleIDs: ["com.tinyspeck.slackmacgap"],
        capabilities: electronMessagingCapabilities(visibleContextAdapterSupport: .supported)
    )

    static let channelTalk = KnownAppDefinition(
        appID: .channelTalk,
        displayName: "ChannelTalk",
        bundleIDs: ["com.zoyi.channel.desk.osx"],
        capabilities: electronMessagingCapabilities(visibleContextAdapterSupport: .supported)
    )

    static let discord = KnownAppDefinition(
        appID: .discord,
        displayName: "Discord",
        bundleIDs: ["com.hnc.Discord"],
        capabilities: electronMessagingCapabilities(visibleContextAdapterSupport: .unsupported)
    )

    static let notion = KnownAppDefinition(
        appID: .notion,
        displayName: "Notion Desktop",
        bundleIDs: ["notion.id"],
        capabilities: electronDocumentCapabilities(visibleContextAdapterSupport: .unsupported)
    )

    static let vsCode = KnownAppDefinition(
        appID: .vsCode,
        displayName: "VS Code",
        bundleIDs: ["com.microsoft.VSCode"],
        capabilities: AppCompatibilityCapabilities(
            focusedInputRead: .supported,
            selectedRangeRead: .limited,
            boundsRead: .limited,
            directApply: .limited,
            pasteFallback: .supported,
            visibleContextAdapterSupport: .unsupported,
            electronAXEnableRequired: true
        )
    )

    private static func electronMessagingCapabilities(
        visibleContextAdapterSupport: AppCompatibilitySupport
    ) -> AppCompatibilityCapabilities {
        AppCompatibilityCapabilities(
            focusedInputRead: .supported,
            selectedRangeRead: .supported,
            boundsRead: .limited,
            directApply: .limited,
            pasteFallback: .supported,
            visibleContextAdapterSupport: visibleContextAdapterSupport,
            electronAXEnableRequired: true
        )
    }

    private static func electronDocumentCapabilities(
        visibleContextAdapterSupport: AppCompatibilitySupport
    ) -> AppCompatibilityCapabilities {
        AppCompatibilityCapabilities(
            focusedInputRead: .supported,
            selectedRangeRead: .limited,
            boundsRead: .limited,
            directApply: .limited,
            pasteFallback: .supported,
            visibleContextAdapterSupport: visibleContextAdapterSupport,
            electronAXEnableRequired: true
        )
    }
}
