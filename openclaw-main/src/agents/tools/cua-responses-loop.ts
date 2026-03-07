/**
 * CUA Responses Loop — Tua Agent integration of the OpenAI GPT-5.4 Computer Use Agent.
 *
 * Adapted from openai-cua-sample-app/packages/runner-core/src/responses-loop.ts.
 * Provides both "native" (raw computer-tool actions) and "code" (Playwright REPL) execution
 * modes against a Playwright browser session, driven by the OpenAI Responses API.
 */

import vm from "node:vm";
import util from "node:util";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type ComputerAction = {
  [key: string]: unknown;
  type: string;
};

type ComputerCallItem = {
  actions?: ComputerAction[];
  call_id?: string;
  pending_safety_checks?: SafetyCheck[];
  type: "computer_call";
};

type FunctionCallItem = {
  arguments?: string;
  call_id?: string;
  name?: string;
  type: "function_call";
};

type MessageItem = {
  content?: Array<{
    text?: string;
    type?: string;
  }>;
  role?: string;
  type: "message";
};

type ResponseOutputItem =
  | ComputerCallItem
  | FunctionCallItem
  | MessageItem
  | { [key: string]: unknown; type: string };

type ResponsesApiResponse = {
  error?: { message?: string } | null;
  id: string;
  output?: ResponseOutputItem[];
  status?: string;
  usage?: {
    input_tokens?: number;
    output_tokens?: number;
    output_tokens_details?: {
      reasoning_tokens?: number;
    };
    total_tokens?: number;
  } | null;
};

type SafetyCheck = {
  code?: string;
  message?: string;
};

type ToolOutput =
  | { text: string; type: "input_text" }
  | { detail: "original"; image_url: string; type: "input_image" };

export type CuaMode = "native" | "code";

export interface CuaRunOptions {
  apiKey: string;
  prompt: string;
  instructions?: string;
  model?: string;
  mode?: CuaMode;
  maxTurns?: number;
  headless?: boolean;
  startUrl?: string;
  screenshotDir?: string;
  signal?: AbortSignal;
}

export interface CuaRunResult {
  finalMessage?: string;
  notes: string[];
  screenshots: string[];
  usage: { inputTokens: number; outputTokens: number; reasoningTokens: number };
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const DEFAULT_MAX_TURNS = 24;
const DEFAULT_MODEL = "gpt-5.4";
const DEFAULT_INTER_ACTION_DELAY_MS = 120;
const TOOL_EXECUTION_TIMEOUT_MS = 20_000;

const DEFAULT_VIEWPORT = { width: 1440, height: 900 };

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function normalizePlaywrightKey(key: string): string {
  const normalized = key.trim();
  const lookup = normalized.toUpperCase();
  switch (lookup) {
    case "CTRL":
    case "CONTROL":
      return "Control";
    case "CMD":
    case "COMMAND":
    case "META":
      return "Meta";
    case "ALT":
    case "OPTION":
      return "Alt";
    case "SHIFT":
      return "Shift";
    case "ENTER":
    case "RETURN":
      return "Enter";
    case "ESC":
    case "ESCAPE":
      return "Escape";
    case "SPACE":
      return "Space";
    case "TAB":
      return "Tab";
    case "BACKSPACE":
      return "Backspace";
    case "DELETE":
      return "Delete";
    case "HOME":
      return "Home";
    case "END":
      return "End";
    case "PGUP":
    case "PAGEUP":
      return "PageUp";
    case "PGDN":
    case "PAGEDOWN":
      return "PageDown";
    case "UP":
    case "ARROWUP":
      return "ArrowUp";
    case "DOWN":
    case "ARROWDOWN":
      return "ArrowDown";
    case "LEFT":
    case "ARROWLEFT":
      return "ArrowLeft";
    case "RIGHT":
    case "ARROWRIGHT":
      return "ArrowRight";
    default:
      return normalized.length === 1
        ? normalized
        : normalized.charAt(0).toUpperCase() + normalized.slice(1).toLowerCase();
  }
}

function normalizeImageDataUrl(value: string): string {
  return value.startsWith("data:image/") ? value : `data:image/png;base64,${value}`;
}

function assertActive(signal?: AbortSignal): void {
  if (signal?.aborted) {
    throw new Error("CUA run aborted.");
  }
}

async function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  if (ms <= 0) return;
  assertActive(signal);
  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => {
      if (signal) signal.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      if (signal) signal.removeEventListener("abort", onAbort);
      reject(new Error("CUA run aborted."));
    };
    if (signal) signal.addEventListener("abort", onAbort, { once: true });
  });
}

