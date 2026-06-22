import ApplicationServices
import Foundation

struct ChannelTalkAXNode: Equatable {
    var role: String?
    var subrole: String?
    var value: String?
    var title: String?
    var label: String?
    var children: [ChannelTalkAXNode]

    init(
        role: String? = nil,
        subrole: String? = nil,
        value: String? = nil,
        title: String? = nil,
        label: String? = nil,
        children: [ChannelTalkAXNode] = []
    ) {
        self.role = role
        self.subrole = subrole
        self.value = value
        self.title = title
        self.label = label
        self.children = children
    }
}

protocol ChannelTalkAXTreeReading {
    func tree(rootedAt element: AXElement) -> ChannelTalkAXNode?
}

struct ChannelTalkContextAdapter: AppContextAdapter {
    static var bundleID: String {
        KnownAppCatalog.defaultCatalog.primaryBundleID(for: .channelTalk) ?? ""
    }

    var supportedBundleIDs: Set<String> {
        KnownAppCatalog.defaultCatalog.bundleIDs(for: .channelTalk)
    }

    private let treeReader: any ChannelTalkAXTreeReading
    private let messageIDFactory: () -> UUID

    init(
        treeReader: any ChannelTalkAXTreeReading = SystemChannelTalkAXTreeReader(),
        messageIDFactory: @escaping () -> UUID = UUID.init
    ) {
        self.treeReader = treeReader
        self.messageIDFactory = messageIDFactory
    }

    func extractContext(for request: AppContextExtractionRequest) -> ConversationContext? {
        guard request.includeConversationContext else {
            return nil
        }

        guard KnownAppCatalog.defaultCatalog.definition(for: .channelTalk)?.matches(bundleID: request.sourceBundleID) == true else {
            return nil
        }

        guard let focusedElement = request.focusedElement,
              let rootNode = treeReader.tree(rootedAt: focusedElement.element) else {
            return nil
        }

        let candidates = extractMessageCandidates(from: rootNode)
        let limitedCandidates = request.maxVisibleMessages > 0
            ? Array(candidates.suffix(request.maxVisibleMessages))
            : []

        return ConversationContext(
            appBundleID: Self.bundleID,
            conversationTitle: conversationTitle(from: rootNode),
            visibleMessages: limitedCandidates.map { candidate in
                ConversationMessage(
                    id: messageIDFactory(),
                    author: candidate.author,
                    timestamp: candidate.timestamp,
                    text: candidate.text
                )
            }
        )
    }

    private func extractMessageCandidates(from node: ChannelTalkAXNode) -> [MessageCandidate] {
        if let candidate = messageCandidate(fromContainer: node) {
            return [candidate]
        }

        let childCandidates = node.children.flatMap { extractMessageCandidates(from: $0) }
        if childCandidates.isEmpty == false {
            return childCandidates
        }

        if let leafCandidate = messageCandidate(fromTextLeaf: node) {
            return [leafCandidate]
        }

        return []
    }

    private func messageCandidate(fromContainer node: ChannelTalkAXNode) -> MessageCandidate? {
        guard isMessageContainerRole(node.role) else {
            return nil
        }

        let directFragments = directTextFragments(in: node)
        if directFragments.count >= 2,
           let candidate = messageCandidate(from: directFragments) {
            return candidate
        }

        guard isRowLikeRole(node.role) else {
            return nil
        }

        let recursiveFragments = recursiveTextFragments(in: node)
        guard recursiveFragments.count <= 6 else {
            return nil
        }

        return messageCandidate(from: recursiveFragments)
    }

    private func messageCandidate(fromTextLeaf node: ChannelTalkAXNode) -> MessageCandidate? {
        guard node.children.isEmpty,
              isTextRole(node.role),
              let text = displayText(for: node),
              looksLikeTimestamp(text) == false,
              isLikelyUIChromeText(text) == false else {
            return nil
        }

        return MessageCandidate(author: nil, timestamp: nil, text: text)
    }

    private func messageCandidate(from fragments: [String]) -> MessageCandidate? {
        let normalizedFragments = fragments.compactMap(normalizedText)
        guard normalizedFragments.isEmpty == false else {
            return nil
        }

        var timestamp: Date?
        var timestampIndex: Int?
        for (index, fragment) in normalizedFragments.enumerated() where looksLikeTimestamp(fragment) {
            timestampIndex = index
            timestamp = parseTimestamp(fragment)
            break
        }

        var authorIndex: Int?
        if normalizedFragments.count >= 2 {
            let possibleAuthorIndex = normalizedFragments.indices.first { index in
                index != timestampIndex && isLikelyAuthor(normalizedFragments[index])
            }

            if let possibleAuthorIndex {
                let remainingText = normalizedFragments.indices.contains { index in
                    index != timestampIndex && index != possibleAuthorIndex
                }

                if remainingText {
                    authorIndex = possibleAuthorIndex
                }
            }
        }

        let textFragments = normalizedFragments.enumerated().compactMap { index, fragment -> String? in
            guard index != timestampIndex, index != authorIndex else {
                return nil
            }

            return fragment
        }

        guard textFragments.isEmpty == false else {
            return nil
        }

        let text = textFragments.joined(separator: "\n")
        guard isLikelyUIChromeText(text) == false else {
            return nil
        }

        return MessageCandidate(
            author: authorIndex.map { normalizedFragments[$0] },
            timestamp: timestamp,
            text: text
        )
    }

    private func directTextFragments(in node: ChannelTalkAXNode) -> [String] {
        node.children.compactMap { child in
            guard isTextRole(child.role) else {
                return nil
            }

            return displayText(for: child)
        }
    }

