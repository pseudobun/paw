import Carbon.HIToolbox
import PawCore

/// Carbon `RegisterEventHotKey`: no permission needed. Each instance owns one hotkey.
final class GlobalHotkey {
    private static var nextID: UInt32 = 1

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        self.onPress = onPress
    }

    deinit { unregister() }

    @discardableResult
    func register(_ spec: HotkeySpec) -> Bool {
        unregister()
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard status == noErr, pressed.signature == GlobalHotkey.signature else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            guard pressed.id == hotkey.id else { return OSStatus(eventNotHandledErr) }
            hotkey.onPress()
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventSpec,
                                         Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        let hotKeyID = EventHotKeyID(signature: GlobalHotkey.signature, id: id)
        return RegisterEventHotKey(spec.keyCode, spec.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    private static let signature = OSType(0x7061_7721) // 'paw!'
}