function isFunctionCall(item: ResponseOutputItem): item is FunctionCallItem {
  return item.type === "function_call";
}

function isComputerCall(item: ResponseOutputItem): item is ComputerCallItem {
  return item.type === "computer_call";
}

function extractAssistantText(response: ResponsesApiResponse): string {
  return (response.output ?? [])
    .filter((item): item is MessageItem => item.type === "message")
    .flatMap((item) => item.content ?? [])
    .filter((part) => part.type === "output_text")
    .map((part) => part.text?.trim())
    .filter((text): text is string => Boolean(text))
    .join("\n\n");
}

// ---------------------------------------------------------------------------
// Dynamic Playwright import (optional dependency)
// ---------------------------------------------------------------------------

let playwrightModule: typeof import("playwright") | null = null;

async function requirePlaywright(): Promise<typeof import("playwright")> {
  if (playwrightModule) return playwrightModule;
  try {
    playwrightModule = await import("playwright");
    return playwrightModule;
  } catch {
    throw new Error(
      "Playwright is required for CUA browser automation but is not installed. " +
        "Run: npm install playwright && npx playwright install chromium",
    );
  }
}

// ---------------------------------------------------------------------------
// OpenAI client (lightweight wrapper)
// ---------------------------------------------------------------------------

async function callResponsesApi(
  apiKey: string,
  request: Record<string, unknown>,
  signal?: AbortSignal,
): Promise<ResponsesApiResponse> {
  const OpenAI = (await import("openai")).default;
  const client = new OpenAI({ apiKey });
  return (await client.responses.create(request, { signal })) as ResponsesApiResponse;
}

// ---------------------------------------------------------------------------
// Computer action executor (same as CUA sample app)
// ---------------------------------------------------------------------------

async function executeComputerAction(
  page: import("playwright").Page,
  action: ComputerAction,
  signal?: AbortSignal,
): Promise<void> {
  const buttonValue = action.button;
  const button =
    buttonValue === "right" || buttonValue === 2 || buttonValue === 3
      ? ("right" as const)
      : buttonValue === "middle" || buttonValue === "wheel"
        ? ("middle" as const)
        : ("left" as const);
  const x = Number(action.x ?? 0);
  const y = Number(action.y ?? 0);

  switch (action.type) {
    case "click":
      await page.mouse.click(x, y, { button });
      break;
    case "double_click":
      await page.mouse.dblclick(x, y, { button });
      break;
    case "drag": {
      const dragPath = Array.isArray(action.path)
        ? action.path
            .map((point) =>
              point && typeof point === "object" && "x" in point && "y" in point
                ? { x: Number((point as { x: unknown }).x), y: Number((point as { y: unknown }).y) }
                : null,
            )
            .filter((p): p is { x: number; y: number } => p !== null)
        : [];
      if (dragPath.length < 2) throw new Error("drag action needs at least 2 path points.");
      const start = dragPath[0]!;
      await page.mouse.move(start.x, start.y);
      await page.mouse.down();
      for (const point of dragPath.slice(1)) {
        await page.mouse.move(point.x, point.y);
      }
      await page.mouse.up();
      break;
    }
    case "move":
      await page.mouse.move(x, y);
      break;
    case "scroll":
      if (Number.isFinite(x) && Number.isFinite(y)) await page.mouse.move(x, y);
      await page.mouse.wheel(
        Number(action.delta_x ?? action.deltaX ?? 0),
        Number(action.delta_y ?? action.deltaY ?? action.scroll_y ?? 0),
      );
      break;
    case "type":
      await page.keyboard.type(String(action.text ?? ""));
      break;
    case "keypress": {
      const keys = Array.isArray(action.keys)
        ? action.keys.map((k) => normalizePlaywrightKey(String(k))).filter(Boolean)
        : [normalizePlaywrightKey(String(action.key ?? ""))].filter(Boolean);
      if (keys.length === 0) throw new Error("keypress action missing key value.");
      await page.keyboard.press(keys.join("+"));
      break;
    }
    case "wait": {
      const durationMs = Number(action.ms ?? action.duration_ms ?? 1_000);
      await sleep(Math.max(0, durationMs), signal);
      break;
    }
    case "screenshot":
      break;
    default:
      throw new Error(`Unsupported CUA computer action: ${action.type}`);
  }

  if (action.type !== "wait" && action.type !== "screenshot") {
    await sleep(DEFAULT_INTER_ACTION_DELAY_MS, signal);
  }
}

