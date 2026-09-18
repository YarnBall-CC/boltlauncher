import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    static let privacyPolicyURL = URL(
        string: "https://github.com/YarnBall-CC/boltlauncher/blob/main/PRIVACY.md"
    )!

    @Published var apps: [AppEntry] = []
    @Published var scenes: [SceneEntry] = []
    @Published var loginEnabled: Bool
    @Published var loginRequiresApproval: Bool
    @Published var hotkeyIssues: [String] = []
    @Published var notice: AppNotice?

    private var store: SQLiteStore?
    private let launcher = AppLauncher()
    private let loginItemManager = LoginItemManager()
    private var activeSceneApps: [Int: Set<Int>] = [:]
    private var openingSceneIDs: Set<Int> = []
    private var openedResourceIDs: Set<Int> = []
    private lazy var hotkeyManager: HotkeyManager = {
        HotkeyManager { [weak self] target in
            self?.handleHotkey(target)
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
            scenes = try store.fetchScenes()
            hotkeyIssues = hotkeyManager.register(apps: apps, scenes: scenes)
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
        guard isSafeHotkey(hotkey) else {
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
        if let conflictingScene = scenes.first(where: { $0.hotkey == hotkey }) {
            present(title: "Hotkey Already Assigned", message: "\(hotkey.displayString) is assigned to \(conflictingScene.name).")
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

    func addScene() {
        let existing = Set(scenes.map(\.name))
        var name = "New Scene"
        var suffix = 2
        while existing.contains(name) {
            name = "New Scene \(suffix)"
            suffix += 1
        }
        do {
            try requireStore().createScene(name: name)
            reload()
        } catch {
            present(title: "Couldn’t Create Scene", error: error)
        }
    }

    func renameScene(_ scene: SceneEntry, to input: String) {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else {
            present(title: "Invalid Scene Name", message: "Use a name from 1 to 80 characters.")
            return
        }
        guard name != scene.name else { return }
        do {
            try requireStore().renameScene(id: scene.id, name: name)
            reload()
        } catch {
            present(title: "Couldn’t Rename Scene", error: error)
        }
    }

    func updateHotkey(for scene: SceneEntry, hotkey: Hotkey) {
        guard isSafeHotkey(hotkey) else {
            present(title: "Choose a Safer Hotkey", message: "Use Command, Option, or Control with the key. Function keys may be used without a modifier.")
            return
        }
        if let app = apps.first(where: { $0.hotkey == hotkey }) {
            present(title: "Hotkey Already Assigned", message: "\(hotkey.displayString) is assigned to \(app.name).")
            return
        }
        if let other = scenes.first(where: { $0.id != scene.id && $0.hotkey == hotkey }) {
            present(title: "Hotkey Already Assigned", message: "\(hotkey.displayString) is assigned to \(other.name).")
            return
        }
        do {
            try requireStore().updateSceneHotkey(id: scene.id, hotkey: hotkey)
            reload()
            if let issue = hotkeyIssues.first(where: { $0.contains(scene.name) }) {
                present(title: "Hotkey Unavailable", message: issue)
            }
        } catch {
            present(title: "Couldn’t Save Scene Hotkey", error: error)
        }
    }

    func setSceneApp(_ app: AppEntry, in scene: SceneEntry, included: Bool) {
        do {
            try requireStore().setSceneApp(sceneId: scene.id, appId: app.id, included: included)
            reload()
        } catch {
            present(title: "Couldn’t Update Scene", error: error)
        }
    }

    func addWebsite(_ input: String, to scene: SceneEntry) {
        guard let url = SceneResource.validatedWebsite(input) else {
            present(title: "Invalid Website", message: "Enter a complete http or https URL.")
            return
        }
        do {
            try requireStore().addSceneResource(sceneId: scene.id, kind: .website, value: url, bookmarkData: nil)
            reload()
        } catch {
            present(title: "Couldn’t Add Website", error: error)
        }
    }

    func addFiles(to scene: SceneEntry) {
        let panel = NSOpenPanel()
        panel.title = "Add Files or Folders to \(scene.name)"
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do {
            let store = try requireStore()
            for url in panel.urls {
                try store.addSceneResource(
                    sceneId: scene.id,
                    kind: .file,
                    value: url.path,
                    bookmarkData: makeBookmark(for: url)
                )
            }
            reload()
        } catch {
            present(title: "Couldn’t Add File or Folder", error: error)
        }
    }

    func remove(_ resource: SceneResource) {
        do {
            try requireStore().removeSceneResource(id: resource.id)
            openedResourceIDs.remove(resource.id)
            reload()
        } catch {
            present(title: "Couldn’t Remove Resource", error: error)
        }
    }

    func remove(scene: SceneEntry) {
        do {
            try requireStore().removeScene(id: scene.id)
            activeSceneApps.removeValue(forKey: scene.id)
            openingSceneIDs.remove(scene.id)
            reload()
        } catch {
            present(title: "Couldn’t Remove Scene", error: error)
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

    func toggle(scene: SceneEntry) {
        guard !openingSceneIDs.contains(scene.id) else { return }
        let selectedApps = scene.appIDs.compactMap { id in apps.first(where: { $0.id == id }) }
        guard !selectedApps.isEmpty else {
            present(title: "Scene Needs an App", message: "Choose at least one application in Settings.")
            return
        }

        if let activeAppIDs = activeSceneApps[scene.id] {
            let sharedAppIDs = Set(activeSceneApps
                .filter { $0.key != scene.id }
                .flatMap(\.value))
            let toHide = apps.filter { activeAppIDs.contains($0.id) && !sharedAppIDs.contains($0.id) }
            openingSceneIDs.insert(scene.id)
            hideSceneApps(toHide, sceneID: scene.id, at: 0, failures: [])
            return
        }

        openingSceneIDs.insert(scene.id)
        let resourceFailures = openResources(in: scene)
        let launchOrder = Array(selectedApps.dropFirst()) + [selectedApps[0]]
        activateSceneApps(launchOrder, sceneID: scene.id, at: 0, activatedAppIDs: [], failures: resourceFailures)
    }

    private func hideSceneApps(_ selectedApps: [AppEntry], sceneID: Int, at index: Int, failures: [AppEntry]) {
        guard index < selectedApps.count else {
            openingSceneIDs.remove(sceneID)
            if failures.isEmpty {
                activeSceneApps.removeValue(forKey: sceneID)
            } else {
                activeSceneApps[sceneID] = Set(failures.map(\.id))
                present(title: "Couldn’t Hide Scene", message: failures.map(\.name).joined(separator: ", "))
            }
            return
        }
        launcher.hide(app: selectedApps[index]) { [weak self] hidden in
            Task { @MainActor in
                guard let self, self.scenes.contains(where: { $0.id == sceneID }) else { return }
                let nextFailures = hidden ? failures : failures + [selectedApps[index]]
                self.hideSceneApps(selectedApps, sceneID: sceneID, at: index + 1, failures: nextFailures)
            }
        }
    }

    private func activateSceneApps(
        _ selectedApps: [AppEntry],
        sceneID: Int,
        at index: Int,
        activatedAppIDs: Set<Int>,
        failures: [String]
    ) {
        guard index < selectedApps.count else {
            openingSceneIDs.remove(sceneID)
            if !activatedAppIDs.isEmpty, scenes.contains(where: { $0.id == sceneID }) {
                activeSceneApps[sceneID] = activatedAppIDs
            }
            reload()
            if !failures.isEmpty {
                present(title: "Scene Opened with Issues", message: failures.joined(separator: "\n"))
            }
            return
        }

        let app = selectedApps[index]
        launcher.activate(app: app) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                var nextFailures = failures
                var nextActivatedAppIDs = activatedAppIDs
                switch result {
                case .success(.launched(let refreshedBookmark, let resolvedPath)):
                    nextActivatedAppIDs.insert(app.id)
                    do {
                        try self.requireStore().logLaunch(
                            appId: app.id,
                            at: Date(),
                            refreshedBookmark: refreshedBookmark,
                            path: resolvedPath ?? app.path
                        )
                    } catch {
                        nextFailures.append("\(app.name): \(error.localizedDescription)")
                    }
                case .success(.hidden):
                    break
                case .failure(let error):
                    nextFailures.append("\(app.name): \(error.localizedDescription)")
                }
                self.activateSceneApps(
                    selectedApps,
                    sceneID: sceneID,
                    at: index + 1,
                    activatedAppIDs: nextActivatedAppIDs,
                    failures: nextFailures
                )
            }
        }
    }

    private func openResources(in scene: SceneEntry) -> [String] {
        var failures: [String] = []
        for resource in scene.resources where !openedResourceIDs.contains(resource.id) {
            do {
                try open(resource)
                openedResourceIDs.insert(resource.id)
            } catch {
                failures.append("\(resource.title): \(error.localizedDescription)")
            }
        }
        return failures
    }

    private func open(_ resource: SceneResource) throws {
        switch resource.kind {
        case .website:
            guard let value = SceneResource.validatedWebsite(resource.value),
                  let url = URL(string: value), NSWorkspace.shared.open(url) else {
                throw AppStoreError.couldNotOpenResource
            }
        case .file:
            guard let bookmarkData = resource.bookmarkData else {
                throw AppStoreError.resourceAccessRequired
            }
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
            guard NSWorkspace.shared.open(url) else { throw AppStoreError.couldNotOpenResource }
            if isStale {
                try requireStore().updateSceneResourceBookmark(id: resource.id, bookmarkData: makeBookmark(for: url))
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
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func requireStore() throws -> SQLiteStore {
        guard let store else { throw AppStoreError.databaseUnavailable }
        return store
    }

    private func isSafeHotkey(_ hotkey: Hotkey) -> Bool {
        let safeModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        return !hotkey.modifierFlags.intersection(safeModifiers).isEmpty
            || KeyCodeMapper.isFunctionKey(hotkey.keyCode)
    }

    private func handleHotkey(_ target: HotkeyTarget) {
        switch target {
        case .app(let id):
            guard let app = apps.first(where: { $0.id == id }) else { return }
            launch(app: app)
        case .scene(let id):
            guard let scene = scenes.first(where: { $0.id == id }) else { return }
            toggle(scene: scene)
        }
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
    case resourceAccessRequired
    case couldNotOpenResource

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            "The local database is unavailable. Restart BoltLauncher and try again."
        case .resourceAccessRequired:
            "Access to this file or folder is missing. Remove it and add it again in Settings."
        case .couldNotOpenResource:
            "macOS could not open this resource."
        }
    }
}
