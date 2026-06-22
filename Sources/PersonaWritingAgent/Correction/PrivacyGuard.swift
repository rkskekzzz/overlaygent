import Foundation

enum PrivacyGuardError: Error, Equatable {
    case secureSourceMetadata(field: String, value: String)
    case noAllowedAgentsForSourceBundle(String)

    var safeDescription: String {
        switch self {
        case let .secureSourceMetadata(field, _):
            return "Secure source metadata rejected at \(field)."
        case .noAllowedAgentsForSourceBundle:
            return "No allowed agents for source bundle."
        }
    }
}

struct PrivacyGuard {
    func validateAndRedact(_ request: AgentRunRequest) throws -> AgentRunRequest {
        try rejectSecureSourceMetadata(in: request)

        let allowedAgents = filterAllowedAgents(
            request.activeAgents,
            sourceBundleID: request.input.sourceBundleID
        )
        guard allowedAgents.isEmpty == false else {
            throw PrivacyGuardError.noAllowedAgentsForSourceBundle(request.input.sourceBundleID)
        }

        let requestRedactor = ContextRedactor(redactionRules: request.privacyPolicy.redactionRules)

        return AgentRunRequest(
            input: redactedInput(request.input, redactor: requestRedactor),
            activeAgents: allowedAgents.map { redactedAgent($0, redactor: requestRedactor) },
            appContext: sanitizedContext(request.appContext, policy: request.privacyPolicy, redactor: requestRedactor),
            memory: redactedMemory(request.memory, redactor: requestRedactor),
            privacyPolicy: redactedPrivacyPolicy(request.privacyPolicy, redactor: requestRedactor)
        )
    }

    private func rejectSecureSourceMetadata(in request: AgentRunRequest) throws {
        try rejectIfSecureMetadata(
            field: "input.sourceElementRole",
            value: request.input.sourceElementRole
        )
        try rejectIfSecureMetadata(
            field: "input.sourceBundleID",
            value: request.input.sourceBundleID
        )
        try rejectIfSecureMetadata(
            field: "appContext.appBundleID",
            value: request.appContext?.appBundleID
        )
    }

    private func rejectIfSecureMetadata(field: String, value: String?) throws {
        guard let value, isSecureLikeMetadata(value) else {
            return
        }

        throw PrivacyGuardError.secureSourceMetadata(field: field, value: value)
    }

    private func filterAllowedAgents(
        _ agents: [AgentProfile],
        sourceBundleID: String
    ) -> [AgentProfile] {
        let normalizedSourceBundleID = BundleIdentifier.lookupKey(for: sourceBundleID)

        return agents.filter { agent in
            let disabledBundleIDs = BundleIdentifier.lookupKeys(for: agent.disabledBundleIDs)
            guard disabledBundleIDs.contains(normalizedSourceBundleID) == false else {
                return false
            }

            let enabledBundleIDs = BundleIdentifier.lookupKeys(for: agent.enabledBundleIDs)
            guard enabledBundleIDs.isEmpty == false else {
                return true
            }

            return enabledBundleIDs.contains(normalizedSourceBundleID)
        }
    }

    private func sanitizedContext(
        _ context: ConversationContext?,
        policy: PrivacyPolicy,
        redactor: ContextRedactor
    ) -> ConversationContext? {
        guard policy.includeConversationContext, var context else {
            return nil
        }

        context.conversationTitle = redactor.redact(context.conversationTitle)
        context.visibleMessages = limitedMessages(
            context.visibleMessages,
            maxVisibleMessages: policy.maxVisibleMessages
        ).map { message in
            redactedMessage(message, redactor: redactor)
        }

        return context
    }

    private func limitedMessages(
        _ messages: [ConversationMessage],
        maxVisibleMessages: Int
    ) -> [ConversationMessage] {
        guard maxVisibleMessages > 0 else {
            return []
        }

        guard messages.count > maxVisibleMessages else {
            return messages
        }

        return Array(messages.suffix(maxVisibleMessages))
    }

    private func redactedInput(
        _ input: TextSnapshot,
        redactor: ContextRedactor
    ) -> TextSnapshot {
        TextSnapshot(
            text: redactor.redact(input.text),
            selectedRange: input.selectedRange,
            sourceBundleID: input.sourceBundleID,
            sourceElementRole: input.sourceElementRole,
            contentHash: input.contentHash
        )
    }

    private func redactedMessage(
        _ message: ConversationMessage,
        redactor: ContextRedactor
    ) -> ConversationMessage {
        ConversationMessage(
            id: message.id,
            author: redactor.redact(message.author),
            timestamp: message.timestamp,
            text: redactor.redact(message.text)
        )
    }

    private func redactedMemory(
        _ memory: AgentMemory,
        redactor: ContextRedactor
    ) -> AgentMemory {
        AgentMemory(
            terminologyRules: memory.terminologyRules.map { redactedTerminologyRule($0, redactor: redactor) },
            tonePreferences: memory.tonePreferences.map(redactor.redact),
            writingRules: memory.writingRules.map(redactor.redact)
        )
    }

    private func redactedPrivacyPolicy(
        _ privacyPolicy: PrivacyPolicy,
        redactor: ContextRedactor
    ) -> PrivacyPolicy {
        PrivacyPolicy(
            includeConversationContext: privacyPolicy.includeConversationContext,
            maxVisibleMessages: privacyPolicy.maxVisibleMessages,
            allowClipboardFallback: privacyPolicy.allowClipboardFallback,
            redactionRules: privacyPolicy.redactionRules.map(redactor.redact)
        )
    }

    private func redactedAgent(
        _ agent: AgentProfile,
        redactor: ContextRedactor
    ) -> AgentProfile {
        AgentProfile(
            id: agent.id,
            name: redactor.redact(agent.name),
            description: redactor.redact(agent.description),
            isEnabled: agent.isEnabled,
            isActive: agent.isActive,
            providerID: agent.providerID,
            modelOverride: redactor.redact(agent.modelOverride),
            systemPrompt: redactor.redact(agent.systemPrompt),
            instruction: redactor.redact(agent.instruction),
            tone: agent.tone,
            aggressiveness: agent.aggressiveness,
            scope: agent.scope,
            terminologyRules: agent.terminologyRules.map { redactedTerminologyRule($0, redactor: redactor) },
            enabledBundleIDs: agent.enabledBundleIDs,
            disabledBundleIDs: agent.disabledBundleIDs,
            applyMode: agent.applyMode
        )
    }

    private func redactedTerminologyRule(
        _ rule: TerminologyRule,
        redactor: ContextRedactor
    ) -> TerminologyRule {
        TerminologyRule(
            id: rule.id,
            match: redactor.redact(rule.match),
            replacement: redactor.redact(rule.replacement),
            note: redactor.redact(rule.note),
            isCaseSensitive: rule.isCaseSensitive
        )
    }

    private func isSecureLikeMetadata(_ value: String) -> Bool {
        let canonicalValue = canonicalIdentifier(value)

        return canonicalValue.contains("secure")
            || canonicalValue.contains("password")
            || canonicalValue.contains("passcode")
            || canonicalValue.contains("private")
            || canonicalValue.contains("secret")
            || canonicalValue.contains("credential")
    }

    private func canonicalIdentifier(_ value: String) -> String {
        value
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0).lowercased() }
            .joined()
    }
}
