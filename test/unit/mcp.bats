#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	MCP_SERVER="$REPO_ROOT/scripts/launchlayer-mcp.py"
}

run_mcp() {
	printf '%s\n' "$@" | LAUNCHLAYER_MCP_SERVER_VERSION=0.12.0 python3 "$MCP_SERVER"
}

@test "MCP initializes with negotiated protocol and read-only tools" {
	run run_mcp \
		'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}' \
		'{"jsonrpc":"2.0","method":"notifications/initialized"}' \
		'{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

	[ "$status" -eq 0 ]
	python3 -c '
import json, sys
messages = [json.loads(line) for line in sys.stdin]
assert messages[0]["result"]["protocolVersion"] == "2025-06-18"
assert messages[0]["result"]["serverInfo"]["version"] == "0.12.0"
tools = messages[1]["result"]["tools"]
assert [tool["name"] for tool in tools] == sorted(tool["name"] for tool in tools)
assert all(tool["annotations"]["readOnlyHint"] for tool in tools)
assert all(not tool["annotations"]["destructiveHint"] for tool in tools)
' <<< "$output"
}

@test "MCP rejects tool calls before initialization" {
	run run_mcp '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

	[ "$status" -eq 0 ]
	[[ "$output" == *'"code":-32002'* ]]
}

@test "MCP distinguishes malformed JSON from invalid JSON-RPC" {
	run run_mcp \
		'not-json' \
		'{"jsonrpc":"2.0","id":2,"params":{}}' \
		'[]' \
		'{"jsonrpc":"2.0","id":[],"method":"ping"}'

	[ "$status" -eq 0 ]
	python3 -c '
import json, sys
messages = [json.loads(line) for line in sys.stdin]
assert [message["error"]["code"] for message in messages] == [-32700, -32600, -32600, -32600]
assert messages[1]["id"] == 2
assert messages[2]["id"] is None
assert messages[3]["id"] is None
' <<< "$output"
}

@test "MCP 2026 discovers capabilities and serves tools without initialization" {
	local meta
	meta='"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}'
	run run_mcp \
		"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"server/discover\",\"params\":{$meta}}" \
		"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{$meta}}"

	[ "$status" -eq 0 ]
	python3 -c '
import json, sys
messages = [json.loads(line) for line in sys.stdin]
assert messages[0]["result"]["supportedVersions"] == ["2026-07-28"]
assert messages[0]["result"]["resultType"] == "complete"
assert messages[1]["result"]["resultType"] == "complete"
assert messages[1]["result"]["_meta"]["io.modelcontextprotocol/serverInfo"]["name"] == "launchlayer"
assert messages[1]["result"]["ttlMs"] == 3600000
assert messages[1]["result"]["cacheScope"] == "public"
assert len(messages[1]["result"]["tools"]) >= 10
' <<< "$output"
}

@test "MCP 2026 rejects incomplete and unsupported request envelopes" {
	run run_mcp \
		'{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}' \
		'{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2099-01-01","io.modelcontextprotocol/clientCapabilities":{}}}}' \
		'{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/clientCapabilities":{}}}}'

	[ "$status" -eq 0 ]
	python3 -c '
import json, sys
messages = [json.loads(line) for line in sys.stdin]
assert messages[0]["error"]["code"] == -32021
assert messages[1]["error"]["code"] == -32022
assert messages[1]["error"]["data"]["supportedVersions"] == ["2026-07-28"]
assert messages[2]["error"]["code"] == -32022
' <<< "$output"
}

@test "legacy initialization does not negotiate the handshake-free protocol" {
	run run_mcp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2026-07-28","capabilities":{},"clientInfo":{"name":"legacy","version":"1"}}}'

	[ "$status" -eq 0 ]
	[[ "$output" == *'"protocolVersion":"2025-11-25"'* ]]
}

@test "MCP reports unsafe and unknown tool arguments as tool errors" {
	run run_mcp \
		'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}' \
		'{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"show_config","arguments":{"game":"--help"}}}' \
		'{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_games","arguments":{"extra":true}}}'

	[ "$status" -eq 0 ]
	[[ "$output" == *'"isError":true'* ]]
	[[ "$output" == *'unsafe value'* ]]
	[[ "$output" == *'unknown argument(s): extra'* ]]
}

@test "launchlayer --mcp exposes the stdio server" {
	run bash -c 'printf '\''%s\n'\'' '\''{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}'\'' | "$1/launchlayer" --mcp' _ "$REPO_ROOT"

	[ "$status" -eq 0 ]
	[[ "$output" == *'"name":"launchlayer"'* ]]
	expected_version="$(sed -n 's/^LAUNCHLAYER_VERSION=//p' "$REPO_ROOT/lib/cli.sh")"
	[[ "$output" == *"\"version\":\"$expected_version\""* ]]
}

