export const RATE_LIMIT_WINDOW_MS = 60_000;
export const RATE_LIMIT_RETENTION_MS = 24 * 60 * 60 * 1_000;
export const DOWNLOAD_DEDUP_RETENTION_MS = 30 * 24 * 60 * 60 * 1_000;

export const RATE_LIMITS = {
  recommend: 30,
  similarMachines: 30,
  myConfig: 60,
  getConfig: 120,
  publish: 10,
  delete: 5,
} as const;

export type RateLimitRoute = keyof typeof RATE_LIMITS;

export function rateLimitBucketKey(
  route: RateLimitRoute,
  identifier: string,
): string {
  return `${route}:${identifier}`;
}

export function rateLimitWindowStart(now: number): number {
  return now - (now % RATE_LIMIT_WINDOW_MS);
}

export function rateLimitAllows(count: number, max: number): boolean {
  return count < max;
}

export function rateLimitExceededError(): never {
  throw new Error("RATE_LIMITED: Too many requests — try again later");
}

/**
 * Client IP for rate limiting / download dedupe.
 * Prefer platform-assigned headers; fall back to common proxy headers.
 * Do not key rate limits on client-supplied fingerprint hashes alone —
 * those are trivial to rotate and bypass per-client caps.
 */
export function trustedClientIdentity(request: Request): string {
  const header = process.env.HUB_TRUSTED_CLIENT_IP_HEADER?.trim().toLowerCase();
  if (!header) {
    throw new Error(
      "CONFIG_ERROR: HUB_TRUSTED_CLIENT_IP_HEADER must name an ingress-controlled header",
    );
  }
  const value = request.headers.get(header)?.trim();
  if (!value) {
    throw new Error(
      `CONFIG_ERROR: trusted client identity header ${header} is missing`,
    );
  }
  return `ip:${value}`;
}

async function hmacSha256(value: string): Promise<string> {
  const secret = process.env.HUB_IDENTIFIER_HASH_KEY?.trim();
  if (!secret || secret.length < 32) {
    throw new Error(
      "CONFIG_ERROR: HUB_IDENTIFIER_HASH_KEY must contain at least 32 characters",
    );
  }
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(value));
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

export async function requestIdentifier(
  request: Request,
  _body?: Record<string, unknown>,
): Promise<string> {
  return `hmac-sha256:${await hmacSha256(trustedClientIdentity(request))}`;
}
