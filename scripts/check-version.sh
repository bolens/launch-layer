#!/usr/bin/env bash
# Verify LAUNCHLAYER_VERSION is consistent across known surfaces.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

version="$(sed -n 's/^LAUNCHLAYER_VERSION=//p' lib/cli.sh | head -1)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
	echo "invalid LAUNCHLAYER_VERSION in lib/cli.sh: ${version:-<empty>}" >&2
	exit 1
}

fail=0
check_contains() {
	local file=$1 needle=$2
	if [[ ! -f "$file" ]]; then
		echo "missing file: $file" >&2
		fail=1
		return
	fi
	if ! grep -qF "$needle" "$file"; then
		echo "expected '$needle' in $file" >&2
		fail=1
	fi
}

check_contains test/integration/cli.bats "version reports the release version"
check_contains test/integration/cli.bats '"$expected_version"'
check_contains docs/tui.md 'LaunchLayer <version>'
check_contains CHANGELOG.md "## [${version}]"
check_contains lib/commands/dispatch-mcp.sh 'LAUNCHLAYER_MCP_SERVER_VERSION="$LAUNCHLAYER_VERSION"'

if (( fail )); then
	exit 1
fi

echo "version ${version} is consistent"
