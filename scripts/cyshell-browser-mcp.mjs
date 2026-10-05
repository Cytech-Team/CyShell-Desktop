#!/usr/bin/env node
import readline from "node:readline";

const BRIDGE_URL = process.env.CYSHELL_BROWSER_BRIDGE_URL || "http://127.0.0.1:17373/api";
const MAX_BRIDGE_REQUEST_BYTES = 1024 * 1024;
const MAX_BRIDGE_RESPONSE_BYTES = 16 * 1024 * 1024;
const PROTOCOL_VERSION = "2024-11-05";
const SERVER_NAME = "cyshell-browser";
const SERVER_VERSION = "0.3.1";

const ACTIONS = [
  "tabs", "open", "switch", "close", "navigate", "back", "forward", "reload",
  "state", "screenshot", "move", "click", "double_click", "drag", "type",
  "keypress", "scroll", "wait"
];

const actionSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    action: { type: "string", enum: ACTIONS },
    tabId: { type: "integer", description: "Optional browser tab id. Defaults to the active tab." },
    url: { type: "string", description: "URL for open/navigate." },
    active: { type: "boolean", description: "Whether a newly opened tab should be active." },
    selector: { type: "string", description: "Optional CSS selector for semantic targeting." },
    text: { type: "string", description: "Visible text for semantic targeting or literal text for type." },
    index: { type: "integer", description: "Element index from state; requires snapshotId from that state." },
    snapshotId: { type: "string", description: "State snapshot identity required for an observed index." },
    frameId: { type: "integer", description: "Semantic pointer frame; only top frame (0) is supported. Use viewport coordinates for child frames." },
    x: { type: "integer", description: "Viewport x coordinate." },
    y: { type: "integer", description: "Viewport y coordinate, or legacy vertical scroll delta when deltaY is omitted." },
    button: { type: "string", enum: ["left", "middle", "right"], description: "Mouse button." },
    path: {
      type: "array",
      minItems: 2,
      items: {
        type: "object",
        additionalProperties: false,
        properties: { x: { type: "integer" }, y: { type: "integer" } },
        required: ["x", "y"]
      },
      description: "Drag path in viewport coordinates."
    },
    startX: { type: "integer" },
    startY: { type: "integer" },
    endX: { type: "integer" },
    endY: { type: "integer" },
    deltaX: { type: "integer", description: "Horizontal wheel delta." },
    deltaY: { type: "integer", description: "Vertical wheel delta." },
    key: { type: "string", description: "Key or chord such as ENTER or CTRL+A." },
    keys: {
      type: "array",
      items: { type: "string" },
      description: "Key/modifier list such as [\"CTRL\", \"A\"]."
    },
    ms: { type: "integer", minimum: 0, maximum: 15000, description: "Wait duration in milliseconds." }
  },
  required: ["action"]
};

const tool = {
  name: "browser_control",
  description:
    "Control the user's connected browser through the CyCom extension using a visual computer-use loop. " +
    "Supports deep rendered state, native PNG screenshots, real pointer move/click/double-click/drag/wheel, " +
    "real keyboard type/keypress, real tabs and navigation. " +
    "Actions can change page state and may focus a tab or browser window, including during capture; " +
    "this is not an isolated browser. Mutating actions automatically return a fresh screenshot. " +
    "Use state for semantic/accessible page understanding and screenshots when visual context matters.",
  inputSchema: actionSchema
};

function write(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

function textContent(text) {
  return { type: "text", text };
}

function safeJson(value, max = 180000) {
  let text;
  try { text = JSON.stringify(value); }
  catch { text = String(value); }
  if (text.length <= max) return text;
  return text.slice(0, max) + `...[truncated ${text.length - max} chars]`;
}

async function readBridgeResponse(response) {
  if (!response.body) return "";

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const chunks = [];
  let totalBytes = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      totalBytes += value.byteLength;
      if (totalBytes > MAX_BRIDGE_RESPONSE_BYTES) {
        throw new Error("CyShell Browser Bridge response exceeds 16 MiB limit");
      }

      chunks.push(decoder.decode(value, { stream: true }));
    }
    chunks.push(decoder.decode());
    return chunks.join("");
  } catch (error) {
    try { await reader.cancel(); } catch {}
    throw error;
  } finally {
    reader.releaseLock();
  }
}

