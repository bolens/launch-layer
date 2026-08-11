import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalMutation } from "./_generated/server";
import {
  DOWNLOAD_DEDUP_RETENTION_MS,
  RATE_LIMITS,
  RATE_LIMIT_RETENTION_MS,
  rateLimitAllows,
  rateLimitBucketKey,
  rateLimitExceededError,
  rateLimitWindowStart,
  type RateLimitRoute,
} from "./lib/rate_limit";

export const enforceRateLimit = internalMutation({
  args: {
    route: v.string(),
    identifier: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const route = args.route as RateLimitRoute;
    const max = RATE_LIMITS[route];
    if (!max) {
      return null;
    }

    const now = Date.now();
    const windowStart = rateLimitWindowStart(now);
    const bucketKey = rateLimitBucketKey(route, args.identifier);

    const existing = await ctx.db
      .query("rateLimitBuckets")
      .withIndex("by_bucket_key", (q) => q.eq("bucketKey", bucketKey))
      .unique();

    if (!existing || existing.windowStart !== windowStart) {
      if (existing) {
        await ctx.db.patch("rateLimitBuckets", existing._id, { windowStart, count: 1 });
      } else {
        await ctx.db.insert("rateLimitBuckets", {
          bucketKey,
          windowStart,
          count: 1,
        });
      }
      return null;
    }

    if (!rateLimitAllows(existing.count, max)) {
      rateLimitExceededError();
    }

    await ctx.db.patch("rateLimitBuckets", existing._id, { count: existing.count + 1 });
    return null;
  },
});

const CLEANUP_BATCH_SIZE = 200;

export const cleanupExpiredRecords = internalMutation({
  args: {},
  returns: v.object({
    rateLimitBuckets: v.number(),
    downloadDedup: v.number(),
  }),
  handler: async (ctx) => {
    const now = Date.now();
    const buckets = await ctx.db
      .query("rateLimitBuckets")
      .withIndex("by_window_start", (q) =>
        q.lt("windowStart", now - RATE_LIMIT_RETENTION_MS),
      )
      .take(CLEANUP_BATCH_SIZE);
    const downloads = await ctx.db
      .query("configDownloadDedup")
      .withIndex("by_recorded_at", (q) =>
        q.lt("recordedAt", now - DOWNLOAD_DEDUP_RETENTION_MS),
      )
      .take(CLEANUP_BATCH_SIZE);
    for (const row of buckets) {
      await ctx.db.delete("rateLimitBuckets", row._id);
    }
    for (const row of downloads) {
      await ctx.db.delete("configDownloadDedup", row._id);
    }
    if (
      buckets.length === CLEANUP_BATCH_SIZE ||
      downloads.length === CLEANUP_BATCH_SIZE
    ) {
      await ctx.scheduler.runAfter(
        0,
        internal.rate_limits.cleanupExpiredRecords,
        {},
      );
    }
    return {
      rateLimitBuckets: buckets.length,
      downloadDedup: downloads.length,
    };
  },
});
