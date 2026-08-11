import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  assertRequestBodySize,
  MAX_HTTP_BODY_BYTES,
  parseDetection,
  parseJsonObjectBody,
  utf8ByteLength,
} from "./http_body";

describe("assertRequestBodySize", () => {
  it("rejects Content-Length above the cap", () => {
    assert.throws(
      () => assertRequestBodySize(MAX_HTTP_BODY_BYTES + 1, 0),
      /VALIDATION_ERROR: request body too large/,
    );
  });

  it("rejects actual body length above the cap", () => {
    assert.throws(
      () => assertRequestBodySize(0, MAX_HTTP_BODY_BYTES + 1),
      /VALIDATION_ERROR: request body too large/,
    );
  });

  it("allows bodies within the cap", () => {
    assert.doesNotThrow(() =>
      assertRequestBodySize(128, 128, MAX_HTTP_BODY_BYTES),
    );
  });
});

describe("utf8ByteLength", () => {
  it("counts encoded bytes rather than UTF-16 code units", () => {
    assert.equal("🎮".length, 2);
    assert.equal(utf8ByteLength("🎮"), 4);
  });
});

describe("parseJsonObjectBody", () => {
  it("parses JSON objects and defaults empty bodies to {}", () => {
    assert.deepEqual(parseJsonObjectBody('{"appid":"1"}'), { appid: "1" });
    assert.deepEqual(parseJsonObjectBody(""), {});
  });

  it("rejects non-object JSON payloads", () => {
    assert.throws(
      () => parseJsonObjectBody("[]"),
      /VALIDATION_ERROR: request body must be a JSON object/,
    );
    assert.throws(
      () => parseJsonObjectBody('"hello"'),
      /VALIDATION_ERROR: request body must be a JSON object/,
    );
  });

  it("rejects invalid JSON", () => {
    assert.throws(
      () => parseJsonObjectBody("{bad json"),
      /VALIDATION_ERROR: request body contains invalid JSON/,
    );
  });
});

describe("parseDetection", () => {
  it("defaults missing detection to native=false and anticheat=false", () => {
    assert.deepEqual(parseDetection(undefined), {
      native: false,
      anticheat: false,
    });
    assert.deepEqual(parseDetection(null), {
      native: false,
      anticheat: false,
    });
  });

  it("coerces booleans and preserves engine slug", () => {
    assert.deepEqual(
      parseDetection({ native: 1, anticheat: "yes", engine: "unity" }),
      { native: true, anticheat: true, engine: "unity" },
    );
  });

  it("drops empty engine values", () => {
    const parsed = parseDetection({ engine: "" });
    assert.equal(parsed.native, false);
    assert.equal(parsed.anticheat, false);
    assert.equal(parsed.engine, undefined);
  });
});
