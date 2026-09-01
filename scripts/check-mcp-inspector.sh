#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPO_ROOT
readonly INSPECTOR_VERSION="2.4.0"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

config="$tmp_dir/mcp.json"
sed \
	-e "s|@COMMAND@|$REPO_ROOT/launchlayer|g" \
	"$SCRIPT_DIR/mcp-inspector.json.in" > "$config"

npx --yes "@modelcontextprotocol/inspector@$INSPECTOR_VERSION" --cli \
	--config "$config" --server launchlayer-legacy --method tools/list \
	--strict --format json >/dev/null

npx --yes "@modelcontextprotocol/inspector@$INSPECTOR_VERSION" --cli \
	--config "$config" --server launchlayer-modern --method tools/list \
	--strict --format json >/dev/null
