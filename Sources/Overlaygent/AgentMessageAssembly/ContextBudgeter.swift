import Foundation

struct AgentMessageBudgetedContext: Equatable {
    var input: TextSnapshot
    var agentTerminologyRules: [TerminologyRule]
    var memory: AgentMemory
    var conversationContext: ConversationContext?
    var metadata: AgentMessageBudgetMetadata
}

struct ContextBudgeter: Equatable {
    var characterBudget: Int?

    init(characterBudget: Int? = nil) {
        self.characterBudget = characterBudget.map { max(0, $0) }
    }

    func budget(agent: AgentProfile, request: AgentRunRequest) -> AgentMessageBudgetedContext {
        let inputCharacterCount = request.input.text.count
        var remainingCharacters = characterBudget.map { max(0, $0 - inputCharacterCount) }
        var didTrimForCharacterBudget = characterBudget.map { inputCharacterCount > $0 } ?? false

        let agentTerminologyResult = retainItems(
            agent.terminologyRules,
            remainingCharacters: &remainingCharacters,
            estimatedCharacterCount: estimatedTerminologyRuleCharacterCount
        )
        didTrimForCharacterBudget = didTrimForCharacterBudget || agentTerminologyResult.didTrim

        let memoryTerminologyResult = retainItems(
            request.memory.terminologyRules,
            remainingCharacters: &remainingCharacters,
            estimatedCharacterCount: estimatedTerminologyRuleCharacterCount
        )
        didTrimForCharacterBudget = didTrimForCharacterBudget || memoryTerminologyResult.didTrim

        let tonePreferenceResult = retainItems(
            request.memory.tonePreferences,
            remainingCharacters: &remainingCharacters,
            estimatedCharacterCount: estimatedStringCharacterCount
        )
        didTrimForCharacterBudget = didTrimForCharacterBudget || tonePreferenceResult.didTrim

        let writingRuleResult = retainItems(
            request.memory.writingRules,
            remainingCharacters: &remainingCharacters,
            estimatedCharacterCount: estimatedStringCharacterCount
        )
        didTrimForCharacterBudget = didTrimForCharacterBudget || writingRuleResult.didTrim

        let limitedContext = contextLimitedByPrivacyPolicy(request: request)
        let messageResult = retainVisibleMessages(
            limitedContext.context?.visibleMessages ?? [],
            remainingCharacters: &remainingCharacters
        )
        didTrimForCharacterBudget = didTrimForCharacterBudget || messageResult.didTrim

        let budgetedContext = limitedContext.context.map { context in
            ConversationContext(
                appBundleID: context.appBundleID,
                conversationTitle: context.conversationTitle,
                visibleMessages: messageResult.items
            )
        }
        let budgetedMemory = AgentMemory(
            terminologyRules: memoryTerminologyResult.items,
            tonePreferences: tonePreferenceResult.items,
            writingRules: writingRuleResult.items
        )
        let metadata = AgentMessageBudgetMetadata(
            characterBudget: characterBudget,
            maxVisibleMessages: max(0, request.privacyPolicy.maxVisibleMessages),
            includeConversationContext: request.privacyPolicy.includeConversationContext,
            inputCharacterCount: inputCharacterCount,
            retainedInputCharacterCount: inputCharacterCount,
            originalAgentTerminologyRuleCount: agent.terminologyRules.count,
            retainedAgentTerminologyRuleCount: agentTerminologyResult.items.count,
            originalMemoryTerminologyRuleCount: request.memory.terminologyRules.count,
            retainedMemoryTerminologyRuleCount: memoryTerminologyResult.items.count,
            originalTonePreferenceCount: request.memory.tonePreferences.count,
            retainedTonePreferenceCount: tonePreferenceResult.items.count,
            originalWritingRuleCount: request.memory.writingRules.count,
            retainedWritingRuleCount: writingRuleResult.items.count,
            originalVisibleMessageCount: limitedContext.originalVisibleMessageCount,
            retainedVisibleMessageCount: messageResult.items.count,
            didTrimForCharacterBudget: didTrimForCharacterBudget,
            didTrimVisibleMessages: limitedContext.didTrimVisibleMessages
        )

        return AgentMessageBudgetedContext(
            input: request.input,
            agentTerminologyRules: agentTerminologyResult.items,
            memory: budgetedMemory,
            conversationContext: budgetedContext,
            metadata: metadata
        )
    }

    private func contextLimitedByPrivacyPolicy(
        request: AgentRunRequest
    ) -> (context: ConversationContext?, originalVisibleMessageCount: Int, didTrimVisibleMessages: Bool) {
        guard request.privacyPolicy.includeConversationContext, let context = request.appContext else {
            return (nil, 0, false)
        }

        let maxVisibleMessages = max(0, request.privacyPolicy.maxVisibleMessages)
        let originalVisibleMessages = context.visibleMessages
        let retainedVisibleMessages: [ConversationMessage]
        if maxVisibleMessages == 0 {
            retainedVisibleMessages = []
        } else {
            retainedVisibleMessages = Array(originalVisibleMessages.suffix(maxVisibleMessages))
        }

        return (
            ConversationContext(
                appBundleID: context.appBundleID,
                conversationTitle: context.conversationTitle,
                visibleMessages: retainedVisibleMessages
            ),
            originalVisibleMessages.count,
            retainedVisibleMessages.count < originalVisibleMessages.count
        )
    }

    private func retainItems<Item>(
        _ items: [Item],
        remainingCharacters: inout Int?,
        estimatedCharacterCount: (Item) -> Int
    ) -> (items: [Item], didTrim: Bool) {
        guard remainingCharacters != nil else {
            return (items, false)
        }

        var retainedItems: [Item] = []
        var didTrim = false

        for item in items {
            let characterCount = max(0, estimatedCharacterCount(item))
            if characterCount <= remainingCharacters ?? 0 {
                retainedItems.append(item)
                remainingCharacters = (remainingCharacters ?? 0) - characterCount
            } else {
                didTrim = true
            }
        }

        return (retainedItems, didTrim)
    }

    private func retainVisibleMessages(
        _ messages: [ConversationMessage],
        remainingCharacters: inout Int?
    ) -> (items: [ConversationMessage], didTrim: Bool) {
        guard remainingCharacters != nil else {
            return (messages, false)
        }

        var retainedMessages: [ConversationMessage] = []
        var didTrim = false

        for message in messages.reversed() {
            let characterCount = estimatedConversationMessageCharacterCount(message)
            if characterCount <= remainingCharacters ?? 0 {
                retainedMessages.insert(message, at: 0)
                remainingCharacters = (remainingCharacters ?? 0) - characterCount
            } else {
                didTrim = true
            }
        }

        return (retainedMessages, didTrim)
    }

    private func estimatedTerminologyRuleCharacterCount(_ rule: TerminologyRule) -> Int {
        rule.match.count + rule.replacement.count + (rule.note?.count ?? 0) + 24
    }

    private func estimatedStringCharacterCount(_ string: String) -> Int {
        string.count
    }

    private func estimatedConversationMessageCharacterCount(_ message: ConversationMessage) -> Int {
        (message.author?.count ?? 7) + message.text.count + (message.timestamp == nil ? 0 : 20) + 16
    }
}
