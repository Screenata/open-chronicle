import { generateObject } from "ai";
import { anthropic } from "@ai-sdk/anthropic";
import { openai } from "@ai-sdk/openai";
import { fireworks } from "@ai-sdk/fireworks";
import { z } from "zod";
import {
  getCapturesInWindow,
  getUnsummarizedWindows,
  insertMemory,
  getSetting,
} from "./db.js";
import { log } from "./logger.js";

type Provider = "anthropic" | "openai" | "fireworks";

const DEFAULT_MODELS: Record<Provider, string> = {
  anthropic: "claude-haiku-4-5-20251001",
  openai: "gpt-4o-mini",
  fireworks: "accounts/fireworks/models/kimi-k2p6",
};

function getModel() {
  const provider = (process.env.CHRONICLE_LLM_PROVIDER || "anthropic") as Provider;
  const modelId = process.env.CHRONICLE_LLM_MODEL || DEFAULT_MODELS[provider];

  switch (provider) {
    case "openai":
      return openai(modelId);
    case "fireworks":
      return fireworks(modelId);
    case "anthropic":
    default:
      return anthropic(modelId);
  }
}

const SYSTEM_PROMPT = `You are a memory summarizer for a developer productivity tool called Chronicle.
You receive raw screen capture data (app name, window title, OCR text) from a developer's recent work session.

Your job is to produce a structured memory:
1. A concise title (one line, max 80 chars) describing what the developer was doing
2. A summary (2-4 sentences) explaining the work context, what they were focused on, and any direction or decisions visible
3. A project hint (project name or directory if visible, otherwise null)

Rules:
- Be specific: mention file names, function names, tools, and concepts you can see
- Be factual: only describe what the captures show, don't speculate
- Be concise: this will be retrieved by an AI assistant for context, not read by a human at length
- If the OCR text contains code, mention the language and key identifiers
- If it looks like documentation, mention what topic`;

const memorySchema = z.object({
  title: z.string().describe("Concise one-line description of what the developer was working on (max 80 chars)"),
  summary: z.string().describe("2-4 sentence summary of the work context"),
  project_hint: z.string().nullable().describe("Project name or directory if visible, otherwise null"),
});

async function summarizeWindow(
  windowStart: string,
  windowEnd: string
): Promise<void> {
  const captures = getCapturesInWindow(windowStart, windowEnd);
  if (captures.length === 0) return;

  const appCounts = new Map<string, number>();
  for (const c of captures) {
    appCounts.set(c.app_name, (appCounts.get(c.app_name) || 0) + 1);
  }
  const primaryApp =
    [...appCounts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] || "Unknown";

  const contextParts = captures.map((c) => {
    const lines = [
      `[${c.ts}] ${c.app_name} | ${c.window_title}`,
    ];
    if (c.ocr_text) {
      const truncated =
        c.ocr_text.length > 500 ? c.ocr_text.slice(0, 500) + "..." : c.ocr_text;
      lines.push(truncated);
    }
    return lines.join("\n");
  });

  const rawContext = contextParts.join("\n---\n");

  const prompt = `Here are screen captures from a developer's recent work window (${windowStart} to ${windowEnd}):

${rawContext}

Summarize what the developer was working on.`;

  const provider = process.env.CHRONICLE_LLM_PROVIDER || "anthropic";
  const modelId = process.env.CHRONICLE_LLM_MODEL || "default";
  log.info(`[open-chronicle] Summarizing window ${windowStart} – ${windowEnd} (${captures.length} captures) via ${provider}/${modelId}`);

  try {
    const { object } = await generateObject({
      model: getModel(),
      system: SYSTEM_PROMPT,
      prompt,
      schema: memorySchema,
      maxOutputTokens: 300,
      temperature: 0.3,
    });

    insertMemory({
      start_ts: windowStart,
      end_ts: windowEnd,
      app_name: primaryApp,
      title: object.title,
      summary: object.summary,
      raw_context: rawContext.slice(0, 2000),
      project_hint: object.project_hint,
    });

    log.info(`[open-chronicle] Memory created: "${object.title}" (${windowStart} – ${windowEnd})`);
  } catch (err) {
    log.error(`[open-chronicle] Failed to generate memory for window ${windowStart} – ${windowEnd}`, err);
  }
}

export async function runMemoryBuilder(): Promise<void> {
  const windowSec = parseInt(getSetting("memory_window_sec") || "60", 10);
  const windows = getUnsummarizedWindows(windowSec);

  for (const w of windows) {
    await summarizeWindow(w.windowStart, w.windowEnd);
  }
}

export function startMemoryBuilderLoop(intervalMs = 30_000): NodeJS.Timeout {
  log.info(`[open-chronicle] Memory builder started (interval: ${intervalMs / 1000}s)`);

  const timer = setInterval(async () => {
    try {
      await runMemoryBuilder();
    } catch (err) {
      log.error(`[open-chronicle] Memory builder tick error`, err);
    }
  }, intervalMs);

  runMemoryBuilder().catch((err) => log.error(`[open-chronicle] Memory builder initial run failed`, err));

  return timer;
}
