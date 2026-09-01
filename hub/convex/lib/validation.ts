import { fingerprintHashFromRecord } from "./fingerprint_hash";
import type { Fingerprint } from "./similarity";

export const QUERY_LIMITS = {
  default: 10,
  min: 1,
  max: 50,
} as const;

export const MAX_CONFIGS_SCORED = 500;
export const MAX_MACHINES_SCORED = 500;

export function capScoredCandidates<T>(
  items: readonly T[],
  max: number,
): T[] {
  return items.slice(0, max);
}

export const PUBLISH_LIMITS = {
  envContent: 64_000,
  envLines: 500,
  gameName: 200,
  note: 500,
  machineLabel: 100,
  preset: 200,
  launchlayerVersion: 32,
  settingsCount: 100,
  settingKey: 128,
  settingValue: 4096,
  profilesCount: 32,
  profileName: 64,
  gpusCount: 8,
  displaysCount: 16,
  gpuName: 128,
  displayName: 64,
  pciSlot: 32,
  outputName: 64,
  engine: 64,
  osPretty: 128,
  osId: 64,
  x3dCpus: 128,
  audio: 32,
  desktop: 32,
  slug: 64,
  displayMaxSide: 16_384,
  refreshMax: 1_000,
  vramMbMax: 262_144,
} as const;

const PATTERNS = {
  appid: /^[0-9]{1,10}$/,
  configId: /^[a-z0-9]{10,64}$/,
  fingerprintHash: /^[a-f0-9]{64}$/,
  slug: /^[a-z0-9][a-z0-9+._:/-]{0,63}$/i,
  profile: /^[a-z0-9][a-z0-9._-]{0,63}$/,
  settingKey: /^[A-Z][A-Z0-9_]{0,127}$/,
  display: /^[0-9]{1,5}x[0-9]{1,5}@[0-9]{1,3}Hz$/,
  pciSlot: /^[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]$/i,
  presetPath: /^[a-zA-Z0-9/_.-]{0,200}$/,
  semver: /^[0-9A-Za-z.+~ -]{1,32}$/,
  printableText: /^[^\x00-\x08\x0B\x0C\x0E-\x1F\x7F]*$/,
} as const;

const FINGERPRINT_LEVELS = new Set(["minimal", "standard", "detailed"]);
const SESSION_TYPES = new Set(["wayland", "x11", "tty", "unknown"]);
const GPU_ROLES = new Set(["discrete", "integrated", "unknown"]);
const DISPLAY_TIERS = new Set([
  "5k+",
  "4k",
  "ultrawide",
  "1440p",
  "1080p",
  "sub1080p",
  "unknown",
]);
const REFRESH_TIERS = new Set(["hi144+", "mid75_120", "std60", "unknown"]);
const VRAM_TIERS = new Set(["16gb+", "12gb", "8gb", "4gb", "lt4gb", "unknown"]);
const MONITOR_LAYOUTS = new Set(["triple+", "dual", "single", "unknown"]);
const PRIMARY_ASPECTS = new Set(["21:9", "16:10", "16:9", "other", "unknown"]);

export type PublishSubmission = {
  fingerprintHash: string;
  fingerprint: Fingerprint;
  machineLabel?: string;
  appid: string;
  gameName: string;
  envContent: string;
  settings: Array<{ key: string; value: string; source?: string }>;
  preset?: string;
  note?: string;
  detection: { native: boolean; anticheat: boolean; engine?: string };
  launchlayerVersion?: string;
  configId?: string;
};

function validationError(message: string): never {
  throw new Error(`VALIDATION_ERROR: ${message}`);
}

function assertMaxLength(label: string, value: string, max: number): void {
  if (value.length > max) {
    validationError(`${label} exceeds ${max} characters`);
  }
}

function assertPattern(
  label: string,
  value: string,
  pattern: RegExp,
  max?: number,
): void {
  if (max !== undefined) {
    assertMaxLength(label, value, max);
  }
  if (!pattern.test(value)) {
    validationError(`${label} has invalid format`);
  }
}

