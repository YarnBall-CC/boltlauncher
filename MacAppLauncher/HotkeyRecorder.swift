import AppKit
import SwiftUI

struct HotkeyRecorder: View {
    let hotkey: Hotkey
    let onUpdate: (Hotkey) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? "Recording..." : hotkey.displayString) {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }
        .accessibilityLabel(isRecording ? "Recording hotkey" : "Hotkey \(hotkey.displayString)")
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let newHotkey = Hotkey(keyCode: Int(event.keyCode), modifiers: Int(modifiers.rawValue))
            onUpdate(newHotkey)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
