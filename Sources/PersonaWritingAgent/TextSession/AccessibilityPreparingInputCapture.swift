import Foundation

struct AccessibilityPreparingInputCapture: AgentRunInputCapturing {
    private let preparer: any FocusedApplicationAccessibilityPreparing
    private let baseCapture: any AgentRunInputCapturing

    init(
        preparer: any FocusedApplicationAccessibilityPreparing,
        baseCapture: any AgentRunInputCapturing
    ) {
        self.preparer = preparer
        self.baseCapture = baseCapture
    }

    func capture() throws -> FocusedTextCapture {
        preparer.prepareFocusedApplication()
        return try baseCapture.capture()
    }
}
