import Carbon
import Foundation

enum HotkeyRegistrationError: Error, Equatable, LocalizedError {
    case eventHandlerInstallFailed(OSStatus)
    case hotkeyRegistrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .eventHandlerInstallFailed(status):
            return "Failed to install hotkey event handler with OSStatus \(status)."
        case let .hotkeyRegistrationFailed(status):
            return "Failed to register global hotkey with OSStatus \(status)."
        }
    }
}

final class CarbonHotkeyRegistrar: HotkeyRegistering {
    private static let signature: OSType = 0x5057_4148
    private static let eventHandler: EventHandlerUPP = { _, eventRef, userData in
        guard let eventRef, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        let registrar = Unmanaged<CarbonHotkeyRegistrar>
            .fromOpaque(userData)
            .takeUnretainedValue()

        var hotkeyID = EventHotKeyID(signature: 0, id: 0)
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        guard status == noErr else {
            return status
        }

        registrar.triggerHotkey(identifier: hotkeyID.id)
        return noErr
    }

    private var callbacks: [UInt32: () -> Void] = [:]
    private var nextIdentifier: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?

    deinit {
        callbacks.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func registerHotkey(
        _ config: HotkeyConfig,
        onTriggered: @escaping () -> Void
    ) throws -> HotkeyRegistration {
        try installEventHandlerIfNeeded()

        let identifier = allocateIdentifier()
        let eventHotkeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            config.keyCode,
            config.modifiers.rawValue,
            eventHotkeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotkeyRef
        )

        guard status == noErr, let hotkeyRef else {
            throw HotkeyRegistrationError.hotkeyRegistrationFailed(status)
        }

        callbacks[identifier] = onTriggered

        return CarbonHotkeyRegistration(
            hotkeyRef: hotkeyRef,
            identifier: identifier,
            unregisterCallback: { [weak self] identifier in
                self?.callbacks[identifier] = nil
            }
        )
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handlerRef: EventHandlerRef?

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        guard status == noErr, let handlerRef else {
            throw HotkeyRegistrationError.eventHandlerInstallFailed(status)
        }

        eventHandlerRef = handlerRef
    }

    private func allocateIdentifier() -> UInt32 {
        while callbacks[nextIdentifier] != nil {
            advanceIdentifier()
        }

        let identifier = nextIdentifier
        advanceIdentifier()
        return identifier
    }

    private func advanceIdentifier() {
        nextIdentifier = nextIdentifier == UInt32.max ? 1 : nextIdentifier + 1
    }

    private func triggerHotkey(identifier: UInt32) {
        guard let callback = callbacks[identifier] else {
            return
        }

        if Thread.isMainThread {
            callback()
        } else {
            DispatchQueue.main.async(execute: callback)
        }
    }
}

private final class CarbonHotkeyRegistration: HotkeyRegistration {
    private var hotkeyRef: EventHotKeyRef?
    private let identifier: UInt32
    private let unregisterCallback: (UInt32) -> Void
    private var isUnregistered = false

    init(
        hotkeyRef: EventHotKeyRef,
        identifier: UInt32,
        unregisterCallback: @escaping (UInt32) -> Void
    ) {
        self.hotkeyRef = hotkeyRef
        self.identifier = identifier
        self.unregisterCallback = unregisterCallback
    }

    deinit {
        unregister()
    }

    func unregister() {
        guard !isUnregistered else {
            return
        }

        isUnregistered = true

        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }

        unregisterCallback(identifier)
    }
}