function assertOptionalPattern(
  label: string,
  value: string | undefined,
  pattern: RegExp,
  max?: number,
): void {
  if (value === undefined) {
    return;
  }
  assertPattern(label, value, pattern, max);
}

function assertPrintableText(label: string, value: string, max: number): void {
  if (value.length === 0) {
    validationError(`${label} is required`);
  }
  assertMaxLength(label, value, max);
  if (!PATTERNS.printableText.test(value)) {
    validationError(`${label} contains invalid characters`);
  }
}

function assertSlug(label: string, value: string, allowed?: Set<string>): void {
  assertMaxLength(label, value, PUBLISH_LIMITS.slug);
  if (allowed?.has(value)) {
    return;
  }
  if (!PATTERNS.slug.test(value)) {
    validationError(`${label} has invalid format`);
  }
}

function assertOptionalSlug(
  label: string,
  value: string | undefined,
  allowed?: Set<string>,
): void {
  if (value === undefined) {
    return;
  }
  assertSlug(label, value, allowed);
}

function assertOptionalPrintable(
  label: string,
  value: string | undefined,
  max: number,
): void {
  if (value === undefined) {
    return;
  }
  assertPrintableText(label, value, max);
}

function assertFiniteNumber(
  label: string,
  value: number,
  min: number,
  max: number,
): void {
  if (!Number.isFinite(value) || value < min || value > max) {
    validationError(`${label} is out of range`);
  }
}

/**
 * Keys that must not appear with a non-empty value in published hub configs.
 * Remote clients eval or execute these on apply/launch (RCE / local damage).
 * Keep in sync with the hub column in share/launchlayer/config-keys.tsv.
 * This is asserted in tests because Convex cannot read repository files at runtime.
 */
export const HUB_UNTRUSTED_ENV_KEYS = new Set([
  "PRE_LAUNCH_CMD",
  "POST_LAUNCH_CMD",
  "LAUNCH_WRAPPERS",
  "LAUNCH_WRAPPERS_BEFORE",
  "OVERRIDE_PROTON",
  "VRAM_HOG_UNITS",
  "VRAM_HOG_PIDS",
  "VRAM_HOGS",
  "WINETRICKS_VERBS",
  "WINETRICKS_GUI",
  "WINECFG_BEFORE",
  "REGISTRY_FILES",
  "WINE_FSR",
  "WINE_FSR_STRENGTH",
  "WINE_FSR_MODE",
  "SPECIAL_K",
  "SPECIAL_K_DLL",
  "SPECIAL_K_SOURCE",
  "SPECIAL_K_INI",
  "SPECIAL_K_FETCH",
  "SPECIAL_K_FETCH_URL",
  "SPECIAL_K_VERSION",
  "RESHADE",
  "RESHADE_DLL",
  "RESHADE_SOURCE",
  "RESHADE_SK_VERSION",
  "DEPTH3D",
  "DEPTH3D_SOURCE",
  "DEPTH3D_FETCH_URL",
  "SKIF",
  "SKIF_PATH",
  "SKIF_LAUNCH",
  "VALVEPLUG",
  "VALVEPLUG_SOURCE",
  "VALVEPLUG_STEAM_DIR",
  "FLAWLESS_WIDESCREEN",
  "FWS",
  "FWS_PATH",
  "FWS_COLAUNCH",
  "OPENVR_FSR",
  "OPENVR_FSR_SOURCE",
  "GEO11",
  "GEO11_SOURCE",
  "GEO11_SBS_VR",
  "SBS_VR",
  "SBS_VR_PLAYER",
  "SBS_VR_REQUIRE_HMD",
  "FLAT2VR",
  "FLAT2VR_SOURCE",
  "CONTY",
  "CONTY_PATH",
  "BLOCK_INTERNET",
  "SPECIALTY_RUNTIME",
]);

