#!/usr/bin/env python3
"""Dependency-free, read-only MCP stdio server for LaunchLayer."""

import json
import os
import signal
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any, Dict, List, Optional


MODERN_PROTOCOL_VERSION = "2026-07-28"
LEGACY_PROTOCOL_VERSIONS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
PROTOCOL_VERSION_META = "io.modelcontextprotocol/protocolVersion"
CLIENT_CAPABILITIES_META = "io.modelcontextprotocol/clientCapabilities"
SERVER_INFO_META = "io.modelcontextprotocol/serverInfo"
MAX_REQUEST_BYTES = 1024 * 1024
MAX_RESULT_BYTES = 4 * 1024 * 1024
ROOT = Path(__file__).resolve().parent.parent
LAUNCHLAYER = ROOT / "launchlayer"
OUTPUT_LOCK = threading.Lock()
RUNNING_LOCK = threading.Lock()
RUNNING: Dict[Any, subprocess.Popen] = {}
CANCELLED = set()
WORKERS: List[threading.Thread] = []


TOOLS: List[Dict[str, Any]] = [
	{
		"name": "cache_report",
		"title": "Inspect game caches",
		"description": "Report shader and compatibility-data cache sizes without deleting data.",
		"inputSchema": {"type": "object", "properties": {
			"minimum_gb": {"type": "integer", "minimum": 0, "maximum": 100000, "default": 5},
			"kind": {"type": "string", "enum": ["both", "shader", "compat"], "default": "both"},
			"name_filter": {"type": "string", "maxLength": 200},
		}, "additionalProperties": False},
	},
	{
		"name": "list_games",
		"title": "List Steam games",
		"description": "List discovered Steam games and their LaunchLayer configuration state.",
		"inputSchema": {"type": "object", "properties": {
			"configured_only": {"type": "boolean", "default": False},
			"name_filter": {"type": "string", "maxLength": 200},
		}, "additionalProperties": False},
	},
	{
		"name": "launch_stats",
		"title": "Inspect launch statistics",
		"description": "Summarize recorded LaunchLayer launches for all games or one game.",
		"inputSchema": {"type": "object", "properties": {
			"game": {"type": "string", "minLength": 1, "maxLength": 200},
		}, "additionalProperties": False},
	},
	{
		"name": "show_config",
		"title": "Inspect resolved game config",
		"description": "Resolve a game configuration and launch wrapper chain without launching it.",
		"inputSchema": {"type": "object", "properties": {
			"game": {"type": "string", "minLength": 1, "maxLength": 200},
		}, "required": ["game"], "additionalProperties": False},
	},
	{
		"name": "show_paths",
		"title": "Inspect game paths",
		"description": "Return install, shader-cache, and compatibility-data paths for a game.",
		"inputSchema": {"type": "object", "properties": {
			"game": {"type": "string", "minLength": 1, "maxLength": 200},
		}, "required": ["game"], "additionalProperties": False},
	},
	{
		"name": "status",
		"title": "Inspect LaunchLayer status",
		"description": "Return current runtime, maintenance, and optional per-game status.",
		"inputSchema": {"type": "object", "properties": {
			"game": {"type": "string", "minLength": 1, "maxLength": 200},
		}, "additionalProperties": False},
	},
	{
		"name": "detect_environment",
		"title": "Detect gaming environment",
		"description": "Return detected OS, desktop, display, GPU, and optional-tool state.",
		"inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
	},
	{
		"name": "detect_defaults",
		"title": "Detect recommended defaults",
		"description": "Return LaunchLayer's computed settings for this machine without writing configuration.",
		"inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
	},
	{
		"name": "doctor",
		"title": "Run LaunchLayer diagnostics",
		"description": "Run read-only environment and configuration health checks.",
		"inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
	},
	{
		"name": "validate_config",
		"title": "Validate LaunchLayer config",
		"description": "Validate all configuration or one game without changing files.",
		"inputSchema": {"type": "object", "properties": {
			"target": {"type": "string", "minLength": 1, "maxLength": 200, "default": "all"},
		}, "additionalProperties": False},
	},
]

