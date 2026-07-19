import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        if appStore.apps.isEmpty {
            Text("No apps configured")
                .padding(.vertical, 4)
        } else {
            ForEach(appStore.apps) { app in
                Button {
                    appStore.launch(app: app)
                } label: {
                    if app.requiresAuthorization {
                        Label("\(app.name) — Access Required", systemImage: "lock.trianglebadge.exclamationmark")
                    } else {
                        Text("\(app.name) (\(app.launchCount))")
                    }
                }
            }
        }

        Divider()

        Button("Settings...") {
            SettingsWindowController.shared.show(appStore: appStore)
        }

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .alert(item: $appStore.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    func show(appStore: AppStore) {
        if window == nil {
            window = buildWindow(appStore: appStore)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow(appStore: AppStore) -> NSWindow {
        let content = NSHostingView(
            rootView: AnyView(SettingsView().environmentObject(appStore))
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.contentView = content
        return window
    }
}
