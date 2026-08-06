import { convexTest } from "convex-test";
import { describe, expect, it, vi } from "vitest";
import { internal } from "./_generated/api";
import {
  DOWNLOAD_DEDUP_RETENTION_MS,
  RATE_LIMITS,
  RATE_LIMIT_RETENTION_MS,
} from "./lib/rate_limit";
import { modules } from "../test/convex_test_modules";
import schema from "./schema";

describe("enforceRateLimit", () => {
  it("allows requests below the route cap", async () => {
    const t = convexTest(schema, modules);
    const identifier = "hash:rate-limit-ok";

    await expect(
      t.mutation(internal.rate_limits.enforceRateLimit, {
        route: "recommend",
        identifier,
      }),
    ).resolves.toBeNull();
  });

  it("throws RATE_LIMITED when the cap is exceeded in the same window", async () => {
    const t = convexTest(schema, modules);
    const identifier = "hash:rate-limit-blocked";

    for (let i = 0; i < RATE_LIMITS.recommend; i += 1) {
      await t.mutation(internal.rate_limits.enforceRateLimit, {
        route: "recommend",
        identifier,
      });
    }

    await expect(
      t.mutation(internal.rate_limits.enforceRateLimit, {
        route: "recommend",
        identifier,
      }),
    ).rejects.toThrowError(/RATE_LIMITED/);
  });

  it("tracks separate buckets per route and identifier", async () => {
    const t = convexTest(schema, modules);

    for (let i = 0; i < RATE_LIMITS.recommend; i += 1) {
      await t.mutation(internal.rate_limits.enforceRateLimit, {
        route: "recommend",
        identifier: "hash:shared-id",
      });
    }

    await expect(
      t.mutation(internal.rate_limits.enforceRateLimit, {
        route: "similarMachines",
        identifier: "hash:shared-id",
      }),
    ).resolves.toBeNull();
  });

  it("enforces publish and delete route caps", async () => {
    const t = convexTest(schema, modules);
    const publishId = "ip:203.0.113.80";
    const deleteId = "ip:203.0.113.81";

    for (let i = 0; i < RATE_LIMITS.publish; i += 1) {
      await t.mutation(internal.rate_limits.enforceRateLimit, {
        route: "publish",
        identifier: publishId,
      });
    }
    await expect(
      t.mutation(internal.rate_limits.enforceRateLimit, {
        route: "publish",
        identifier: publishId,
      }),
    ).rejects.toThrowError(/RATE_LIMITED/);

    for (let i = 0; i < RATE_LIMITS.delete; i += 1) {
      await t.mutation(internal.rate_limits.enforceRateLimit, {
        route: "delete",
        identifier: deleteId,
      });
    }
    await expect(
      t.mutation(internal.rate_limits.enforceRateLimit, {
        route: "delete",
        identifier: deleteId,
      }),
    ).rejects.toThrowError(/RATE_LIMITED/);
  });
});

describe("cleanupExpiredRecords", () => {
  it("removes expired operational rows and keeps recent rows", async () => {
    const t = convexTest(schema, modules);
    const now = Date.now();
    await t.run(async (ctx) => {
      await ctx.db.insert("rateLimitBuckets", {
        bucketKey: "old",
        windowStart: now - RATE_LIMIT_RETENTION_MS - 1,
        count: 1,
      });
      await ctx.db.insert("rateLimitBuckets", {
        bucketKey: "new",
        windowStart: now,
        count: 1,
      });
      const machineId = await ctx.db.insert("machines", {
        fingerprintHash: "a".repeat(64),
        fingerprint: {
          gpu_vendor: "unknown",
          os_family: "linux",
          session_type: "unknown",
          profiles: [],
          display_tier: "unknown",
          vrr: false,
          wsl2: false,
          flatpak_steam: false,
          steam_deck: false,
          immutable: false,
        },
        updatedAt: now,
      });
      const configId = await ctx.db.insert("sharedConfigs", {
        machineId,
        appid: "1",
        gameName: "Test",
        envContent: "",
        settings: [],
        detection: { native: false, anticheat: false },
        publishedAt: now,
        downloads: 0,
      });
      await ctx.db.insert("configDownloadDedup", {
        configId,
        identifier: "old",
        recordedAt: now - DOWNLOAD_DEDUP_RETENTION_MS - 1,
      });
      await ctx.db.insert("configDownloadDedup", {
        configId,
        identifier: "new",
        recordedAt: now,
      });
    });

    const result = await t.mutation(
      internal.rate_limits.cleanupExpiredRecords,
      {},
    );
    expect(result).toEqual({ rateLimitBuckets: 1, downloadDedup: 1 });
  });

  it("reschedules cleanup when an expired batch is full", async () => {
    vi.useFakeTimers();
    try {
      const t = convexTest(schema, modules);
      const expired = Date.now() - RATE_LIMIT_RETENTION_MS - 1;
      await t.run(async (ctx) => {
        for (let i = 0; i < 201; i += 1) {
          await ctx.db.insert("rateLimitBuckets", {
            bucketKey: `expired-${i}`,
            windowStart: expired,
            count: 1,
          });
        }
      });

      const first = await t.mutation(
        internal.rate_limits.cleanupExpiredRecords,
        {},
      );
      expect(first.rateLimitBuckets).toBe(200);
      await t.finishAllScheduledFunctions(vi.runAllTimers);

      const remaining = await t.run(async (ctx) =>
        ctx.db
          .query("rateLimitBuckets")
          .withIndex("by_window_start", (q) =>
            q.lt("windowStart", Date.now() - RATE_LIMIT_RETENTION_MS),
          )
          .collect(),
      );
      expect(remaining).toHaveLength(0);
    } finally {
      vi.useRealTimers();
    }
  });
});
