import Foundation

struct AppContextExtractionRequest: Equatable {
    var snapshot: TextSnapshot
    var focusedElement: AXFocusedElement?
    var includeConversationContext: Bool
    var maxVisibleMessages: Int

    init(
        snapshot: TextSnapshot,
        focusedElement: AXFocusedElement? = nil,
        includeConversationContext: Bool = false,
        maxVisibleMessages: Int = 0
    ) {
        self.snapshot = snapshot
        self.focusedElement = focusedElement
        self.includeConversationContext = includeConversationContext
        self.maxVisibleMessages = max(0, maxVisibleMessages)
    }

    var sourceBundleID: String {
        snapshot.sourceBundleID
    }
}

protocol AppContextAdapter {
    var supportedBundleIDs: Set<String> { get }

    func extractContext(for request: AppContextExtractionRequest) throws -> ConversationContext?
}

struct GenericAXContextAdapter: AppContextAdapter {
    var supportedBundleIDs: Set<String> {
        []
    }

    func extractContext(for request: AppContextExtractionRequest) -> ConversationContext? {
        nil
    }
}

struct AppContextAdapterRegistry {
    static var defaultAdapters: [any AppContextAdapter] {
        [
            SlackContextAdapter(),
            ChannelTalkContextAdapter()
        ]
    }

    private let adaptersByBundleID: [String: any AppContextAdapter]
    private let fallbackAdapter: any AppContextAdapter

    init(
        adapters: [any AppContextAdapter] = Self.defaultAdapters,
        fallbackAdapter: any AppContextAdapter = GenericAXContextAdapter()
    ) {
        self.adaptersByBundleID = adapters.reduce(into: [:]) { registeredAdapters, adapter in
            for bundleID in adapter.supportedBundleIDs {
                let normalizedBundleID = BundleIdentifier.lookupKey(for: bundleID)
                guard normalizedBundleID.isEmpty == false else {
                    continue
                }

                registeredAdapters[normalizedBundleID] = adapter
            }
        }
        self.fallbackAdapter = fallbackAdapter
    }

    func adapter(for bundleID: String) -> any AppContextAdapter {
        adaptersByBundleID[BundleIdentifier.lookupKey(for: bundleID)] ?? fallbackAdapter
    }

    func context(for request: AppContextExtractionRequest) -> ConversationContext? {
        guard request.includeConversationContext else {
            return nil
        }

        do {
            return try adapter(for: request.sourceBundleID).extractContext(for: request)
        } catch {
            return nil
        }
    }

}
