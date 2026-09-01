export const MAX_HTTP_BODY_BYTES = 256 * 1024;

export function utf8ByteLength(value: string): number {
  return new TextEncoder().encode(value).byteLength;
}

export function assertRequestBodySize(
  contentLength: number,
  bodyLength: number,
  maxBytes = MAX_HTTP_BODY_BYTES,
): void {
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    throw new Error("VALIDATION_ERROR: request body too large");
  }
  if (bodyLength > maxBytes) {
    throw new Error("VALIDATION_ERROR: request body too large");
  }
}

export function parseJsonObjectBody(body: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(body || "{}");
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("VALIDATION_ERROR: request body must be a JSON object");
    }
    return parsed as Record<string, unknown>;
  } catch (error) {
    if (error instanceof Error && error.message.startsWith("VALIDATION_ERROR:")) {
      throw error;
    }
    throw new Error("VALIDATION_ERROR: request body contains invalid JSON", {
      cause: error,
    });
  }
}

export function parseDetection(raw: unknown): {
  native: boolean;
  anticheat: boolean;
  engine?: string;
} {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { native: false, anticheat: false };
  }
  const detection = raw as Record<string, unknown>;
  return {
    native: Boolean(detection.native),
    anticheat: Boolean(detection.anticheat),
    engine:
      typeof detection.engine === "string" && detection.engine.length > 0
        ? detection.engine
        : undefined,
  };
}