TOOLS.sort(key=lambda item: item["name"])
for tool in TOOLS:
	tool["annotations"] = {
		"readOnlyHint": True,
		"destructiveHint": False,
		"idempotentHint": True,
		"openWorldHint": False,
	}


def server_info() -> Dict[str, str]:
	return {
		"name": "launchlayer",
		"version": os.environ.get("LAUNCHLAYER_MCP_SERVER_VERSION", "unknown"),
		"description": "Read-only local inspection for LaunchLayer and Steam game configuration.",
	}


def response(request_id: Any, result: Optional[Dict[str, Any]] = None,
		code: Optional[int] = None, message: str = "", data: Any = None,
		modern: bool = False) -> None:
	payload: Dict[str, Any] = {"jsonrpc": "2.0", "id": request_id}
	if code is None:
		response_result = dict(result) if result is not None else {}
		if modern:
			response_result.setdefault("resultType", "complete")
			metadata = response_result.setdefault("_meta", {})
			metadata.setdefault(SERVER_INFO_META, server_info())
		payload["result"] = response_result
	else:
		payload["error"] = {"code": code, "message": message}
		if data is not None:
			payload["error"]["data"] = data
	with OUTPUT_LOCK:
		print(json.dumps(payload, separators=(",", ":")), flush=True)


def valid_text(value: Any, name: str, default: Optional[str] = None) -> Optional[str]:
	if value is None:
		return default
	if not isinstance(value, str) or not value or len(value) > 200:
		raise ValueError("%s must be a non-empty string of at most 200 characters" % name)
	if value.startswith("-") or any(ord(char) < 32 for char in value):
		raise ValueError("%s contains an unsafe value" % name)
	return value


def command_for(name: str, arguments: Dict[str, Any]) -> List[str]:
	if not isinstance(arguments, dict):
		raise ValueError("arguments must be an object")
	tool = next((item for item in TOOLS if item["name"] == name), None)
	if tool is None:
		raise KeyError(name)
	allowed = set(tool["inputSchema"].get("properties", {}))
	unknown = sorted(set(arguments) - allowed)
	if unknown:
		raise ValueError("unknown argument(s): %s" % ", ".join(unknown))

	if name == "cache_report":
		minimum_gb = arguments.get("minimum_gb", 5)
		if not isinstance(minimum_gb, int) or isinstance(minimum_gb, bool) or not 0 <= minimum_gb <= 100000:
			raise ValueError("minimum_gb must be an integer from 0 to 100000")
		kind = arguments.get("kind", "both")
		if kind not in ("both", "shader", "compat"):
			raise ValueError("kind must be both, shader, or compat")
		args = ["--cache-report", "--min-gb", str(minimum_gb), "--json"]
		if kind == "shader":
			args.append("--shader-only")
		elif kind == "compat":
			args.append("--compat-only")
		name_filter = valid_text(arguments.get("name_filter"), "name_filter")
		if name_filter:
			args.extend(["--grep", name_filter])
		return args
	if name == "list_games":
		configured = arguments.get("configured_only", False)
		if not isinstance(configured, bool):
			raise ValueError("configured_only must be a boolean")
		args = ["--list-games", "--json"]
		if configured:
			args.append("--configured")
		name_filter = valid_text(arguments.get("name_filter"), "name_filter")
		if name_filter:
			args.extend(["--grep", name_filter])
		return args
	if name == "launch_stats":
		args = ["--launch-stats"]
		game = valid_text(arguments.get("game"), "game")
		if game:
			args.append(game)
		args.append("--json")
		return args
	if name == "show_config":
		return ["--show-config", valid_text(arguments.get("game"), "game"), "--json"]
	if name == "show_paths":
		return ["--paths", valid_text(arguments.get("game"), "game"), "--json"]
	if name == "status":
		args = ["--status"]
		game = valid_text(arguments.get("game"), "game")
		if game:
			args.append(game)
		args.append("--json")
		return args
	if name == "detect_environment":
		return ["--detect-environment", "--json"]
	if name == "detect_defaults":
		return ["--detect-defaults", "--json"]
	if name == "doctor":
		return ["--doctor", "--json"]
	if name == "validate_config":
		return ["--validate-config", valid_text(arguments.get("target"), "target", "all"), "--json"]
	raise KeyError(name)


