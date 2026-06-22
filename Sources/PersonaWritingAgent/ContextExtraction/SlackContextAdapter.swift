import ApplicationServices
import Foundation

protocol SlackAXTreeReading {
    func snapshot(for element: AXElement) -> SlackAXNodeSnapshot?
    func children(of element: AXElement) -> [AXElement]
    func parent(of element: AXElement) -> AXElement?
}

struct SlackAXNodeSnapshot: Equatable {
    var role: String?
    var subrole: String?
    var title: String?
    var value: String?
    var description: String?
    var identifier: String?
}

struct SlackContextAdapter: AppContextAdapter {
    static var slackBundleID: String {
        KnownAppCatalog.defaultCatalog.primaryBundleID(for: .slack) ?? ""
    }

    var supportedBundleIDs: Set<String> {
        KnownAppCatalog.defaultCatalog.bundleIDs(for: .slack)
    }

    private let accessibilityTree: any SlackAXTreeReading
    private let uuidGenerator: () -> UUID

    init(
        accessibilityTree: any SlackAXTreeReading = SystemSlackAXTreeReader(),
        uuidGenerator: @escaping () -> UUID = { UUID() }
    ) {
        self.accessibilityTree = accessibilityTree
        self.uuidGenerator = uuidGenerator
    }

    func extractContext(for request: AppContextExtractionRequest) -> ConversationContext? {
        guard Self.isSupportedBundleID(request.sourceBundleID) else {
            return nil
        }

        guard let focusedElement = request.focusedElement?.element else {
            return emptyContext(for: request)
        }

        let rootElement = rootElement(for: focusedElement)
        let title = conversationTitle(from: rootElement)
        let messages = visibleMessages(from: rootElement, maxCount: request.maxVisibleMessages)

        return ConversationContext(
            appBundleID: request.sourceBundleID,
            conversationTitle: title,
            visibleMessages: messages
        )
    }

    private static func isSupportedBundleID(_ bundleID: String) -> Bool {
        KnownAppCatalog.defaultCatalog.definition(for: .slack)?.matches(bundleID: bundleID) == true
    }

    private func emptyContext(for request: AppContextExtractionRequest) -> ConversationContext {
        ConversationContext(
            appBundleID: request.sourceBundleID,
            conversationTitle: nil,
            visibleMessages: []
        )
    }

    private func rootElement(for focusedElement: AXElement) -> AXElement {
        var currentElement = focusedElement
        var visitedElements: Set<AXElement> = [focusedElement]

        for _ in 0..<12 {
            guard let parentElement = accessibilityTree.parent(of: currentElement),
                  visitedElements.contains(parentElement) == false
            else {
                break
            }

            currentElement = parentElement
            visitedElements.insert(parentElement)
        }

        return currentElement
    }

    private func conversationTitle(from rootElement: AXElement) -> String? {
        for node in traversal(from: rootElement, maxDepth: 5, maxNodes: 120) {
            guard let snapshot = node.snapshot else {
                continue
            }

            if let title = snapshot.title?.trimmedSlackText,
               isLikelyConversationTitle(title, role: snapshot.role)
            {
                return title
            }
        }

        return nil
    }

    private func visibleMessages(from rootElement: AXElement, maxCount: Int) -> [ConversationMessage] {
        guard maxCount > 0 else {
            return []
        }

        let candidates = deduplicatedMessageCandidates(from: rootElement)
        let limitedCandidates = Array(candidates.suffix(maxCount))

        return limitedCandidates.map { candidate in
            ConversationMessage(
                id: uuidGenerator(),
                author: candidate.author,
                timestamp: candidate.timestamp,
                text: candidate.text
            )
        }
    }

    private func deduplicatedMessageCandidates(from rootElement: AXElement) -> [SlackMessageCandidate] {
        var candidates = messageCandidates(from: rootElement)

        if candidates.isEmpty {
            candidates = fallbackTextMessageCandidates(from: rootElement)
        }

        var bestCandidatesByText: [String: SlackMessageCandidate] = [:]
        for candidate in candidates {
            let key = candidate.text.normalizedSlackText
            guard key.isEmpty == false else {
                continue
            }

            if let existingCandidate = bestCandidatesByText[key],
               existingCandidate.score >= candidate.score
            {
                continue
            }

            bestCandidatesByText[key] = candidate
        }

        return bestCandidatesByText.values.sorted { lhs, rhs in
            lhs.order < rhs.order
        }
    }

    private func messageCandidates(from rootElement: AXElement) -> [SlackMessageCandidate] {
        traversal(from: rootElement, maxDepth: 14, maxNodes: 1_500).compactMap { node in
            guard let snapshot = node.snapshot,
                  isPotentialMessageContainer(snapshot),
                  hasImmediateTextEvidence(in: node.element, snapshot: snapshot)
            else {
                return nil
            }

            let fragments = textFragments(from: node.element, maxDepth: 6, maxFragments: 12)
            return messageCandidate(from: fragments, order: node.order)
        }
    }

