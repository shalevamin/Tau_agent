import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import type { AgentToolResult } from "@mariozechner/pi-agent-core";
import { runCua, type CuaMode } from "./cua-responses-loop.js";
import { Type } from "@sinclair/typebox";
import {
  type CameraFacing,
  cameraTempPath,
  parseCameraClipPayload,
  parseCameraSnapPayload,
  writeCameraClipPayloadToFile,
  writeCameraPayloadToFile,
} from "../../cli/nodes-camera.js";
import { parseEnvPairs, parseTimeoutMs } from "../../cli/nodes-run.js";
import {
  parseScreenRecordPayload,
  screenRecordTempPath,
  writeScreenRecordToFile,
} from "../../cli/nodes-screen.js";
import { parseDurationMs } from "../../cli/parse-duration.js";
import type { OpenClawConfig } from "../../config/config.js";
import { parsePreparedSystemRunPayload } from "../../infra/system-run-approval-context.js";
import { imageMimeFromFormat } from "../../media/mime.js";
import type { GatewayMessageChannel } from "../../utils/message-channel.js";
import { resolveSessionAgentId } from "../agent-scope.js";
import { resolveImageSanitizationLimits } from "../image-sanitization.js";
import { optionalStringEnum, stringEnum } from "../schema/typebox.js";
import { sanitizeToolResultImages } from "../tool-images.js";
import { type AnyAgentTool, jsonResult, readStringParam } from "./common.js";
import { callGatewayTool, readGatewayCallOptions } from "./gateway.js";
import { listNodes, resolveNode, resolveNodeId, resolveNodeIdFromList } from "./nodes-utils.js";

const NODES_TOOL_ACTIONS = [
  "status",
  "describe",
  "pending",
  "approve",
  "reject",
  "notify",
  "camera_snap",
  "camera_list",
  "camera_clip",
  "photos_latest",
  "screen_record",
  "computer_screenshot",
  "computer_mouse",
  "computer_type",
  "computer_keypress",
  "cua_run",
  "location_get",
  "notifications_list",
  "notifications_action",
  "device_status",
  "device_info",
  "device_permissions",
  "device_health",
  "run",
  "invoke",
] as const;

const CUA_MODES = ["native", "code"] as const;

const NOTIFY_PRIORITIES = ["passive", "active", "timeSensitive"] as const;
const NOTIFY_DELIVERIES = ["system", "overlay", "auto"] as const;
const NOTIFICATIONS_ACTIONS = ["open", "dismiss", "reply"] as const;
const CAMERA_FACING = ["front", "back", "both"] as const;
const LOCATION_ACCURACY = ["coarse", "balanced", "precise"] as const;
const COMPUTER_MOUSE_ACTIONS = ["move", "click", "doubleClick", "down", "up", "scroll"] as const;
const COMPUTER_MOUSE_BUTTONS = ["left", "right", "center"] as const;
const COMPUTER_INPUT_ORIGINS = ["topLeft", "bottomLeft"] as const;
const COMPUTER_KEY_MODIFIERS = ["command", "shift", "option", "control", "fn"] as const;
const MEDIA_INVOKE_ACTIONS = {
  "camera.snap": "camera_snap",
  "camera.clip": "camera_clip",
  "photos.latest": "photos_latest",
  "screen.record": "screen_record",
  "system.screenshot": "computer_screenshot",
} as const;
const NODE_READ_ACTION_COMMANDS = {
  camera_list: "camera.list",
  notifications_list: "notifications.list",
  device_status: "device.status",
  device_info: "device.info",
  device_permissions: "device.permissions",
  device_health: "device.health",
} as const;
type GatewayCallOptions = ReturnType<typeof readGatewayCallOptions>;

async function invokeNodeCommandPayload(params: {
  gatewayOpts: GatewayCallOptions;
  node: string;
  command: string;
  commandParams?: Record<string, unknown>;
}): Promise<unknown> {
  const nodeId = await resolveNodeId(params.gatewayOpts, params.node);
  const raw = await callGatewayTool<{ payload: unknown }>("node.invoke", params.gatewayOpts, {
    nodeId,
    command: params.command,
    params: params.commandParams ?? {},
    idempotencyKey: crypto.randomUUID(),
  });
  return raw?.payload ?? {};
}

type ComputerScreenshotPayload = {
  format: string;
  base64: string;
  width: number;
  height: number;
  coordinateWidth: number;
  coordinateHeight: number;
  screenIndex: number;
  screenOriginX?: number;
  screenOriginY?: number;
  inputOrigin?: string;
};