def call_tool(name: str, arguments: Dict[str, Any], request_id: Any = None) -> Dict[str, Any]:
	try:
		args = command_for(name, arguments)
	except KeyError:
		raise
	except ValueError as error:
		return {"content": [{"type": "text", "text": str(error)}], "isError": True}

	environment = os.environ.copy()
	environment.update({"NO_COLOR": "1", "LC_ALL": "C", "LAUNCHLAYER_QUIET": "1"})
	process = subprocess.Popen(
			[str(LAUNCHLAYER)] + args,
			cwd=str(ROOT), env=environment, stdin=subprocess.DEVNULL,
			stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
		)
	with RUNNING_LOCK:
		RUNNING[request_id] = process
		cancelled = request_id in CANCELLED
	if cancelled:
		process.terminate()
	try:
		stdout_raw, stderr_raw = process.communicate(timeout=45)
	except subprocess.TimeoutExpired:
		process.kill()
		process.communicate()
		with RUNNING_LOCK:
			RUNNING.pop(request_id, None)
		return {"content": [{"type": "text", "text": "LaunchLayer command timed out"}], "isError": True}
	finally:
		with RUNNING_LOCK:
			RUNNING.pop(request_id, None)
			cancelled = request_id in CANCELLED
			CANCELLED.discard(request_id)
	if cancelled:
		return {"content": [{"type": "text", "text": "LaunchLayer tool call cancelled"}], "isError": True}

	stdout = stdout_raw.strip()
	stderr = stderr_raw.strip()
	if len(stdout.encode("utf-8")) > MAX_RESULT_BYTES:
		return {"content": [{"type": "text", "text": "LaunchLayer result exceeded 4 MiB"}], "isError": True}
	if process.returncode != 0:
		message = stderr or stdout or "LaunchLayer command failed with exit %d" % process.returncode
		return {"content": [{"type": "text", "text": message[:MAX_RESULT_BYTES]}], "isError": True}
	try:
		data = json.loads(stdout)
	except json.JSONDecodeError:
		return {"content": [{"type": "text", "text": "LaunchLayer returned invalid JSON"}], "isError": True}
	if os.environ.get("LAUNCHLAYER_MCP_PRIVACY_MODE", "standard") == "redacted":
		data = redact_data(data)
	structured = data if isinstance(data, dict) else {"items": data}
	return {
		"content": [{"type": "text", "text": json.dumps(data, separators=(",", ":"))}],
		"structuredContent": structured,
		"isError": False,
	}


def redact_data(value: Any, key: str = "") -> Any:
	"""Remove local paths and exact hardware identifiers from MCP results."""
	key_lower = key.lower()
	if any(part in key_lower for part in ("path", "directory", "config_dir", "steam_root")) \
			or key_lower.endswith(("_dir", "_file")):
		return "[redacted]" if value not in (None, "") else value
	if key_lower in ("gpus", "displays", "monitors", "cpu_model", "gpu_name", "output_name"):
		return "[redacted]" if value not in (None, "", []) else value
	if isinstance(value, dict):
		return {child_key: redact_data(child_value, child_key) for child_key, child_value in value.items()}
	if isinstance(value, list):
		return [redact_data(item, key) for item in value]
	if isinstance(value, str) and (value.startswith("/") or value.startswith("~/")):
		return "[redacted]"
	return value


