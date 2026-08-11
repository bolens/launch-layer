import { convexTest } from "convex-test";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { internal } from "./_generated/api";
import schema from "./schema";
import { modules } from "../test/convex_test_modules";
import { buildPublishArgs } from "../test/test_helpers";

const previousIdentityHeader = process.env.HUB_TRUSTED_CLIENT_IP_HEADER;
const previousIdentifierKey = process.env.HUB_IDENTIFIER_HASH_KEY;
const CLIENT_IP = "203.0.113.50";

function clientHeaders(
  headers: Record<string, string> = {},
): Record<string, string> {
  return { "CF-Connecting-IP": CLIENT_IP, ...headers };
}

beforeAll(() => {
  process.env.HUB_TRUSTED_CLIENT_IP_HEADER = "CF-Connecting-IP";
  process.env.HUB_IDENTIFIER_HASH_KEY =
    "test-identifier-key-with-32-characters";
});

afterAll(() => {
  if (previousIdentityHeader === undefined) {
    delete process.env.HUB_TRUSTED_CLIENT_IP_HEADER;
  } else {
    process.env.HUB_TRUSTED_CLIENT_IP_HEADER = previousIdentityHeader;
  }
  if (previousIdentifierKey === undefined) {
    delete process.env.HUB_IDENTIFIER_HASH_KEY;
  } else {
    process.env.HUB_IDENTIFIER_HASH_KEY = previousIdentifierKey;
  }
});