function isUnsafeIncludePath(includePath: string): boolean {
  const trimmed = includePath.trim().replace(/^["']|["']$/g, "");
  if (!trimmed) {
    return true;
  }
  if (trimmed.startsWith("/") || trimmed.startsWith("~")) {
    return true;
  }
  if (trimmed.includes("..")) {
    return true;
  }
  return !PATTERNS.presetPath.test(trimmed);
}

function validateEnvContent(envContent: string): void {
  assertMaxLength("env_content", envContent, PUBLISH_LIMITS.envContent);
  if (!PATTERNS.printableText.test(envContent)) {
    validationError("env_content contains invalid characters");
  }
  const lines = envContent.split("\n");
  if (lines.length > PUBLISH_LIMITS.envLines) {
    validationError(`env_content exceeds ${PUBLISH_LIMITS.envLines} lines`);
  }
  for (const [index, rawLine] of lines.entries()) {
    const line = rawLine.replace(/#.*$/, "").trim();
    if (!line) {
      continue;
    }
    if (/^INCLUDE=/i.test(line)) {
      const includePath = line.slice("INCLUDE=".length);
      if (isUnsafeIncludePath(includePath)) {
        validationError(
          `env_content line ${index + 1}: INCLUDE path is not allowed for hub publish`,
        );
      }
      continue;
    }
    const match = /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/.exec(line);
    if (!match) {
      continue;
    }
    const key = match[1] ?? "";
    const value = (match[2] ?? "").trim().replace(/^["']|["']$/g, "");
    if (HUB_UNTRUSTED_ENV_KEYS.has(key) && value.length > 0) {
      validationError(
        `env_content must not set ${key} (rejected for hub publish safety)`,
      );
    }
  }
}

function validateSettings(
  settings: Array<{ key: string; value: string; source?: string }>,
): void {
  if (settings.length > PUBLISH_LIMITS.settingsCount) {
    validationError(`settings exceeds ${PUBLISH_LIMITS.settingsCount} entries`);
  }
  for (const [index, setting] of settings.entries()) {
    assertPattern(
      `settings[${index}].key`,
      setting.key,
      PATTERNS.settingKey,
      PUBLISH_LIMITS.settingKey,
    );
    assertMaxLength(
      `settings[${index}].value`,
      setting.value,
      PUBLISH_LIMITS.settingValue,
    );
    if (!PATTERNS.printableText.test(setting.value)) {
      validationError(`settings[${index}].value contains invalid characters`);
    }
    if (HUB_UNTRUSTED_ENV_KEYS.has(setting.key) && setting.value.trim().length > 0) {
      validationError(
        `settings must not include ${setting.key} (rejected for hub publish safety)`,
      );
    }
    if (setting.source !== undefined) {
      assertMaxLength(`settings[${index}].source`, setting.source, 128);
      if (!PATTERNS.printableText.test(setting.source)) {
        validationError(`settings[${index}].source contains invalid characters`);
      }
    }
  }
}

function validateFingerprint(fingerprint: Fingerprint): void {
  if (
    fingerprint.fingerprint_level !== undefined &&
    !FINGERPRINT_LEVELS.has(fingerprint.fingerprint_level)
  ) {
    validationError("fingerprint.fingerprint_level has invalid format");
  }

  assertSlug("fingerprint.gpu_vendor", fingerprint.gpu_vendor);
  assertSlug("fingerprint.os_family", fingerprint.os_family);
  assertSlug("fingerprint.session_type", fingerprint.session_type, SESSION_TYPES);
  assertSlug("fingerprint.display_tier", fingerprint.display_tier, DISPLAY_TIERS);
  assertOptionalSlug(
    "fingerprint.refresh_tier",
    fingerprint.refresh_tier,
    REFRESH_TIERS,
  );
  assertOptionalSlug("fingerprint.vram_tier", fingerprint.vram_tier, VRAM_TIERS);
  assertOptionalSlug(
    "fingerprint.monitor_layout",
    fingerprint.monitor_layout,
    MONITOR_LAYOUTS,
  );
  assertOptionalSlug(
    "fingerprint.primary_aspect",
    fingerprint.primary_aspect,
    PRIMARY_ASPECTS,
  );
  assertOptionalPrintable("fingerprint.desktop", fingerprint.desktop, PUBLISH_LIMITS.desktop);
  assertOptionalPrintable("fingerprint.display", fingerprint.display, 32);
  assertOptionalPrintable("fingerprint.os_pretty", fingerprint.os_pretty, PUBLISH_LIMITS.osPretty);
  assertOptionalPrintable("fingerprint.os_id", fingerprint.os_id, PUBLISH_LIMITS.osId);
  assertOptionalPrintable("fingerprint.x3d_cpus", fingerprint.x3d_cpus, PUBLISH_LIMITS.x3dCpus);
  assertOptionalPrintable("fingerprint.audio", fingerprint.audio, PUBLISH_LIMITS.audio);
  assertOptionalPrintable(
    "fingerprint.active_output",
    fingerprint.active_output,
    PUBLISH_LIMITS.outputName,
  );
  assertOptionalPrintable(
    "fingerprint.primary_output",
    fingerprint.primary_output,
    PUBLISH_LIMITS.outputName,
  );

  if (fingerprint.display !== undefined && !PATTERNS.display.test(fingerprint.display)) {
    validationError("fingerprint.display has invalid format");
  }

  if (fingerprint.profiles.length > PUBLISH_LIMITS.profilesCount) {
    validationError(`fingerprint.profiles exceeds ${PUBLISH_LIMITS.profilesCount} entries`);
  }
  for (const [index, profile] of fingerprint.profiles.entries()) {
    assertPattern(
      `fingerprint.profiles[${index}]`,
      profile,
      PATTERNS.profile,
      PUBLISH_LIMITS.profileName,
    );
  }

  if (fingerprint.gpus !== undefined) {
    if (fingerprint.gpus.length > PUBLISH_LIMITS.gpusCount) {
      validationError(`fingerprint.gpus exceeds ${PUBLISH_LIMITS.gpusCount} entries`);
    }
    for (const [index, gpu] of fingerprint.gpus.entries()) {
      assertSlug(`fingerprint.gpus[${index}].vendor`, gpu.vendor);
      assertOptionalPrintable(
        `fingerprint.gpus[${index}].name`,
        gpu.name,
        PUBLISH_LIMITS.gpuName,
      );
      assertOptionalSlug(
        `fingerprint.gpus[${index}].role`,
        gpu.role,
        GPU_ROLES,
      );
      assertFiniteNumber(
        `fingerprint.gpus[${index}].index`,
        gpu.index,
        0,
        32,
      );
      assertFiniteNumber(
        `fingerprint.gpus[${index}].vram_mb`,
        gpu.vram_mb,
        0,
        PUBLISH_LIMITS.vramMbMax,
      );
      assertMaxLength(
        `fingerprint.gpus[${index}].pci_slot`,
        gpu.pci_slot,
        PUBLISH_LIMITS.pciSlot,
      );
      if (gpu.pci_slot && !PATTERNS.pciSlot.test(gpu.pci_slot)) {
        validationError(`fingerprint.gpus[${index}].pci_slot has invalid format`);
      }
    }
  }

  if (fingerprint.displays !== undefined) {
    if (fingerprint.displays.length > PUBLISH_LIMITS.displaysCount) {
      validationError(
        `fingerprint.displays exceeds ${PUBLISH_LIMITS.displaysCount} entries`,
      );
    }
    for (const [index, display] of fingerprint.displays.entries()) {
      assertOptionalPrintable(
        `fingerprint.displays[${index}].name`,
        display.name,
        PUBLISH_LIMITS.displayName,
      );
      assertFiniteNumber(
        `fingerprint.displays[${index}].width`,
        display.width,
        0,
        PUBLISH_LIMITS.displayMaxSide,
      );
      assertFiniteNumber(
        `fingerprint.displays[${index}].height`,
        display.height,
        0,
        PUBLISH_LIMITS.displayMaxSide,
      );
      assertFiniteNumber(
        `fingerprint.displays[${index}].refresh`,
        display.refresh,
        0,
        PUBLISH_LIMITS.refreshMax,
      );
    }
  }
}

/** Clamp public query limits to a safe bounded range. */
export function clampQueryLimit(limit?: number): number {
  if (limit === undefined) {
    return QUERY_LIMITS.default;
  }
  if (!Number.isFinite(limit)) {
    validationError("limit must be a finite number");
  }
  const rounded = Math.floor(limit);
  if (rounded < QUERY_LIMITS.min) {
    validationError(`limit must be at least ${QUERY_LIMITS.min}`);
  }
  return Math.min(rounded, QUERY_LIMITS.max);
}

export function validateRecommendRequest(args: {
  fingerprint: Fingerprint;
  appid: string;
  limit?: number;
}): number {
  assertPattern("appid", args.appid, PATTERNS.appid);
  validateFingerprint(args.fingerprint);
  return clampQueryLimit(args.limit);
}

export function validateSimilarMachinesRequest(args: {
  fingerprint: Fingerprint;
  limit?: number;
}): number {
  validateFingerprint(args.fingerprint);
  return clampQueryLimit(args.limit);
}

export function validateConfigId(configId: string): void {
  assertPattern("config_id", configId.toLowerCase(), PATTERNS.configId);
}

export function validateDeleteRequest(args: {
  configId: string;
  fingerprintHash: string;
}): void {
  validateConfigId(args.configId);
  assertPattern("fingerprint_hash", args.fingerprintHash, PATTERNS.fingerprintHash);
}

export async function assertFingerprintHashMatches(
  fingerprint: Fingerprint,
  fingerprintHash: string,
): Promise<void> {
  const expected = await fingerprintHashFromRecord(fingerprint);
  if (expected !== fingerprintHash) {
    validationError("fingerprint_hash does not match fingerprint");
  }
}

/** Reject malformed or oversized publish payloads before writing to Convex. */
export function validatePublishSubmission(args: PublishSubmission): void {
  assertPattern("appid", args.appid, PATTERNS.appid);
  assertPattern("fingerprint_hash", args.fingerprintHash, PATTERNS.fingerprintHash);
  assertOptionalPrintable("machine_label", args.machineLabel, PUBLISH_LIMITS.machineLabel);
  assertPrintableText("game_name", args.gameName, PUBLISH_LIMITS.gameName);
  assertOptionalPrintable("note", args.note, PUBLISH_LIMITS.note);
  assertOptionalPattern("preset", args.preset, PATTERNS.presetPath, PUBLISH_LIMITS.preset);
  assertOptionalPattern(
    "launchlayer_version",
    args.launchlayerVersion,
    PATTERNS.semver,
    PUBLISH_LIMITS.launchlayerVersion,
  );
  assertOptionalPrintable(
    "detection.engine",
    args.detection.engine,
    PUBLISH_LIMITS.engine,
  );
  if (
    args.detection.engine !== undefined &&
    !PATTERNS.slug.test(args.detection.engine)
  ) {
    validationError("detection.engine has invalid format");
  }

  validateEnvContent(args.envContent);
  validateSettings(args.settings);
  validateFingerprint(args.fingerprint);
  if (args.configId !== undefined) {
    validateConfigId(args.configId);
  }
}

/** Lightweight checks for read-only lookup endpoints. */
export function validateLookupIdentity(args: {
  fingerprintHash: string;
  appid: string;
}): void {
  assertPattern("appid", args.appid, PATTERNS.appid);
  assertPattern("fingerprint_hash", args.fingerprintHash, PATTERNS.fingerprintHash);
}