// ---------------------------------------------------------------------------
// Main CUA run function
// ---------------------------------------------------------------------------

export async function runCua(options: CuaRunOptions): Promise<CuaRunResult> {
  const pw = await requirePlaywright();
  const model = options.model || DEFAULT_MODEL;
  const mode = options.mode || "native";
  const maxTurns = options.maxTurns || DEFAULT_MAX_TURNS;
  const viewport = DEFAULT_VIEWPORT;
  const screenshotDir =
    options.screenshotDir || path.join(os.tmpdir(), `tua-cua-${crypto.randomUUID()}`);
  await fs.mkdir(screenshotDir, { recursive: true });

  const screenshots: string[] = [];
  const totalUsage = { inputTokens: 0, outputTokens: 0, reasoningTokens: 0 };

  // Launch browser
  const browser = await pw.chromium.launch({
    args: [`--window-size=${viewport.width},${viewport.height}`],
    headless: options.headless !== false,
  });
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  const startUrl = options.startUrl || "about:blank";
  await page.goto(startUrl, { waitUntil: "load" });

  async function captureScreenshot(label: string): Promise<string> {
    const filename = `${String(screenshots.length + 1).padStart(3, "0")}-${label
      .replace(/[^a-z0-9]+/gi, "-")
      .slice(0, 64)}.png`;
    const filePath = path.join(screenshotDir, filename);
    await page.screenshot({ path: filePath });
    screenshots.push(filePath);
    return filePath;
  }

  async function captureDataUrl(): Promise<string> {
    const buffer = await page.screenshot({ type: "png" });
    return `data:image/png;base64,${buffer.toString("base64")}`;
  }

  const instructions =
    options.instructions ||
    "You are Tua Agent, a computer-use operator. Complete the user's task by interacting with the browser.";

  try {
    if (mode === "code") {
      return await runCodeLoop();
    }
    return await runNativeLoop();
  } finally {
    await context.close().catch(() => {});
    await browser.close().catch(() => {});
  }

  // ------- Native mode -------
  async function runNativeLoop(): Promise<CuaRunResult> {
    let previousResponseId: string | undefined;
    let nextInput: unknown = [
      {
        content: [
          { text: options.prompt, type: "input_text" },
          { detail: "original", image_url: await captureDataUrl(), type: "input_image" },
        ],
        role: "user",
      },
    ];
    let finalMessage: string | undefined;

    for (let turn = 1; turn <= maxTurns; turn++) {
      assertActive(options.signal);
      const response = await callResponsesApi(
        options.apiKey,
        {
          instructions,
          input: nextInput,
          model,
          parallel_tool_calls: false,
          previous_response_id: previousResponseId,
          reasoning: { effort: "low" },
          tools: [{ type: "computer" }],
          truncation: "auto",
        },
        options.signal,
      );
      if (response.error?.message) throw new Error(response.error.message);
      if (response.status === "failed") throw new Error("CUA Responses API request failed.");

      accumulateUsage(response);
      previousResponseId = response.id;

      const hasToolCalls = (response.output ?? []).some(
        (item) => item.type === "computer_call" || item.type === "function_call",
      );
      if (!hasToolCalls) {
        finalMessage = extractAssistantText(response) || undefined;
        break;
      }

      const toolOutputs = [];
      for (const outputItem of response.output ?? []) {
        if (!isComputerCall(outputItem)) continue;

        const pendingSafety = outputItem.pending_safety_checks ?? [];
        if (pendingSafety.length > 0) {
          const detail = pendingSafety.map((c) => c.message ?? c.code ?? "unknown").join(" | ");
          throw new Error(`CUA safety check required: ${detail}`);
        }

        const actions = outputItem.actions ?? [];
        for (const action of actions) {
          await executeComputerAction(page, action, options.signal);
        }

        await captureScreenshot(`native-turn-${turn}`);
        const screenshotDataUrl = await captureDataUrl();

        toolOutputs.push({
          type: "computer_call_output",
          call_id: outputItem.call_id,
          output: { image_url: screenshotDataUrl, type: "computer_screenshot" },
        });
      }

      nextInput = toolOutputs;
    }

    if (!finalMessage) {
      throw new Error(`CUA native loop exhausted ${maxTurns}-turn budget without final message.`);
    }

    return {
      finalMessage,
      notes: ["Executed CUA via live Responses API native computer-tool loop.", `Final: ${finalMessage}`],
      screenshots,
      usage: totalUsage,
    };
  }

  // ------- Code mode -------
  async function runCodeLoop(): Promise<CuaRunResult> {
    const jsOutputRef: { current: ToolOutput[] } = { current: [] };
    const sandbox = {
      Buffer,
      browser,
      console: {
        log: (...values: unknown[]) => {
          jsOutputRef.current.push({
            text: util.formatWithOptions({ getters: false, maxStringLength: 2_000, showHidden: false }, ...values),
            type: "input_text" as const,
          });
        },
      },
      context,
      display: (base64Image: string) => {
        jsOutputRef.current.push({
          detail: "original" as const,
          image_url: normalizeImageDataUrl(base64Image),
          type: "input_image" as const,
        });
      },
      page,
      __setToolOutputs(outputs: ToolOutput[]) {
        jsOutputRef.current = outputs;
      },
    };
    const vmContext = vm.createContext(sandbox);
    let previousResponseId: string | undefined;
    let nextInput: unknown = options.prompt;
    let finalMessage: string | undefined;

    for (let turn = 1; turn <= maxTurns; turn++) {
      assertActive(options.signal);
      const response = await callResponsesApi(
        options.apiKey,
        {
          instructions,
          input: nextInput,
          model,
          parallel_tool_calls: false,
          previous_response_id: previousResponseId,
          reasoning: { effort: "low" },
          tools: [
            {
              type: "function",
              name: "exec_js",
              description: "Execute JavaScript in a persistent Playwright REPL context.",
              strict: true,
              parameters: {
                additionalProperties: false,
                properties: {
                  code: {
                    description:
                      "JavaScript to execute in an async Playwright REPL. Available globals: console.log, display(base64Image), Buffer, browser, context, page.",
                    type: "string",
                  },
                },
                required: ["code"],
                type: "object",
              },
            },
          ],
          truncation: "auto",
        },
        options.signal,
      );
      if (response.error?.message) throw new Error(response.error.message);
      if (response.status === "failed") throw new Error("CUA Responses API request failed.");

      accumulateUsage(response);
      previousResponseId = response.id;

      const functionCalls = (response.output ?? []).filter(isFunctionCall);
      if (functionCalls.length === 0) {
        finalMessage = extractAssistantText(response) || undefined;
        break;
      }

      const toolOutputs = [];
      for (const funcCall of functionCalls) {
        if (!funcCall.call_id) throw new Error("Unexpected function call without call_id.");
        const parsed = JSON.parse(funcCall.arguments ?? "{}") as { code?: string };
        const code = parsed.code ?? "";
        const outputs: ToolOutput[] = [];
        jsOutputRef.current = outputs;

        if (code.trim().length > 0) {
          try {
            const wrapped = `(async () => {\n${code}\n})();`;
            const execution = new vm.Script(wrapped, { filename: "exec_js.js" }).runInContext(vmContext);
            await Promise.resolve(execution);
          } catch (error) {
            const msg = error instanceof Error ? `${error.message}\n${error.stack ?? ""}` : String(error);
            outputs.push({ text: msg.trim(), type: "input_text" });
          }
        }

        if (outputs.length === 0) {
          outputs.push({ text: "exec_js completed with no console output.", type: "input_text" });
        }

        await captureScreenshot(`code-turn-${turn}`);
        toolOutputs.push({ call_id: funcCall.call_id, output: outputs, type: "function_call_output" });
      }

      nextInput = toolOutputs;
    }

    if (!finalMessage) {
      throw new Error(`CUA code loop exhausted ${maxTurns}-turn budget without final message.`);
    }

    return {
      finalMessage,
      notes: ["Executed CUA via live Responses API code (Playwright REPL) loop.", `Final: ${finalMessage}`],
      screenshots,
      usage: totalUsage,
    };
  }

  function accumulateUsage(response: ResponsesApiResponse): void {
    totalUsage.inputTokens += response.usage?.input_tokens ?? 0;
    totalUsage.outputTokens += response.usage?.output_tokens ?? 0;
    totalUsage.reasoningTokens += response.usage?.output_tokens_details?.reasoning_tokens ?? 0;
  }
}
