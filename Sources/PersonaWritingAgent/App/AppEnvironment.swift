import AppKit

struct AppEnvironment {
    typealias DashboardFactory = () -> DashboardWindowController
    typealias StatusBarFactory = (
        StatusBarController.Actions,
        [StatusBarController.ActiveAgentEntry]
    ) -> StatusBarController

    var agentProfileStore: AgentProfileStore
    var llmProviderStore: LLMProviderStore
    var memoryStore: AgentMemoryStore
    var apiKeyStore: any LLMProviderAPIKeyStoring
    var dashboardDependencies: DashboardDependencies
    var permissionCoordinator: PermissionCoordinator
    var hotkeyRegistrar: any HotkeyRegistering
    var runActiveAgentsCoordinator: any RunActiveAgentsCoordinating
    var activeAgentRunTaskController: any ActiveAgentRunTaskControlling
    var logger: SafeLogger
    var makeDashboardWindowController: DashboardFactory
    var makeStatusBarController: StatusBarFactory
    var terminateApplication: () -> Void

    static func live() -> AppEnvironment {
        let agentProfileStore = AgentProfileStore.defaultStore
        let llmProviderStore = LLMProviderStore()
        let memoryStore = AgentMemoryStore.defaultStore
        let apiKeyStore = KeychainStore()
        let dashboardDependencies = DashboardDependencies(
            agentProfileStore: agentProfileStore,
            llmProviderStore: llmProviderStore,
            apiKeyStore: apiKeyStore
        )
        let logger = SafeLogger.default
        let textSession = AccessibilityPreparingInputCapture(
            preparer: FocusedApplicationAccessibilityPreparer(logger: logger.log),
            baseCapture: FocusedTextSession()
        )
        let requestFactory = AgentRunRequestFactory(
            textSession: textSession,
            agentProfileStore: agentProfileStore,
            memoryStore: memoryStore,
            contextResolver: AppContextAdapterRegistry()
        )
        let correctionEngine = CorrectionEngine(
            providerConfigLoader: SeededLLMProviderConfigLoader(providerStore: llmProviderStore),
            apiKeyStore: apiKeyStore,
            llmProvider: OpenAICompatibleProvider(),
            responseCache: SQLiteLLMResponseCache()
        )
        let runActiveAgentsCoordinator = RunActiveAgentsCoordinator(
            requestFactory: requestFactory,
            correctionEngine: correctionEngine,
            overlayPresenter: OverlayController(),
            suggestionApplyCoordinator: SuggestionApplyCoordinator(),
            privacyOptions: AgentRunPrivacyOptions(allowClipboardFallback: true),
            logger: logger.log
        )
        let activeAgentRunTaskController = ActiveAgentRunTaskController(
            coordinator: runActiveAgentsCoordinator
        )

        return AppEnvironment(
            agentProfileStore: agentProfileStore,
            llmProviderStore: llmProviderStore,
            memoryStore: memoryStore,
            apiKeyStore: apiKeyStore,
            dashboardDependencies: dashboardDependencies,
            permissionCoordinator: PermissionCoordinator(),
            hotkeyRegistrar: CarbonHotkeyRegistrar(),
            runActiveAgentsCoordinator: runActiveAgentsCoordinator,
            activeAgentRunTaskController: activeAgentRunTaskController,
            logger: logger,
            makeDashboardWindowController: {
                DashboardWindowController(dependencies: dashboardDependencies)
            },
            makeStatusBarController: { actions, activeAgentEntries in
                StatusBarController(
                    actions: actions,
                    activeAgentEntries: activeAgentEntries
                )
            },
            terminateApplication: {
                NSApp.terminate(nil)
            }
        )
    }
}
