#!/usr/bin/env bash
# Integration tests for config export, import, and backup archives.
load '../helpers.bash'

setup() {
	bats_integration_setup
}

teardown() {
	bats_integration_teardown
}

@test "export-config and import-config round-trip" {
	local tmp archive dest
	tmp="$(mktemp -d)"
	dest="$(mktemp -d)"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games"
	cat > "$tmp/launch.d/default.env" <<'EOF'
GAMEMODE=1
EOF
	cat > "$tmp/launch.d/presets/standard.env" <<'EOF'
MANGOHUD=0
EOF
	cat > "$tmp/games/42424242.env" <<'EOF'
# Round Trip Game (Steam AppID 42424242)
INCLUDE=presets/standard.env
GAME_EXTRA_ARGS="-test"
EOF
	archive="$dest/roundtrip.tar.gz"
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --export-config --output "$archive" --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"file_count"'* ]]
	[[ -f "$archive" ]]
	[[ "$(stat -c %a "$archive")" == 600 ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["file_count"]>=3' "$output"

	rm -f "$tmp/games/42424242.env"
	[[ ! -f "$tmp/games/42424242.env" ]]

	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --import-config "$archive" --yes --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"applied"'* ]]
	[[ -f "$tmp/games/42424242.env" ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["applied"]>=1' "$output"

	rm -rf "$tmp" "$dest"
}

@test "import-config dry-run does not create games directory" {
	local tmp source archive games
	tmp="$(mktemp -d)"
	source="$tmp/source"
	games="$tmp/missing-games"
	mkdir -p "$source/launch.d/presets" "$source/games"
	echo 'GAMEMODE=1' > "$source/launch.d/default.env"
	echo 'MANGOHUD=0' > "$source/launch.d/presets/standard.env"
	echo 'INCLUDE=presets/standard.env' > "$source/games/42424242.env"
	archive="$tmp/export.tar.gz"
	run env LAUNCHLAYER_CONFIG_DIR="$source" LAUNCHLAYER_GAMES_DIR="$source/games" \
		"$SCRIPT" --export-config --output "$archive"
	[[ $status -eq 0 ]]
	run env LAUNCHLAYER_CONFIG_DIR="$source" LAUNCHLAYER_GAMES_DIR="$games" \
		"$SCRIPT" --import-config "$archive" --dry-run
	[[ $status -eq 0 ]]
	[[ ! -e "$games" ]]
	rm -rf "$tmp"
}

@test "export-config defaults output to backup.conf backup_dir" {
	local tmp backup_dir
	tmp="$(mktemp -d)"
	backup_dir="$tmp/export-target"
	mkdir -p "$tmp/launch.d/presets" "$tmp/launchlayer"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	cat > "$tmp/launchlayer/backup.conf" <<EOF
backup_dir=$backup_dir
keep=7
timer_type=calendar
on_calendar=*-*-* 03:15:00
on_boot_sec=15min
on_unit_active_sec=12h
randomized_delay_sec=1800
include_local=1
include_profiles=1
include_tui=0
auto_prune=1
EOF
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_CONFIG_HOME="$tmp" \
		HOME="$tmp" \
		"$SCRIPT" --export-config --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"file_count"'* ]]
	[[ "$output" == *"$backup_dir"* ]]
	[[ "$output" != *'"/launchlayer-export'* ]]
	ls "$backup_dir"/launchlayer-export-*.tar.gz >/dev/null
	[[ $(find "$tmp" -maxdepth 1 -name 'launchlayer-export-*.tar.gz' | wc -l) -eq 0 ]]
	rm -rf "$tmp"
}

@test "restore-backup --list uses backup.conf backup_dir when --dir omitted" {
	local tmp backup_dir
	tmp="$(mktemp -d)"
	backup_dir="$tmp/conf-backups"
	mkdir -p "$tmp/launch.d/presets" "$backup_dir" "$tmp/launchlayer"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	cat > "$tmp/launchlayer/backup.conf" <<EOF
backup_dir=$backup_dir
keep=7
timer_type=calendar
on_calendar=*-*-* 03:15:00
on_boot_sec=15min
on_unit_active_sec=12h
randomized_delay_sec=1800
include_local=1
include_profiles=1
include_tui=0
auto_prune=1
EOF
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		XDG_CONFIG_HOME="$tmp" \
		HOME="$tmp" \
		"$SCRIPT" --backup-config --output "$backup_dir"
	[[ $status -eq 0 ]]
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		XDG_CONFIG_HOME="$tmp" \
		HOME="$tmp" \
		"$SCRIPT" --restore-backup --list --json
	[[ $status -eq 0 ]]
	[[ "$output" == *"$backup_dir"* ]]
	[[ "$output" == *'"count":1'* ]]
	rm -rf "$tmp"
}

@test "restore-backup restores from backup.conf dir when --dir omitted" {
	local tmp backup_dir
	tmp="$(mktemp -d)"
	backup_dir="$tmp/conf-backups"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games" "$tmp/launchlayer"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	cat > "$tmp/games/42424242.env" <<'EOF'
# Restore Game (Steam AppID 42424242)
INCLUDE=presets/standard.env
GAME_EXTRA_ARGS="-from-conf-backup"
EOF
	cat > "$tmp/launchlayer/backup.conf" <<EOF
backup_dir=$backup_dir
keep=7
timer_type=calendar
on_calendar=*-*-* 03:15:00
on_boot_sec=15min
on_unit_active_sec=12h
randomized_delay_sec=1800
include_local=1
include_profiles=1
include_tui=0
auto_prune=1
EOF
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_CONFIG_HOME="$tmp" \
		HOME="$tmp" \
		"$SCRIPT" --backup-config --output "$backup_dir"
	[[ $status -eq 0 ]]

	echo 'INCLUDE=presets/standard.env' > "$tmp/games/42424242.env"
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_CONFIG_HOME="$tmp" \
		HOME="$tmp" \
		"$SCRIPT" --restore-backup --appid 42424242 --yes --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"applied":1'* ]]
	[[ "$output" == *"$backup_dir"* || "$output" == *"games/42424242.env"* ]]
	grep -q 'from-conf-backup' "$tmp/games/42424242.env"
	rm -rf "$tmp"
}

@test "import-config merge skips existing files" {
	local tmp archive
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'INCLUDE=presets/standard.env' > "$tmp/games/11111111.env"
	cat > "$tmp/launch.d/presets/standard.env" <<'EOF'
MANGOHUD=0
EOF
	archive="$tmp/export.tar.gz"
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --export-config --output "$archive"
	[[ $status -eq 0 ]]

	echo 'INCLUDE=presets/standard.env' > "$tmp/games/22222222.env"
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --import-config "$archive" --yes --merge --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"skipped"'* ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["skipped"]>=1' "$output"
	[[ -f "$tmp/games/22222222.env" ]]

	rm -rf "$tmp"
}

@test "backup-config writes timestamped archive" {
	local tmp outdir
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$tmp/launch.d/presets" "$outdir"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" "$SCRIPT" --backup-config --output "$outdir"
	[[ $status -eq 0 ]]
	[[ "$output" == *"launchlayer-backup"* ]]
	[[ $(find "$outdir" -maxdepth 1 -name 'launchlayer-backup-*.tar.gz' | wc -l) -eq 1 ]]
	rm -rf "$tmp"
}

@test "backup-config defaults output to backup.conf backup_dir" {
	local tmp backup_dir
	tmp="$(mktemp -d)"
	backup_dir="$tmp/conf-backups"
	mkdir -p "$tmp/launch.d/presets" "$tmp/launchlayer"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	cat > "$tmp/launchlayer/backup.conf" <<EOF
backup_dir=$backup_dir
keep=7
timer_type=calendar
on_calendar=*-*-* 03:15:00
on_boot_sec=15min
on_unit_active_sec=12h
randomized_delay_sec=1800
include_local=1
include_profiles=1
include_tui=0
auto_prune=1
EOF
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		XDG_CONFIG_HOME="$tmp" \
		HOME="$tmp" \
		"$SCRIPT" --backup-config --json
	[[ $status -eq 0 ]]
	[[ "$output" == *"$backup_dir"* ]]
	[[ "$output" == *launchlayer-backup-* ]]
	ls "$backup_dir"/launchlayer-backup-*.tar.gz >/dev/null
	[[ $(find "$tmp" -maxdepth 1 -name 'launchlayer-backup-*.tar.gz' | wc -l) -eq 0 ]]
	rm -rf "$tmp"
}

@test "backup-config --output creates timestamped archive under non-existent dir" {
	local tmp backup_dir
	tmp="$(mktemp -d)"
	backup_dir="$tmp/fresh-backups"
	mkdir -p "$tmp/launch.d/presets" "$tmp/launchlayer"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	[[ ! -d "$backup_dir" ]]
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		XDG_CONFIG_HOME="$tmp" \
		HOME="$tmp" \
		"$SCRIPT" --backup-config --output "$backup_dir" --json
	[[ $status -eq 0 ]]
	[[ "$output" == *"$backup_dir"* ]]
	[[ "$output" == *launchlayer-backup-* ]]
	[[ "$output" == *.tar.gz* ]]
	ls "$backup_dir"/launchlayer-backup-*.tar.gz >/dev/null
	[[ -d "$backup_dir" ]]
	rm -rf "$tmp"
}

@test "backup-config allows consecutive backups to same dir in same second" {
	local tmp outdir
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$tmp/launch.d/presets" "$outdir"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		XDG_CONFIG_HOME="$tmp" \
		HOME="$tmp" \
		"$SCRIPT" --backup-config --output "$outdir" --json
	[[ $status -eq 0 ]]
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		XDG_CONFIG_HOME="$tmp" \
		HOME="$tmp" \
		"$SCRIPT" --backup-config --output "$outdir" --json
	[[ $status -eq 0 ]]
	[[ "$output" == *launchlayer-backup-* ]]
	[[ $(find "$outdir" -maxdepth 1 -name 'launchlayer-backup-*.tar.gz' | wc -l) -ge 1 ]]
	rm -rf "$tmp"
}

@test "import-config dry-run does not apply" {
	local tmp archive
	tmp="$(temp_config_dir)"
	archive="$tmp/export.tar.gz"
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --export-config --output "$archive"
	[[ $status -eq 0 ]]
	echo 'INCLUDE=presets/standard.env' > "$tmp/games/99999998.env"
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --import-config "$archive" --dry-run --replace
	[[ $status -eq 0 ]]
	[[ "$output" == *"preview"* || "$output" == *"--yes"* ]]
	[[ -f "$tmp/games/99999998.env" ]]
	rm -rf "$tmp"
}

@test "restore-backup uses latest archive and replaces game config" {
	local tmp outdir archive
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games" "$outdir"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	cat > "$tmp/games/42424242.env" <<'EOF'
# Restore Game (Steam AppID 42424242)
INCLUDE=presets/standard.env
GAME_EXTRA_ARGS="-from-backup"
EOF
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --backup-config --output "$outdir"
	[[ $status -eq 0 ]]

	echo 'INCLUDE=presets/standard.env' > "$tmp/games/42424242.env"
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_CONFIG_HOME="$tmp/config" \
		HOME="$tmp" \
		"$SCRIPT" --restore-backup --dir "$outdir" --appid 42424242 --yes --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"applied":1'* ]]
	[[ "$output" == *"games/42424242.env"* ]]
	grep -q 'from-backup' "$tmp/games/42424242.env"

	rm -rf "$tmp"
}

@test "restore-backup --list reports archives" {
	local tmp outdir
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$tmp/launch.d/presets" "$outdir"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" "$SCRIPT" --backup-config --output "$outdir"
	[[ $status -eq 0 ]]
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		XDG_CONFIG_HOME="$tmp/config" \
		HOME="$tmp" \
		"$SCRIPT" --restore-backup --list --dir "$outdir" --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"count":1'* ]]
	[[ "$output" == *"launchlayer-backup"* ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["count"]==1' "$output"
	rm -rf "$tmp"
}

@test "restore-backup dry-run does not modify configs" {
	local tmp outdir
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games" "$outdir"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	cat > "$tmp/games/42424242.env" <<'EOF'
# Restore Game (Steam AppID 42424242)
INCLUDE=presets/standard.env
GAME_EXTRA_ARGS="-from-backup"
EOF
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --backup-config --output "$outdir"
	[[ $status -eq 0 ]]

	echo 'INCLUDE=presets/standard.env' > "$tmp/games/42424242.env"
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_CONFIG_HOME="$tmp/config" \
		HOME="$tmp" \
		"$SCRIPT" --restore-backup --dir "$outdir" --appid 42424242 --dry-run --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"dry_run":true'* ]]
	[[ "$output" == *'"applied":0'* ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["dry_run"] is True and d["applied"]==0' "$output"
	! grep -q 'from-backup' "$tmp/games/42424242.env"

	rm -rf "$tmp"
}

@test "restore-backup --merge skips existing game config" {
	local tmp outdir
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games" "$outdir"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	cat > "$tmp/games/42424242.env" <<'EOF'
# Restore Game (Steam AppID 42424242)
INCLUDE=presets/standard.env
GAME_EXTRA_ARGS="-from-backup"
EOF
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --backup-config --output "$outdir"
	[[ $status -eq 0 ]]

	echo 'INCLUDE=presets/standard.env' > "$tmp/games/42424242.env"
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_CONFIG_HOME="$tmp/config" \
		HOME="$tmp" \
		"$SCRIPT" --restore-backup --dir "$outdir" --appid 42424242 --yes --merge --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"skipped":1'* ]]
	[[ "$output" == *'"applied":0'* ]]
	[[ "$output" == *'"action":"skip"'* ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["skipped"]==1 and d["applied"]==0' "$output"
	! grep -q 'from-backup' "$tmp/games/42424242.env"

	rm -rf "$tmp"
}

@test "restore-backup picks newest archive when multiple exist" {
	local tmp outdir old new
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games" "$outdir"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	cat > "$tmp/games/42424242.env" <<'EOF'
# Restore Game (Steam AppID 42424242)
INCLUDE=presets/standard.env
GAME_EXTRA_ARGS="-old-backup"
EOF
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --backup-config --output "$outdir"
	[[ $status -eq 0 ]]
	old="$(find "$outdir" -maxdepth 1 -name 'launchlayer-backup-*.tar.gz' -print -quit)"
	[[ -n "$old" ]]

	cat > "$tmp/games/42424242.env" <<'EOF'
# Restore Game (Steam AppID 42424242)
INCLUDE=presets/standard.env
GAME_EXTRA_ARGS="-new-backup"
EOF
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --backup-config --output "$outdir"
	[[ $status -eq 0 ]]
	for new in "$outdir"/launchlayer-backup-*.tar.gz; do
		[[ "$new" == "$old" ]] && continue
		break
	done
	[[ -n "$new" && -f "$new" ]]
	touch -d '2020-01-01 00:00:00' "$old"
	touch -d '2024-06-01 00:00:00' "$new"

	echo 'INCLUDE=presets/standard.env' > "$tmp/games/42424242.env"
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_CONFIG_HOME="$tmp/config" \
		HOME="$tmp" \
		"$SCRIPT" --restore-backup --dir "$outdir" --appid 42424242 --yes --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"applied"'* ]]
	grep -q 'new-backup' "$tmp/games/42424242.env"
	! grep -q 'old-backup' "$tmp/games/42424242.env"

	rm -rf "$tmp"
}

@test "restore-backup uses explicit archive path over latest" {
	local tmp outdir archive
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games" "$outdir"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	cat > "$tmp/games/42424242.env" <<'EOF'
# Restore Game (Steam AppID 42424242)
INCLUDE=presets/standard.env
GAME_EXTRA_ARGS="-older"
EOF
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --backup-config --output "$outdir"
	[[ $status -eq 0 ]]
	older="$(find "$outdir" -maxdepth 1 -name 'launchlayer-backup-*.tar.gz' -print -quit)"
	mv "$older" "$outdir/launchlayer-backup-20200101-000000.tar.gz"
	older="$outdir/launchlayer-backup-20200101-000000.tar.gz"

	cat > "$tmp/games/42424242.env" <<'EOF'
# Restore Game (Steam AppID 42424242)
INCLUDE=presets/standard.env
GAME_EXTRA_ARGS="-newer"
EOF
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --backup-config --output "$outdir"
	[[ $status -eq 0 ]]
	newer="$(find "$outdir" -maxdepth 1 -name 'launchlayer-backup-*.tar.gz' ! -name 'launchlayer-backup-20200101-000000.tar.gz' -print -quit)"
	touch -d '2020-01-01 00:00:00' "$older"
	touch -d '2024-06-01 00:00:00' "$newer"

	echo 'INCLUDE=presets/standard.env' > "$tmp/games/42424242.env"
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_CONFIG_HOME="$tmp/config" \
		HOME="$tmp" \
		"$SCRIPT" --restore-backup "$older" --appid 42424242 --yes --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"applied":1'* ]]
	[[ "$output" == *"20200101"* ]]
	grep -q 'older' "$tmp/games/42424242.env"
	! grep -q 'newer' "$tmp/games/42424242.env"

	rm -rf "$tmp"
}

@test "restore-backup --appid fails when game missing from archive" {
	local tmp outdir
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games" "$outdir"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	cat > "$tmp/games/42424242.env" <<'EOF'
# Restore Game (Steam AppID 42424242)
INCLUDE=presets/standard.env
EOF
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --backup-config --output "$outdir"
	[[ $status -eq 0 ]]

	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_CONFIG_HOME="$tmp/config" \
		HOME="$tmp" \
		"$SCRIPT" --restore-backup --dir "$outdir" --appid 99999999 --yes
	[[ $status -eq 1 ]]
	[[ "$output" == *"Archive does not contain games/99999999.env"* ]]

	rm -rf "$tmp"
}

@test "restore-backup full restore replaces launch.d and games configs" {
	local tmp outdir
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games" "$outdir"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	echo 'DEBUG=0' > "$tmp/launch.d/local.env"
	cat > "$tmp/games/42424242.env" <<'EOF'
# Restore Game (Steam AppID 42424242)
INCLUDE=presets/standard.env
GAME_EXTRA_ARGS="-from-backup"
EOF
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --backup-config --output "$outdir"
	[[ $status -eq 0 ]]

	echo 'GAMEMODE=0' > "$tmp/launch.d/default.env"
	echo 'DEBUG=1' > "$tmp/launch.d/local.env"
	echo 'INCLUDE=presets/standard.env' > "$tmp/games/42424242.env"
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_CONFIG_HOME="$tmp/config" \
		HOME="$tmp" \
		"$SCRIPT" --restore-backup --dir "$outdir" --yes --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"applied":'* ]]
	[[ "$output" == *"launch.d/default.env"* ]]
	[[ "$output" == *"games/42424242.env"* ]]
	[[ "$output" == *"launch.d/local.env"* ]]
	grep -q 'GAMEMODE=1' "$tmp/launch.d/default.env"
	grep -q 'DEBUG=0' "$tmp/launch.d/local.env"
	grep -q 'from-backup' "$tmp/games/42424242.env"
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["applied"]>=3' "$output"

	rm -rf "$tmp"
}

@test "restore-backup --exclude-local skips local.env" {
	local tmp outdir
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games" "$outdir"
	echo 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	echo 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	echo 'LOCAL=from-backup' > "$tmp/launch.d/local.env"
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" "$SCRIPT" --backup-config --output "$outdir"
	[[ $status -eq 0 ]]

	echo 'LOCAL=current' > "$tmp/launch.d/local.env"
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_CONFIG_HOME="$tmp/config" \
		HOME="$tmp" \
		"$SCRIPT" --restore-backup --dir "$outdir" --yes --exclude-local --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"applied":2'* ]]
	[[ "$output" != *"launch.d/local.env"* ]]
	grep -q 'LOCAL=current' "$tmp/launch.d/local.env"
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert all(a["path"]!="launch.d/local.env" for a in d["actions"])' "$output"

	rm -rf "$tmp"
}
