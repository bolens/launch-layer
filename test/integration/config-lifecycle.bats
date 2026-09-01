#!/usr/bin/env bash
# Integration tests for init, prune, and appid lifecycle commands.
load '../helpers.bash'

setup() {
	bats_integration_setup
}

teardown() {
	bats_integration_teardown
}

@test "init-unconfigured dry-run does not create files" {
	local tmp before after
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games"
	before="$(find "$tmp/games" -maxdepth 1 -name '[0-9]*.env' 2>/dev/null | wc -l)"
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --init-unconfigured --eac-only --dry-run
	[[ $status -eq 0 ]]
	[[ "$output" == *"Init unconfigured (dry-run)"* ]]
	after="$(find "$tmp/games" -maxdepth 1 -name '[0-9]*.env' 2>/dev/null | wc -l)"
	[[ "$before" -eq "$after" ]]
	rm -rf "$tmp"
}

@test "prune-uninstalled dry-run finds orphan configs" {
	local tmp steam_root
	tmp="$(mktemp -d)"
	steam_root="$tmp/steam"
	mkdir -p "$tmp/launch.d" "$tmp/games" "$steam_root/steamapps"
	cat > "$tmp/games/99999999.env" <<'EOF'
# Test Orphan Game (Steam AppID 99999999)
INCLUDE=presets/standard.env
EOF
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" STEAM_ROOT="$steam_root" "$SCRIPT" --prune-uninstalled --dry-run
	[[ $status -eq 0 ]]
	[[ "$output" == *"Prune uninstalled (dry-run)"* ]]
	[[ "$output" == *"99999999"* ]]
	[[ "$output" == *"Test Orphan Game"* ]]
	[[ -f "$tmp/games/99999999.env" ]]
	rm -rf "$tmp"
}

@test "prune-uninstalled yes removes orphan configs" {
	local tmp steam_root
	tmp="$(mktemp -d)"
	steam_root="$tmp/steam"
	mkdir -p "$tmp/launch.d" "$tmp/games" "$steam_root/steamapps"
	echo 'INCLUDE=presets/standard.env' > "$tmp/games/99999999.env"
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" STEAM_ROOT="$steam_root" "$SCRIPT" --prune-uninstalled --yes
	[[ $status -eq 0 ]]
	[[ "$output" == *"removed=1"* ]]
	[[ ! -f "$tmp/games/99999999.env" ]]
	rm -rf "$tmp"
}

@test "prune-uninstalled json output" {
	local tmp steam_root
	tmp="$(mktemp -d)"
	steam_root="$tmp/steam"
	mkdir -p "$tmp/launch.d" "$tmp/games" "$steam_root/steamapps"
	echo 'INCLUDE=presets/standard.env' > "$tmp/games/99999999.env"
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" STEAM_ROOT="$steam_root" "$SCRIPT" --prune-uninstalled --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"appid":"99999999"'* || "$output" == *'"appid": "99999999"'* ]]
	[[ "$output" == *'"orphans"'* ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["orphans"][0]["appid"]=="99999999"' "$output"
	rm -rf "$tmp"
}

@test "prune-uninstalled refuses deletion when Steam discovery is unavailable" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/launch.d" "$tmp/games"
	echo 'INCLUDE=presets/standard.env' > "$tmp/games/99999999.env"
	run env HOME="$tmp/home" LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" STEAM_ROOT="$tmp/missing-steam" "$SCRIPT" --prune-uninstalled --yes
	[[ $status -ne 0 ]]
	[[ "$output" == *"refusing to classify configs as uninstalled"* ]]
	[[ -f "$tmp/games/99999999.env" ]]
	rm -rf "$tmp"
}

@test "init-appid force overwrites in temp config dir" {
	local tmp_cfg fake_steam
	tmp_cfg="$(mktemp -d)"
	fake_steam="$(fake_steam_root 2357570 "Overwatch")"
	mkdir -p "$tmp_cfg/games" "$tmp_cfg/launch.d/presets"
	cp "$REPO_ROOT/launch.d/presets/"*.env "$tmp_cfg/launch.d/presets/"
	printf '%s\n' '# old' 'INCLUDE=presets/standard.env' > "$tmp_cfg/games/2357570.env"
	run env LAUNCHLAYER_CONFIG_DIR="$tmp_cfg" LAUNCHLAYER_GAMES_DIR="$tmp_cfg/games" STEAM_ROOT="$fake_steam" "$SCRIPT" --init-appid 2357570 lightweight --force
	[[ $status -eq 0 ]]
	[[ "$output" == *"Overwrote"* ]]
	grep -q 'presets/lightweight.env' "$tmp_cfg/games/2357570.env"
	rm -rf "$tmp_cfg" "$fake_steam"
}
