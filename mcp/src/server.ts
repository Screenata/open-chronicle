import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import {
  getLatestCapture,
  getLatestMemory,
  getRecentMemories,
  searchMemories,
} from "./db.js";

export function createMcpServer(): McpServer {
  const server = new McpServer({
    name: "open-chronicle",
    version: "0.1.0",
  });

  server.tool(
    "current_context",
    "Returns the most recent screen capture and memory. Use this to understand what the developer is currently working on or was just working on.",
    {},
    async () => {
      const capture = getLatestCapture();
      const memory = getLatestMemory();

      const result: Record<string, unknown> = {};

      if (capture) {
        result.current_capture = {
          ts: capture.ts,
          app_name: capture.app_name,
          window_title: capture.window_title,
          ocr_text_preview: capture.ocr_text?.slice(0, 300) || null,
        };
      }

      if (memory) {
        result.latest_memory = {
          title: memory.title,
          summary: memory.summary,
          app_name: memory.app_name,
          start_ts: memory.start_ts,
          end_ts: memory.end_ts,
          project_hint: memory.project_hint,
        };
      }

      if (!capture && !memory) {
        return {
          content: [
            {
              type: "text" as const,
              text: "No captures or memories available yet. Chronicle may not be recording.",
            },
          ],
        };
      }

      return {
        content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }],
      };
    }
  );

  server.tool(
    "recent_memories",
    "Returns the N most recent memory summaries. Each memory represents a time window of developer activity with a title, summary, and raw context.",
    { limit: z.number().min(1).max(50).default(5).describe("Number of memories to return") },
    async ({ limit }) => {
      const memories = getRecentMemories(limit);

      if (memories.length === 0) {
        return {
          content: [
            {
              type: "text" as const,
              text: "No memories available yet. The developer may not have been working long enough for memories to be generated.",
            },
          ],
        };
      }

      const items = memories.map((m) => ({
        title: m.title,
        summary: m.summary,
        app_name: m.app_name,
        start_ts: m.start_ts,
        end_ts: m.end_ts,
        raw_context: m.raw_context,
        project_hint: m.project_hint,
      }));

      return {
        content: [
          { type: "text" as const, text: JSON.stringify({ items }, null, 2) },
        ],
      };
    }
  );

  server.tool(
    "search_memories",
    "Search through developer memories by keyword. Matches against titles, summaries, and raw context. Use this to find specific past work, files, or topics the developer was working on.",
    {
      query: z.string().describe("Search query to match against memory titles, summaries, and context"),
      limit: z.number().min(1).max(50).default(5).describe("Maximum results to return"),
    },
    async ({ query, limit }) => {
      const memories = searchMemories(query, limit);

      if (memories.length === 0) {
        return {
          content: [
            {
              type: "text" as const,
              text: `No memories found matching "${query}".`,
            },
          ],
        };
      }

      const items = memories.map((m) => ({
        title: m.title,
        summary: m.summary,
        app_name: m.app_name,
        start_ts: m.start_ts,
        end_ts: m.end_ts,
        raw_context: m.raw_context,
        project_hint: m.project_hint,
      }));

      return {
        content: [
          { type: "text" as const, text: JSON.stringify({ items }, null, 2) },
        ],
      };
    }
  );

  return server;
}