describe("hub HTTP routes", () => {
  it("handles CORS preflight for API routes", async () => {
    const t = convexTest(schema, modules);
    const response = await t.fetch("/api/publish", {
      method: "OPTIONS",
      headers: {
        Origin: "https://example.test",
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "Authorization, Content-Type",
      },
    });
    expect(response.status).toBe(204);
    expect(response.headers.get("Access-Control-Allow-Methods")).toContain(
      "POST",
    );
    expect(response.headers.get("Access-Control-Allow-Headers")).toContain(
      "Authorization",
    );
  });

  it("reports whether publish auth is enforced", async () => {
    const previousAllowOpen = process.env.HUB_ALLOW_OPEN_PUBLISH;
    const previousToken = process.env.HUB_PUBLISH_TOKEN;
    process.env.HUB_ALLOW_OPEN_PUBLISH = "1";
    delete process.env.HUB_PUBLISH_TOKEN;
    try {
      const t = convexTest(schema, modules);

      const response = await t.fetch("/api/auth");
      expect(response.status).toBe(200);

      const body = await response.json();
      expect(body).toMatchObject({ publish_auth_required: false });
    } finally {
      if (previousAllowOpen === undefined) {
        delete process.env.HUB_ALLOW_OPEN_PUBLISH;
      } else {
        process.env.HUB_ALLOW_OPEN_PUBLISH = previousAllowOpen;
      }
      if (previousToken === undefined) {
        delete process.env.HUB_PUBLISH_TOKEN;
      } else {
        process.env.HUB_PUBLISH_TOKEN = previousToken;
      }
    }
  });

  it("reports publish auth required when fail-closed", async () => {
    const previousAllowOpen = process.env.HUB_ALLOW_OPEN_PUBLISH;
    const previousToken = process.env.HUB_PUBLISH_TOKEN;
    delete process.env.HUB_ALLOW_OPEN_PUBLISH;
    delete process.env.HUB_PUBLISH_TOKEN;
    try {
      const t = convexTest(schema, modules);

      const response = await t.fetch("/api/auth");
      expect(response.status).toBe(200);

      const body = await response.json();
      expect(body).toMatchObject({ publish_auth_required: true });
    } finally {
      if (previousAllowOpen === undefined) {
        delete process.env.HUB_ALLOW_OPEN_PUBLISH;
      } else {
        process.env.HUB_ALLOW_OPEN_PUBLISH = previousAllowOpen;
      }
      if (previousToken === undefined) {
        delete process.env.HUB_PUBLISH_TOKEN;
      } else {
        process.env.HUB_PUBLISH_TOKEN = previousToken;
      }
    }
  });

  it("returns validation errors for malformed recommend requests", async () => {
    const t = convexTest(schema, modules);

    const response = await t.fetch("/api/recommend", {
      method: "POST",
      headers: clientHeaders({ "Content-Type": "application/json" }),
      body: JSON.stringify({
        fingerprint: {},
        appid: "not-a-number",
      }),
    });

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.code).toBe("VALIDATION_ERROR");
  });

  it("returns a shared config and records deduped downloads", async () => {
    const t = convexTest(schema, modules);
    const args = await buildPublishArgs({ appid: "271590" });
    const published = await t.mutation(internal.configs.publishConfig, args);

    const first = await t.fetch(`/api/config/${published.config_id}`, {
      headers: clientHeaders(),
    });
    expect(first.status).toBe(200);
    const firstBody = await first.json();
    expect(firstBody).toMatchObject({
      config_id: published.config_id,
      appid: "271590",
    });

    const second = await t.fetch(`/api/config/${published.config_id}`, {
      headers: clientHeaders(),
    });
    expect(second.status).toBe(200);

    const config = await t.run(async (ctx) => ctx.db.get("sharedConfigs", published.config_id));
    expect(config?.downloads).toBe(1);
  });

  it("rejects invalid config ids on GET /api/config", async () => {
    const t = convexTest(schema, modules);

    const response = await t.fetch("/api/config/cfg-test-1");
    expect(response.status).toBe(400);

    const body = await response.json();
    expect(body.code).toBe("VALIDATION_ERROR");
  });

  it("rejects delete requests with invalid config ids", async () => {
    const previousAllowOpen = process.env.HUB_ALLOW_OPEN_PUBLISH;
    const previousToken = process.env.HUB_PUBLISH_TOKEN;
    process.env.HUB_ALLOW_OPEN_PUBLISH = "1";
    delete process.env.HUB_PUBLISH_TOKEN;
    try {
      const t = convexTest(schema, modules);
      const args = await buildPublishArgs({ appid: "252950" });
      await t.mutation(internal.configs.publishConfig, args);

      const response = await t.fetch("/api/delete", {
        method: "POST",
        headers: clientHeaders({ "Content-Type": "application/json" }),
        body: JSON.stringify({
          config_id: "cfg-test-1",
          fingerprint_hash: args.fingerprintHash,
        }),
      });

      expect(response.status).toBe(400);
      const body = await response.json();
      expect(body.code).toBe("VALIDATION_ERROR");
    } finally {
      if (previousAllowOpen === undefined) {
        delete process.env.HUB_ALLOW_OPEN_PUBLISH;
      } else {
        process.env.HUB_ALLOW_OPEN_PUBLISH = previousAllowOpen;
      }
      if (previousToken === undefined) {
        delete process.env.HUB_PUBLISH_TOKEN;
      } else {
        process.env.HUB_PUBLISH_TOKEN = previousToken;
      }
    }
  });

  it("rejects privileged delete when publish auth is fail-closed", async () => {
    const previousAllowOpen = process.env.HUB_ALLOW_OPEN_PUBLISH;
    const previousToken = process.env.HUB_PUBLISH_TOKEN;
    delete process.env.HUB_ALLOW_OPEN_PUBLISH;
    delete process.env.HUB_PUBLISH_TOKEN;
    try {
      const t = convexTest(schema, modules);
      const response = await t.fetch("/api/delete", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          config_id: "jh7exampleconfigid01",
          fingerprint_hash: "a".repeat(64),
        }),
      });
      expect(response.status).toBe(401);
    } finally {
      if (previousAllowOpen === undefined) {
        delete process.env.HUB_ALLOW_OPEN_PUBLISH;
      } else {
        process.env.HUB_ALLOW_OPEN_PUBLISH = previousAllowOpen;
      }
      if (previousToken === undefined) {
        delete process.env.HUB_PUBLISH_TOKEN;
      } else {
        process.env.HUB_PUBLISH_TOKEN = previousToken;
      }
    }
  });

  it("rejects privileged publish when publish auth is fail-closed", async () => {
    const previousAllowOpen = process.env.HUB_ALLOW_OPEN_PUBLISH;
    const previousToken = process.env.HUB_PUBLISH_TOKEN;
    delete process.env.HUB_ALLOW_OPEN_PUBLISH;
    delete process.env.HUB_PUBLISH_TOKEN;
    try {
      const t = convexTest(schema, modules);
      const response = await t.fetch("/api/publish", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          fingerprint_hash: "a".repeat(64),
          fingerprint: {},
          appid: "42424242",
          game_name: "Test",
          env_content: "GAMEMODE=1\n",
          settings: [],
        }),
      });
      expect(response.status).toBe(401);
    } finally {
      if (previousAllowOpen === undefined) {
        delete process.env.HUB_ALLOW_OPEN_PUBLISH;
      } else {
        process.env.HUB_ALLOW_OPEN_PUBLISH = previousAllowOpen;
      }
      if (previousToken === undefined) {
        delete process.env.HUB_PUBLISH_TOKEN;
      } else {
        process.env.HUB_PUBLISH_TOKEN = previousToken;
      }
    }
  });

  it("can fetch config history list and a specific historical config", async () => {
    const t = convexTest(schema, modules);
    const args = await buildPublishArgs({ appid: "271590", note: "version 1" });
    const published = await t.mutation(internal.configs.publishConfig, args);

    // Update config to generate a second history record
    const updateArgs = await buildPublishArgs({ appid: "271590", note: "version 2" });
    await t.mutation(internal.configs.publishConfig, updateArgs);

    // 1. Fetch history list via HTTP GET /api/config/<configId>/history
    const historyRes = await t.fetch(
      `/api/config/${published.config_id}/history`,
      { headers: clientHeaders() },
    );
    expect(historyRes.status).toBe(200);
    const historyList = await historyRes.json();
    expect(historyList).toHaveLength(2);
    expect(historyList[0].note).toBe("version 2");
    expect(historyList[1].note).toBe("version 1");

    // 2. Fetch specific historical version via HTTP GET /api/config-history/<historyId>
    const historyId = historyList[1].history_id;
    const historyDocRes = await t.fetch(`/api/config-history/${historyId}`, {
      headers: clientHeaders(),
    });
    expect(historyDocRes.status).toBe(200);
    const historyDoc = await historyDocRes.json();
    expect(historyDoc).toMatchObject({
      history_id: historyId,
      config_id: published.config_id,
      appid: "271590",
      note: "version 1",
    });
    expect(typeof historyDoc.appid).toBe("string");
    expect(historyDoc.appid).toMatch(/^\d+$/);
  });

  it("returns 404 for history of a missing config", async () => {
    const t = convexTest(schema, modules);
    const args = await buildPublishArgs({ appid: "11111", note: "temp" });
    const published = await t.mutation(internal.configs.publishConfig, args);
    await t.mutation(internal.configs.deleteConfig, {
      configId: published.config_id,
      fingerprintHash: args.fingerprintHash,
    });
    const historyRes = await t.fetch(
      `/api/config/${published.config_id}/history`,
      { headers: clientHeaders() },
    );
    expect(historyRes.status).toBe(404);
  });
});