def modern_request(request: Dict[str, Any]) -> bool:
	params = request.get("params", {})
	if not isinstance(params, dict):
		return False
	metadata = params.get("_meta", {})
	return isinstance(metadata, dict) and metadata.get(PROTOCOL_VERSION_META) == MODERN_PROTOCOL_VERSION


def handle(request: Dict[str, Any], initialized: bool) -> bool:
	method = request.get("method")
	request_id = request.get("id")
	modern = method == "server/discover" or modern_request(request)
	if method == "notifications/cancelled":
		params = request.get("params", {})
		cancel_id = params.get("requestId") if isinstance(params, dict) else None
		with RUNNING_LOCK:
			CANCELLED.add(cancel_id)
			process = RUNNING.get(cancel_id)
		if process is not None:
			process.terminate()
		return initialized
	if "id" not in request:
		return initialized
	if method == "server/discover":
		privacy = os.environ.get("LAUNCHLAYER_MCP_PRIVACY_MODE", "standard")
		response(request_id, {
			"supportedVersions": [MODERN_PROTOCOL_VERSION],
			"capabilities": {"tools": {}},
			"instructions": "Use these read-only tools to inspect games, resolved settings, recommendations, paths, and host health. No tool launches games or changes configuration. Privacy mode: %s." % privacy,
			"ttlMs": 3600000,
			"cacheScope": "public",
		}, modern=True)
		return initialized
	if method == "initialize":
		if initialized:
			response(request_id, code=-32600, message="Server is already initialized")
			return initialized
		params = request.get("params", {})
		requested = params.get("protocolVersion") if isinstance(params, dict) else None
		protocol_version = requested if requested in LEGACY_PROTOCOL_VERSIONS else LEGACY_PROTOCOL_VERSIONS[0]
		privacy = os.environ.get("LAUNCHLAYER_MCP_PRIVACY_MODE", "standard")
		response(request_id, {
			"protocolVersion": protocol_version,
			"capabilities": {"tools": {"listChanged": False}},
			"serverInfo": server_info(),
			"instructions": "Use these read-only tools to inspect games, resolved settings, recommendations, paths, and host health. No tool launches games or changes configuration. Privacy mode: %s." % privacy,
		})
		return True
	elif not initialized and not modern:
		response(request_id, code=-32002, message="Server is not initialized")
	elif method == "ping":
		response(request_id, {}, modern=modern)
	elif method == "tools/list":
		response(request_id, {"tools": TOOLS}, modern=modern)
	elif method == "tools/call":
		params = request.get("params", {})
		if not isinstance(params, dict) or not isinstance(params.get("name"), str):
			response(request_id, code=-32602, message="Invalid tools/call parameters")
			return initialized
		def run_tool_request() -> None:
			try:
				result = call_tool(params["name"], params.get("arguments", {}), request_id)
			except KeyError:
				response(request_id, code=-32602, message="Unknown tool: %s" % params["name"])
				return
			response(request_id, result, modern=modern)
		worker = threading.Thread(target=run_tool_request, name="mcp-tool-%s" % request_id)
		WORKERS.append(worker)
		worker.start()
	else:
		response(request_id, code=-32601, message="Method not found: %s" % method)
	return initialized


def main() -> int:
	signal.signal(signal.SIGPIPE, signal.SIG_DFL)
	initialized = False
	for raw_line in sys.stdin.buffer:
		if len(raw_line) > MAX_REQUEST_BYTES:
			response(None, code=-32600, message="Request exceeds 1 MiB")
			continue
		try:
			request = json.loads(raw_line)
			if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
				raise ValueError
		except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
			response(None, code=-32700, message="Parse error")
			continue
		initialized = handle(request, initialized)
	for worker in WORKERS:
		worker.join()
	return 0


if __name__ == "__main__":
	sys.exit(main())