    private func recursiveTextFragments(in node: ChannelTalkAXNode) -> [String] {
        var fragments: [String] = []

        if isTextRole(node.role),
           let text = displayText(for: node) {
            fragments.append(text)
        }

        for child in node.children {
            fragments.append(contentsOf: recursiveTextFragments(in: child))
        }

        return fragments
    }

    private func displayText(for node: ChannelTalkAXNode) -> String? {
        [node.value, node.title, node.label]
            .compactMap { $0 }
            .compactMap(normalizedText)
            .first
    }

    private func conversationTitle(from node: ChannelTalkAXNode) -> String? {
        if let title = normalizedText(node.title),
           looksLikeTimestamp(title) == false,
           isLikelyUIChromeText(title) == false {
            return title
        }

        for child in node.children {
            if let title = conversationTitle(from: child) {
                return title
            }
        }

        return nil
    }

    private func isMessageContainerRole(_ role: String?) -> Bool {
        guard let role else {
            return false
        }

        return ["AXGroup", "AXRow", "AXCell", "AXListItem"].contains(role)
    }

    private func isRowLikeRole(_ role: String?) -> Bool {
        guard let role else {
            return false
        }

        return ["AXRow", "AXCell", "AXListItem"].contains(role)
    }

    private func isTextRole(_ role: String?) -> Bool {
        guard let role else {
            return false
        }

        return ["AXStaticText", "AXTextArea", "AXTextField"].contains(role)
    }

    private func normalizedText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let normalized = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }

    private func isLikelyAuthor(_ text: String) -> Bool {
        guard looksLikeTimestamp(text) == false,
              text.count <= 80,
              text.contains("\n") == false,
              text.range(of: #"[.!?]$"#, options: .regularExpression) == nil else {
            return false
        }

        return text.split(separator: " ").count <= 8
    }

    private func looksLikeTimestamp(_ text: String) -> Bool {
        if parseTimestamp(text) != nil {
            return true
        }

        let patterns = [
            #"^\d{1,2}:\d{2}(\s?[APap][Mm])?$"#,
            #"^\d{4}[-/.]\d{1,2}[-/.]\d{1,2}"#,
            #"^(today|yesterday)$"#,
            #"\b(ago|AM|PM|am|pm)\b"#
        ]

        return patterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func parseTimestamp(_ text: String) -> Date? {
        if let date = Self.iso8601DateFormatter.date(from: text) {
            return date
        }

        return Self.timestampDateFormatters.lazy.compactMap { formatter in
            formatter.date(from: text)
        }.first
    }

    private func isLikelyUIChromeText(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        return [
            "send",
            "search",
            "message",
            "type a message",
            "write a message"
        ].contains(lowercased)
    }

    private static let iso8601DateFormatter = ISO8601DateFormatter()

    private static let timestampDateFormatters: [DateFormatter] = [
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd h:mm a",
        "yyyy/MM/dd HH:mm",
        "yyyy.MM.dd HH:mm"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}

private struct MessageCandidate: Equatable {
    var author: String?
    var timestamp: Date?
    var text: String
}

final class SystemChannelTalkAXTreeReader: ChannelTalkAXTreeReading {
    private let maxDepth: Int
    private let maxNodes: Int

    init(maxDepth: Int = 12, maxNodes: Int = 1_000) {
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
    }

    func tree(rootedAt element: AXElement) -> ChannelTalkAXNode? {
        var remainingNodes = maxNodes
        return node(for: element, depth: 0, remainingNodes: &remainingNodes)
    }

    private func node(for element: AXElement, depth: Int, remainingNodes: inout Int) -> ChannelTalkAXNode? {
        guard depth <= maxDepth, remainingNodes > 0 else {
            return nil
        }

        guard isValidAXUIElement(element) else {
            return nil
        }

        remainingNodes -= 1

        return ChannelTalkAXNode(
            role: stringAttribute(kAXRoleAttribute, from: element),
            subrole: stringAttribute(kAXSubroleAttribute, from: element),
            value: stringAttribute(kAXValueAttribute, from: element),
            title: stringAttribute(kAXTitleAttribute, from: element),
            label: stringAttribute(kAXDescriptionAttribute, from: element),
            children: childElements(of: element).compactMap { child in
                node(for: child, depth: depth + 1, remainingNodes: &remainingNodes)
            }
        )
    }

    private func isValidAXUIElement(_ element: AXElement) -> Bool {
        CFGetTypeID(element.rawValue) == AXUIElementGetTypeID()
    }

    private func stringAttribute(_ attribute: String, from element: AXElement) -> String? {
        guard let rawValue = copyAttribute(attribute, from: element) else {
            return nil
        }

        if let string = rawValue as? String {
            return string
        }

        if let attributedString = rawValue as? NSAttributedString {
            return attributedString.string
        }

        return nil
    }

    private func childElements(of element: AXElement) -> [AXElement] {
        guard let rawValue = copyAttribute(kAXChildrenAttribute, from: element),
              let rawChildren = rawValue as? [AnyObject] else {
            return []
        }

        return rawChildren.map(AXElement.init)
    }

    private func copyAttribute(_ attribute: String, from element: AXElement) -> CFTypeRef? {
        guard isValidAXUIElement(element) else {
            return nil
        }

        let axElement = unsafeBitCast(element.rawValue, to: AXUIElement.self)
        var rawValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(axElement, attribute as CFString, &rawValue)

        guard error == .success else {
            return nil
        }

        return rawValue
    }
}