function parseComputerScreenshotPayload(payload: unknown): ComputerScreenshotPayload {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("invalid system.screenshot payload");
  }
  const raw = payload as Record<string, unknown>;
  const format = typeof raw.format === "string" ? raw.format.trim().toLowerCase() : "";
  const base64 = typeof raw.base64 === "string" ? raw.base64.trim() : "";
  const width = typeof raw.width === "number" ? raw.width : Number.NaN;
  const height = typeof raw.height === "number" ? raw.height : Number.NaN;
  const coordinateWidth =
    typeof raw.coordinateWidth === "number" ? raw.coordinateWidth : Number.NaN;
  const coordinateHeight =
    typeof raw.coordinateHeight === "number" ? raw.coordinateHeight : Number.NaN;
  const screenIndex = typeof raw.screenIndex === "number" ? raw.screenIndex : Number.NaN;
  if (!format || !base64 || !Number.isFinite(width) || !Number.isFinite(height)) {
    throw new Error("invalid system.screenshot payload");
  }
  if (!Number.isFinite(coordinateWidth) || !Number.isFinite(coordinateHeight)) {
    throw new Error("invalid coordinate metadata in system.screenshot payload");
  }
  if (!Number.isFinite(screenIndex)) {
    throw new Error("missing screen index in system.screenshot payload");
  }
  return {
    format,
    base64,
    width,
    height,
    coordinateWidth,
    coordinateHeight,
    screenIndex,
    ...(typeof raw.screenOriginX === "number" ? { screenOriginX: raw.screenOriginX } : {}),
    ...(typeof raw.screenOriginY === "number" ? { screenOriginY: raw.screenOriginY } : {}),
    ...(typeof raw.inputOrigin === "string" ? { inputOrigin: raw.inputOrigin } : {}),
  };
}

function computerScreenshotTempPath(format: string): string {
  const normalized = format === "png" ? "png" : "jpg";
  return path.join(os.tmpdir(), `openclaw-computer-${crypto.randomUUID()}.${normalized}`);
}

async function writeBase64ToFile(filePath: string, base64: string): Promise<void> {
  await fs.writeFile(filePath, Buffer.from(base64, "base64"));
}

function isPairingRequiredMessage(message: string): boolean {
  const lower = message.toLowerCase();
  return lower.includes("pairing required") || lower.includes("not_paired");
}

function extractPairingRequestId(message: string): string | null {
  const match = message.match(/\(requestId:\s*([^)]+)\)/i);
  if (!match) {
    return null;
  }
  const value = (match[1] ?? "").trim();
  return value.length > 0 ? value : null;
}

// Flattened schema: runtime validates per-action requirements.
const NodesToolSchema = Type.Object({
  action: stringEnum(NODES_TOOL_ACTIONS),
  gatewayUrl: Type.Optional(Type.String()),
  gatewayToken: Type.Optional(Type.String()),
  timeoutMs: Type.Optional(Type.Number()),
  node: Type.Optional(Type.String()),
  requestId: Type.Optional(Type.String()),
  // notify
  title: Type.Optional(Type.String()),
  body: Type.Optional(Type.String()),
  sound: Type.Optional(Type.String()),
  priority: optionalStringEnum(NOTIFY_PRIORITIES),
  delivery: optionalStringEnum(NOTIFY_DELIVERIES),
  // camera_snap / camera_clip
  facing: optionalStringEnum(CAMERA_FACING, {
    description: "camera_snap: front/back/both; camera_clip: front/back only.",
  }),
  maxWidth: Type.Optional(Type.Number()),
  quality: Type.Optional(Type.Number()),
  delayMs: Type.Optional(Type.Number()),
  deviceId: Type.Optional(Type.String()),
  limit: Type.Optional(Type.Number()),
  duration: Type.Optional(Type.String()),
  durationMs: Type.Optional(Type.Number({ maximum: 300_000 })),
  includeAudio: Type.Optional(Type.Boolean()),
  // screen_record
  fps: Type.Optional(Type.Number()),
  screenIndex: Type.Optional(Type.Number()),
  outPath: Type.Optional(Type.String()),
  // computer_use
  mouseAction: optionalStringEnum(COMPUTER_MOUSE_ACTIONS),
  x: Type.Optional(Type.Number()),
  y: Type.Optional(Type.Number()),
  button: optionalStringEnum(COMPUTER_MOUSE_BUTTONS),
  origin: optionalStringEnum(COMPUTER_INPUT_ORIGINS),
  deltaX: Type.Optional(Type.Number()),
  deltaY: Type.Optional(Type.Number()),
  imageWidth: Type.Optional(Type.Number()),
  imageHeight: Type.Optional(Type.Number()),
  text: Type.Optional(Type.String()),
  key: Type.Optional(Type.String()),
  modifiers: Type.Optional(Type.Array(stringEnum(COMPUTER_KEY_MODIFIERS))),
  // location_get
  maxAgeMs: Type.Optional(Type.Number()),
  locationTimeoutMs: Type.Optional(Type.Number()),
  desiredAccuracy: optionalStringEnum(LOCATION_ACCURACY),
  // notifications_action
  notificationAction: optionalStringEnum(NOTIFICATIONS_ACTIONS),
  notificationKey: Type.Optional(Type.String()),
  notificationReplyText: Type.Optional(Type.String()),
  // run
  command: Type.Optional(Type.Array(Type.String())),
  cwd: Type.Optional(Type.String()),
  env: Type.Optional(Type.Array(Type.String())),
  commandTimeoutMs: Type.Optional(Type.Number()),
  invokeTimeoutMs: Type.Optional(Type.Number()),
  needsScreenRecording: Type.Optional(Type.Boolean()),
  // invoke
  invokeCommand: Type.Optional(Type.String()),
  invokeParamsJson: Type.Optional(Type.String()),
  // cua_run (GPT-5.4 Responses API browser automation)
  cuaPrompt: Type.Optional(Type.String()),
  cuaMode: optionalStringEnum(CUA_MODES),
  cuaModel: Type.Optional(Type.String()),
  cuaMaxTurns: Type.Optional(Type.Number()),
  cuaStartUrl: Type.Optional(Type.String()),
  cuaHeadless: Type.Optional(Type.Boolean()),
});

