import AppKit
import Carbon
import TokcatKit

/// Carbon hotkeys work across apps without Accessibility or Input Monitoring
/// permission, and report a failure when another hotkey owns the combination.
@MainActor
final class LauncherHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    func register(_ shortcut: LauncherShortcut) -> OSStatus {
        unregister()
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x544B4C52, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            MainActor.assumeIsolated {
                Unmanaged<LauncherHotKey>.fromOpaque(context).takeUnretainedValue().onPress?()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return installed }
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: 0x544B4C52, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { unregister() }
        return status
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