    private func fallbackTextMessageCandidates(from rootElement: AXElement) -> [SlackMessageCandidate] {
        textFragments(from: rootElement, maxDepth: 14, maxFragments: 200).compactMap { fragment in
            guard isLikelyMessageText(fragment.text) else {
                return nil
            }

            return SlackMessageCandidate(
                author: nil,
                timestamp: nil,
                text: fragment.text,
                order: fragment.order,
                score: 0
            )
        }
    }

    private func hasImmediateTextEvidence(in element: AXElement, snapshot: SlackAXNodeSnapshot) -> Bool {
        if textValues(from: snapshot).isEmpty == false {
            return true
        }

        return accessibilityTree.children(of: element).contains { childElement in
            guard let childSnapshot = accessibilityTree.snapshot(for: childElement) else {
                return false
            }

            return textValues(from: childSnapshot).isEmpty == false
        }
    }

    private func messageCandidate(
        from fragments: [SlackTextFragment],
        order: Int
    ) -> SlackMessageCandidate? {
        let uniqueFragments = uniqueTextFragments(fragments)
        guard uniqueFragments.isEmpty == false,
              uniqueFragments.count <= 12
        else {
            return nil
        }

        let timestampIndex = uniqueFragments.firstIndex { isTimestampLike($0.text) }
        let authorIndex = authorIndex(in: uniqueFragments, timestampIndex: timestampIndex)
        let timestamp = timestampIndex.flatMap { date(fromTimestampCandidate: uniqueFragments[$0].text) }

        let bodyFragments = uniqueFragments.enumerated().compactMap { index, fragment -> String? in
            guard index != timestampIndex,
                  index != authorIndex,
                  isLikelyNonMessageMetadata(fragment.text) == false
            else {
                return nil
            }

            return fragment.text
        }

        let messageText: String
        if bodyFragments.isEmpty, uniqueFragments.count == 1 {
            messageText = uniqueFragments[0].text
        } else {
            messageText = bodyFragments.joined(separator: "\n").trimmedSlackText
        }

        guard isLikelyMessageText(messageText) else {
            return nil
        }

        let author = authorIndex.map { uniqueFragments[$0].text }
        let score = (author == nil ? 0 : 2)
            + (timestampIndex == nil ? 0 : 1)
            + min(messageText.count / 80, 3)

        return SlackMessageCandidate(
            author: author,
            timestamp: timestamp,
            text: messageText,
            order: order,
            score: score
        )
    }

    private func authorIndex(
        in fragments: [SlackTextFragment],
        timestampIndex: Int?
    ) -> Int? {
        guard fragments.count >= 2 else {
            return nil
        }

        return fragments.enumerated().first { index, fragment in
            index != timestampIndex
                && index < fragments.count - 1
                && isLikelyAuthor(fragment.text)
        }?.offset
    }

    private func uniqueTextFragments(_ fragments: [SlackTextFragment]) -> [SlackTextFragment] {
        var seenTexts: Set<String> = []
        var uniqueFragments: [SlackTextFragment] = []

        for fragment in fragments {
            let key = fragment.text.normalizedSlackText
            guard key.isEmpty == false,
                  seenTexts.contains(key) == false
            else {
                continue
            }

            seenTexts.insert(key)
            uniqueFragments.append(fragment)
        }

        return uniqueFragments
    }

    private func textFragments(
        from rootElement: AXElement,
        maxDepth: Int,
        maxFragments: Int
    ) -> [SlackTextFragment] {
        var fragments: [SlackTextFragment] = []

        for node in traversal(from: rootElement, maxDepth: maxDepth, maxNodes: 400) {
            guard let snapshot = node.snapshot else {
                continue
            }

            for value in textValues(from: snapshot) {
                fragments.append(
                    SlackTextFragment(
                        text: value,
                        order: node.order
                    )
                )

                if fragments.count >= maxFragments {
                    return fragments
                }
            }
        }

        return fragments
    }

    private func textValues(from snapshot: SlackAXNodeSnapshot) -> [String] {
        guard isTextRole(snapshot.role) else {
            return []
        }

        var values: [String] = []
        for value in [snapshot.value, snapshot.title, snapshot.description] {
            guard let text = value?.trimmedSlackText,
                  text.isEmpty == false,
                  values.contains(text) == false
            else {
                continue
            }

            values.append(text)
        }

        return values
    }

    private func traversal(
        from rootElement: AXElement,
        maxDepth: Int,
        maxNodes: Int
    ) -> [SlackTraversalNode] {
        var stack: [(element: AXElement, depth: Int)] = [(rootElement, 0)]
        var visitedElements: Set<AXElement> = []
        var nodes: [SlackTraversalNode] = []

        while let current = stack.popLast(),
              nodes.count < maxNodes
        {
            guard visitedElements.contains(current.element) == false else {
                continue
            }

            visitedElements.insert(current.element)

            nodes.append(
                SlackTraversalNode(
                    element: current.element,
                    snapshot: accessibilityTree.snapshot(for: current.element),
                    order: nodes.count
                )
            )

            guard current.depth < maxDepth else {
                continue
            }

            let children = accessibilityTree.children(of: current.element)
            for child in children.reversed() {
                stack.append((child, current.depth + 1))
            }
        }

        return nodes
    }

