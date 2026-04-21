import { appendFileSync, mkdirSync, existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";

const DATA_DIR = join(homedir(), ".open-chronicle");
const LOG_PATH = join(DATA_DIR, "mcp.log");

if (!existsSync(DATA_DIR)) {
  mkdirSync(DATA_DIR, { recursive: true });
}

function write(level: "INFO" | "ERROR", msg: string, ...rest: unknown[]) {
  const parts = [msg, ...rest.map((r) => (typeof r === "string" ? r : JSON.stringify(r, null, 2)))];
  const line = `[${new Date().toISOString()}] [${level}] ${parts.join(" ")}`;
  try {
    appendFileSync(LOG_PATH, line + "\n");
  } catch {
    // If log write fails, fall through to stderr only.
  }
  console.error(line);
}

export const log = {
  info: (msg: string, ...rest: unknown[]) => write("INFO", msg, ...rest),
  error: (msg: string, err?: unknown) => {
    const detail =
      err instanceof Error
        ? `${err.message}\n${err.stack || ""}`
        : err !== undefined
          ? JSON.stringify(err)
          : "";
    write("ERROR", msg, detail);
  },
};
