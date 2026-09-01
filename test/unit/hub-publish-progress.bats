#!/usr/bin/env bash
# Bulk hub operations keep users informed without corrupting JSON stdout.
load '../helpers.bash'

setup() {
	bats_unit_setup
	source_lib commands prefs platform hardware cli tools config inspect hub
}

@test "bulk publish reports per-game progress on stderr and keeps JSON on stdout" {
	local tmp games stdout_file stderr_file
	tmp="$(mktemp -d)"
	games="$tmp/games"
	stdout_file="$tmp/stdout"
	stderr_file="$tmp/stderr"
	mkdir -p "$games" "$tmp/launch.d/presets"
	printf 'GAMEMODE=1\n' > "$tmp/launch.d/default.env"
	printf 'MANGOHUD=0\n' > "$tmp/launch.d/presets/standard.env"
	printf 'INCLUDE=presets/standard.env\n' > "$games/111.env"
	printf 'INCLUDE=presets/standard.env\n' > "$games/222.env"

	run env CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$games" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib commands prefs platform hardware cli tools config inspect hub
		command_required_or_fail() { return 0; }
		hub_require_url() { return 0; }
		load_hub_prefs() { return 0; }
		hub_require_privileged_auth() { return 0; }
		hub_load_launch_context() { return 0; }
		hub_fingerprint_from_detection() { printf "{}\n"; }
		list_games() {
			printf "%s\n" \
				"{\"appid\":\"111\",\"name\":\"First Game\"}" \
				"{\"appid\":\"222\",\"name\":\"Second Game\"}"
		}
		hub_sync_one_game() {
			HUB_SYNC_RESPONSE="{\"config_id\":\"cfgtest00001\",\"updated\":false}"
			if [[ "$2" == 222 ]]; then
				HUB_SYNC_UPDATED=1
			else
				HUB_SYNC_UPDATED=0
			fi
		}
		hub_publish_config --all-configured --json > "'"$stdout_file"'" 2> "'"$stderr_file"'"
	'
	[[ $status -eq 0 ]]
	python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d == {"published":["111","222"],"updated":["222"],"created":["111"]}' "$stdout_file"
	[[ "$(cat "$stderr_file")" == $'Discovering configured games...\n[1] Publishing First Game (111)... created\n[2] Publishing Second Game (222)... updated' ]]
	rm -rf "$tmp"
}
