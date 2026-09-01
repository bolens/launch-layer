#!/usr/bin/env bash
# Integration tests for game listing, paths, and cache reports.
load '../helpers.bash'

setup() {
	bats_integration_setup
}

teardown() {
	bats_integration_teardown
}

@test "list-games json output" {
	local fake_steam
	fake_steam="$(fake_steam_root 1794680 "Vampire Survivors")"
	run env STEAM_ROOT="$fake_steam" "$SCRIPT" --list-games --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"appid"'* ]]
	rm -rf "$fake_steam"
}

@test "list-games uses heuristic native column" {
	local fake_steam
	fake_steam="$(fake_steam_root 1794680 "Vampire Survivors")"
	run env STEAM_ROOT="$fake_steam" "$SCRIPT" --list-games --grep "Vampire Survivors"
	[[ $status -eq 0 ]]
	[[ "$output" == *"1794680"* ]]
	[[ "$output" == *"yes"* ]]
	rm -rf "$fake_steam"
}

@test "list-games tabular rows are not prefixed by scan progress text" {
	local fake_steam
	fake_steam="$(fake_steam_root 1794680 "Vampire Survivors")"
	run env STEAM_ROOT="$fake_steam" TERM=xterm-256color "$SCRIPT" --list-games --grep "Vampire Survivors"
	[[ $status -eq 0 ]]
	[[ "$output" != *"games scanned)"*"1794680"* ]]
	[[ "$output" =~ ^APPID[[:space:]] ]]
	rm -rf "$fake_steam"
}

@test "list-games output survives an unwritable TUI cache" {
	local fake_steam blocked_cache
	fake_steam="$(fake_steam_root 1794680 "Vampire Survivors")"
	blocked_cache="$(mktemp)"
	run env STEAM_ROOT="$fake_steam" XDG_CACHE_HOME="$blocked_cache" "$SCRIPT" --list-games --grep "Vampire Survivors"
	[[ $status -eq 0 ]]
	[[ "$output" =~ ^APPID[[:space:]] ]]
	[[ "$output" == *"1794680"* ]]
	[[ "$output" != *"Not a directory"* ]]
	rm -rf "$fake_steam"
	rm -f "$blocked_cache"
}

@test "list-games updates persisted games cache on full scan" {
	local fake_steam cache_dir lines_file
	fake_steam="$(fake_steam_root 1794680 "Vampire Survivors")"
	cache_dir="$(mktemp -d)"
	lines_file="$cache_dir/launchlayer/tui-games/lines"
	run env STEAM_ROOT="$fake_steam" XDG_CACHE_HOME="$cache_dir" "$SCRIPT" --list-games --grep "Vampire Survivors"
	[[ $status -eq 0 ]]
	[[ "$output" == *"1794680"* ]]
	[[ -f "$lines_file" ]]
	[[ "$(<"$cache_dir/launchlayer/tui-games/status")" == "ready" ]]
	grep -q '1794680' "$lines_file"
	rm -rf "$fake_steam" "$cache_dir"
}

@test "list-games json mode still updates persisted games cache" {
	local fake_steam cache_dir
	fake_steam="$(fake_steam_root 1794680 "Vampire Survivors")"
	cache_dir="$(mktemp -d)"
	run env STEAM_ROOT="$fake_steam" XDG_CACHE_HOME="$cache_dir" "$SCRIPT" --list-games --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"1794680"'* ]]
	[[ -f "$cache_dir/launchlayer/tui-games/lines" ]]
	grep -q '1794680' "$cache_dir/launchlayer/tui-games/lines"
	rm -rf "$fake_steam" "$cache_dir"
}

@test "list-games configured only" {
	local fake_steam
	fake_steam="$(fake_steam_root 2357570 "Overwatch")"
	run env STEAM_ROOT="$fake_steam" LAUNCHLAYER_GAMES_DIR="$REPO_ROOT/examples/games" "$SCRIPT" --list-games --configured --grep "Overwatch"
	[[ $status -eq 0 ]]
	[[ "$output" == *"2357570"* ]]
	rm -rf "$fake_steam"
}

@test "paths by name" {
	local fake_steam
	fake_steam="$(fake_steam_root 2357570 "Overwatch")"
	run env STEAM_ROOT="$fake_steam" "$SCRIPT" --paths overwatch
	[[ $status -eq 0 ]]
	[[ "$output" == *"2357570"* ]]
	[[ "$output" == *"Shader cache"* ]]
	rm -rf "$fake_steam"
}

@test "paths json is valid" {
	local fake_steam
	fake_steam="$(fake_steam_root 2357570 "Overwatch")"
	run env STEAM_ROOT="$fake_steam" "$SCRIPT" --paths 2357570 --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"appid":"2357570"'* || "$output" == *'"appid": "2357570"'* ]]
	[[ "$output" == *'"shader_cache"'* ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["appid"]=="2357570"' "$output"
	rm -rf "$fake_steam"
}

@test "cache-report runs" {
	run "$SCRIPT" --cache-report --min-gb 999
	[[ $status -eq 0 ]]
	[[ "$output" == *"Cache report"* ]]
}

@test "cache-report json runs" {
	run "$SCRIPT" --cache-report --min-gb 999 --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"entries"'* || "$output" == *'"games"'* || "$output" == *'"shader"'* ]]
	python3 -c 'import json,sys; json.loads(sys.argv[1])' "$output"
}

@test "cache-report grep filters" {
	local fake_steam
	fake_steam="$(fake_steam_root 2357570 "Overwatch")"
	run env STEAM_ROOT="$fake_steam" "$SCRIPT" --cache-report --min-gb 0 --grep "Overwatch"
	[[ $status -eq 0 ]]
	[[ "$output" == *"2357570"* ]]
	rm -rf "$fake_steam"
}

@test "cache-report shader-only mode" {
	run "$SCRIPT" --cache-report --min-gb 999 --shader-only
	[[ $status -eq 0 ]]
	[[ "$output" == *"Cache report"* ]]
	[[ "$output" != *"compat total"* || "$output" == *"shader"* ]]
}

@test "tui-game-preview for Overwatch" {
	[[ -f "$REPO_ROOT/examples/games/2357570.env" ]] || skip "2357570.env missing"
	local fake_steam
	fake_steam="$(fake_steam_root 2357570 "Overwatch")"
	run env STEAM_ROOT="$fake_steam" LAUNCHLAYER_GAMES_DIR="$REPO_ROOT/examples/games" "$SCRIPT" --tui-game-preview 2357570
	[[ $status -eq 0 ]]
	[[ "$output" == *"2357570"* ]]
	rm -rf "$fake_steam"
}

@test "bulk-set-include dry-run on configured games" {
	local fake_steam tmp_games
	fake_steam="$(fake_steam_root 2357570 "Overwatch")"
	tmp_games="$(mktemp -d)"
	cp "$REPO_ROOT/examples/games/2357570.env" "$tmp_games/"
	run env \
		STEAM_ROOT="$fake_steam" \
		LAUNCHLAYER_GAMES_DIR="$tmp_games" \
		"$SCRIPT" --bulk-set-include competitive --all-configured --dry-run
	[[ $status -eq 0 ]]
	[[ "$output" == *"2357570"* ]]
	[[ "$output" == *"competitive"* ]]
	rm -rf "$fake_steam" "$tmp_games"
}

@test "help documents hub-prefs and bulk-set-include" {
	run "$SCRIPT" --help
	[[ $status -eq 0 ]]
	[[ "$output" == *"--hub-prefs"* ]]
	[[ "$output" == *"--bulk-set-include"* ]]
}
