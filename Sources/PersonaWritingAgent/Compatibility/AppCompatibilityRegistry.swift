import Foundation

enum AppCompatibilitySupport: String, Equatable {
    case supported
    case limited
    case required
    case unsupported

    var displayName: String {
        switch self {
        case .supported:
            "Supported"
        case .limited:
            "Limited"
        case .required:
            "Required"
        case .unsupported:
            "Unsupported"
        }
    }
}

enum AppCompatibilityCapability: CaseIterable, Identifiable, Equatable {
    case focusedInputRead
    case selectedRangeRead
    case boundsRead
    case directApply
    case pasteFallback
    case visibleContextAdapterSupport
    case electronAXEnableRequired

    var id: String {
        key
    }

    var key: String {
        switch self {
        case .focusedInputRead:
            "focused_input_read"
        case .selectedRangeRead:
            "selected_range_read"
        case .boundsRead:
            "bounds_read"
        case .directApply:
            "direct_apply"
        case .pasteFallback:
            "paste_fallback"
        case .visibleContextAdapterSupport:
            "visible_context_adapter_support"
        case .electronAXEnableRequired:
            "electron_ax_enable_required"
        }
    }

    var displayName: String {
        switch self {
        case .focusedInputRead:
            "Focused input read"
        case .selectedRangeRead:
            "Selected range read"
        case .boundsRead:
            "Bounds read"
        case .directApply:
            "Direct apply"
        case .pasteFallback:
            "Paste fallback"
        case .visibleContextAdapterSupport:
            "Visible context adapter"
        case .electronAXEnableRequired:
            "Electron AX enable"
        }
    }
}

struct AppCompatibilityCapabilitySummary: Identifiable, Equatable {
    var capability: AppCompatibilityCapability
    var support: AppCompatibilitySupport

    var id: String {
        capability.id
    }
}

struct AppCompatibilityCapabilities: Equatable {
    var focusedInputRead: AppCompatibilitySupport
    var selectedRangeRead: AppCompatibilitySupport
    var boundsRead: AppCompatibilitySupport
    var directApply: AppCompatibilitySupport
    var pasteFallback: AppCompatibilitySupport
    var visibleContextAdapterSupport: AppCompatibilitySupport
    var electronAXEnableRequired: Bool

    func support(for capability: AppCompatibilityCapability) -> AppCompatibilitySupport {
        switch capability {
        case .focusedInputRead:
            focusedInputRead
        case .selectedRangeRead:
            selectedRangeRead
        case .boundsRead:
            boundsRead
        case .directApply:
            directApply
        case .pasteFallback:
            pasteFallback
        case .visibleContextAdapterSupport:
            visibleContextAdapterSupport
        case .electronAXEnableRequired:
            electronAXEnableRequired ? .required : .unsupported
        }
    }

    var summaries: [AppCompatibilityCapabilitySummary] {
        AppCompatibilityCapability.allCases.map { capability in
            AppCompatibilityCapabilitySummary(
                capability: capability,
                support: support(for: capability)
            )
        }
    }
}

enum AppCompatibilityDiagnosticSeverity: String, Equatable {
    case info
    case warning
}

enum AppCompatibilityDiagnosticCode: String, Equatable {
    case electronAccessibilityEnablementRequired
    case boundsReadLimited
    case directApplyLimited
    case selectedRangeReadLimited
    case visibleContextAdapterUnavailable

    var message: String {
        switch self {
        case .electronAccessibilityEnablementRequired:
            "Electron accessibility must be enabled before AX reads are reliable."
        case .boundsReadLimited:
            "Range bounds can vary across Electron editor implementations."
        case .directApplyLimited:
            "Direct AX apply can be limited; paste fallback remains available."
        case .selectedRangeReadLimited:
            "Selected range reads can be limited by the focused editor."
        case .visibleContextAdapterUnavailable:
            "No app-specific visible context adapter is registered."
        }
    }
}

struct AppCompatibilityDiagnosticNote: Identifiable, Equatable {
    var code: AppCompatibilityDiagnosticCode
    var severity: AppCompatibilityDiagnosticSeverity

    var id: String {
        code.rawValue
    }

    var message: String {
        code.message
    }
}

struct AppCompatibilityProfile: Identifiable, Equatable {
    var id: String
    var displayName: String
    var bundleIDs: Set<String>
    var capabilities: AppCompatibilityCapabilities