async function bridgeCall(args) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25000);
  try {
    const requestBody = JSON.stringify(args);
    if (Buffer.byteLength(requestBody, "utf8") > MAX_BRIDGE_REQUEST_BYTES) {
      throw new Error("CyShell Browser Bridge request exceeds 1 MiB limit");
    }

    const response = await fetch(BRIDGE_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: requestBody,
      signal: controller.signal
    });
    const body = await readBridgeResponse(response);
    if (!response.ok) {
      throw new Error(`CyShell Browser Bridge HTTP ${response.status}: ${body}`);
    }
    let envelope;
    try { envelope = JSON.parse(body); }
    catch { throw new Error("CyShell Browser Bridge returned invalid JSON"); }
    if (!envelope?.ok) {
      throw new Error(String(envelope?.error || "CyShell Browser Bridge request failed"));
    }
    return envelope.result;
  } finally {
    clearTimeout(timeout);
  }
}

function stripScreenshotData(result) {
  if (!result || typeof result !== "object") return result;
  const { data, ...meta } = result;
  return meta;
}

function screenshotResult(result, prefix = "CyShell Browser screenshot") {
  if (!result || typeof result.data !== "string" || !result.data) {
    throw new Error("CyShell Browser screenshot did not contain image data");
  }
  const meta = stripScreenshotData(result);
  return {
    content: [
      textContent(prefix + "\n" + safeJson(meta, 12000)),
      { type: "image", data: result.data, mimeType: result.mimeType || "image/png" }
    ],
    structuredContent: meta,
    isError: false
  };
}

function needsPostActionObservation(action) {
  return new Set([
    "open", "switch", "navigate", "back", "forward", "reload",
    "move", "click", "double_click", "drag", "type", "keypress", "scroll", "wait"
  ]).has(action);
}

function tabIdFromResult(args, result) {
  const candidate = result?.tabId ?? result?.id ?? args?.tabId;
  return Number.isInteger(candidate) ? candidate : undefined;
}

async function callTool(args) {
  const action = args?.action;
  if (!ACTIONS.includes(action)) {
    throw new Error(`Unsupported browser action: ${String(action)}`);
  }

  const result = await bridgeCall(args);

  if (action === "screenshot") {
    return screenshotResult(result);
  }

  if (!needsPostActionObservation(action) || (action === "open" && args.active === false)) {
    return {
      content: [textContent(safeJson(result))],
      structuredContent: result,
      isError: false
    };
  }

  const screenshotArgs = { action: "screenshot" };
  const tabId = tabIdFromResult(args, result);
  if (tabId !== undefined) screenshotArgs.tabId = tabId;

  let shot;
  try {
    shot = await bridgeCall(screenshotArgs);
  } catch (error) {
    return {
      content: [
        textContent(
          "CyShell Browser action completed, but the visual verification screenshot failed.\n" +
          safeJson({ action_result: result, observation_error: String(error?.message || error) })
        )
      ],
      structuredContent: {
        action_result: result,
        observation_error: String(error?.message || error)
      },
      isError: false
    };
  }

  const observation = stripScreenshotData(shot);
  return {
    content: [
      textContent("CyShell Browser action completed. Fresh visual observation follows.\n" + safeJson(result, 30000)),
      { type: "image", data: shot.data, mimeType: shot.mimeType || "image/png" }
    ],
    structuredContent: {
      action_result: result,
      observation
    },
    isError: false
  };
}

async function handle(req) {
  if (req.method === "initialize") {
    return {
      protocolVersion: req.params?.protocolVersion || PROTOCOL_VERSION,
      capabilities: { tools: { listChanged: false } },
      serverInfo: { name: SERVER_NAME, version: SERVER_VERSION }
    };
  }
  if (req.method === "tools/list") {
    return { tools: [tool] };
  }
  if (req.method === "tools/call") {
    if (req.params?.name !== tool.name) {
      throw new Error(`Unknown tool: ${String(req.params?.name)}`);
    }
    return await callTool(req.params?.arguments || {});
  }
  if (req.method === "ping") return {};
  throw Object.assign(new Error(`Method not found: ${req.method}`), { code: -32601 });
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of rl) {
  if (!line.trim()) continue;
  let req;
  try {
    req = JSON.parse(line);
  } catch {
    write({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
    continue;
  }

  if (req.id === undefined || req.id === null) {
    continue;
  }

  try {
    const result = await handle(req);
    write({ jsonrpc: "2.0", id: req.id, result });
  } catch (error) {
    write({
      jsonrpc: "2.0",
      id: req.id,
      error: {
        code: Number.isInteger(error?.code) ? error.code : -32000,
        message: String(error?.message || error)
      }
    });
  }
}
