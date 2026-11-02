import Carbon.HIToolbox
import Foundation

/// Global shortcut via Carbon `RegisterEventHotKey`, which doesn't need Accessibility permission.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onTrigger: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(_ preset: HotKeyPreset) {
        unregister()
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HotKeyManager.shared.onTrigger?() }
                }
                return noErr
            }, 1, &spec, nil, &handlerRef)
        }
        let id = EventHotKeyID(signature: OSType(0x4E_54_43_48), id: 1)
        RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}

extension HotKeyPreset {
    var keyCode: UInt32 {
        switch self {
        case .optionN, .controlOptionN, .commandShiftN: return UInt32(kVK_ANSI_N)
        case .optionSpace: return UInt32(kVK_Space)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionN, .optionSpace: return UInt32(optionKey)
        case .controlOptionN: return UInt32(controlKey | optionKey)
        case .commandShiftN: return UInt32(cmdKey | shiftKey)
        }
    }
}
