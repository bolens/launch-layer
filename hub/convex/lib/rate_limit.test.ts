import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
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

const previousHeader = process.env.HUB_TRUSTED_CLIENT_IP_HEADER;
const previousHashKey = process.env.HUB_IDENTIFIER_HASH_KEY;

before(() => {
  process.env.HUB_TRUSTED_CLIENT_IP_HEADER = "CF-Connecting-IP";
  process.env.HUB_IDENTIFIER_HASH_KEY = "test-identifier-key-with-32-characters";
});

after(() => {
  if (previousHeader === undefined) {
    delete process.env.HUB_TRUSTED_CLIENT_IP_HEADER;
  } else {
    process.env.HUB_TRUSTED_CLIENT_IP_HEADER = previousHeader;
  }
  if (previousHashKey === undefined) {
    delete process.env.HUB_IDENTIFIER_HASH_KEY;
  } else {
    process.env.HUB_IDENTIFIER_HASH_KEY = previousHashKey;
  }
});

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
    assert.match(identifier, /^hmac-sha256:[a-f0-9]{64}$/);
    assert.equal(identifier.includes("203.0.113.10"), false);
  });

  it("rejects requests missing the configured trusted header", () => {
    const request = new Request("https://example.test/api/config/id", {
      headers: {
        "X-Forwarded-For": "203.0.113.10",
        "X-Real-IP": "198.51.100.44",
      },
    });
    assert.throws(
      () => trustedClientIdentity(request),
      /CONFIG_ERROR: trusted client identity header/,
    );
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

  it("requires explicit identity configuration", () => {
    const previous = process.env.HUB_TRUSTED_CLIENT_IP_HEADER;
    delete process.env.HUB_TRUSTED_CLIENT_IP_HEADER;
    try {
      const request = new Request("https://example.test/api/config/id");
      assert.throws(
        () => trustedClientIdentity(request),
        /HUB_TRUSTED_CLIENT_IP_HEADER/,
      );
    } finally {
      process.env.HUB_TRUSTED_CLIENT_IP_HEADER = previous;
    }
  });

  it("requires a sufficiently long HMAC key", async () => {
    const previous = process.env.HUB_IDENTIFIER_HASH_KEY;
    process.env.HUB_IDENTIFIER_HASH_KEY = "short";
    try {
      const request = new Request("https://example.test/api/config/id", {
        headers: { "CF-Connecting-IP": "203.0.113.10" },
      });
      await assert.rejects(
        () => requestIdentifier(request),
        /HUB_IDENTIFIER_HASH_KEY/,
      );
    } finally {
      process.env.HUB_IDENTIFIER_HASH_KEY = previous;
    }
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
