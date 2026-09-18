import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteStore {
    private let db: OpaquePointer
    private let dateFormatter = ISO8601DateFormatter()

    init(databaseURL: URL? = nil) throws {
        let url = try databaseURL ?? Self.databaseURL()
        let folder = url.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw SQLiteStoreError.fileSystem(error)
        }

        var handle: OpaquePointer?
        let openStatus = sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard openStatus == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown database error"
            if let handle {
                sqlite3_close(handle)
            }
            throw SQLiteStoreError.operationFailed("Open database", message)
        }

        db = handle

        do {
            try execute(sql: "PRAGMA foreign_keys = ON;")
            try execute(sql: """
            CREATE TABLE IF NOT EXISTS apps (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bundle_id TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL,
                path TEXT NOT NULL,
                key_code INTEGER NOT NULL,
                modifiers INTEGER NOT NULL,
                launch_count INTEGER NOT NULL DEFAULT 0,
                last_launched_at TEXT,
                bookmark_data BLOB
            );
            """)
            try execute(sql: """
            CREATE TABLE IF NOT EXISTS launch_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app_id INTEGER NOT NULL,
                launched_at TEXT NOT NULL,
                FOREIGN KEY(app_id) REFERENCES apps(id) ON DELETE CASCADE
            );
            """)
            try execute(sql: """
            CREATE TABLE IF NOT EXISTS scenes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                key_code INTEGER NOT NULL DEFAULT -1,
                modifiers INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS scene_apps (
                scene_id INTEGER NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
                app_id INTEGER NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
                PRIMARY KEY(scene_id, app_id)
            );
            CREATE TABLE IF NOT EXISTS scene_resources (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                scene_id INTEGER NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
                kind TEXT NOT NULL CHECK(kind IN ('website', 'file')),
                value TEXT NOT NULL,
                bookmark_data BLOB,
                UNIQUE(scene_id, kind, value)
            );
            """)
            try migrateAppsTableIfNeeded()
        } catch {
            sqlite3_close(db)
            throw error
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func fetchApps() throws -> [AppEntry] {
        let sql = """
        SELECT id, bundle_id, name, path, key_code, modifiers, launch_count,
               last_launched_at, bookmark_data
        FROM apps
        ORDER BY name COLLATE NOCASE;
        """
        let statement = try prepare(sql: sql)
        defer { sqlite3_finalize(statement) }

        var results: [AppEntry] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                return results
            }
            guard status == SQLITE_ROW else {
                throw databaseError(operation: "Read applications")
            }

            results.append(
                AppEntry(
                    id: Int(sqlite3_column_int(statement, 0)),
                    bundleId: stringColumn(statement, index: 1),
                    name: stringColumn(statement, index: 2),
                    path: stringColumn(statement, index: 3),
                    bookmarkData: dataColumn(statement, index: 8),
                    hotkey: Hotkey(
                        keyCode: Int(sqlite3_column_int(statement, 4)),
                        modifiers: Int(sqlite3_column_int(statement, 5))
                    ),
                    launchCount: Int(sqlite3_column_int(statement, 6)),
                    lastLaunchedAt: dateColumn(statement, index: 7)
                )
            )
        }
    }

    func upsertApp(bundleId: String, name: String, path: String, bookmarkData: Data) throws {
        let sql = """
        INSERT INTO apps (bundle_id, name, path, key_code, modifiers, launch_count, bookmark_data)
        VALUES (?, ?, ?, -1, 0, 0, ?)
        ON CONFLICT(bundle_id) DO UPDATE SET
            name = excluded.name,
            path = excluded.path,
            bookmark_data = excluded.bookmark_data;
        """
        let statement = try prepare(sql: sql)
        defer { sqlite3_finalize(statement) }

        bindText(bundleId, to: statement, index: 1)
        bindText(name, to: statement, index: 2)
        bindText(path, to: statement, index: 3)
        bindData(bookmarkData, to: statement, index: 4)
        try stepDone(statement, operation: "Save application")
    }

    func updateBookmark(appId: Int, path: String, bookmarkData: Data) throws {
        let statement = try prepare(sql: "UPDATE apps SET path = ?, bookmark_data = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }

        bindText(path, to: statement, index: 1)
        bindData(bookmarkData, to: statement, index: 2)
        sqlite3_bind_int64(statement, 3, sqlite3_int64(appId))
        try stepDone(statement, operation: "Update application access")
    }

    func updateHotkey(appId: Int, hotkey: Hotkey) throws {
        let statement = try prepare(sql: "UPDATE apps SET key_code = ?, modifiers = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, sqlite3_int64(hotkey.keyCode))
        sqlite3_bind_int64(statement, 2, sqlite3_int64(hotkey.modifiers))
        sqlite3_bind_int64(statement, 3, sqlite3_int64(appId))
        try stepDone(statement, operation: "Update hotkey")
    }

    func removeApp(appId: Int) throws {
        let statement = try prepare(sql: "DELETE FROM apps WHERE id = ?;")
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, sqlite3_int64(appId))
        try stepDone(statement, operation: "Remove application")
    }

    func fetchScenes() throws -> [SceneEntry] {
        let statement = try prepare(sql: "SELECT id, name, key_code, modifiers FROM scenes ORDER BY name COLLATE NOCASE;")
        defer { sqlite3_finalize(statement) }

        var scenes: [SceneEntry] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return scenes }
            guard status == SQLITE_ROW else { throw databaseError(operation: "Read scenes") }
            let id = Int(sqlite3_column_int64(statement, 0))
            scenes.append(SceneEntry(
                id: id,
                name: stringColumn(statement, index: 1),
                hotkey: Hotkey(
                    keyCode: Int(sqlite3_column_int(statement, 2)),
                    modifiers: Int(sqlite3_column_int(statement, 3))
                ),
                appIDs: try fetchSceneAppIDs(sceneId: id),
                resources: try fetchSceneResources(sceneId: id)
            ))
        }
    }

    func createScene(name: String) throws {
        let statement = try prepare(sql: "INSERT INTO scenes (name) VALUES (?);")
        defer { sqlite3_finalize(statement) }
        bindText(name, to: statement, index: 1)
        try stepDone(statement, operation: "Create scene")
    }

    func renameScene(id: Int, name: String) throws {
        let statement = try prepare(sql: "UPDATE scenes SET name = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        bindText(name, to: statement, index: 1)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(id))
        try stepDone(statement, operation: "Rename scene")
    }

    func updateSceneHotkey(id: Int, hotkey: Hotkey) throws {
        let statement = try prepare(sql: "UPDATE scenes SET key_code = ?, modifiers = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(hotkey.keyCode))
        sqlite3_bind_int64(statement, 2, sqlite3_int64(hotkey.modifiers))
        sqlite3_bind_int64(statement, 3, sqlite3_int64(id))
        try stepDone(statement, operation: "Update scene hotkey")
    }

    func setSceneApp(sceneId: Int, appId: Int, included: Bool) throws {
        let sql = included
            ? "INSERT OR IGNORE INTO scene_apps (scene_id, app_id) VALUES (?, ?);"
            : "DELETE FROM scene_apps WHERE scene_id = ? AND app_id = ?;"
        let statement = try prepare(sql: sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(sceneId))
        sqlite3_bind_int64(statement, 2, sqlite3_int64(appId))
        try stepDone(statement, operation: "Update scene applications")
    }

    func addSceneResource(sceneId: Int, kind: SceneResource.Kind, value: String, bookmarkData: Data?) throws {
        let statement = try prepare(sql: """
        INSERT OR IGNORE INTO scene_resources (scene_id, kind, value, bookmark_data) VALUES (?, ?, ?, ?);
        """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(sceneId))
        bindText(kind.rawValue, to: statement, index: 2)
        bindText(value, to: statement, index: 3)
        if let bookmarkData {
            bindData(bookmarkData, to: statement, index: 4)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        try stepDone(statement, operation: "Add scene resource")
    }

    func updateSceneResourceBookmark(id: Int, bookmarkData: Data) throws {
        let statement = try prepare(sql: "UPDATE scene_resources SET bookmark_data = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        bindData(bookmarkData, to: statement, index: 1)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(id))
        try stepDone(statement, operation: "Refresh scene resource access")
    }

    func removeSceneResource(id: Int) throws {
        let statement = try prepare(sql: "DELETE FROM scene_resources WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(id))
        try stepDone(statement, operation: "Remove scene resource")
    }

    func removeScene(id: Int) throws {
        let statement = try prepare(sql: "DELETE FROM scenes WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(id))
        try stepDone(statement, operation: "Remove scene")
    }

    // ponytail: scenes are few; batch these reads if a user can create hundreds of them.
    private func fetchSceneAppIDs(sceneId: Int) throws -> [Int] {
        let statement = try prepare(sql: "SELECT app_id FROM scene_apps WHERE scene_id = ? ORDER BY rowid;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(sceneId))
        var ids: [Int] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return ids }
            guard status == SQLITE_ROW else { throw databaseError(operation: "Read scene applications") }
            ids.append(Int(sqlite3_column_int64(statement, 0)))
        }
    }

    private func fetchSceneResources(sceneId: Int) throws -> [SceneResource] {
        let statement = try prepare(sql: """
        SELECT id, kind, value, bookmark_data FROM scene_resources WHERE scene_id = ? ORDER BY id;
        """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(sceneId))
        var resources: [SceneResource] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return resources }
            guard status == SQLITE_ROW else { throw databaseError(operation: "Read scene resources") }
            guard let kind = SceneResource.Kind(rawValue: stringColumn(statement, index: 1)) else { continue }
            resources.append(SceneResource(
                id: Int(sqlite3_column_int64(statement, 0)),
                kind: kind,
                value: stringColumn(statement, index: 2),
                bookmarkData: dataColumn(statement, index: 3)
            ))
        }
    }

    func logLaunch(appId: Int, at date: Date, refreshedBookmark: Data? = nil, path: String? = nil) throws {
        let timestamp = dateFormatter.string(from: date)
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")

        do {
            let insertStatement = try prepare(
                sql: "INSERT INTO launch_logs (app_id, launched_at) VALUES (?, ?);"
            )
            sqlite3_bind_int64(insertStatement, 1, sqlite3_int64(appId))
            bindText(timestamp, to: insertStatement, index: 2)
            do {
                try stepDone(insertStatement, operation: "Save launch history")
                sqlite3_finalize(insertStatement)
            } catch {
                sqlite3_finalize(insertStatement)
                throw error
            }

            let updateStatement: OpaquePointer
            if let refreshedBookmark, let path {
                updateStatement = try prepare(sql: """
                UPDATE apps
                SET launch_count = launch_count + 1,
                    last_launched_at = ?,
                    path = ?,
                    bookmark_data = ?
                WHERE id = ?;
                """)
                bindText(timestamp, to: updateStatement, index: 1)
                bindText(path, to: updateStatement, index: 2)
                bindData(refreshedBookmark, to: updateStatement, index: 3)
                sqlite3_bind_int64(updateStatement, 4, sqlite3_int64(appId))
            } else {
                updateStatement = try prepare(sql: """
                UPDATE apps
                SET launch_count = launch_count + 1, last_launched_at = ?
                WHERE id = ?;
                """)
                bindText(timestamp, to: updateStatement, index: 1)
                sqlite3_bind_int64(updateStatement, 2, sqlite3_int64(appId))
            }

            do {
                try stepDone(updateStatement, operation: "Update launch count")
                sqlite3_finalize(updateStatement)
            } catch {
                sqlite3_finalize(updateStatement)
                throw error
            }

            try execute(sql: "COMMIT;")
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
    }

    private func migrateAppsTableIfNeeded() throws {
        guard try !hasColumn("bookmark_data", in: "apps") else { return }
        try execute(sql: "ALTER TABLE apps ADD COLUMN bookmark_data BLOB;")
    }

    private func hasColumn(_ column: String, in table: String) throws -> Bool {
        let statement = try prepare(sql: "PRAGMA table_info(\(table));")
        defer { sqlite3_finalize(statement) }

        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                return false
            }
            guard status == SQLITE_ROW else {
                throw databaseError(operation: "Inspect database schema")
            }
            if stringColumn(statement, index: 1) == column {
                return true
            }
        }
    }

    private func execute(sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, sql, nil, nil, &errorPointer)
        defer { sqlite3_free(errorPointer) }

        guard status == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(db))
            throw SQLiteStoreError.operationFailed("Database operation", message)
        }
    }

    private func prepare(sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            if let statement {
                sqlite3_finalize(statement)
            }
            throw databaseError(operation: "Prepare database statement")
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer, operation: String) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError(operation: operation)
        }
    }

    private func bindText(_ value: String, to statement: OpaquePointer, index: Int32) {
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, sqliteTransient)
    }

    private func bindData(_ value: Data, to statement: OpaquePointer, index: Int32) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
        }
    }

    private func stringColumn(_ statement: OpaquePointer, index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private func dataColumn(_ statement: OpaquePointer, index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let length = Int(sqlite3_column_bytes(statement, index))
        guard length > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: length)
    }

    private func dateColumn(_ statement: OpaquePointer, index: Int32) -> Date? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return dateFormatter.date(from: String(cString: cString))
    }

    private func databaseError(operation: String) -> SQLiteStoreError {
        SQLiteStoreError.operationFailed(operation, String(cString: sqlite3_errmsg(db)))
    }

    private static func databaseURL() throws -> URL {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SQLiteStoreError.applicationSupportUnavailable
        }
        return base.appendingPathComponent("BoltLauncher").appendingPathComponent("launcher.sqlite")
    }
}

private enum SQLiteStoreError: LocalizedError {
    case applicationSupportUnavailable
    case fileSystem(Error)
    case operationFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "The Application Support folder is unavailable."
        case .fileSystem(let error):
            return "BoltLauncher could not create its data folder: \(error.localizedDescription)"
        case .operationFailed(let operation, let message):
            return "\(operation) failed: \(message)"
        }
    }
}
