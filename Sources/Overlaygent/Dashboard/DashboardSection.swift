import Foundation

enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case llmProvider
    case agents
    case appRules
    case privacy
    case diagnostics

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general:
            "General"
        case .llmProvider:
            "LLM Provider"
        case .agents:
            "Agents"
        case .appRules:
            "App Rules"
        case .privacy:
            "Privacy"
        case .diagnostics:
            "Diagnostics"
        }
    }

    var systemImageName: String {
        switch self {
        case .general:
            "gearshape"
        case .llmProvider:
            "server.rack"
        case .agents:
            "person.2"
        case .appRules:
            "app.badge"
        case .privacy:
            "hand.raised"
        case .diagnostics:
            "stethoscope"
        }
    }
}
