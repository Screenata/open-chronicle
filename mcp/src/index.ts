import { config as loadEnv } from "dotenv";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

// Load .env from an absolute path resolved relative to this source file,
// so it works regardless of the cwd Claude Code spawns us from.
const __dirname = dirname(fileURLToPath(import.meta.url));
loadEnv({ path: join(__dirname, "..", ".env") });

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createMcpServer } from "./server.js";
import { startMemoryBuilderLoop } from "./memory-builder.js";
import { log } from "./logger.js";

async function main() {
  const memoryIntervalMs = parseInt(
    process.env.CHRONICLE_MEMORY_INTERVAL_MS || "30000",
    10
  );

  const provider = process.env.CHRONICLE_LLM_PROVIDER || "anthropic (default)";
  const model = process.env.CHRONICLE_LLM_MODEL || "(default)";
  log.info(`[open-chronicle] Loaded config: provider=${provider}, model=${model}`);

  startMemoryBuilderLoop(memoryIntervalMs);

  const server = createMcpServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);

  log.info("[open-chronicle] MCP server running on stdio");
}

main().catch((err) => {
  log.error("[open-chronicle] Fatal error", err);
  process.exit(1);
});
