import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  RATE_LIMITS,
  RATE_LIMIT_WINDOW_MS,
  rateLimitAllows,
  rateLimitBucketKey,
  rateLimitExceededError,
  rateLimitWindowStart,
  requestIdentifier,
  trustedClientIdentity,
} from "./rate_limit";

describe("rateLimitWindowStart", () => {
  it("aligns timestamps to fixed windows", () => {
    const now = 1_700_000_123_456;
    assert.equal(rateLimitWindowStart(now), now - (now % RATE_LIMIT_WINDOW_MS));
  });
});

describe("rateLimitAllows", () => {
  it("allows requests below the cap", () => {
    assert.equal(rateLimitAllows(0, RATE_LIMITS.recommend), true);
    assert.equal(rateLimitAllows(RATE_LIMITS.recommend - 1, RATE_LIMITS.recommend), true);
    assert.equal(rateLimitAllows(RATE_LIMITS.recommend, RATE_LIMITS.recommend), false);
  });
});

describe("rateLimitBucketKey", () => {
  it("namespaces route and identifier", () => {
    assert.equal(
      rateLimitBucketKey("recommend", "ip:203.0.113.10"),
      "recommend:ip:203.0.113.10",
    );
  });
});

describe("requestIdentifier", () => {
  it("hashes the configured trusted ingress identity", async () => {
    const request = new Request("https://example.test/api/recommend", {
      method: "POST",
      headers: { "CF-Connecting-IP": "203.0.113.10" },
    });
    const identifier = await requestIdentifier(request, {
      fingerprint_hash: "a".repeat(64),
    });
    assert.match(identifier, /^sha256:[a-f0-9]{64}$/);
    assert.equal(identifier.includes("203.0.113.10"), false);
  });

  it("ignores spoofable forwarding fallbacks", () => {
    const request = new Request("https://example.test/api/config/id", {
      headers: {
        "X-Forwarded-For": "203.0.113.10",
        "X-Real-IP": "198.51.100.44",
      },
    });
    assert.equal(trustedClientIdentity(request), "ip:unknown");
  });

  it("supports an explicitly configured ingress header", () => {
    const previous = process.env.HUB_TRUSTED_CLIENT_IP_HEADER;
    process.env.HUB_TRUSTED_CLIENT_IP_HEADER = "True-Client-IP";
    const request = new Request("https://example.test/api/config/id", {
      headers: { "True-Client-IP": "203.0.113.10" },
    });
    assert.equal(trustedClientIdentity(request), "ip:203.0.113.10");
    if (previous === undefined) {
      delete process.env.HUB_TRUSTED_CLIENT_IP_HEADER;
    } else {
      process.env.HUB_TRUSTED_CLIENT_IP_HEADER = previous;
    }
  });

  it("uses ip:unknown when no client identity headers are present", () => {
    const request = new Request("https://example.test/api/config/id");
    assert.equal(trustedClientIdentity(request), "ip:unknown");
  });
});

describe("rateLimitExceededError", () => {
  it("throws a RATE_LIMITED error", () => {
    assert.throws(
      () => rateLimitExceededError(),
      /RATE_LIMITED: Too many requests/,
    );
  });
});

describe("RATE_LIMITS", () => {
  it("caps privileged write routes", () => {
    assert.equal(RATE_LIMITS.publish, 10);
    assert.equal(RATE_LIMITS.delete, 5);
  });
});
