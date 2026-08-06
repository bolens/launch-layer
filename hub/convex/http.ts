import { httpRouter } from "convex/server";
import { httpAction, type ActionCtx } from "./_generated/server";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import {
  publishAuthEnforced,
  verifyPrivilegedHubAuth,
} from "./lib/auth";
import { parseFingerprint } from "./lib/fingerprint";
import { publishHttpStatusForError } from "./lib/publish";
import {
  requestIdentifier,
  type RateLimitRoute,
} from "./lib/rate_limit";
import {
  assertRequestBodySize,
  MAX_HTTP_BODY_BYTES,
  parseDetection,
  parseJsonObjectBody,
} from "./lib/http_body";
import { validateConfigId } from "./lib/validation";

const http = httpRouter();

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

function errorResponse(error: unknown, fallbackMessage: string): Response {
  const message = error instanceof Error ? error.message : fallbackMessage;
  const status = publishHttpStatusForError(message);
  return jsonResponse(
    { error: message.replace(/^[^:]+:\s*/, ""), code: message.split(":")[0] },
    status,
  );
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  const contentLength = Number(request.headers.get("Content-Length") ?? 0);
  const body = await request.text();
  assertRequestBodySize(contentLength, body.length, MAX_HTTP_BODY_BYTES);
  return parseJsonObjectBody(body);
}

async function enforceRouteRateLimit(
  ctx: ActionCtx,
  request: Request,
  route: RateLimitRoute,
  body?: Record<string, unknown>,
): Promise<void> {
  await ctx.runMutation(internal.rate_limits.enforceRateLimit, {
    route,
    identifier: await requestIdentifier(request, body),
  });
}

http.route({
  path: "/api/auth",
  method: "GET",
  handler: httpAction(async () => {
    return jsonResponse({ publish_auth_required: publishAuthEnforced() });
  }),
});

http.route({
  path: "/api/publish",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const authError = verifyPrivilegedHubAuth(request);
    if (authError) {
      return authError;
    }

    try {
      const body = await readJson(request);
      await enforceRouteRateLimit(ctx, request, "publish", body);
      const settings = (body.settings as Array<{ key: string; value: string }>) ?? [];
      const detection = parseDetection(body.detection);
      const configIdRaw = body.config_id ? String(body.config_id) : undefined;
      if (configIdRaw) {
        validateConfigId(configIdRaw);
      }

      const result = await ctx.runMutation(internal.configs.publishConfig, {
        fingerprintHash: String(body.fingerprint_hash),
        fingerprint: parseFingerprint(body.fingerprint),
        machineLabel: body.machine_label ? String(body.machine_label) : undefined,
        appid: String(body.appid),
        gameName: String(body.game_name),
        envContent: String(body.env_content),
        settings,
        preset: body.preset ? String(body.preset) : undefined,
        note: body.note ? String(body.note) : undefined,
        detection,
        launchlayerVersion: body.launchlayer_version
          ? String(body.launchlayer_version)
          : undefined,
        configId: configIdRaw
          ? (configIdRaw as Id<"sharedConfigs">)
          : undefined,
      });

      return jsonResponse(result);
    } catch (error) {
      return errorResponse(error, "Publish failed");
    }
  }),
});

http.route({
  path: "/api/my-config",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await readJson(request);
      await enforceRouteRateLimit(ctx, request, "myConfig", body);
      const fingerprintHash = String(body.fingerprint_hash ?? "");
      const appid = String(body.appid ?? "");
      const result = await ctx.runQuery(internal.configs.findMyConfig, {
        fingerprintHash,
        appid,
      });
      return jsonResponse(result);
    } catch (error) {
      return errorResponse(error, "Lookup failed");
    }
  }),
});

