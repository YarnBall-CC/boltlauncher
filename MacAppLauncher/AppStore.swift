import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    static let privacyPolicyURL = URL(
        string: "https://github.com/YarnBall-CC/boltlauncher/blob/main/PRIVACY.md"
    )!

    @Published var apps: [AppEntry] = []
    @Published var loginEnabled: Bool
    @Published var loginRequiresApproval: Bool
    @Published var hotkeyIssues: [String] = []
    @Published var notice: AppNotice?

    private var store: SQLiteStore?
    private let launcher = AppLauncher()
    private let loginItemManager = LoginItemManager()
    private lazy var hotkeyManager: HotkeyManager = {
        HotkeyManager { [weak self] appId in
            self?.handleHotkey(appId)
        }
    }()

    init() {
        loginEnabled = loginItemManager.isEnabled
        loginRequiresApproval = loginItemManager.requiresApproval

        do {
            store = try SQLiteStore()
            reload()
        } catch {
            present(title: "Database Unavailable", error: error)
        }
    }

    func reload() {
        guard let store else { return }
        do {
            apps = try store.fetchApps()
            hotkeyIssues = hotkeyManager.register(apps: apps)
        } catch {
            present(title: "Couldn’t Load Applications", error: error)
        }
    }

    func addAppFromPanel() {
        let panel = applicationPanel(
            title: "Add an Application",
            prompt: "Add",
            directoryURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveApplication(at: url)
    }

    func grantAccess(to app: AppEntry) {
        let currentURL = URL(fileURLWithPath: app.path)
        let panel = applicationPanel(
            title: "Grant Access to \(app.name)",
            prompt: "Grant Access",
            directoryURL: currentURL.deletingLastPathComponent()
        )
        panel.message = "Select \(app.name) again so BoltLauncher can open it from the App Store sandbox."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url) else {
            present(title: "Invalid Application", message: "The selected item is not a macOS application.")
            return
        }

        let selectedBundleId = bundle.bundleIdentifier ?? url.lastPathComponent
        guard selectedBundleId == app.bundleId else {
            present(
                title: "Different Application Selected",
                message: "Select \(app.name), not \(url.deletingPathExtension().lastPathComponent)."
            )
            return
        }

        do {
            let bookmarkData = try makeBookmark(for: url)
            try requireStore().updateBookmark(appId: app.id, path: url.path, bookmarkData: bookmarkData)
            reload()
        } catch {
            present(title: "Couldn’t Save Permission", error: error)
        }
    }

    func updateHotkey(for app: AppEntry, hotkey: Hotkey) {
        let safeModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        let hasSafeModifier = !hotkey.modifierFlags.intersection(safeModifiers).isEmpty
        guard hasSafeModifier || KeyCodeMapper.isFunctionKey(hotkey.keyCode) else {
            present(
                title: "Choose a Safer Hotkey",
                message: "Use Command, Option, or Control with the key. Function keys may be used without a modifier."
            )
            return
        }

        if let conflictingApp = apps.first(where: { $0.id != app.id && $0.hotkey == hotkey }) {
            present(
                title: "Hotkey Already Assigned",
                message: "\(hotkey.displayString) is already assigned to \(conflictingApp.name)."
            )
            return
        }

        do {
            try requireStore().updateHotkey(appId: app.id, hotkey: hotkey)
            reload()
            if let issue = hotkeyIssues.first(where: { $0.contains(app.name) }) {
                present(title: "Hotkey Unavailable", message: issue)
            }
        } catch {
            present(title: "Couldn’t Save Hotkey", error: error)
        }
    }

    func remove(app: AppEntry) {
        do {
            try requireStore().removeApp(appId: app.id)
            reload()
        } catch {
            present(title: "Couldn’t Remove Application", error: error)
        }
    }

    func launch(app: AppEntry) {
        launcher.toggle(app: app) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(.hidden):
                    break
                case .success(.launched(let refreshedBookmark, let resolvedPath)):
                    do {
                        try self.requireStore().logLaunch(
                            appId: app.id,
                            at: Date(),
                            refreshedBookmark: refreshedBookmark,
                            path: resolvedPath ?? app.path
                        )
                        self.reload()
                    } catch {
                        self.present(title: "Couldn’t Save Launch History", error: error)
                    }
                case .failure(let error):
                    self.present(title: "Couldn’t Open \(app.name)", error: error)
                }
            }
        }
    }

    func toggleLogin(_ enabled: Bool) {
        do {
            try loginItemManager.setEnabled(enabled)
        } catch {
            present(title: "Couldn’t Update Login Item", error: error)
        }

        loginEnabled = loginItemManager.isEnabled
        loginRequiresApproval = loginItemManager.requiresApproval
        if loginRequiresApproval {
            present(
                title: "Approval Required",
                message: "Allow BoltLauncher in System Settings > General > Login Items, then return here."
            )
        }
    }

    func openLoginItemSettings() {
        loginItemManager.openSystemSettings()
    }

    private func saveApplication(at url: URL) {
        guard let bundle = Bundle(url: url) else {
            present(title: "Invalid Application", message: "The selected item is not a macOS application.")
            return
        }

        let bundleId = bundle.bundleIdentifier ?? url.lastPathComponent
        let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        do {
            let bookmarkData = try makeBookmark(for: url)
            try requireStore().upsertApp(
                bundleId: bundleId,
                name: name,
                path: url.path,
                bookmarkData: bookmarkData
            )
            reload()
        } catch {
            present(title: "Couldn’t Add Application", error: error)
        }
    }

    private func applicationPanel(title: String, prompt: String, directoryURL: URL) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.directoryURL = directoryURL
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return panel
    }

    private func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func requireStore() throws -> SQLiteStore {
        guard let store else { throw AppStoreError.databaseUnavailable }
        return store
    }

    private func handleHotkey(_ appId: Int) {
        guard let app = apps.first(where: { $0.id == appId }) else { return }
        launch(app: app)
    }

    private func present(title: String, error: Error) {
        present(title: title, message: error.localizedDescription)
    }

    private func present(title: String, message: String) {
        notice = AppNotice(title: title, message: message)
    }
}

private enum AppStoreError: LocalizedError {
    case databaseUnavailable

    var errorDescription: String? {
        "The local database is unavailable. Restart BoltLauncher and try again."
    }
}
