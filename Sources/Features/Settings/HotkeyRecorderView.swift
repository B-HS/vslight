import AppKit
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var hotkey: Hotkey?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(isRecording ? "키 입력..." : (hotkey?.displayString ?? "단축키 없음"))
                    .font(.caption.monospaced())
                    .frame(minWidth: 92)
            }
            .buttonStyle(.bordered)

            if hotkey != nil {
                Button {
                    hotkey = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("단축키 지우기")
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        guard monitor == nil else {
            return
        }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let modifiers = Hotkey.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else {
                NSSound.beep()
                return nil
            }
            hotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
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