    private func isPotentialMessageContainer(_ snapshot: SlackAXNodeSnapshot) -> Bool {
        let haystack = [
            snapshot.role,
            snapshot.subrole,
            snapshot.identifier,
            snapshot.description
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return haystack.contains("group")
            || haystack.contains("row")
            || haystack.contains("cell")
            || haystack.contains("message")
    }

    private func isTextRole(_ role: String?) -> Bool {
        guard let role = role?.lowercased() else {
            return false
        }

        return role.contains("statictext")
            || role.contains("text area")
            || role.contains("textarea")
            || role.contains("textfield")
            || role.contains("text field")
    }

    private func isLikelyConversationTitle(_ text: String, role: String?) -> Bool {
        guard text.count <= 120 else {
            return false
        }

        if text.hasPrefix("#") || text.hasPrefix("@") {
            return true
        }

        return role?.caseInsensitiveCompare("AXWindow") == .orderedSame
            && text.caseInsensitiveCompare("Slack") != .orderedSame
    }

    private func isLikelyAuthor(_ text: String) -> Bool {
        text.count <= 80
            && isTimestampLike(text) == false
            && isLikelyNonMessageMetadata(text) == false
    }

    private func isLikelyMessageText(_ text: String) -> Bool {
        text.trimmedSlackText.isEmpty == false
            && isTimestampLike(text) == false
            && isLikelyNonMessageMetadata(text) == false
    }

    private func isLikelyNonMessageMetadata(_ text: String) -> Bool {
        let normalizedText = text.normalizedSlackText

        return normalizedText == "edited"
            || normalizedText == "moreactions"
            || normalizedText == "react"
            || normalizedText == "reply"
            || normalizedText == "thread"
    }

    private func isTimestampLike(_ text: String) -> Bool {
        let trimmedText = text.trimmedSlackText
        let lowercasedText = trimmedText.lowercased()

        if lowercasedText == "today" || lowercasedText == "yesterday" {
            return true
        }

        let timePattern = #"^\d{1,2}:\d{2}\s?(am|pm)?$"#
        return trimmedText.range(
            of: timePattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func date(fromTimestampCandidate text: String) -> Date? {
        ISO8601DateFormatter().date(from: text.trimmedSlackText)
    }
}

struct SystemSlackAXTreeReader: SlackAXTreeReading {
    func snapshot(for element: AXElement) -> SlackAXNodeSnapshot? {
        guard isValidAXElement(element) else {
            return nil
        }

        return SlackAXNodeSnapshot(
            role: stringAttribute("AXRole", from: element),
            subrole: stringAttribute("AXSubrole", from: element),
            title: stringAttribute("AXTitle", from: element),
            value: stringAttribute("AXValue", from: element),
            description: stringAttribute("AXDescription", from: element),
            identifier: stringAttribute("AXIdentifier", from: element)
        )
    }

    func children(of element: AXElement) -> [AXElement] {
        guard isValidAXElement(element),
              let rawChildren = copyAttribute("AXChildren", from: element) as? [AnyObject]
        else {
            return []
        }

        return rawChildren.compactMap { rawChild in
            guard CFGetTypeID(rawChild) == AXUIElementGetTypeID() else {
                return nil
            }

            return AXElement(rawChild)
        }
    }

    func parent(of element: AXElement) -> AXElement? {
        guard isValidAXElement(element),
              let rawParent = copyAttribute("AXParent", from: element),
              CFGetTypeID(rawParent) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return AXElement(rawParent as AnyObject)
    }

    private func stringAttribute(_ attribute: String, from element: AXElement) -> String? {
        guard let value = copyAttribute(attribute, from: element) else {
            return nil
        }

        if let string = value as? String {
            return string
        }

        if let attributedString = value as? NSAttributedString {
            return attributedString.string
        }

        return nil
    }

    private func copyAttribute(_ attribute: String, from element: AXElement) -> CFTypeRef? {
        let axElement = unsafeBitCast(element.rawValue, to: AXUIElement.self)
        var rawValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(axElement, attribute as CFString, &rawValue)

        guard error == .success else {
            return nil
        }

        return rawValue
    }

    private func isValidAXElement(_ element: AXElement) -> Bool {
        CFGetTypeID(element.rawValue) == AXUIElementGetTypeID()
    }
}

private struct SlackTraversalNode {
    var element: AXElement
    var snapshot: SlackAXNodeSnapshot?
    var order: Int
}

private struct SlackTextFragment {
    var text: String
    var order: Int
}

private struct SlackMessageCandidate {
    var author: String?
    var timestamp: Date?
    var text: String
    var order: Int
    var score: Int
}

private extension String {
    var trimmedSlackText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedSlackText: String {
        components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()
    }
}
