import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalHotKeyManager {
    private enum HotKeyID: UInt32 {
        case toggleVisibility = 1
        case toggleGhostMode = 2
        case toggleExpand = 3
    }

    private let signature: OSType = 0x4147_4844 // 'AGHD'
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?

    var onToggleVisibility: (() -> Void)?
    var onToggleGhostMode: (() -> Void)?
    var onToggleExpand: (() -> Void)?

    init() {
        installHandler()
        registerHotKeys()
    }

    deinit {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else {
                    return status
                }
                let rawId = hotKeyID.id
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.handleHotKey(id: rawId)
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
    }

    private func registerHotKeys() {
        let cmdShift = UInt32(cmdKey | shiftKey)
        register(keyCode: UInt32(kVK_ANSI_H), modifiers: cmdShift, id: .toggleVisibility)
        register(keyCode: UInt32(kVK_ANSI_G), modifiers: cmdShift, id: .toggleGhostMode)
        register(keyCode: UInt32(kVK_ANSI_E), modifiers: cmdShift, id: .toggleExpand)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: HotKeyID) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
        }
    }

    private func handleHotKey(id: UInt32) {
        switch HotKeyID(rawValue: id) {
        case .toggleVisibility:
            onToggleVisibility?()
        case .toggleGhostMode:
            onToggleGhostMode?()
        case .toggleExpand:
            onToggleExpand?()
        case .none:
            break
        }
    }
}
