import Foundation

struct AgentSuggestion: Identifiable, Equatable {
    var id: UUID
    var agentName: String
    var result: CorrectionResult

    init(
        id: UUID = UUID(),
        agentName: String,
        result: CorrectionResult
    ) {
        self.id = id
        self.agentName = agentName
        self.result = result
    }

    var summary: String? {
        result.summary
    }

    var edits: [CorrectionEdit] {
        result.edits
    }

    var fullRewrite: String? {
        result.fullRewrite
    }
}
