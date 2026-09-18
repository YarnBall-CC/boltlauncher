import AppKit
import SQLite3
import XCTest
@testable import BoltLauncher

final class CoreTests: XCTestCase {
    func testHotkeyDisplayStringUsesMacModifierOrder() {
        let hotkey = Hotkey(
            keyCode: 0,
            modifiers: Int(
                NSEvent.ModifierFlags([.control, .option, .shift, .command]).rawValue
            )
        )

        XCTAssertEqual(hotkey.displayString, "⌃⌥⇧⌘A")
    }

    func testFunctionKeyRecognition() {
        XCTAssertTrue(KeyCodeMapper.isFunctionKey(122))
        XCTAssertTrue(KeyCodeMapper.isFunctionKey(111))
        XCTAssertFalse(KeyCodeMapper.isFunctionKey(0))
    }

    func testSQLiteStorePersistsBookmarksHotkeysAndLaunches() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("launcher.sqlite")
        let store = try SQLiteStore(databaseURL: databaseURL)
        let bookmark = Data([0x01, 0x02, 0x03])

        try store.upsertApp(
            bundleId: "com.example.Editor",
            name: "Editor",
            path: "/Applications/Editor.app",
            bookmarkData: bookmark
        )

        var app = try XCTUnwrap(store.fetchApps().first)
        XCTAssertEqual(app.bookmarkData, bookmark)
        XCTAssertEqual(app.launchCount, 0)

        let hotkey = Hotkey(
            keyCode: 14,
            modifiers: Int(NSEvent.ModifierFlags.command.rawValue)
        )
        try store.updateHotkey(appId: app.id, hotkey: hotkey)
        try store.logLaunch(appId: app.id, at: Date())

        app = try XCTUnwrap(store.fetchApps().first)
        XCTAssertEqual(app.hotkey, hotkey)
        XCTAssertEqual(app.launchCount, 1)
        XCTAssertNotNil(app.lastLaunchedAt)

        try store.removeApp(appId: app.id)
        XCTAssertTrue(try store.fetchApps().isEmpty)
    }

    func testSQLiteStoreMigratesLegacyAppsTableWithoutDataLoss() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let databaseURL = folderURL.appendingPathComponent("launcher.sqlite")

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let createLegacySchema = """
        CREATE TABLE apps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bundle_id TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            path TEXT NOT NULL,
            key_code INTEGER NOT NULL,
            modifiers INTEGER NOT NULL,
            launch_count INTEGER NOT NULL DEFAULT 0,
            last_launched_at TEXT
        );
        INSERT INTO apps (
            bundle_id, name, path, key_code, modifiers, launch_count
        ) VALUES (
            'com.example.Legacy', 'Legacy', '/Applications/Legacy.app', -1, 0, 4
        );
        """
        XCTAssertEqual(sqlite3_exec(database, createLegacySchema, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let store = try SQLiteStore(databaseURL: databaseURL)
        var app = try XCTUnwrap(store.fetchApps().first)
        XCTAssertEqual(app.name, "Legacy")
        XCTAssertEqual(app.launchCount, 4)
        XCTAssertNil(app.bookmarkData)

        let bookmark = Data([0x0A, 0x0B])
        try store.updateBookmark(appId: app.id, path: app.path, bookmarkData: bookmark)
        app = try XCTUnwrap(store.fetchApps().first)
        XCTAssertEqual(app.bookmarkData, bookmark)
        XCTAssertEqual(app.launchCount, 4)
    }

    func testScenePersistsResourcesHotkeyAndAppDeletion() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("launcher.sqlite")
        let store = try SQLiteStore(databaseURL: databaseURL)
        try store.upsertApp(
            bundleId: "com.example.Editor",
            name: "Editor",
            path: "/Applications/Editor.app",
            bookmarkData: Data([1])
        )
        let appID = try XCTUnwrap(store.fetchApps().first?.id)
        try store.createScene(name: "Writing")
        let sceneID = try XCTUnwrap(store.fetchScenes().first?.id)
        try store.setSceneApp(sceneId: sceneID, appId: appID, included: true)
        try store.updateSceneHotkey(id: sceneID, hotkey: Hotkey(keyCode: 0, modifiers: 256))
        try store.addSceneResource(sceneId: sceneID, kind: .website, value: "https://example.com", bookmarkData: nil)
        try store.addSceneResource(sceneId: sceneID, kind: .file, value: "/tmp/notes.txt", bookmarkData: Data([2]))

        var scene = try XCTUnwrap(store.fetchScenes().first)
        XCTAssertEqual(scene.appIDs, [appID])
        XCTAssertEqual(scene.hotkey.keyCode, 0)
        XCTAssertEqual(scene.resources.map(\.kind), [.website, .file])
        XCTAssertNil(SceneResource.validatedWebsite("javascript:alert(1)"))
        XCTAssertEqual(SceneResource.validatedWebsite(" https://example.com "), "https://example.com")

        try store.removeApp(appId: appID)
        scene = try XCTUnwrap(store.fetchScenes().first)
        XCTAssertTrue(scene.appIDs.isEmpty)
        XCTAssertEqual(scene.resources.count, 2)
        try store.removeScene(id: sceneID)
        XCTAssertTrue(try store.fetchScenes().isEmpty)
    }
}