export function createNodesTool(options?: {
  agentSessionKey?: string;
  agentChannel?: GatewayMessageChannel;
  agentAccountId?: string;
  currentChannelId?: string;
  currentThreadTs?: string | number;
  config?: OpenClawConfig;
  modelHasVision?: boolean;
  allowMediaInvokeCommands?: boolean;
}): AnyAgentTool {
  const sessionKey = options?.agentSessionKey?.trim() || undefined;
  const turnSourceChannel = options?.agentChannel?.trim() || undefined;
  const turnSourceTo = options?.currentChannelId?.trim() || undefined;
  const turnSourceAccountId = options?.agentAccountId?.trim() || undefined;
  const turnSourceThreadId = options?.currentThreadTs;
  const agentId = resolveSessionAgentId({
    sessionKey: options?.agentSessionKey,
    config: options?.config,
  });
  const imageSanitization = resolveImageSanitizationLimits(options?.config);
  return {
    label: "Nodes",
    name: "nodes",
    description:
      "Discover and control paired nodes (status/describe/pairing/notify/camera/photos/screen/computer-use/location/notifications/run/invoke).",
    parameters: NodesToolSchema,
    execute: async (_toolCallId, args) => {
      const params = args as Record<string, unknown>;
      const action = readStringParam(params, "action", { required: true });
      const gatewayOpts = readGatewayCallOptions(params);

      try {
        switch (action) {
          case "status":
            return jsonResult(await callGatewayTool("node.list", gatewayOpts, {}));
          case "describe": {
            const node = readStringParam(params, "node", { required: true });
            const nodeId = await resolveNodeId(gatewayOpts, node);
            return jsonResult(await callGatewayTool("node.describe", gatewayOpts, { nodeId }));
          }
          case "pending":
            return jsonResult(await callGatewayTool("node.pair.list", gatewayOpts, {}));
          case "approve": {
            const requestId = readStringParam(params, "requestId", {
              required: true,
            });
            return jsonResult(
              await callGatewayTool("node.pair.approve", gatewayOpts, {
                requestId,
              }),
            );
          }
          case "reject": {
            const requestId = readStringParam(params, "requestId", {
              required: true,
            });
            return jsonResult(
              await callGatewayTool("node.pair.reject", gatewayOpts, {
                requestId,
              }),
            );
          }
          case "notify": {
            const node = readStringParam(params, "node", { required: true });
            const title = typeof params.title === "string" ? params.title : "";
            const body = typeof params.body === "string" ? params.body : "";
            if (!title.trim() && !body.trim()) {
              throw new Error("title or body required");
            }
            const nodeId = await resolveNodeId(gatewayOpts, node);
            await callGatewayTool("node.invoke", gatewayOpts, {
              nodeId,
              command: "system.notify",
              params: {
                title: title.trim() || undefined,
                body: body.trim() || undefined,
                sound: typeof params.sound === "string" ? params.sound : undefined,
                priority: typeof params.priority === "string" ? params.priority : undefined,
                delivery: typeof params.delivery === "string" ? params.delivery : undefined,
              },
              idempotencyKey: crypto.randomUUID(),
            });
            return jsonResult({ ok: true });
          }
          case "camera_snap": {
            const node = readStringParam(params, "node", { required: true });
            const resolvedNode = await resolveNode(gatewayOpts, node);
            const nodeId = resolvedNode.nodeId;
            const facingRaw =
              typeof params.facing === "string" ? params.facing.toLowerCase() : "front";
            const facings: CameraFacing[] =
              facingRaw === "both"
                ? ["front", "back"]
                : facingRaw === "front" || facingRaw === "back"
                  ? [facingRaw]
                  : (() => {
                      throw new Error("invalid facing (front|back|both)");
                    })();
            const maxWidth =
              typeof params.maxWidth === "number" && Number.isFinite(params.maxWidth)
                ? params.maxWidth
                : 1600;
            const quality =
              typeof params.quality === "number" && Number.isFinite(params.quality)
                ? params.quality
                : 0.95;
            const delayMs =
              typeof params.delayMs === "number" && Number.isFinite(params.delayMs)
                ? params.delayMs
                : undefined;
            const deviceId =
              typeof params.deviceId === "string" && params.deviceId.trim()
                ? params.deviceId.trim()
                : undefined;
            if (deviceId && facings.length > 1) {
              throw new Error("facing=both is not allowed when deviceId is set");
            }

            const content: AgentToolResult<unknown>["content"] = [];
            const details: Array<Record<string, unknown>> = [];

            for (const facing of facings) {
              const raw = await callGatewayTool<{ payload: unknown }>("node.invoke", gatewayOpts, {
                nodeId,
                command: "camera.snap",
                params: {
                  facing,
                  maxWidth,
                  quality,
                  format: "jpg",
                  delayMs,
                  deviceId,
                },
                idempotencyKey: crypto.randomUUID(),
              });
              const payload = parseCameraSnapPayload(raw?.payload);
              const normalizedFormat = payload.format.toLowerCase();
              if (
                normalizedFormat !== "jpg" &&
                normalizedFormat !== "jpeg" &&
                normalizedFormat !== "png"
              ) {
                throw new Error(`unsupported camera.snap format: ${payload.format}`);
              }

              const isJpeg = normalizedFormat === "jpg" || normalizedFormat === "jpeg";
              const filePath = cameraTempPath({
                kind: "snap",
                facing,
                ext: isJpeg ? "jpg" : "png",
              });
              await writeCameraPayloadToFile({
                filePath,
                payload,
                expectedHost: resolvedNode.remoteIp,
                invalidPayloadMessage: "invalid camera.snap payload",
              });
              content.push({ type: "text", text: `MEDIA:${filePath}` });
              if (options?.modelHasVision && payload.base64) {
                content.push({
                  type: "image",
                  data: payload.base64,
                  mimeType:
                    imageMimeFromFormat(payload.format) ?? (isJpeg ? "image/jpeg" : "image/png"),
                });
              }
              details.push({
                facing,
                path: filePath,
                width: payload.width,
                height: payload.height,
              });
            }

            const result: AgentToolResult<unknown> = { content, details };
            return await sanitizeToolResultImages(result, "nodes:camera_snap", imageSanitization);
          }
          case "photos_latest": {
            const node = readStringParam(params, "node", { required: true });
            const resolvedNode = await resolveNode(gatewayOpts, node);
            const nodeId = resolvedNode.nodeId;
            const limitRaw =
              typeof params.limit === "number" && Number.isFinite(params.limit)
                ? Math.floor(params.limit)
                : DEFAULT_PHOTOS_LIMIT;
            const limit = Math.max(1, Math.min(limitRaw, MAX_PHOTOS_LIMIT));
            const maxWidth =
              typeof params.maxWidth === "number" && Number.isFinite(params.maxWidth)
                ? params.maxWidth
                : DEFAULT_PHOTOS_MAX_WIDTH;
            const quality =
              typeof params.quality === "number" && Number.isFinite(params.quality)
                ? params.quality
                : DEFAULT_PHOTOS_QUALITY;
            const raw = await callGatewayTool<{ payload: unknown }>("node.invoke", gatewayOpts, {
              nodeId,
              command: "photos.latest",
              params: {
                limit,
                maxWidth,
                quality,
              },
              idempotencyKey: crypto.randomUUID(),
            });
            const payload =
              raw?.payload && typeof raw.payload === "object" && !Array.isArray(raw.payload)
                ? (raw.payload as Record<string, unknown>)
                : {};
            const photos = Array.isArray(payload.photos) ? payload.photos : [];

            if (photos.length === 0) {
              const result: AgentToolResult<unknown> = {
                content: [],
                details: [],
              };
              return await sanitizeToolResultImages(
                result,
                "nodes:photos_latest",
                imageSanitization,
              );
            }

            const content: AgentToolResult<unknown>["content"] = [];
            const details: Array<Record<string, unknown>> = [];

            for (const [index, photoRaw] of photos.entries()) {
              const photo = parseCameraSnapPayload(photoRaw);
              const normalizedFormat = photo.format.toLowerCase();
              if (
                normalizedFormat !== "jpg" &&
                normalizedFormat !== "jpeg" &&
                normalizedFormat !== "png"
              ) {
                throw new Error(`unsupported photos.latest format: ${photo.format}`);
              }
              const isJpeg = normalizedFormat === "jpg" || normalizedFormat === "jpeg";
              const filePath = cameraTempPath({
                kind: "snap",
                ext: isJpeg ? "jpg" : "png",
                id: crypto.randomUUID(),
              });
              await writeCameraPayloadToFile({
                filePath,
                payload: photo,
                expectedHost: resolvedNode.remoteIp,
                invalidPayloadMessage: "invalid photos.latest payload",
              });

              content.push({ type: "text", text: `MEDIA:${filePath}` });
              if (options?.modelHasVision && photo.base64) {
                content.push({
                  type: "image",
                  data: photo.base64,
                  mimeType:
                    imageMimeFromFormat(photo.format) ?? (isJpeg ? "image/jpeg" : "image/png"),
                });
              }

              const createdAt =
                photoRaw && typeof photoRaw === "object" && !Array.isArray(photoRaw)
                  ? (photoRaw as Record<string, unknown>).createdAt
                  : undefined;
              details.push({
                index,
                path: filePath,
                width: photo.width,
                height: photo.height,
                ...(typeof createdAt === "string" ? { createdAt } : {}),
              });
            }

            const result: AgentToolResult<unknown> = { content, details };
            return await sanitizeToolResultImages(result, "nodes:photos_latest", imageSanitization);
          }
          case "camera_list":
          case "notifications_list":
          case "device_status":
          case "device_info":
          case "device_permissions":
          case "device_health": {
            const node = readStringParam(params, "node", { required: true });
            const command = NODE_READ_ACTION_COMMANDS[action];
            const payloadRaw = await invokeNodeCommandPayload({
              gatewayOpts,
              node,
              command,
            });
            const payload =
              payloadRaw && typeof payloadRaw === "object" && payloadRaw !== null ? payloadRaw : {};
            return jsonResult(payload);
          }
          case "notifications_action": {
            const node = readStringParam(params, "node", { required: true });
            const notificationKey = readStringParam(params, "notificationKey", { required: true });
            const notificationAction =
              typeof params.notificationAction === "string"
                ? params.notificationAction.trim().toLowerCase()
                : "";
            if (
              notificationAction !== "open" &&
              notificationAction !== "dismiss" &&
              notificationAction !== "reply"
            ) {
              throw new Error("notificationAction must be open|dismiss|reply");
            }
            const notificationReplyText =
              typeof params.notificationReplyText === "string"
                ? params.notificationReplyText.trim()
                : undefined;
            if (notificationAction === "reply" && !notificationReplyText) {
              throw new Error("notificationReplyText required when notificationAction=reply");
            }
            const payloadRaw = await invokeNodeCommandPayload({
              gatewayOpts,
              node,
              command: "notifications.actions",
              commandParams: {
                key: notificationKey,
                action: notificationAction,
                replyText: notificationReplyText,
              },
            });
            const payload =
              payloadRaw && typeof payloadRaw === "object" && payloadRaw !== null ? payloadRaw : {};
            return jsonResult(payload);
          }
          case "camera_clip": {
            const node = readStringParam(params, "node", { required: true });
            const resolvedNode = await resolveNode(gatewayOpts, node);
            const nodeId = resolvedNode.nodeId;
            const facing =
              typeof params.facing === "string" ? params.facing.toLowerCase() : "front";
            if (facing !== "front" && facing !== "back") {
              throw new Error("invalid facing (front|back)");
            }
            const durationMs =
              typeof params.durationMs === "number" && Number.isFinite(params.durationMs)
                ? params.durationMs
                : typeof params.duration === "string"
                  ? parseDurationMs(params.duration)
                  : 3000;
            const includeAudio =
              typeof params.includeAudio === "boolean" ? params.includeAudio : true;
            const deviceId =
              typeof params.deviceId === "string" && params.deviceId.trim()
                ? params.deviceId.trim()
                : undefined;
            const raw = await callGatewayTool<{ payload: unknown }>("node.invoke", gatewayOpts, {
              nodeId,
              command: "camera.clip",
              params: {
                facing,
                durationMs,
                includeAudio,
                format: "mp4",
                deviceId,
              },
              idempotencyKey: crypto.randomUUID(),
            });
            const payload = parseCameraClipPayload(raw?.payload);
            const filePath = await writeCameraClipPayloadToFile({
              payload,
              facing,
              expectedHost: resolvedNode.remoteIp,
            });
            return {
              content: [{ type: "text", text: `FILE:${filePath}` }],
              details: {
                facing,
                path: filePath,
                durationMs: payload.durationMs,
                hasAudio: payload.hasAudio,
              },
            };
          }
          case "screen_record": {
            const node = readStringParam(params, "node", { required: true });
            const nodeId = await resolveNodeId(gatewayOpts, node);
            const durationMs = Math.min(
              typeof params.durationMs === "number" && Number.isFinite(params.durationMs)
                ? params.durationMs
                : typeof params.duration === "string"
                  ? parseDurationMs(params.duration)
                  : 10_000,
              300_000,
            );
            const fps =
              typeof params.fps === "number" && Number.isFinite(params.fps) ? params.fps : 10;
            const screenIndex =
              typeof params.screenIndex === "number" && Number.isFinite(params.screenIndex)
                ? params.screenIndex
                : 0;
            const includeAudio =
              typeof params.includeAudio === "boolean" ? params.includeAudio : true;
            const raw = await callGatewayTool<{ payload: unknown }>("node.invoke", gatewayOpts, {
              nodeId,
              command: "screen.record",
              params: {
                durationMs,
                screenIndex,
                fps,
                format: "mp4",
                includeAudio,
              },
              idempotencyKey: crypto.randomUUID(),
            });
            const payload = parseScreenRecordPayload(raw?.payload);
            const filePath =
              typeof params.outPath === "string" && params.outPath.trim()
                ? params.outPath.trim()
                : screenRecordTempPath({ ext: payload.format || "mp4" });
            const written = await writeScreenRecordToFile(filePath, payload.base64);
            return {
              content: [{ type: "text", text: `FILE:${written.path}` }],
              details: {
                path: written.path,
                durationMs: payload.durationMs,
                fps: payload.fps,
                screenIndex: payload.screenIndex,
                hasAudio: payload.hasAudio,
              },
            };
          }
          case "computer_screenshot": {
            const node = readStringParam(params, "node", { required: true });
            const nodeId = await resolveNodeId(gatewayOpts, node);
            const screenIndex =
              typeof params.screenIndex === "number" && Number.isFinite(params.screenIndex)
                ? params.screenIndex
                : 0;
            const maxWidth =
              typeof params.maxWidth === "number" && Number.isFinite(params.maxWidth)
                ? params.maxWidth
                : undefined;
            const quality =
              typeof params.quality === "number" && Number.isFinite(params.quality)
                ? params.quality
                : undefined;
            const raw = await callGatewayTool<{ payload: unknown }>("node.invoke", gatewayOpts, {
              nodeId,
              command: "system.screenshot",
              params: {
                screenIndex,
                maxWidth,
                quality,
                format: "jpeg",
              },
              idempotencyKey: crypto.randomUUID(),
            });
            const payload = parseComputerScreenshotPayload(raw?.payload);
            const filePath = computerScreenshotTempPath(payload.format);
            await writeBase64ToFile(filePath, payload.base64);

            const content: AgentToolResult<unknown>["content"] = [
              { type: "text", text: `MEDIA:${filePath}` },
            ];
            if (options?.modelHasVision) {
              content.push({
                type: "image",
                data: payload.base64,
                mimeType: payload.format === "png" ? "image/png" : "image/jpeg",
              });
            }

            const result: AgentToolResult<unknown> = {
              content,
              details: {
                path: filePath,
                width: payload.width,
                height: payload.height,
                coordinateWidth: payload.coordinateWidth,
                coordinateHeight: payload.coordinateHeight,
                screenIndex: payload.screenIndex,
                screenOriginX: payload.screenOriginX,
                screenOriginY: payload.screenOriginY,
                inputOrigin: payload.inputOrigin ?? "topLeft",
              },
            };
            return await sanitizeToolResultImages(
              result,
              "nodes:computer_screenshot",
              imageSanitization,
            );
          }
          case "computer_mouse": {
            const node = readStringParam(params, "node", { required: true });
            const mouseAction =
              typeof params.mouseAction === "string" ? params.mouseAction.trim() : "";
            if (
              mouseAction !== "move" &&
              mouseAction !== "click" &&
              mouseAction !== "doubleClick" &&
              mouseAction !== "down" &&
              mouseAction !== "up" &&
              mouseAction !== "scroll"
            ) {
              throw new Error("mouseAction must be move|click|doubleClick|down|up|scroll");
            }
            const payload = await invokeNodeCommandPayload({
              gatewayOpts,
              node,
              command: "system.mouse",
              commandParams: {
                action: mouseAction,
                x: typeof params.x === "number" && Number.isFinite(params.x) ? params.x : undefined,
                y: typeof params.y === "number" && Number.isFinite(params.y) ? params.y : undefined,
                screenIndex:
                  typeof params.screenIndex === "number" && Number.isFinite(params.screenIndex)
                    ? params.screenIndex
                    : undefined,
                origin: typeof params.origin === "string" ? params.origin : undefined,
                button: typeof params.button === "string" ? params.button : undefined,
                deltaX:
                  typeof params.deltaX === "number" && Number.isFinite(params.deltaX)
                    ? params.deltaX
                    : undefined,
                deltaY:
                  typeof params.deltaY === "number" && Number.isFinite(params.deltaY)
                    ? params.deltaY
                    : undefined,
                fromWidth:
                  typeof params.imageWidth === "number" && Number.isFinite(params.imageWidth)
                    ? params.imageWidth
                    : undefined,
                fromHeight:
                  typeof params.imageHeight === "number" && Number.isFinite(params.imageHeight)
                    ? params.imageHeight
                    : undefined,
              },
            });
            return jsonResult(payload);
          }
          case "computer_type": {
            const node = readStringParam(params, "node", { required: true });
            const text = readStringParam(params, "text", { required: true });
            const payload = await invokeNodeCommandPayload({
              gatewayOpts,
              node,
              command: "system.type",
              commandParams: { text },
            });
            return jsonResult(payload);
          }
          case "computer_keypress": {
            const node = readStringParam(params, "node", { required: true });
            const key = readStringParam(params, "key", { required: true });
            const modifiers = Array.isArray(params.modifiers)
              ? params.modifiers.filter(
                  (value): value is string =>
                    typeof value === "string" &&
                    ["command", "shift", "option", "control", "fn"].includes(value),
                )
              : undefined;
            const payload = await invokeNodeCommandPayload({
              gatewayOpts,
              node,
              command: "system.keypress",
              commandParams: { key, modifiers },
            });
            return jsonResult(payload);
          }
          case "location_get": {
            const node = readStringParam(params, "node", { required: true });
            const maxAgeMs =
              typeof params.maxAgeMs === "number" && Number.isFinite(params.maxAgeMs)
                ? params.maxAgeMs
                : undefined;
            const desiredAccuracy =
              params.desiredAccuracy === "coarse" ||
              params.desiredAccuracy === "balanced" ||
              params.desiredAccuracy === "precise"
                ? params.desiredAccuracy
                : undefined;
            const locationTimeoutMs =
              typeof params.locationTimeoutMs === "number" &&
              Number.isFinite(params.locationTimeoutMs)
                ? params.locationTimeoutMs
                : undefined;
            const payload = await invokeNodeCommandPayload({
              gatewayOpts,
              node,
              command: "location.get",
              commandParams: {
                maxAgeMs,
                desiredAccuracy,
                timeoutMs: locationTimeoutMs,
              },
            });
            return jsonResult(payload);
          }
          case "run": {
            const node = readStringParam(params, "node", { required: true });
            const nodes = await listNodes(gatewayOpts);
            if (nodes.length === 0) {
              throw new Error(
                "system.run requires a paired companion app or node host (no nodes available).",
              );
            }
            const nodeId = resolveNodeIdFromList(nodes, node);
            const nodeInfo = nodes.find((entry) => entry.nodeId === nodeId);
            const supportsSystemRun = Array.isArray(nodeInfo?.commands)
              ? nodeInfo?.commands?.includes("system.run")
              : false;
            if (!supportsSystemRun) {
              throw new Error(
                "system.run requires a companion app or node host; the selected node does not support system.run.",
              );
            }
            const commandRaw = params.command;
            if (!commandRaw) {
              throw new Error("command required (argv array, e.g. ['echo', 'Hello'])");
            }
            if (!Array.isArray(commandRaw)) {
              throw new Error("command must be an array of strings (argv), e.g. ['echo', 'Hello']");
            }
            const command = commandRaw.map((c) => String(c));
            if (command.length === 0) {
              throw new Error("command must not be empty");
            }
            const cwd =
              typeof params.cwd === "string" && params.cwd.trim() ? params.cwd.trim() : undefined;
            const env = parseEnvPairs(params.env);
            const commandTimeoutMs = parseTimeoutMs(params.commandTimeoutMs);
            const invokeTimeoutMs = parseTimeoutMs(params.invokeTimeoutMs);
            const needsScreenRecording =
              typeof params.needsScreenRecording === "boolean"
                ? params.needsScreenRecording
                : undefined;
            const prepareRaw = await callGatewayTool<{ payload?: unknown }>(
              "node.invoke",
              gatewayOpts,
              {
                nodeId,
                command: "system.run.prepare",
                params: {
                  command,
                  cwd,
                  agentId,
                  sessionKey,
                },
                timeoutMs: invokeTimeoutMs,
                idempotencyKey: crypto.randomUUID(),
              },
            );
            const prepared = parsePreparedSystemRunPayload(prepareRaw?.payload);
            if (!prepared) {
              throw new Error("invalid system.run.prepare response");
            }
            const runParams = {
              command: prepared.plan.argv,
              rawCommand: prepared.plan.rawCommand ?? prepared.cmdText,
              cwd: prepared.plan.cwd ?? cwd,
              env,
              timeoutMs: commandTimeoutMs,
              needsScreenRecording,
              agentId: prepared.plan.agentId ?? agentId,
              sessionKey: prepared.plan.sessionKey ?? sessionKey,
            };

            // First attempt without approval flags.
            try {
              const raw = await callGatewayTool<{ payload?: unknown }>("node.invoke", gatewayOpts, {
                nodeId,
                command: "system.run",
                params: runParams,
                timeoutMs: invokeTimeoutMs,
                idempotencyKey: crypto.randomUUID(),
              });
              return jsonResult(raw?.payload ?? {});
            } catch (firstErr) {
              const msg = firstErr instanceof Error ? firstErr.message : String(firstErr);
              if (!msg.includes("SYSTEM_RUN_DENIED: approval required")) {
                throw firstErr;
              }
            }

            // Node requires approval – create a pending approval request on
            // the gateway and wait for the user to approve/deny via the UI.
            const APPROVAL_TIMEOUT_MS = 120_000;
            const approvalId = crypto.randomUUID();
            const approvalResult = await callGatewayTool(
              "exec.approval.request",
              { ...gatewayOpts, timeoutMs: APPROVAL_TIMEOUT_MS + 5_000 },
              {
                id: approvalId,
                command: prepared.cmdText,
                commandArgv: prepared.plan.argv,
                systemRunPlan: prepared.plan,
                cwd: prepared.plan.cwd ?? cwd,
                nodeId,
                host: "node",
                agentId: prepared.plan.agentId ?? agentId,
                sessionKey: prepared.plan.sessionKey ?? sessionKey,
                turnSourceChannel,
                turnSourceTo,
                turnSourceAccountId,
                turnSourceThreadId,
                timeoutMs: APPROVAL_TIMEOUT_MS,
              },
            );
            const decisionRaw =
              approvalResult && typeof approvalResult === "object"
                ? (approvalResult as { decision?: unknown }).decision
                : undefined;
            const approvalDecision =
              decisionRaw === "allow-once" || decisionRaw === "allow-always" ? decisionRaw : null;

            if (!approvalDecision) {
              if (decisionRaw === "deny") {
                throw new Error("exec denied: user denied");
              }
              if (decisionRaw === undefined || decisionRaw === null) {
                throw new Error("exec denied: approval timed out");
              }
              throw new Error("exec denied: invalid approval decision");
            }

            // Retry with the approval decision.
            const raw = await callGatewayTool<{ payload?: unknown }>("node.invoke", gatewayOpts, {
              nodeId,
              command: "system.run",
              params: {
                ...runParams,
                runId: approvalId,
                approved: true,
                approvalDecision,
              },
              timeoutMs: invokeTimeoutMs,
              idempotencyKey: crypto.randomUUID(),
            });
            return jsonResult(raw?.payload ?? {});
          }
          case "invoke": {
            const node = readStringParam(params, "node", { required: true });
            const nodeId = await resolveNodeId(gatewayOpts, node);
            const invokeCommand = readStringParam(params, "invokeCommand", { required: true });
            const invokeCommandNormalized = invokeCommand.trim().toLowerCase();
            const dedicatedAction =
              MEDIA_INVOKE_ACTIONS[invokeCommandNormalized as keyof typeof MEDIA_INVOKE_ACTIONS];
            if (dedicatedAction && !options?.allowMediaInvokeCommands) {
              throw new Error(
                `invokeCommand "${invokeCommand}" returns media payloads and is blocked to prevent base64 context bloat; use action="${dedicatedAction}"`,
              );
            }
            const invokeParamsJson =
              typeof params.invokeParamsJson === "string" ? params.invokeParamsJson.trim() : "";
            let invokeParams: unknown = {};
            if (invokeParamsJson) {
              try {
                invokeParams = JSON.parse(invokeParamsJson);
              } catch (err) {
                const message = err instanceof Error ? err.message : String(err);
                throw new Error(`invokeParamsJson must be valid JSON: ${message}`, {
                  cause: err,
                });
              }
            }
            const invokeTimeoutMs = parseTimeoutMs(params.invokeTimeoutMs);
            const raw = await callGatewayTool("node.invoke", gatewayOpts, {
              nodeId,
              command: invokeCommand,
              params: invokeParams,
              timeoutMs: invokeTimeoutMs,
              idempotencyKey: crypto.randomUUID(),
            });
            return jsonResult(raw ?? {});
          }
          case "cua_run": {
            const cuaPrompt = typeof params.cuaPrompt === "string" ? params.cuaPrompt.trim() : "";
            if (!cuaPrompt) {
              throw new Error("cuaPrompt is required for cua_run");
            }
            const cuaMode = (typeof params.cuaMode === "string" ? params.cuaMode.trim() : "native") as CuaMode;
            const cuaModel = typeof params.cuaModel === "string" ? params.cuaModel.trim() : undefined;
            const cuaMaxTurns =
              typeof params.cuaMaxTurns === "number" && Number.isFinite(params.cuaMaxTurns)
                ? params.cuaMaxTurns
                : undefined;
            const cuaStartUrl = typeof params.cuaStartUrl === "string" ? params.cuaStartUrl.trim() : undefined;
            const cuaHeadless = typeof params.cuaHeadless === "boolean" ? params.cuaHeadless : true;

            const apiKey = process.env.OPENAI_API_KEY;
            if (!apiKey) {
              throw new Error(
                "OPENAI_API_KEY is required for cua_run. Set it in your environment or openclaw config.",
              );
            }

            const result = await runCua({
              apiKey,
              prompt: cuaPrompt,
              mode: cuaMode,
              model: cuaModel,
              maxTurns: cuaMaxTurns,
              startUrl: cuaStartUrl,
              headless: cuaHeadless,
            });

            return jsonResult({
              finalMessage: result.finalMessage,
              screenshots: result.screenshots,
              usage: result.usage,
              notes: result.notes,
            });
          }
          default:
            throw new Error(`Unknown action: ${action}`);
        }
      } catch (err) {
        const nodeLabel =
          typeof params.node === "string" && params.node.trim() ? params.node.trim() : "auto";
        const gatewayLabel =
          gatewayOpts.gatewayUrl && gatewayOpts.gatewayUrl.trim()
            ? gatewayOpts.gatewayUrl.trim()
            : "default";
        const agentLabel = agentId ?? "unknown";
        let message = err instanceof Error ? err.message : String(err);
        if (action === "invoke" && isPairingRequiredMessage(message)) {
          const requestId = extractPairingRequestId(message);
          const approveHint = requestId
            ? `Approve pairing request ${requestId} and retry.`
            : "Approve the pending pairing request and retry.";
          message = `pairing required before node invoke. ${approveHint}`;
        }
        throw new Error(
          `agent=${agentLabel} node=${nodeLabel} gateway=${gatewayLabel} action=${action}: ${message}`,
          { cause: err },
        );
      }
    },
  };
}

const DEFAULT_PHOTOS_LIMIT = 1;
const MAX_PHOTOS_LIMIT = 20;
const DEFAULT_PHOTOS_MAX_WIDTH = 1600;
const DEFAULT_PHOTOS_QUALITY = 0.85;
