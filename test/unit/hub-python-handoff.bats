#!/usr/bin/env bats
# The mock must not re-enter a caller's version manager after fixture isolation.
load '../helpers.bash'

setup() {
	HARNESS_TMP=$(mktemp -d)
	HARNESS_ROOT=$(launchlayer_root)
	HARNESS_REAL_PYTHON=$(python3 -I -c 'import os, sys; print(os.path.realpath(sys.executable))')
}

teardown() {
	rm -rf "$HARNESS_TMP"
}

@test "hub mock keeps the selected real Python across isolated HOME and XDG paths" {
	mkdir -p "$HARNESS_TMP/bin" "$HARNESS_TMP/original/config" "$HARNESS_TMP/original/cache" "$HARNESS_TMP/original/state" "$HARNESS_TMP/isolated"
	cat > "$HARNESS_TMP/bin/python3" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail
if [[ $HOME != "$EXPECTED_HOME" || $XDG_CONFIG_HOME != "$EXPECTED_CONFIG" || $XDG_CACHE_HOME != "$EXPECTED_CACHE" || $XDG_STATE_HOME != "$EXPECTED_STATE" ]]; then
	printf '%s\n' VERSION_MANAGER_CONTEXT_CHANGED >&2
	exit 79
fi
printf '%s\n' 'resolved in original context' >> "$LAUNCHER_CALLS"
exec "$REAL_PYTHON" "$@"
LAUNCHER
	chmod +x "$HARNESS_TMP/bin/python3"

	run env \
		PATH="$HARNESS_TMP/bin:$PATH" \
		BATS_TEST_DIRNAME="$HARNESS_ROOT/test/unit" \
		HOME="$HARNESS_TMP/original" \
		XDG_CONFIG_HOME="$HARNESS_TMP/original/config" \
		XDG_CACHE_HOME="$HARNESS_TMP/original/cache" \
		XDG_STATE_HOME="$HARNESS_TMP/original/state" \
		EXPECTED_HOME="$HARNESS_TMP/original" \
		EXPECTED_CONFIG="$HARNESS_TMP/original/config" \
		EXPECTED_CACHE="$HARNESS_TMP/original/cache" \
		EXPECTED_STATE="$HARNESS_TMP/original/state" \
		REAL_PYTHON="$HARNESS_REAL_PYTHON" \
		LAUNCHER_CALLS="$HARNESS_TMP/launcher-calls" \
		bash -c '
			set -euo pipefail
			source "$1/test/helpers.bash"
			unset BATS_PYTHON_EXECUTABLE
			bats_integration_setup
			trap '\''stop_hub_mock_server; bats_integration_teardown'\'' EXIT
			export HOME="$2/isolated" XDG_CONFIG_HOME="$2/isolated/config" XDG_CACHE_HOME="$2/isolated/cache" XDG_STATE_HOME="$2/isolated/state"
			start_hub_mock_server test-secret 0
			"$REAL_PYTHON" -I -c '\''import json, sys, urllib.request; opener = urllib.request.build_opener(urllib.request.ProxyHandler({})); data = json.load(opener.open(sys.argv[1] + "/api/auth", timeout=5)); assert data == {"publish_auth_required": True}'\'' "$HUB_MOCK_URL"
		' bash "$HARNESS_ROOT" "$HARNESS_TMP"
	if [[ $status -ne 0 ]]; then
		printf '%s\n' "$output" >&2
		return 1
	fi
	[[ $(wc -l < "$HARNESS_TMP/launcher-calls") -eq 1 ]]
}