http.route({
  path: "/api/delete",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const authError = verifyPrivilegedHubAuth(request);
    if (authError) {
      return authError;
    }

    try {
      const body = await readJson(request);
      await enforceRouteRateLimit(ctx, request, "delete", body);
      const configId = String(body.config_id ?? "");
      const fingerprintHash = String(body.fingerprint_hash ?? "");
      if (!configId) {
        return jsonResponse({ error: "config_id is required" }, 400);
      }
      if (!fingerprintHash) {
        return jsonResponse({ error: "fingerprint_hash is required" }, 400);
      }
      validateConfigId(configId);

      const result = await ctx.runMutation(internal.configs.deleteConfig, {
        configId: configId as Id<"sharedConfigs">,
        fingerprintHash,
      });
      if (!result) {
        return jsonResponse({ error: "Config not found" }, 404);
      }

      return jsonResponse(result);
    } catch (error) {
      return errorResponse(error, "Delete failed");
    }
  }),
});

http.route({
  path: "/api/recommend",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await readJson(request);
      await enforceRouteRateLimit(ctx, request, "recommend", body);
      const results = await ctx.runQuery(internal.configs.recommendConfigs, {
        fingerprint: parseFingerprint(body.fingerprint),
        appid: String(body.appid),
        limit: body.limit ? Number(body.limit) : undefined,
      });
      return jsonResponse({ results });
    } catch (error) {
      return errorResponse(error, "Recommend failed");
    }
  }),
});

http.route({
  path: "/api/similar-machines",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    try {
      const body = await readJson(request);
      await enforceRouteRateLimit(ctx, request, "similarMachines", body);
      const results = await ctx.runQuery(internal.machines.similarMachines, {
        fingerprint: parseFingerprint(body.fingerprint),
        limit: body.limit ? Number(body.limit) : undefined,
      });
      return jsonResponse({ results });
    } catch (error) {
      return errorResponse(error, "Similar machines failed");
    }
  }),
});

http.route({
  pathPrefix: "/api/config-history/",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    try {
      const url = new URL(request.url);
      const historyId = url.pathname.replace(/^\/api\/config-history\//, "").split("?")[0] ?? "";
      validateConfigId(historyId);
      await enforceRouteRateLimit(ctx, request, "getConfig");

      const typedHistoryId = historyId as Id<"sharedConfigsHistory">;
      const history = await ctx.runQuery(internal.configs.getHistoricalConfig, {
        historyId: typedHistoryId,
      });
      if (!history) {
        return jsonResponse({ error: "Historical config not found" }, 404);
      }
      return jsonResponse(history);
    } catch (error) {
      return errorResponse(error, "Historical config fetch failed");
    }
  }),
});

http.route({
  pathPrefix: "/api/config/",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    try {
      const url = new URL(request.url);
      const remainingPath = url.pathname.replace(/^\/api\/config\//, "").split("?")[0] ?? "";
      const parts = remainingPath.split("/");
      const configId = parts[0] ?? "";
      validateConfigId(configId);

      if (parts[1] === "history") {
        await enforceRouteRateLimit(ctx, request, "getConfig");
        const typedConfigId = configId as Id<"sharedConfigs">;
        const config = await ctx.runQuery(internal.configs.getConfig, {
          configId: typedConfigId,
        });
        if (!config) {
          return jsonResponse({ error: "Config not found" }, 404);
        }
        const history = await ctx.runQuery(internal.configs.getConfigHistory, {
          configId: typedConfigId,
        });
        return jsonResponse(history);
      }

      await enforceRouteRateLimit(ctx, request, "getConfig");
      const typedConfigId = configId as Id<"sharedConfigs">;
      const config = await ctx.runQuery(internal.configs.getConfig, {
        configId: typedConfigId,
      });
      if (!config) {
        return jsonResponse({ error: "Config not found" }, 404);
      }
      await ctx.runMutation(internal.configs.recordDownload, {
        configId: typedConfigId,
        identifier: await requestIdentifier(request),
      });
      return jsonResponse(config);
    } catch (error) {
      return errorResponse(error, "Config fetch failed");
    }
  }),
});

export default http;
