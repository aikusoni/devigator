import Carbon.HIToolbox
import Foundation

struct HotKeyBinding: Codable, Equatable {
    static let defaultsKey = "globalHotKeyBinding"

    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String

    static var saved: HotKeyBinding {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data) {
            return binding
        }

        // Migrate the preset-only setting used by Devigator 0.1.
        if let rawValue = UserDefaults.standard.string(forKey: "globalShortcutPreset"),
           let preset = GlobalShortcutPreset(rawValue: rawValue) {
            return preset.binding
        }
        return GlobalShortcutPreset.optionShiftSpace.binding
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    var displayKeys: [String] {
        var keys: [String] = []
        if modifiers & UInt32(controlKey) != 0 { keys.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { keys.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { keys.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { keys.append("⌘") }
        keys.append(keyLabel)
        return keys
    }

    var displayName: String {
        let modifiers = displayKeys.dropLast().joined()
        let key = keyLabel == "SPACE" ? " Space" : keyLabel
        return modifiers + key
    }
}

enum GlobalShortcutPreset: String, CaseIterable, Identifiable {
    case optionShiftSpace
    case controlShiftSpace
    case controlOptionSpace
    case controlOptionSlash

    var id: String { rawValue }

    var binding: HotKeyBinding {
        switch self {
        case .optionShiftSpace:
            return HotKeyBinding(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(optionKey | shiftKey),
                keyLabel: "SPACE"
            )
        case .controlShiftSpace:
            return HotKeyBinding(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(controlKey | shiftKey),
                keyLabel: "SPACE"
            )
        case .controlOptionSpace:
            return HotKeyBinding(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(controlKey | optionKey),
                keyLabel: "SPACE"
            )
        case .controlOptionSlash:
            return HotKeyBinding(
                keyCode: UInt32(kVK_ANSI_Slash),
                modifiers: UInt32(controlKey | optionKey),
                keyLabel: "/"
            )
        }
    }
}

final class GlobalHotKey {
    typealias Handler = () -> Void

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit {
        unregister()
    }

    func register(_ shortcut: HotKeyBinding) throws {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.handler() }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )
        guard status == noErr else { throw HotKeyError.registrationFailed(status) }

        let hotKeyID = EventHotKeyID(signature: fourCharacterCode("DVGT"), id: 1)
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            unregister()
            throw HotKeyError.registrationFailed(registerStatus)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }

    enum HotKeyError: LocalizedError {
        case registrationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .registrationFailed(let status):
                return "전역 단축키를 등록하지 못했습니다. (OSStatus \(status))"
            }
        }
    }
}
