import Carbon
import Combine
import Foundation

struct HotKey: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let defaultValue = HotKey(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    var displayName: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyNames[keyCode] ?? "Key \(keyCode)")
        return parts.joined()
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_Space): "Space", UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Return): "Return",
    ]
}

@MainActor
final class GlobalHotKeyController: ObservableObject {
    @Published private(set) var currentHotKey: HotKey
    @Published private(set) var registrationError: String?

    private enum DefaultsKey {
        static let keyCode = "globalHotKey.keyCode"
        static let modifiers = "globalHotKey.modifiers"
    }

    private static let hotKeySignature: OSType = 0x4B_50_73_74 // KPst
    private let userDefaults: UserDefaults
    private let action: () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var nextRegistrationID: UInt32 = 1

    init(
        userDefaults: UserDefaults = .standard,
        action: @escaping () -> Void
    ) {
        self.userDefaults = userDefaults
        self.action = action
        currentHotKey = Self.storedHotKey(in: userDefaults) ?? .defaultValue

        installEventHandler()
        registerInitialHotKey()
    }

    isolated deinit {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }

    @discardableResult
    func updateHotKey(_ candidate: HotKey) -> Bool {
        guard candidate != currentHotKey || hotKeyReference == nil else {
            registrationError = nil
            return true
        }

        var newReference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            candidate.keyCode,
            candidate.modifiers,
            nextHotKeyID(),
            GetApplicationEventTarget(),
            0,
            &newReference
        )

        guard status == noErr, let newReference else {
            registrationError = "This shortcut is already in use by another application."
            return false
        }

        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        hotKeyReference = newReference
        currentHotKey = candidate
        registrationError = nil
        store(candidate)
        return true
    }

    private func registerInitialHotKey() {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            currentHotKey.keyCode,
            currentHotKey.modifiers,
            nextHotKeyID(),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            hotKeyReference = reference
            registrationError = nil
            store(currentHotKey)
        } else {
            registrationError = "The saved shortcut could not be registered."
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        if status != noErr {
            registrationError = "PasteList could not install the global shortcut handler."
        }
    }

    private func handleHotKeyEvent() {
        action()
    }

    private func store(_ hotKey: HotKey) {
        userDefaults.set(Int(hotKey.keyCode), forKey: DefaultsKey.keyCode)
        userDefaults.set(Int(hotKey.modifiers), forKey: DefaultsKey.modifiers)
    }

    private func nextHotKeyID() -> EventHotKeyID {
        defer { nextRegistrationID &+= 1 }
        return EventHotKeyID(
            signature: Self.hotKeySignature,
            id: nextRegistrationID
        )
    }

    private static func storedHotKey(in defaults: UserDefaults) -> HotKey? {
        guard
            defaults.object(forKey: DefaultsKey.keyCode) != nil,
            defaults.object(forKey: DefaultsKey.modifiers) != nil
        else {
            return nil
        }
        return HotKey(
            keyCode: UInt32(defaults.integer(forKey: DefaultsKey.keyCode)),
            modifiers: UInt32(defaults.integer(forKey: DefaultsKey.modifiers))
        )
    }

    private static let eventHandler: EventHandlerUPP = {
        _, _, userData in
        guard let userData else {
            return OSStatus(eventNotHandledErr)
        }
        let controller = Unmanaged<GlobalHotKeyController>
            .fromOpaque(userData)
            .takeUnretainedValue()
        MainActor.assumeIsolated {
            controller.handleHotKeyEvent()
        }
        return noErr
    }
}
