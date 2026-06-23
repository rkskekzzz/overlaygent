import ApplicationServices
import AppKit
import Foundation

protocol AXTextFocusRestoring {
    @discardableResult
    func restoreFocus(to element: AXElement) -> pid_t?
}

struct SystemAXTextFocusRestorer: AXTextFocusRestoring {
    @discardableResult
    func restoreFocus(to element: AXElement) -> pid_t? {
        guard CFGetTypeID(element.rawValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let axElement = unsafeBitCast(element.rawValue, to: AXUIElement.self)
        var processIdentifier: pid_t = 0
        let didReadProcessID = AXUIElementGetPid(axElement, &processIdentifier) == .success

        if didReadProcessID,
           let application = NSRunningApplication(processIdentifier: processIdentifier) {
            application.activate(options: [.activateIgnoringOtherApps])
        }

        AXUIElementSetAttributeValue(
            axElement,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )

        return didReadProcessID ? processIdentifier : nil
    }
}
