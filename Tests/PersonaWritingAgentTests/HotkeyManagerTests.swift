import Carbon
import XCTest
@testable import PersonaWritingAgent

final class HotkeyManagerTests: XCTestCase {
    func testRunActiveAgentsHotkeyConfigMatchesMVPShortcut() {
        let config = HotkeyConfig.runActiveAgents

        XCTAssertEqual(config.keyCode, UInt32(kVK_ANSI_O))
        XCTAssertTrue(config.modifiers.contains(.control))
        XCTAssertTrue(config.modifiers.contains(.command))
        XCTAssertEqual(config.displayName, "Control + Command + O")
    }

    func testStartRegistersHotkeyWithoutUsingSystemRegistrar() throws {
        let registrar = FakeHotkeyRegistrar()
        let manager = HotkeyManager(registrar: registrar)
        var triggerCount = 0

        try manager.start(config: .runActiveAgents) {
            triggerCount += 1
        }

        XCTAssertEqual(registrar.registeredConfigs, [.runActiveAgents])
        XCTAssertEqual(manager.registeredConfig, .runActiveAgents)

        registrar.triggerLastRegistration()

        XCTAssertEqual(triggerCount, 1)
    }

    func testRestartUnregistersPreviousHotkey() throws {
        let registrar = FakeHotkeyRegistrar()
        let manager = HotkeyManager(registrar: registrar)

        try manager.start(config: .runActiveAgents) {}
        let firstRegistration = try XCTUnwrap(registrar.registrations.first)

        try manager.start(config: .runActiveAgents) {}

        XCTAssertTrue(firstRegistration.isUnregistered)
        XCTAssertEqual(registrar.registeredConfigs, [.runActiveAgents, .runActiveAgents])
        XCTAssertEqual(registrar.registrations.count, 2)
    }

    func testStopUnregistersActiveHotkey() throws {
        let registrar = FakeHotkeyRegistrar()
        let manager = HotkeyManager(registrar: registrar)

        try manager.start(config: .runActiveAgents) {}
        let registration = try XCTUnwrap(registrar.registrations.first)

        manager.stop()

        XCTAssertTrue(registration.isUnregistered)
        XCTAssertNil(manager.registeredConfig)
    }

    func testFailedStartLeavesManagerUnregistered() {
        let registrar = FakeHotkeyRegistrar()
        registrar.errorToThrow = TestHotkeyError.registrationFailed
        let manager = HotkeyManager(registrar: registrar)

        XCTAssertThrowsError(
            try manager.start(config: .runActiveAgents) {}
        ) { error in
            XCTAssertEqual(error as? TestHotkeyError, .registrationFailed)
        }
        XCTAssertNil(manager.registeredConfig)
    }
}

private enum TestHotkeyError: Error, Equatable {
    case registrationFailed
}

private final class FakeHotkeyRegistrar: HotkeyRegistering {
    var registeredConfigs: [HotkeyConfig] = []
    var registrations: [FakeHotkeyRegistration] = []
    var handlers: [() -> Void] = []
    var errorToThrow: Error?

    func registerHotkey(
        _ config: HotkeyConfig,
        onTriggered: @escaping () -> Void
    ) throws -> HotkeyRegistration {
        if let errorToThrow {
            throw errorToThrow
        }

        let registration = FakeHotkeyRegistration()
        registeredConfigs.append(config)
        registrations.append(registration)
        handlers.append(onTriggered)
        return registration
    }

    func triggerLastRegistration() {
        handlers.last?()
    }
}

private final class FakeHotkeyRegistration: HotkeyRegistration {
    private(set) var isUnregistered = false

    func unregister() {
        isUnregistered = true
    }
}
