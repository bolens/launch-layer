#!/usr/bin/env bash
# Integration tests for hub apply/recommend/search against the local mock server.
load '../helpers.bash'

setup() {
	bats_integration_setup
	HUB_TMP="$(mktemp -d)"
	export XDG_CONFIG_HOME="$HUB_TMP"
	export HOME="$HUB_TMP"
	CONFIG_TMP="$(temp_config_dir)"
	export LAUNCHLAYER_CONFIG_DIR="$CONFIG_TMP"
	export LAUNCHLAYER_GAMES_DIR="$CONFIG_TMP/games"
	mkdir -p "$LAUNCHLAYER_GAMES_DIR"
	start_hub_mock_server test-secret 0
	write_hub_conf "$XDG_CONFIG_HOME" "$HUB_MOCK_URL" "" minimal
	source_lib commands prefs platform cli tools config inspect hub
}

teardown() {
	stop_hub_mock_server
	[[ -n "${HUB_TMP:-}" ]] && rm -rf "$HUB_TMP"
	[[ -n "${CONFIG_TMP:-}" ]] && rm -rf "$CONFIG_TMP"
	bats_integration_teardown
}

@test "hub_apply_config dry-run prints env content without writing file" {
	run env \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		CONFIG_DIR="$CONFIG_TMP" \
		LAUNCHLAYER_GAMES_DIR="$CONFIG_TMP/games" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib commands prefs platform cli tools config inspect hub
			hub_apply_config cfgtest00001 --dry-run
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Would write"* ]]
	[[ "$output" == *"GAMEMODE=1"* ]]
	[[ "$output" == *"MANGOHUD=1"* ]]
	[[ ! -f "$CONFIG_TMP/games/42424242.env" ]]
}

@test "hub_apply_config writes per-game env and backs up existing file" {
	echo 'GAMEMODE=0' > "$CONFIG_TMP/games/42424242.env"
	run env \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		CONFIG_DIR="$CONFIG_TMP" \
		LAUNCHLAYER_GAMES_DIR="$CONFIG_TMP/games" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib commands prefs platform cli tools config inspect hub
			hub_apply_config cfgtest00001
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Applied hub config"* ]]
	[[ "$output" == *"2024-01-01"* ]]
	grep -q 'GAMEMODE=1' "$CONFIG_TMP/games/42424242.env"
	ls "$CONFIG_TMP/games"/42424242.env.bak.* >/dev/null 2>&1
}

@test "hub_apply_config keeps distinct backups for rapid repeated applies" {
	echo 'GAMEMODE=0' > "$CONFIG_TMP/games/42424242.env"
	run env \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		CONFIG_DIR="$CONFIG_TMP" \
		LAUNCHLAYER_GAMES_DIR="$CONFIG_TMP/games" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib commands prefs platform cli tools config inspect hub
			hub_apply_config cfgtest00001 >/dev/null
			hub_apply_config cfgtest00001 >/dev/null
			find "'"$CONFIG_TMP"'/games" -maxdepth 1 -name "42424242.env.bak.*" -print | wc -l
		'
	[[ $status -eq 0 ]]
	[[ "$output" -eq 2 ]]
}

@test "hub_apply_config --json dry-run emits structured payload" {
	run env \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		CONFIG_DIR="$CONFIG_TMP" \
		LAUNCHLAYER_GAMES_DIR="$CONFIG_TMP/games" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib commands prefs platform cli tools config inspect hub
			hub_apply_config cfgtest00001 --dry-run --json
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *'"appid"'* ]]
	[[ "$output" == *'"42424242"'* ]]
	[[ "$output" == *'GAMEMODE=1'* ]]
}

@test "hub_recommend_configs returns mock results as json" {
	run env \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		CONFIG_DIR="$CONFIG_TMP" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib commands prefs platform hardware cli tools config hub
			hub_recommend_configs 42424242 --limit 5 --json
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *'"config_id"'* ]]
	[[ "$output" == *"cfgtest00001"* ]]
	[[ "$output" == *'"similarity"'* ]]
}

@test "hub_search_machines returns similar machines json" {
	run env \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		CONFIG_DIR="$CONFIG_TMP" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib commands prefs platform hardware cli tools config hub
			hub_search_machines --limit 5 --json
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *'"similar-box"'* ]]
	[[ "$output" == *'"similarity"'* ]]
}

@test "launchlayer hub-apply dry-run via CLI uses configured mock hub" {
	run env \
		HOME="$HUB_TMP" \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		LAUNCHLAYER_CONFIG_DIR="$CONFIG_TMP" \
		LAUNCHLAYER_GAMES_DIR="$CONFIG_TMP/games" \
		"$SCRIPT" --hub-apply cfgtest00001 --dry-run
	[[ $status -eq 0 ]]
	[[ "$output" == *"Would write"* ]]
	[[ "$output" == *"GAMEMODE=1"* ]]
}

@test "hub_apply_config rejects invalid config id before request" {
	run env \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		CONFIG_DIR="$CONFIG_TMP" \
		LAUNCHLAYER_GAMES_DIR="$CONFIG_TMP/games" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib commands prefs platform cli tools config inspect hub
			hub_apply_config cfg-test-1 --dry-run
		'
	[[ $status -eq 1 ]]
	[[ "$output" == *"Invalid hub config ID"* ]]
}

@test "hub_apply_config rejects invalid env content from hub before writing" {
	run env \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		CONFIG_DIR="$CONFIG_TMP" \
		LAUNCHLAYER_GAMES_DIR="$CONFIG_TMP/games" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib commands prefs platform cli tools config inspect hub
			hub_apply_config cfgbadenv01 --dry-run
		'
	[[ $status -eq 1 ]]
	[[ "$output" == *"failed validation"* ]]
	[[ ! -f "$CONFIG_TMP/games/42424242.env" ]]
}

@test "launchlayer hub-apply rejects invalid env content from hub" {
	run env \
		HOME="$HUB_TMP" \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		LAUNCHLAYER_CONFIG_DIR="$CONFIG_TMP" \
		LAUNCHLAYER_GAMES_DIR="$CONFIG_TMP/games" \
		"$SCRIPT" --hub-apply cfgbadenv01 --dry-run
	[[ $status -eq 1 ]]
	[[ "$output" == *"failed validation"* ]]
}

@test "launchlayer hub-apply strips untrusted remote exec keys" {
	mkdir -p "$CONFIG_TMP/launch.d/presets"
	printf 'GAMEMODE=0\n' > "$CONFIG_TMP/launch.d/presets/standard.env"
	run env \
		HOME="$HUB_TMP" \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		LAUNCHLAYER_CONFIG_DIR="$CONFIG_TMP" \
		LAUNCHLAYER_GAMES_DIR="$CONFIG_TMP/games" \
		"$SCRIPT" --hub-apply cfgunsafe01 --dry-run 2>&1
	[[ $status -eq 0 ]]
	[[ "$output" == *"Stripped untrusted hub keys"* ]]
	[[ "$output" == *"Would write"* ]]
	[[ "$output" != *"curl evil.example"* ]]
}
