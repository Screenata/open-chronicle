import Database from "better-sqlite3";
import { existsSync, mkdirSync, renameSync } from "fs";
import { homedir } from "os";
import { join } from "path";

const DATA_DIR = join(homedir(), ".open-chronicle");
const DB_PATH = join(DATA_DIR, "open-chronicle.db");

const LEGACY_DIR = join(homedir(), ".chronicle");
const LEGACY_DB = join(LEGACY_DIR, "chronicle.db");

if (!existsSync(DATA_DIR)) {
  mkdirSync(DATA_DIR, { recursive: true });
}

// One-time migration from legacy ~/.chronicle/ layout.
if (!existsSync(DB_PATH) && existsSync(LEGACY_DB)) {
  try {
    renameSync(LEGACY_DB, DB_PATH);
    const legacyWal = LEGACY_DB + "-wal";
    const legacyShm = LEGACY_DB + "-shm";
    if (existsSync(legacyWal)) renameSync(legacyWal, DB_PATH + "-wal");
    if (existsSync(legacyShm)) renameSync(legacyShm, DB_PATH + "-shm");
    console.error(`[open-chronicle] migrated legacy DB ${LEGACY_DB} -> ${DB_PATH}`);
  } catch (err) {
    console.error(`[open-chronicle] legacy DB migration failed:`, err);
  }
}

let db: Database.Database;

export function getDb(): Database.Database {
  if (!db) {
    db = new Database(DB_PATH);
    db.pragma("journal_mode = WAL");
    db.pragma("busy_timeout = 5000");
  }
  return db;
}

export interface CaptureRow {
  id: number;
  ts: string;
  app_name: string;
  window_title: string;
  image_path: string | null;
  ocr_text: string | null;
  window_hash: string;
  is_duplicate: number;
}

export interface MemoryRow {
  id: number;
  start_ts: string;
  end_ts: string;
  app_name: string;
  title: string;
  summary: string;
  raw_context: string | null;
  project_hint: string | null;
}

export function getRecentCaptures(limit = 20): CaptureRow[] {
  return getDb()
    .prepare(
      "SELECT * FROM captures WHERE is_duplicate = 0 ORDER BY ts DESC LIMIT ?"
    )
    .all(limit) as CaptureRow[];
}

export function getCapturesInWindow(
  startTs: string,
  endTs: string
): CaptureRow[] {
  return getDb()
    .prepare(
      "SELECT * FROM captures WHERE ts >= ? AND ts <= ? AND is_duplicate = 0 ORDER BY ts"
    )
    .all(startTs, endTs) as CaptureRow[];
}

export function getUnsummarizedWindows(
  windowSec: number
): { windowStart: string; windowEnd: string }[] {
  const db = getDb();

  const latest = db
    .prepare("SELECT MAX(end_ts) as last_end FROM memories")
    .get() as { last_end: string | null } | undefined;

  const since = latest?.last_end || "1970-01-01T00:00:00Z";

  const captures = db
    .prepare(
      `SELECT ts FROM captures
       WHERE ts > ? AND is_duplicate = 0 AND ocr_text IS NOT NULL
       ORDER BY ts`
    )
    .all(since) as { ts: string }[];

  if (captures.length === 0) return [];

  const windows: { windowStart: string; windowEnd: string }[] = [];
  let windowStart = captures[0].ts;
  let windowEnd = windowStart;

  for (const cap of captures) {
    const startDate = new Date(windowStart).getTime();
    const capDate = new Date(cap.ts).getTime();

    if (capDate - startDate > windowSec * 1000) {
      windows.push({ windowStart, windowEnd });
      windowStart = cap.ts;
    }
    windowEnd = cap.ts;
  }

  const now = Date.now();
  const windowStartTime = new Date(windowStart).getTime();
  const windowEndTime = new Date(windowEnd).getTime();
  const windowSpan = windowEndTime - windowStartTime;
  const idleTime = now - windowEndTime;

  if (windowSpan >= windowSec * 1000 || idleTime >= windowSec * 1000) {
    windows.push({ windowStart, windowEnd });
  }

  return windows;
}

export function insertMemory(memory: {
  start_ts: string;
  end_ts: string;
  app_name: string;
  title: string;
  summary: string;
  raw_context: string | null;
  project_hint: string | null;
}): number {
  const result = getDb()
    .prepare(
      `INSERT INTO memories (start_ts, end_ts, app_name, title, summary, raw_context, project_hint)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    )
    .run(
      memory.start_ts,
      memory.end_ts,
      memory.app_name,
      memory.title,
      memory.summary,
      memory.raw_context,
      memory.project_hint
    );
  return Number(result.lastInsertRowid);
}

export function getRecentMemories(limit = 5): MemoryRow[] {
  return getDb()
    .prepare("SELECT * FROM memories ORDER BY end_ts DESC LIMIT ?")
    .all(limit) as MemoryRow[];
}

export function searchMemories(query: string, limit = 5): MemoryRow[] {
  const pattern = `%${query}%`;
  return getDb()
    .prepare(
      `SELECT * FROM memories
       WHERE title LIKE ? OR summary LIKE ? OR raw_context LIKE ?
       ORDER BY end_ts DESC LIMIT ?`
    )
    .all(pattern, pattern, pattern, limit) as MemoryRow[];
}

export function getLatestCapture(): CaptureRow | undefined {
  return getDb()
    .prepare("SELECT * FROM captures ORDER BY ts DESC LIMIT 1")
    .get() as CaptureRow | undefined;
}

export function getLatestMemory(): MemoryRow | undefined {
  return getDb()
    .prepare("SELECT * FROM memories ORDER BY end_ts DESC LIMIT 1")
    .get() as MemoryRow | undefined;
}

export function getSetting(key: string): string | undefined {
  const row = getDb()
    .prepare("SELECT value FROM settings WHERE key = ?")
    .get(key) as { value: string } | undefined;
  return row?.value;
}