    func matches(bundleID: String) -> Bool {
        BundleIdentifier.lookupKeys(for: Array(bundleIDs))
            .contains(BundleIdentifier.lookupKey(for: bundleID))
    }

    var sortedBundleIDs: [String] {
        bundleIDs.sorted()
    }

    var diagnosticNotes: [AppCompatibilityDiagnosticNote] {
        var notes: [AppCompatibilityDiagnosticNote] = []

        if capabilities.electronAXEnableRequired {
            notes.append(
                AppCompatibilityDiagnosticNote(
                    code: .electronAccessibilityEnablementRequired,
                    severity: .info
                )
            )
        }

        if capabilities.selectedRangeRead == .limited {
            notes.append(
                AppCompatibilityDiagnosticNote(
                    code: .selectedRangeReadLimited,
                    severity: .warning
                )
            )
        }

        if capabilities.boundsRead == .limited {
            notes.append(
                AppCompatibilityDiagnosticNote(
                    code: .boundsReadLimited,
                    severity: .warning
                )
            )
        }

        if capabilities.directApply == .limited {
            notes.append(
                AppCompatibilityDiagnosticNote(
                    code: .directApplyLimited,
                    severity: .warning
                )
            )
        }

        if capabilities.visibleContextAdapterSupport == .unsupported {
            notes.append(
                AppCompatibilityDiagnosticNote(
                    code: .visibleContextAdapterUnavailable,
                    severity: .info
                )
            )
        }

        return notes
    }

}

struct AppCompatibilityDiagnosticsRow: Identifiable, Equatable {
    var appID: String
    var displayName: String
    var bundleIDs: [String]
    var capabilities: [AppCompatibilityCapabilitySummary]
    var notes: [AppCompatibilityDiagnosticNote]

    var id: String {
        appID
    }
}

struct AppCompatibilityDiagnosticsSummary: Equatable {
    var rows: [AppCompatibilityDiagnosticsRow]

    var knownAppCount: Int {
        rows.count
    }

    var visibleContextAdapterCount: Int {
        rows.filter { row in
            row.capabilities.contains { summary in
                summary.capability == .visibleContextAdapterSupport && summary.support == .supported
            }
        }.count
    }

    var safeDiagnosticsText: String {
        rows.map { row in
            let bundleIDs = row.bundleIDs.joined(separator: ", ")
            let capabilities = row.capabilities.map { summary in
                "\(summary.capability.key)=\(summary.support.rawValue)"
            }.joined(separator: ", ")
            let noteCodes = row.notes.map(\.code.rawValue).joined(separator: ", ")
            return "\(row.displayName) [\(bundleIDs)]: \(capabilities); notes=\(noteCodes)"
        }
        .joined(separator: "\n")
    }
}

struct AppCompatibilityRegistry {
    static let defaultRegistry = AppCompatibilityRegistry(catalog: .defaultCatalog)

    private let profiles: [AppCompatibilityProfile]
    private let profilesByBundleID: [String: AppCompatibilityProfile]

    init(catalog: KnownAppCatalog) {
        self.init(profiles: catalog.compatibilityProfiles)
    }

    init(profiles: [AppCompatibilityProfile]) {
        self.profiles = profiles
        self.profilesByBundleID = profiles.reduce(into: [:]) { mappedProfiles, profile in
            for bundleID in profile.bundleIDs {
                let key = BundleIdentifier.lookupKey(for: bundleID)
                guard key.isEmpty == false else {
                    continue
                }

                mappedProfiles[key] = profile
            }
        }
    }

    var knownApps: [AppCompatibilityProfile] {
        profiles
    }

    func profile(forBundleID bundleID: String) -> AppCompatibilityProfile? {
        profilesByBundleID[BundleIdentifier.lookupKey(for: bundleID)]
    }

    func diagnosticsSummary() -> AppCompatibilityDiagnosticsSummary {
        AppCompatibilityDiagnosticsSummary(
            rows: profiles.map { profile in
                AppCompatibilityDiagnosticsRow(
                    appID: profile.id,
                    displayName: profile.displayName,
                    bundleIDs: profile.sortedBundleIDs,
                    capabilities: profile.capabilities.summaries,
                    notes: profile.diagnosticNotes
                )
            }
        )
    }

}