@test "MCP tool calls return structured LaunchLayer JSON" {
	run run_mcp \
		'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}' \
		'{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"detect_defaults","arguments":{}}}'

	[ "$status" -eq 0 ]
	python3 -c '
import json, sys
messages = [json.loads(line) for line in sys.stdin]
result = messages[1]["result"]
assert result["isError"] is False
assert isinstance(result["structuredContent"]["defaults"], list)
' <<< "$output"
}

@test "MCP exposes cache and launch statistics as read-only tools" {
	run run_mcp \
		'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}' \
		'{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
	[ "$status" -eq 0 ]
	python3 -c '
import json, sys
messages = [json.loads(line) for line in sys.stdin]
tools = {tool["name"]: tool for tool in messages[1]["result"]["tools"]}
assert "cache_report" in tools
assert "launch_stats" in tools
assert tools["cache_report"]["annotations"]["readOnlyHint"] is True
' <<< "$output"
}

@test "MCP redacted privacy removes local paths and exact hardware lists" {
	run python3 -c '
import importlib.util, pathlib, sys
path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("launchlayer_mcp", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
value = module.redact_data({
    "install_dir": "/games/private",
    "gpus": [{"name": "Exact GPU"}],
    "vendor": "nvidia",
    "uri": "file:///games/private/config.env",
    "windows": "C:\\Games\\Private",
    "unc": "\\\\server\\private",
})
assert value == {
    "install_dir": "[redacted]",
    "gpus": "[redacted]",
    "vendor": "nvidia",
    "uri": "[redacted]",
    "windows": "[redacted]",
    "unc": "[redacted]",
}
' "$MCP_SERVER"
	[ "$status" -eq 0 ]
}

@test "MCP error text is bounded by UTF-8 byte size" {
	run python3 - "$MCP_SERVER" <<'PY'
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("launchlayer_mcp", pathlib.Path(sys.argv[1]))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
value = "é" * 10
truncated = module.truncate_utf8(value, 7)
assert truncated == "é" * 3
assert len(truncated.encode("utf-8")) <= 7
PY
	[ "$status" -eq 0 ]
}

@test "launchlayer --mcp validates privacy mode" {
	run "$REPO_ROOT/launchlayer" --mcp --privacy unsafe
	[ "$status" -eq 2 ]
	[[ "$output" == *"standard or redacted"* ]]
}

@test "MCP cancellation terminates an active tool process" {
	local tmp fake
	tmp="$(mktemp -d)"
	fake="$tmp/launchlayer"
	cat > "$fake" <<'EOF'
#!/usr/bin/env bash
sleep 10
printf '{"done":true}\n'
EOF
	chmod +x "$fake"
	run python3 - "$MCP_SERVER" "$fake" <<'PY'
import importlib.util
import io
import json
import pathlib
import sys

spec = importlib.util.spec_from_file_location("launchlayer_mcp", pathlib.Path(sys.argv[1]))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.LAUNCHLAYER = pathlib.Path(sys.argv[2])
request = {"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {"name": "doctor", "arguments": {}}}
module.handle({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25"}}, False)
module.handle(request, True)
module.handle({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": 7, "reason": "test"}}, True)
for worker in module.WORKERS:
    worker.join(2)
assert all(not worker.is_alive() for worker in module.WORKERS)
PY
	[ "$status" -eq 0 ]
	[[ "$output" == *"tool call cancelled"* ]]
	rm -rf "$tmp"
}

@test "MCP ignores cancellation for unknown request IDs" {
	run python3 - "$MCP_SERVER" <<'PY'
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("launchlayer_mcp", pathlib.Path(sys.argv[1]))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for request_id in range(1000):
    module.handle({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": request_id}}, True)
module.handle({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": []}}, True)
assert module.CANCELLED == set()
assert module.PENDING == set()
PY
	[ "$status" -eq 0 ]
}

@test "MCP reports tool process startup failures and clears request state" {
	run python3 - "$MCP_SERVER" <<'PY'
import importlib.util
import io
import pathlib
import sys

spec = importlib.util.spec_from_file_location("launchlayer_mcp", pathlib.Path(sys.argv[1]))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.LAUNCHLAYER = pathlib.Path("/definitely/missing/launchlayer")
module.handle({"jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": {"name": "doctor", "arguments": {}}}, True)
for worker in module.WORKERS:
    worker.join(2)
assert module.PENDING == set()
assert module.RUNNING == {}
PY
	[ "$status" -eq 0 ]
	[[ "$output" == *'"code":-32603'* ]]
}
