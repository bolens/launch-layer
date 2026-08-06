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
  const header =
    process.env.HUB_TRUSTED_CLIENT_IP_HEADER?.trim().toLowerCase() ??
    "cf-connecting-ip";
  const value = request.headers.get(header)?.trim();
  return value ? `ip:${value}` : "ip:unknown";
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

export async function requestIdentifier(
  request: Request,
  _body?: Record<string, unknown>,
): Promise<string> {
  return `sha256:${await sha256(trustedClientIdentity(request))}`;
}
