import Foundation

struct AgentMessageFactory: Equatable {
    static let defaultOutputSchemaID = "CorrectionResult"

    var contextBudgeter: ContextBudgeter
    var outputSchemaID: String

    init(
        contextBudgeter: ContextBudgeter = ContextBudgeter(),
        outputSchemaID: String = AgentMessageFactory.defaultOutputSchemaID
    ) {
        self.contextBudgeter = contextBudgeter
        self.outputSchemaID = outputSchemaID
    }

    func makeBundles(for request: AgentRunRequest) -> [AgentMessageBundle] {
        request.activeAgents.map { agent in
            makeBundle(for: agent, request: request)
        }
    }

    func makeBundle(for agent: AgentProfile, request: AgentRunRequest) -> AgentMessageBundle {
        let budgetedContext = contextBudgeter.budget(agent: agent, request: request)
        let messages = [
            AgentMessage(role: .system, content: renderSystemMessage(agent: agent)),
            AgentMessage(role: .developer, content: renderDeveloperMessage(agent: agent, context: budgetedContext)),
            AgentMessage(role: .user, content: renderUserMessage(context: budgetedContext))
        ]

        return AgentMessageBundle(
            agentID: agent.id,
            agentName: agent.name,
            providerID: agent.providerID,
            resolvedModel: normalizedModelOverride(agent.modelOverride),
            messages: messages,
            outputSchemaID: outputSchemaID,
            budgetMetadata: budgetedContext.metadata
        )
    }

    private func renderSystemMessage(agent: AgentProfile) -> String {
        [
            renderSection(
                "Agent",
                lines: [
                    "ID: \(agent.id.uuidString)",
                    "Name: \(agent.name)",
                    "Provider ID: \(agent.providerID.uuidString)"
                ]
            ),
            renderSection("System Prompt", lines: [normalizedText(agent.systemPrompt)])
        ].joined(separator: "\n\n")
    }

    private func renderDeveloperMessage(
        agent: AgentProfile,
        context: AgentMessageBudgetedContext
    ) -> String {
        [
            renderSection("Instruction", lines: [normalizedText(agent.instruction)]),
            renderSection(
                "Controls",
                lines: [
                    "Tone: \(agent.tone.rawValue)",
                    "Aggressiveness: \(agent.aggressiveness.rawValue)",
                    "Scope: \(agent.scope.rawValue)"
                ]
            ),
            renderSection(
                "Agent Terminology Rules",
                lines: renderTerminologyRules(context.agentTerminologyRules)
            ),
            renderSection("Agent Memory", lines: renderMemory(context.memory)),
            renderSection("Output Contract", lines: renderOutputContract())
        ].joined(separator: "\n\n")
    }

    private func renderUserMessage(context: AgentMessageBudgetedContext) -> String {
        [
            renderSection("Source", lines: renderSource(context.input)),
            renderSection("Conversation Context", lines: renderConversationContext(context.conversationContext)),
            renderSection("Input", lines: [context.input.text])
        ].joined(separator: "\n\n")
    }

    private func renderSource(_ input: TextSnapshot) -> [String] {
        [
            "Bundle ID: \(input.sourceBundleID)",
            "Element role: \(input.sourceElementRole ?? "None")",
            "Selected range: \(formatSelectedRange(input.selectedRange))"
        ]
    }

    private func renderConversationContext(_ context: ConversationContext?) -> [String] {
        guard let context else {
            return ["Not included."]
        }

        var lines = [
            "App bundle ID: \(context.appBundleID)",
            "Title: \(context.conversationTitle ?? "None")"
        ]

        guard context.visibleMessages.isEmpty == false else {
            lines.append("Visible messages: None retained.")
            return lines
        }

        lines.append("Visible messages:")
        lines.append(contentsOf: context.visibleMessages.enumerated().map { index, message in
            "\(index + 1). \(formatConversationMessage(message))"
        })
        return lines
    }

    private func renderMemory(_ memory: AgentMemory) -> [String] {
        [
            "Terminology:",
            renderIndentedList(renderTerminologyRules(memory.terminologyRules)),
            "Tone preferences:",
            renderIndentedList(renderStringList(memory.tonePreferences)),
            "Writing rules:",
            renderIndentedList(renderStringList(memory.writingRules))
        ].flatMap { line in
            line.components(separatedBy: "\n")
        }
    }

    private func renderTerminologyRules(_ rules: [TerminologyRule]) -> [String] {
        guard rules.isEmpty == false else {
            return ["None"]
        }

        return rules.enumerated().map { index, rule in
            let casePolicy = rule.isCaseSensitive ? "case-sensitive" : "case-insensitive"
            let note = rule.note.map { "; note: \($0)" } ?? ""
            return "\(index + 1). \(rule.match) -> \(rule.replacement) (\(casePolicy)\(note))"
        }
    }

    private func renderStringList(_ values: [String]) -> [String] {
        guard values.isEmpty == false else {
            return ["None"]
        }

        return values.enumerated().map { index, value in
            "\(index + 1). \(value)"
        }
    }

    private func renderOutputContract() -> [String] {
        [
            "Return exactly one JSON object and no Markdown or prose.",
            "Schema ID: \(outputSchemaID)",
            #"Required top-level keys: "summary", "edits", "fullRewrite"."#,
            #"Use "summary" as a short string or null."#,
            #"Use "edits" as an array of objects with rangeStart, rangeEnd, original, replacement, and reason."#,
            "Ranges are zero-based character offsets into the Input section.",
            #"Use "fullRewrite" as a complete corrected version string or null."#,
            "If the text is already good, set fullRewrite to the original input and explain that no change is needed in summary."
        ]
    }

    private func renderIndentedList(_ lines: [String]) -> String {
        lines.map { "  \($0)" }.joined(separator: "\n")
    }

    private func renderSection(_ title: String, lines: [String]) -> String {
        (["# \(title)"] + lines).joined(separator: "\n")
    }

    private func formatConversationMessage(_ message: ConversationMessage) -> String {
        let author = message.author ?? "Unknown"
        let timestamp = message.timestamp.map(formatTimestamp) ?? "No timestamp"
        return "\(timestamp) | \(author): \(message.text)"
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func formatSelectedRange(_ range: Range<Int>?) -> String {
        guard let range else {
            return "None"
        }

        return "\(range.lowerBound)..<\(range.upperBound)"
    }

    private func normalizedText(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? "None" : trimmedText
    }

    private func normalizedModelOverride(_ modelOverride: String?) -> String? {
        let trimmedModel = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedModel?.isEmpty == false ? trimmedModel : nil
    }
}
