import Foundation
import SQLite3

final class Database {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "chronicle.db", qos: .utility)

    static let shared = Database()

    static var dataDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".open-chronicle")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var screenshotsDirectory: URL {
        let dir = dataDirectory.appendingPathComponent("screenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var dbPath: String {
        dataDirectory.appendingPathComponent("open-chronicle.db").path
    }

    private static func migrateLegacyLayout() {
        let fm = FileManager.default
        let legacyDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".chronicle")
        let legacyDb = legacyDir.appendingPathComponent("chronicle.db")
        let newDb = URL(fileURLWithPath: dbPath)

        guard !fm.fileExists(atPath: newDb.path),
              fm.fileExists(atPath: legacyDb.path) else { return }

        do {
            try fm.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try fm.moveItem(at: legacyDb, to: newDb)
            for suffix in ["-wal", "-shm"] {
                let legacy = URL(fileURLWithPath: legacyDb.path + suffix)
                let next = URL(fileURLWithPath: newDb.path + suffix)
                if fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: next.path) {
                    try? fm.moveItem(at: legacy, to: next)
                }
            }
            let legacyScreenshots = legacyDir.appendingPathComponent("screenshots")
            let newScreenshots = screenshotsDirectory
            if fm.fileExists(atPath: legacyScreenshots.path) {
                let contents = (try? fm.contentsOfDirectory(at: legacyScreenshots, includingPropertiesForKeys: nil)) ?? []
                for item in contents {
                    let dest = newScreenshots.appendingPathComponent(item.lastPathComponent)
                    if !fm.fileExists(atPath: dest.path) {
                        try? fm.moveItem(at: item, to: dest)
                    }
                }
            }
            print("[open-chronicle] Migrated legacy ~/.chronicle -> ~/.open-chronicle")
        } catch {
            print("[open-chronicle] Legacy migration failed: \(error)")
        }
    }

    private init() {
        Self.migrateLegacyLayout()
        guard sqlite3_open(Self.dbPath, &db) == SQLITE_OK else {
            fatalError("Cannot open database at \(Self.dbPath)")
        }
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA busy_timeout=5000")
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Schema

    private func createTables() {
        let schema = """
        CREATE TABLE IF NOT EXISTS captures (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
            app_name TEXT NOT NULL,
            window_title TEXT NOT NULL DEFAULT '',
            image_path TEXT,
            ocr_text TEXT,
            window_hash TEXT NOT NULL,
            is_duplicate INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_captures_ts ON captures(ts);
        CREATE INDEX IF NOT EXISTS idx_captures_window_hash ON captures(window_hash);
        CREATE TABLE IF NOT EXISTS memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_ts TEXT NOT NULL,
            end_ts TEXT NOT NULL,
            app_name TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT NOT NULL,
            raw_context TEXT,
            project_hint TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_memories_start_ts ON memories(start_ts);
        CREATE INDEX IF NOT EXISTS idx_memories_end_ts ON memories(end_ts);
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        INSERT OR IGNORE INTO settings (key, value) VALUES ('capture_enabled', '1');
        INSERT OR IGNORE INTO settings (key, value) VALUES ('capture_interval_sec', '10');
        INSERT OR IGNORE INTO settings (key, value) VALUES ('screenshot_ttl_minutes', '30');
        INSERT OR IGNORE INTO settings (key, value) VALUES ('memory_window_sec', '60');
        INSERT OR IGNORE INTO settings (key, value) VALUES ('claude_integration_enabled', '1');
        CREATE TABLE IF NOT EXISTS excluded_apps (
            bundle_id TEXT PRIMARY KEY,
            app_name TEXT NOT NULL
        );
        """
        for statement in schema.components(separatedBy: ";") where !statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            execute(statement)
        }
    }

    // MARK: - Execute

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            print("[DB] Error: \(msg) for SQL: \(sql.prefix(80))")
            return false
        }
        return true
    }

    // MARK: - Captures

    func insertCapture(appName: String, windowTitle: String, imagePath: String?, ocrText: String?, windowHash: String, isDuplicate: Bool) -> Int64 {
        queue.sync {
            let sql = """
            INSERT INTO captures (app_name, window_title, image_path, ocr_text, window_hash, is_duplicate)
            VALUES (?, ?, ?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -1 }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (appName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (windowTitle as NSString).utf8String, -1, nil)
            if let p = imagePath {
                sqlite3_bind_text(stmt, 3, (p as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            if let t = ocrText {
                sqlite3_bind_text(stmt, 4, (t as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            sqlite3_bind_text(stmt, 5, (windowHash as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 6, isDuplicate ? 1 : 0)

            guard sqlite3_step(stmt) == SQLITE_DONE else { return -1 }
            return sqlite3_last_insert_rowid(db)
        }
    }

    func recentCaptures(limit: Int = 20) -> [Capture] {
        queue.sync {
            let sql = "SELECT id, ts, app_name, window_title, image_path, ocr_text, window_hash, is_duplicate FROM captures ORDER BY ts DESC LIMIT ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            return readCaptures(stmt: stmt)
        }
    }

    func lastCaptureHash() -> String? {
        queue.sync {
            let sql = "SELECT window_hash FROM captures ORDER BY id DESC LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return String(cString: sqlite3_column_text(stmt, 0))
        }
    }

    private func readCaptures(stmt: OpaquePointer?) -> [Capture] {
        var results: [Capture] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let tsStr = String(cString: sqlite3_column_text(stmt, 1))
            let ts = formatter.date(from: tsStr) ?? Date()
            let appName = String(cString: sqlite3_column_text(stmt, 2))
            let windowTitle = String(cString: sqlite3_column_text(stmt, 3))
            let imagePath = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let ocrText = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            let windowHash = String(cString: sqlite3_column_text(stmt, 6))
            let isDuplicate = sqlite3_column_int(stmt, 7) != 0
            results.append(Capture(id: id, ts: ts, appName: appName, windowTitle: windowTitle,
                                   imagePath: imagePath, ocrText: ocrText, windowHash: windowHash, isDuplicate: isDuplicate))
        }
        return results
    }

    // MARK: - Memories

    func recentMemories(limit: Int = 20) -> [Memory] {
        queue.sync {
            let sql = "SELECT id, start_ts, end_ts, app_name, title, summary, raw_context, project_hint FROM memories ORDER BY end_ts DESC LIMIT ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            return readMemories(stmt: stmt)
        }
    }

    func searchMemories(query: String, limit: Int = 5) -> [Memory] {
        queue.sync {
            let pattern = "%\(query)%"
            let sql = """
            SELECT id, start_ts, end_ts, app_name, title, summary, raw_context, project_hint
            FROM memories
            WHERE title LIKE ? OR summary LIKE ? OR raw_context LIKE ?
            ORDER BY end_ts DESC LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (pattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (pattern as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 4, Int32(limit))
            return readMemories(stmt: stmt)
        }
    }

    private func readMemories(stmt: OpaquePointer?) -> [Memory] {
        var results: [Memory] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let startTs = formatter.date(from: String(cString: sqlite3_column_text(stmt, 1))) ?? Date()
            let endTs = formatter.date(from: String(cString: sqlite3_column_text(stmt, 2))) ?? Date()
            let appName = String(cString: sqlite3_column_text(stmt, 3))
            let title = String(cString: sqlite3_column_text(stmt, 4))
            let summary = String(cString: sqlite3_column_text(stmt, 5))
            let rawContext = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
            let projectHint = sqlite3_column_text(stmt, 7).map { String(cString: $0) }
            results.append(Memory(id: id, startTs: startTs, endTs: endTs, appName: appName,
                                  title: title, summary: summary, rawContext: rawContext, projectHint: projectHint))
        }
        return results
    }

    // MARK: - Settings

    func getSetting(_ key: String) -> String? {
        queue.sync {
            let sql = "SELECT value FROM settings WHERE key = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return String(cString: sqlite3_column_text(stmt, 0))
        }
    }

    func setSetting(_ key: String, value: String) {
        queue.sync {
            let sql = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Excluded Apps

    func excludedApps() -> [ExcludedApp] {
        queue.sync {
            let sql = "SELECT bundle_id, app_name FROM excluded_apps ORDER BY app_name"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            var results: [ExcludedApp] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let bundleId = String(cString: sqlite3_column_text(stmt, 0))
                let appName = String(cString: sqlite3_column_text(stmt, 1))
                results.append(ExcludedApp(bundleId: bundleId, appName: appName))
            }
            return results
        }
    }

    func addExcludedApp(bundleId: String, appName: String) {
        queue.sync {
            let sql = "INSERT OR REPLACE INTO excluded_apps (bundle_id, app_name) VALUES (?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (bundleId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (appName as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
    }

    func removeExcludedApp(bundleId: String) {
        queue.sync {
            let sql = "DELETE FROM excluded_apps WHERE bundle_id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (bundleId as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Destructive

    @discardableResult
    func clearMemories() -> Int {
        queue.sync {
            execute("DELETE FROM memories")
            return Int(sqlite3_changes(db))
        }
    }

    struct ClearResult {
        let memories: Int
        let captures: Int
        let screenshots: Int
    }

    @discardableResult
    func clearAllData() -> ClearResult {
        queue.sync {
            // Wipe screenshot files first while we still have paths.
            var screenshotCount = 0
            let selectSql = "SELECT image_path FROM captures WHERE image_path IS NOT NULL"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selectSql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let p = sqlite3_column_text(stmt, 0) {
                        let path = String(cString: p)
                        if (try? FileManager.default.removeItem(atPath: path)) != nil {
                            screenshotCount += 1
                        }
                    }
                }
            }
            sqlite3_finalize(stmt)

            execute("DELETE FROM memories")
            let memoryCount = Int(sqlite3_changes(db))
            execute("DELETE FROM captures")
            let captureCount = Int(sqlite3_changes(db))

            // Orphaned PNGs in case any rows were missing image_path.
            if let contents = try? FileManager.default.contentsOfDirectory(at: Self.screenshotsDirectory, includingPropertiesForKeys: nil) {
                for url in contents where url.pathExtension.lowercased() == "png" {
                    if (try? FileManager.default.removeItem(at: url)) != nil {
                        screenshotCount += 1
                    }
                }
            }

            return ClearResult(memories: memoryCount, captures: captureCount, screenshots: screenshotCount)
        }
    }

    // MARK: - Cleanup

    func cleanupOldScreenshots(ttlMinutes: Int) {
        queue.sync {
            let cutoff = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(ttlMinutes * 60)))
            let sql = "SELECT image_path FROM captures WHERE ts < ? AND image_path IS NOT NULL"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (cutoff as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let path = sqlite3_column_text(stmt, 0) {
                    try? FileManager.default.removeItem(atPath: String(cString: path))
                }
            }
        }
        execute("DELETE FROM captures WHERE ts < datetime('now', '-\(ttlMinutes) minutes')")
    }
}
