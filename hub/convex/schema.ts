import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

const fingerprintValidator = v.object({
  fingerprint_level: v.optional(v.string()),
  gpu_vendor: v.string(),
  gpus: v.optional(
    v.array(
      v.object({
        vendor: v.string(),
        name: v.string(),
        role: v.string(),
        primary: v.boolean(),
        index: v.number(),
        vram_mb: v.number(),
        pci_slot: v.string(),
      }),
    ),
  ),
  os_family: v.string(),
  os_id: v.optional(v.string()),
  os_pretty: v.optional(v.string()),
  session_type: v.string(),
  desktop: v.optional(v.string()),
  profiles: v.array(v.string()),
  display: v.optional(v.string()),
  display_tier: v.string(),
  refresh_tier: v.optional(v.string()),
  vram_tier: v.optional(v.string()),
  monitor_layout: v.optional(v.string()),
  primary_aspect: v.optional(v.string()),
  has_igpu: v.optional(v.boolean()),
  has_x3d: v.optional(v.boolean()),
  active_output: v.optional(v.string()),
  primary_output: v.optional(v.string()),
  displays: v.optional(
    v.array(
      v.object({
        name: v.string(),
        width: v.number(),
        height: v.number(),
        refresh: v.number(),
        primary: v.boolean(),
      }),
    ),
  ),
  x3d_cpus: v.optional(v.string()),
  vrr: v.boolean(),
  wsl2: v.boolean(),
  flatpak_steam: v.boolean(),
  steam_deck: v.boolean(),
  immutable: v.boolean(),
  container: v.optional(v.boolean()),
  audio: v.optional(v.string()),
});

const settingValidator = v.object({
  key: v.string(),
  value: v.string(),
  source: v.optional(v.string()),
});

const detectionValidator = v.object({
  native: v.boolean(),
  anticheat: v.boolean(),
  engine: v.optional(v.string()),
});

export default defineSchema({
  machines: defineTable({
    fingerprintHash: v.string(),
    fingerprint: fingerprintValidator,
    machineLabel: v.optional(v.string()),
    updatedAt: v.number(),
  })
    .index("by_fingerprint_hash", ["fingerprintHash"])
    .index("by_gpu_vendor", ["fingerprint.gpu_vendor"])
    .index("by_display_tier", ["fingerprint.display_tier"]),

  sharedConfigs: defineTable({
    machineId: v.id("machines"),
    appid: v.string(),
    gameName: v.string(),
    envContent: v.string(),
    settings: v.array(settingValidator),
    preset: v.optional(v.string()),
    note: v.optional(v.string()),
    detection: detectionValidator,
    launchlayerVersion: v.optional(v.string()),
    publishedAt: v.number(),
    downloads: v.number(),
  })
    .index("by_appid", ["appid"])
    .index("by_machine_and_appid", ["machineId", "appid"]),

  sharedConfigsHistory: defineTable({
    configId: v.id("sharedConfigs"),
    envContent: v.string(),
    settings: v.array(settingValidator),
    preset: v.optional(v.string()),
    note: v.optional(v.string()),
    detection: detectionValidator,
    launchlayerVersion: v.optional(v.string()),
    publishedAt: v.number(),
  })
    .index("by_config_id", ["configId"])
    .index("by_config_id_and_published_at", ["configId", "publishedAt"]),

  rateLimitBuckets: defineTable({
    bucketKey: v.string(),
    windowStart: v.number(),
    count: v.number(),
  })
    .index("by_bucket_key", ["bucketKey"])
    .index("by_window_start", ["windowStart"]),

  configDownloadDedup: defineTable({
    configId: v.id("sharedConfigs"),
    identifier: v.string(),
    recordedAt: v.number(),
  })
    .index("by_config_and_identifier", ["configId", "identifier"])
    .index("by_config_id", ["configId"])
    .index("by_recorded_at", ["recordedAt"]),
});

export {
  fingerprintValidator,
  settingValidator,
  detectionValidator,
};
