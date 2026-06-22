protocol HotkeyRegistration: AnyObject {
    func unregister()
}

protocol HotkeyRegistering: AnyObject {
    func registerHotkey(
        _ config: HotkeyConfig,
        onTriggered: @escaping () -> Void
    ) throws -> HotkeyRegistration
}

final class HotkeyManager {
    private let registrar: HotkeyRegistering
    private var registration: HotkeyRegistration?

    private(set) var registeredConfig: HotkeyConfig?

    init(registrar: HotkeyRegistering = CarbonHotkeyRegistrar()) {
        self.registrar = registrar
    }

    deinit {
        stop()
    }

    func start(
        config: HotkeyConfig = .runActiveAgents,
        onTriggered: @escaping () -> Void
    ) throws {
        stop()

        registration = try registrar.registerHotkey(config, onTriggered: onTriggered)
        registeredConfig = config
    }

    func stop() {
        registration?.unregister()
        registration = nil
        registeredConfig = nil
    }
}
