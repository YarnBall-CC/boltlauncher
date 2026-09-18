import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { appStore.loginEnabled },
                    set: { appStore.toggleLogin($0) }
                ))

                if appStore.loginRequiresApproval {
                    HStack {
                        Label("Approval is required in System Settings.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items") {
                            appStore.openLoginItemSettings()
                        }
                    }
                }
            }

            Section("Applications") {
                HStack {
                    Text("Assign a global hotkey to each application.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add App...") {
                        appStore.addAppFromPanel()
                    }
                }

                if appStore.apps.isEmpty {
                    Text("Add an application to get started.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appStore.apps) { app in
                        AppRow(app: app)
                    }
                }
            }

            Section("Scenes") {
                HStack {
                    Text("Open a group of apps and resources with one hotkey. Press it again to hide the apps.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Scene") {
                        appStore.addScene()
                    }
                }

                ForEach(appStore.scenes) { scene in
                    SceneRow(scene: scene)
                }
            }

            if !appStore.hotkeyIssues.isEmpty {
                Section("Hotkey Issues") {
                    ForEach(appStore.hotkeyIssues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Privacy") {
                Text("BoltLauncher stores app permissions, scene resources, and launch counts only on this Mac. It does not collect or transmit data.")
                    .foregroundStyle(.secondary)
                Link("Privacy Policy", destination: AppStore.privacyPolicyURL)
            }
        }
        .formStyle(.grouped)
        .frame(width: 600)
        .frame(minHeight: 440)
        .alert(item: $appStore.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct SceneRow: View {
    @EnvironmentObject private var appStore: AppStore
    let scene: SceneEntry
    @State private var name: String
    @State private var website = ""

    init(scene: SceneEntry) {
        self.scene = scene
        _name = State(initialValue: scene.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Scene name", text: $name)
                    .onSubmit { appStore.renameScene(scene, to: name) }
                Button("Rename") { appStore.renameScene(scene, to: name) }
                    .disabled(name == scene.name)
                HotkeyRecorder(hotkey: scene.hotkey) { hotkey in
                    appStore.updateHotkey(for: scene, hotkey: hotkey)
                }
                Button("Remove", role: .destructive) { appStore.remove(scene: scene) }
            }

            Text("Choose the apps this scene opens. Its first selected app comes to the front.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(appStore.apps) { app in
                Toggle(app.name, isOn: Binding(
                    get: { scene.appIDs.contains(app.id) },
                    set: { appStore.setSceneApp(app, in: scene, included: $0) }
                ))
            }

            HStack {
                TextField("https://example.com/project", text: $website)
                    .onSubmit { addWebsite() }
                Button("Add Website") { addWebsite() }
                Button("Add File or Folder...") { appStore.addFiles(to: scene) }
            }
            ForEach(scene.resources) { resource in
                HStack {
                    Label(resource.title, systemImage: resource.kind == .website ? "link" : "doc")
                        .lineLimit(1)
                    Spacer()
                    Button("Remove") { appStore.remove(resource) }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func addWebsite() {
        appStore.addWebsite(website, to: scene)
        if SceneResource.validatedWebsite(website) != nil { website = "" }
    }
}

private struct AppRow: View {
    @EnvironmentObject private var appStore: AppStore
    let app: AppEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .lineLimit(1)
                    Text(app.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if app.requiresAuthorization {
                    Button("Grant Access...") {
                        appStore.grantAccess(to: app)
                    }
                }

                HotkeyRecorder(hotkey: app.hotkey) { newHotkey in
                    appStore.updateHotkey(for: app, hotkey: newHotkey)
                }

                Button("Remove", role: .destructive) {
                    appStore.remove(app: app)
                }
            }

            if app.requiresAuthorization {
                Label(
                    "Grant access once so this app can be opened from the App Store sandbox.",
                    systemImage: "lock.trianglebadge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
