import AppKit
import Carbon
import Foundation

enum HotkeyTarget: Hashable {
    case app(Int)
    case scene(Int)
}

final class HotkeyManager {
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var hotKeyIdToTarget: [UInt32: HotkeyTarget] = [:]
    private var nextId: UInt32 = 1
    private var handlerInstalled = false
    private var handlerInstallationError: OSStatus?
    private let onTrigger: (HotkeyTarget) -> Void

    init(onTrigger: @escaping (HotkeyTarget) -> Void) {
        self.onTrigger = onTrigger
        installHandlerIfNeeded()
    }

    func register(apps: [AppEntry], scenes: [SceneEntry]) -> [String] {
        unregisterAll()
        var issues: [String] = []

        if let handlerInstallationError {
            issues.append("The global hotkey handler could not be installed (error \(handlerInstallationError)).")
        }

        for app in apps {
            if app.hotkey.keyCode < 0 {
                continue
            }
            if let status = registerHotkey(app.hotkey, target: .app(app.id)) {
                if status == eventHotKeyExistsErr {
                    issues.append("\(app.name): \(app.hotkey.displayString) is already used by another app.")
                } else {
                    issues.append("\(app.name): \(app.hotkey.displayString) could not be registered (error \(status)).")
                }
            }
        }
        for scene in scenes where scene.hotkey.keyCode >= 0 {
            if let status = registerHotkey(scene.hotkey, target: .scene(scene.id)) {
                if status == eventHotKeyExistsErr {
                    issues.append("\(scene.name): \(scene.hotkey.displayString) is already used by another app or scene.")
                } else {
                    issues.append("\(scene.name): \(scene.hotkey.displayString) could not be registered (error \(status)).")
                }
            }
        }
        return issues
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        hotKeyIdToTarget.removeAll()
        nextId = 1
    }

    private func registerHotkey(_ hotkey: Hotkey, target: HotkeyTarget) -> OSStatus? {
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: nextId)
        var ref: EventHotKeyRef?
        let modifiers = carbonModifiers(from: hotkey.modifierFlags)
        let status = RegisterEventHotKey(UInt32(hotkey.keyCode), modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs[hotKeyID.id] = ref
            hotKeyIdToTarget[hotKeyID.id] = target
            nextId += 1
            return nil
        }
        return status
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotKey(id: hotKeyID.id)
            }
            return noErr
        }
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventType, selfPtr, nil)
        if status == noErr {
            handlerInstalled = true
        } else {
            handlerInstallationError = status
        }
    }

    private func handleHotKey(id: UInt32) {
        guard let target = hotKeyIdToTarget[id] else { return }
        DispatchQueue.main.async { [onTrigger] in
            onTrigger(target)
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0
        if flags.contains(.command) {
            carbonFlags |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            carbonFlags |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            carbonFlags |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            carbonFlags |= UInt32(shiftKey)
        }
        return carbonFlags
    }
}

private let hotKeySignature: OSType = 0x4D4C4155
