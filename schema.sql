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
