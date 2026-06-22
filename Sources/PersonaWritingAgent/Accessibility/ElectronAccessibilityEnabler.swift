import ApplicationServices
import Foundation

struct KnownElectronApp: Equatable {
    var displayName: String
    var bundleIDs: Set<String>

    init(displayName: String, bundleIDs: [String]) {
        self.displayName = displayName
        self.bundleIDs = Set(bundleIDs.map { BundleIdentifier($0).trimmed }.filter { $0.isEmpty == false })
    }

    func matches(bundleID: String) -> Bool {
        BundleIdentifier.lookupKeys(for: Array(bundleIDs))
            .contains(BundleIdentifier.lookupKey(for: bundleID))
    }
}

extension KnownElectronApp {
    static let supportedApps: [KnownElectronApp] = KnownAppCatalog.defaultCatalog.electronApps
}

struct ElectronAccessibilityTarget: Equatable {
    var bundleID: String
    var processIdentifier: pid_t?
    var applicationElement: AXElement?

    init(bundleID: String, processIdentifier: pid_t? = nil, applicationElement: AXElement? = nil) {
        self.bundleID = bundleID
        self.processIdentifier = processIdentifier
        self.applicationElement = applicationElement
    }
}

enum ElectronAccessibilityEnablerError: Error, Equatable, CustomStringConvertible {
    case missingApplicationReference
    case invalidApplicationElement
    case setAttributeFailed(attribute: String, code: Int32)

    var description: String {
        switch self {
        case .missingApplicationReference:
            return "Electron accessibility enablement requires either a pid or an app AX element"
        case .invalidApplicationElement:
            return "Invalid application AX element"
        case let .setAttributeFailed(attribute, code):
            return "Failed to set AX attribute \(attribute) (code: \(code))"
        }
    }
}

enum ElectronAccessibilityEnableResult: Equatable {
    case enabled(KnownElectronApp)
    case skippedUnknownBundleID(String)
    case failed(KnownElectronApp, ElectronAccessibilityEnablerError)
}

protocol AXManualAccessibilityWriting {
    func applicationElement(for processIdentifier: pid_t) -> AXElement
    func setManualAccessibility(_ enabled: Bool, on element: AXElement) -> Result<Void, ElectronAccessibilityEnablerError>
}

final class ElectronAccessibilityEnabler {
    static let manualAccessibilityAttribute = "AXManualAccessibility"

    private let knownApps: [KnownElectronApp]
    private let writer: AXManualAccessibilityWriting

    init(
        knownApps: [KnownElectronApp] = KnownElectronApp.supportedApps,
        writer: AXManualAccessibilityWriting = SystemAXManualAccessibilityWriter()
    ) {
        self.knownApps = knownApps
        self.writer = writer
    }

    func isKnownElectronApp(bundleID: String) -> Bool {
        knownElectronApp(bundleID: bundleID) != nil
    }

    func knownElectronApp(bundleID: String) -> KnownElectronApp? {
        return knownApps.first { app in
            app.matches(bundleID: bundleID)
        }
    }

    @discardableResult
    func enableIfNeeded(
        bundleID: String,
        processIdentifier: pid_t? = nil,
        applicationElement: AXElement? = nil
    ) -> ElectronAccessibilityEnableResult {
        enableIfNeeded(
            for: ElectronAccessibilityTarget(
                bundleID: bundleID,
                processIdentifier: processIdentifier,
                applicationElement: applicationElement
            )
        )
    }

    @discardableResult
    func enableIfNeeded(for target: ElectronAccessibilityTarget) -> ElectronAccessibilityEnableResult {
        guard let app = knownElectronApp(bundleID: target.bundleID) else {
            return .skippedUnknownBundleID(target.bundleID)
        }

        let applicationElement: AXElement
        if let providedElement = target.applicationElement {
            applicationElement = providedElement
        } else if let processIdentifier = target.processIdentifier {
            applicationElement = writer.applicationElement(for: processIdentifier)
        } else {
            return .failed(app, .missingApplicationReference)
        }

        switch writer.setManualAccessibility(true, on: applicationElement) {
        case .success:
            return .enabled(app)
        case let .failure(error):
            return .failed(app, error)
        }
    }
}

struct SystemAXManualAccessibilityWriter: AXManualAccessibilityWriting {
    func applicationElement(for processIdentifier: pid_t) -> AXElement {
        AXElement(AXUIElementCreateApplication(processIdentifier))
    }

    func setManualAccessibility(
        _ enabled: Bool,
        on element: AXElement
    ) -> Result<Void, ElectronAccessibilityEnablerError> {
        guard CFGetTypeID(element.rawValue) == AXUIElementGetTypeID() else {
            return .failure(.invalidApplicationElement)
        }

        let axElement = unsafeBitCast(element.rawValue, to: AXUIElement.self)
        let enabledValue: CFBoolean = enabled ? kCFBooleanTrue : kCFBooleanFalse
        let error = AXUIElementSetAttributeValue(
            axElement,
            ElectronAccessibilityEnabler.manualAccessibilityAttribute as CFString,
            enabledValue
        )

        guard error == .success else {
            return .failure(
                .setAttributeFailed(
                    attribute: ElectronAccessibilityEnabler.manualAccessibilityAttribute,
                    code: error.rawValue
                )
            )
        }

        return .success(())
    }
}
