#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "sourcing common does not migrate legacy directories" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/config/steam-launch" "$tmp/state/steam-launch"
	run env \
		HOME="$tmp/home" \
		XDG_CONFIG_HOME="$tmp/config" \
		XDG_STATE_HOME="$tmp/state" \
		CONFIG_DIR="$REPO_ROOT" \
		bash -c 'source "'"$REPO_ROOT"'/lib/common.sh"; [[ -d "$XDG_CONFIG_HOME/steam-launch" && -d "$XDG_STATE_HOME/steam-launch" ]]'
	[[ $status -eq 0 ]]
	rm -rf "$tmp"
}

@test "legacy directory migration is explicit and idempotent" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/config/steam-launch" "$tmp/state/steam-launch"
	touch "$tmp/config/steam-launch/config-marker" "$tmp/state/steam-launch/state-marker"
	run env \
		HOME="$tmp/home" \
		XDG_CONFIG_HOME="$tmp/config" \
		XDG_STATE_HOME="$tmp/state" \
		CONFIG_DIR="$REPO_ROOT" \
		bash -c '
			source "'"$REPO_ROOT"'/lib/common.sh"
			migrate_legacy_install_paths
			migrate_legacy_install_paths
			[[ -f "$XDG_CONFIG_HOME/launchlayer/config-marker" ]]
			[[ -f "$XDG_STATE_HOME/launchlayer/state-marker" ]]
			[[ ! -e "$XDG_CONFIG_HOME/steam-launch" && ! -e "$XDG_STATE_HOME/steam-launch" ]]
		'
	[[ $status -eq 0 ]]
	rm -rf "$tmp"
}

@test "read-only fast CLI paths do not trigger legacy migration" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/config/steam-launch" "$tmp/state/steam-launch"
	run env \
		HOME="$tmp/home" \
		XDG_CONFIG_HOME="$tmp/config" \
		XDG_STATE_HOME="$tmp/state" \
		"$REPO_ROOT/launchlayer" --version
	[[ $status -eq 0 ]]
	[[ -d "$tmp/config/steam-launch" && -d "$tmp/state/steam-launch" ]]
	[[ ! -e "$tmp/config/launchlayer" && ! -e "$tmp/state/launchlayer" ]]
	rm -rf "$tmp"
}
