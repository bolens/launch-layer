#!/usr/bin/env bash
# Unit tests for lib/inspect/backup/common.sh helpers.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "config_bundle_sha256 hashes file contents" {
	local tmp file
	tmp="$(mktemp -d)"
	file="$tmp/sample.env"
	echo 'GAMEMODE=1' > "$file"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		config_bundle_sha256 "'"$file"'"
	'
	[[ $status -eq 0 ]]
	[[ "$output" =~ ^[0-9a-f]{64}$ ]]
	rm -rf "$tmp"
}

@test "config_file_abs_from_rel maps games and launch.d paths" {
	local tmp games
	tmp="$(temp_config_dir)"
	games="$tmp/games-custom"
	mkdir -p "$games"
	run env CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$games" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		printf "%s\n" "$(config_file_abs_from_rel launch.d/default.env)" "$(config_file_abs_from_rel games/12345.env)"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"$tmp/launch.d/default.env"* ]]
	[[ "$output" == *"$games/12345.env"* ]]
	rm -rf "$tmp"
}

@test "collect_managed_config_files lists default presets and games" {
	local tmp games
	tmp="$(temp_config_dir)"
	games="$tmp/games-custom"
	mkdir -p "$games"
	echo 'GAMEMODE=1' > "$games/42424242.env"
	run env CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$games" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		files=()
		collect_managed_config_files 0 0 files
		printf "%s\n" "${files[@]}"
	' 
	[[ $status -eq 0 ]]
	[[ "$output" == *"launch.d/default.env"* ]]
	[[ "$output" == *"presets/standard.env"* ]]
	[[ "$output" == *"games/42424242.env"* ]]
	rm -rf "$tmp"
}

@test "_find_config_bundle_root locates nested bundle directory" {
	local tmp root
	tmp="$(mktemp -d)"
	root="$tmp/nested-bundle"
	mkdir -p "$root/launch.d"
	echo '{}' > "$root/manifest.json"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		_find_config_bundle_root "'"$tmp"'"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "$root" ]]
	rm -rf "$tmp"
}

@test "list_backup_archives returns newest first" {
	local tmp outdir first second
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$outdir"
	touch -d '2020-01-01 00:00:00' "$outdir/launchlayer-backup-20200101-000000.tar.gz"
	touch -d '2024-06-01 00:00:00' "$outdir/launchlayer-backup-20240601-000000.tar.gz"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		list_backup_archives "'"$outdir"'"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"20240601"* ]]
	[[ "$output" == *"20200101"* ]]
	mapfile -t out <<< "$output"
	[[ "${out[0]}" == *"20240601"* ]]
	[[ "${out[1]}" == *"20200101"* ]]
	rm -rf "$tmp"
}

@test "latest_backup_archive picks newest archive" {
	local tmp outdir
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$outdir"
	touch -d '2020-01-01 00:00:00' "$outdir/launchlayer-backup-20200101-000000.tar.gz"
	touch -d '2024-06-01 00:00:00' "$outdir/launchlayer-export-20240601-000000.tar.gz"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		latest_backup_archive "'"$outdir"'"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"20240601"* ]]
	rm -rf "$tmp"
}

@test "list_backup_archives fails when directory is empty" {
	local tmp outdir
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$outdir"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		list_backup_archives "'"$outdir"'"
	'
	[[ $status -eq 1 ]]
	rm -rf "$tmp"
}

@test "resolve_restore_archive returns explicit archive file" {
	local tmp archive
	tmp="$(mktemp -d)"
	archive="$tmp/launchlayer-backup-20240601-000000.tar.gz"
	touch "$archive"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		resolve_restore_archive "'"$archive"'" "'"$tmp"'"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "$archive" ]]
	rm -rf "$tmp"
}

@test "resolve_restore_archive treats directory argument as backup dir" {
	local tmp outdir old new
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$outdir"
	old="$outdir/launchlayer-backup-20200101-000000.tar.gz"
	new="$outdir/launchlayer-backup-20240601-000000.tar.gz"
	touch -d '2020-01-01 00:00:00' "$old"
	touch -d '2024-06-01 00:00:00' "$new"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		resolve_restore_archive "'"$outdir"'" ""
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "$new" ]]
	rm -rf "$tmp"
}

@test "resolve_restore_archive fails when no archives exist" {
	local tmp outdir
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$outdir"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		resolve_restore_archive "" "'"$outdir"'" 2>&1
	'
	[[ $status -eq 1 ]]
	[[ "$output" == *"No launchlayer backup archives"* ]]
	rm -rf "$tmp"
}

@test "list_backups reports empty directory in json" {
	local tmp outdir
	tmp="$(mktemp -d)"
	outdir="$tmp/backups"
	mkdir -p "$outdir"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		list_backups "'"$outdir"'" 1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *'"count":0'* ]]
	[[ "$output" == *'"archives":[]'* ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["count"]==0 and d["archives"]==[]' "$output"
	rm -rf "$tmp"
}

@test "_filter_import_files_by_appid keeps only matching game config" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		files=(games/11111111.env launch.d/default.env games/42424242.env)
		_filter_import_files_by_appid 42424242 files
		printf "%s\n" "${files[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "games/42424242.env" ]]
}

@test "_filter_import_files_by_appid fails when game missing from archive" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		files=(games/11111111.env launch.d/default.env)
		_filter_import_files_by_appid 42424242 files
	'
	[[ $status -eq 1 ]]
	[[ "$output" == *"Archive does not contain games/42424242.env"* ]]
}

@test "_tar_archive_members_are_safe rejects absolute and parent paths" {
	local tmp good bad_abs bad_trav
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/bundle/launch.d"
	echo 'GAMEMODE=1' > "$tmp/bundle/launch.d/default.env"
	good="$tmp/good.tar.gz"
	bad_abs="$tmp/abs.tar.gz"
	bad_trav="$tmp/trav.tar.gz"
	tar -C "$tmp" -czf "$good" bundle
	(
		cd "$tmp"
		printf 'x\n' > evil.txt
		# Absolute member name
		tar --absolute-names -czf "$bad_abs" /etc/hosts 2>/dev/null || \
			tar -czf "$bad_abs" --transform 's|^|/|' evil.txt
		# Parent-directory traversal in member name
		tar -czf "$bad_trav" --transform 's|^|../|' evil.txt
	)
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		_tar_archive_members_are_safe "'"$good"'" && echo good_ok || echo good_bad
		_tar_archive_members_are_safe "'"$bad_abs"'" && echo abs_ok || echo abs_bad
		_tar_archive_members_are_safe "'"$bad_trav"'" && echo trav_ok || echo trav_bad
	'
	rm -rf "$tmp"
	[[ $status -eq 0 ]]
	[[ "$output" == *"good_ok"* ]]
	[[ "$output" == *"abs_bad"* ]]
	[[ "$output" == *"trav_bad"* ]]
}

@test "_tar_archive_members_are_safe rejects links" {
	local tmp archive
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/bundle"
	ln -s /etc/hosts "$tmp/bundle/escape"
	archive="$tmp/link.tar.gz"
	tar -C "$tmp" -czf "$archive" bundle
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		_tar_archive_members_are_safe "'"$archive"'"
	'
	[[ $status -eq 1 ]]
	rm -rf "$tmp"
}

@test "_tar_archive_members_are_safe enforces expanded size limit" {
	local tmp archive
	tmp="$(mktemp -d)"
	printf '1234567890' > "$tmp/file"
	archive="$tmp/large.tar.gz"
	tar -C "$tmp" -czf "$archive" file
	run env LAUNCHLAYER_IMPORT_MAX_BYTES=5 bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		_tar_archive_members_are_safe "'"$archive"'"
	'
	[[ $status -eq 1 ]]
	rm -rf "$tmp"
}

@test "import_config rejects archives with unsafe member paths" {
	local tmp archive
	tmp="$(mktemp -d)"
	(
		cd "$tmp"
		printf 'x\n' > evil.txt
		tar -czf unsafe.tar.gz --transform 's|^|../|' evil.txt
	)
	archive="$tmp/unsafe.tar.gz"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli keys config inspect
		import_config "'"$archive"'" 1 merge 0 1 1 0 0 "" 2>&1
	'
	rm -rf "$tmp"
	[[ $status -ne 0 ]]
	[[ "$output" == *"unsafe member paths"* ]]
}

@test "resolve_restore_filter_appid accepts numeric AppID" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		resolve_restore_filter_appid 42424242
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "42424242" ]]
}

@test "_config_bundle_default_output places archive under non-existent path-like dir" {
	local tmp dir
	tmp="$(mktemp -d)"
	dir="$tmp/custom-backups"
	[[ ! -d "$dir" ]]
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		_config_bundle_default_output "'"$dir"'" launchlayer-export
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "$dir"/launchlayer-export-* ]]
	[[ "$output" != /launchlayer-export-* ]]
	[[ "$output" != launchlayer-export-* ]]
	rm -rf "$tmp"
}

@test "_config_bundle_default_output uses bare prefix when dir is not path-like" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect
		_config_bundle_default_output myprefix launchlayer-export
	'
	[[ $status -eq 0 ]]
	[[ "$output" =~ ^launchlayer-export-[0-9]{8}-[0-9]{6}\.tar\.gz$ ]]
}

@test "default_backup_dir reads backup_dir from backup.conf" {
	local home xdg backup_dir
	home="$(mktemp -d)"
	xdg="$(mktemp -d)"
	backup_dir="$home/my-backups"
	mkdir -p "$xdg/launchlayer"
	printf '%s\n' "backup_dir=$backup_dir" "keep=7" > "$xdg/launchlayer/backup.conf"
	run env HOME="$home" XDG_CONFIG_HOME="$xdg" bash -c '
		unset LAUNCHLAYER_BACKUP_DIR LAUNCHLAYER_BACKUP_KEEP
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect prefs
		default_backup_dir
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "$backup_dir" ]]
	rm -rf "$home" "$xdg"
}

@test "default_backup_keep reads keep from backup.conf" {
	local home xdg
	home="$(mktemp -d)"
	xdg="$(mktemp -d)"
	mkdir -p "$xdg/launchlayer"
	printf '%s\n' "backup_dir=$home/backups" "keep=12" > "$xdg/launchlayer/backup.conf"
	run env HOME="$home" XDG_CONFIG_HOME="$xdg" bash -c '
		unset LAUNCHLAYER_BACKUP_DIR LAUNCHLAYER_BACKUP_KEEP
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect prefs
		default_backup_keep
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "12" ]]
	rm -rf "$home" "$xdg"
}

@test "list_backups uses backup.conf dir when argument omitted" {
	local home xdg backup_dir archive
	home="$(mktemp -d)"
	xdg="$(mktemp -d)"
	backup_dir="$home/conf-backups"
	mkdir -p "$backup_dir" "$xdg/launchlayer"
	archive="$backup_dir/launchlayer-backup-20240601-000000.tar.gz"
	touch -d '2024-06-01 00:00:00' "$archive"
	printf '%s\n' "backup_dir=$backup_dir" "keep=7" > "$xdg/launchlayer/backup.conf"
	run env HOME="$home" XDG_CONFIG_HOME="$xdg" bash -c '
		unset LAUNCHLAYER_BACKUP_DIR LAUNCHLAYER_BACKUP_KEEP
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect prefs
		list_backups "" 1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"$backup_dir"* ]]
	[[ "$output" == *'"count":1'* ]]
	rm -rf "$home" "$xdg"
}

@test "export_config writes to backup.conf dir before it exists" {
	local tmp home xdg backup_dir
	tmp="$(temp_config_dir)"
	home="$(mktemp -d)"
	xdg="$(mktemp -d)"
	backup_dir="$home/fresh-backups"
	mkdir -p "$xdg/launchlayer"
	printf '%s\n' "backup_dir=$backup_dir" "keep=7" > "$xdg/launchlayer/backup.conf"
	[[ ! -d "$backup_dir" ]]
	run env CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" HOME="$home" XDG_CONFIG_HOME="$xdg" bash -c '
		unset LAUNCHLAYER_BACKUP_DIR LAUNCHLAYER_BACKUP_KEEP
		cd "'"$tmp"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform config inspect tools prefs cli
		export_config "" 0 1 0 1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"$backup_dir"* ]]
	[[ "$output" != *'"/launchlayer-export'* ]]
	ls "$backup_dir"/launchlayer-export-*.tar.gz >/dev/null
	[[ ! -f "$tmp/launchlayer-export-"*.tar.gz ]]
	rm -rf "$tmp" "$home" "$xdg"
}

@test "export_config default output does not land in CONFIG_DIR when cwd is config root" {
	local tmp home xdg backup_dir
	tmp="$(temp_config_dir)"
	home="$(mktemp -d)"
	xdg="$(mktemp -d)"
	backup_dir="$home/away-from-config"
	mkdir -p "$xdg/launchlayer"
	printf '%s\n' "backup_dir=$backup_dir" "keep=7" > "$xdg/launchlayer/backup.conf"
	run env CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" HOME="$home" XDG_CONFIG_HOME="$xdg" bash -c '
		unset LAUNCHLAYER_BACKUP_DIR LAUNCHLAYER_BACKUP_KEEP
		cd "'"$tmp"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform config inspect tools prefs cli
		export_config "" 0 1 0 1
	'
	[[ $status -eq 0 ]]
	[[ -d "$backup_dir" ]]
	[[ $(find "$tmp" -maxdepth 1 -name "launchlayer-export-*.tar.gz" | wc -l) -eq 0 ]]
	[[ $(find "$backup_dir" -maxdepth 1 -name "launchlayer-export-*.tar.gz" | wc -l) -eq 1 ]]
	rm -rf "$tmp" "$home" "$xdg"
}

@test "_config_bundle_resolve_archive_path treats non-existent path-like dir as directory" {
	local tmp dir
	tmp="$(mktemp -d)"
	dir="$tmp/fresh-backups"
	[[ ! -d "$dir" ]]
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect prefs
		_config_bundle_resolve_archive_path "'"$dir"'" launchlayer-backup
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "$dir"/launchlayer-backup-* ]]
	[[ "$output" == *.tar.gz ]]
	rm -rf "$tmp"
}

@test "_config_bundle_resolve_archive_path preserves explicit tarball file path" {
	local archive=/tmp/custom-backup-20240101.tar.gz
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect prefs
		_config_bundle_resolve_archive_path "'"$archive"'" launchlayer-backup
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "$archive" ]]
}

@test "backup_config writes timestamped archive under non-existent output dir" {
	local tmp home xdg backup_dir
	tmp="$(temp_config_dir)"
	home="$(mktemp -d)"
	xdg="$(mktemp -d)"
	backup_dir="$home/fresh-backups"
	mkdir -p "$xdg/launchlayer"
	printf '%s\n' "backup_dir=$backup_dir" "keep=7" > "$xdg/launchlayer/backup.conf"
	[[ ! -d "$backup_dir" ]]
	run env CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" HOME="$home" XDG_CONFIG_HOME="$xdg" bash -c '
		unset LAUNCHLAYER_BACKUP_DIR LAUNCHLAYER_BACKUP_KEEP
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform config inspect tools prefs cli
		backup_config "'"$backup_dir"'" 0 1 0 1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"$backup_dir"* ]]
	[[ "$output" == *launchlayer-backup-* ]]
	[[ "$output" == *.tar.gz* ]]
	ls "$backup_dir"/launchlayer-backup-*.tar.gz >/dev/null
	[[ -d "$backup_dir" ]]
	rm -rf "$tmp" "$home" "$xdg"
}

@test "backup_config defaults to backup.conf dir when output omitted" {
	local tmp home xdg backup_dir
	tmp="$(temp_config_dir)"
	home="$(mktemp -d)"
	xdg="$(mktemp -d)"
	backup_dir="$home/conf-backups"
	mkdir -p "$xdg/launchlayer"
	printf '%s\n' "backup_dir=$backup_dir" "keep=7" > "$xdg/launchlayer/backup.conf"
	run env CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" HOME="$home" XDG_CONFIG_HOME="$xdg" bash -c '
		unset LAUNCHLAYER_BACKUP_DIR LAUNCHLAYER_BACKUP_KEEP
		cd "'"$home"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform config inspect tools prefs cli
		backup_config "" 0 1 0 1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"$backup_dir"* ]]
	[[ "$output" == *launchlayer-backup-* ]]
	ls "$backup_dir"/launchlayer-backup-*.tar.gz >/dev/null
	[[ $(find "$home" -maxdepth 1 -name 'launchlayer-backup-*.tar.gz' | wc -l) -eq 0 ]]
	rm -rf "$tmp" "$home" "$xdg"
}

@test "export_config --output resolves non-existent path-like dir to timestamped archive" {
	local tmp dir
	tmp="$(temp_config_dir)"
	dir="$tmp/new-export-dir"
	[[ ! -d "$dir" ]]
	run env CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform config inspect tools prefs cli
		export_config "'"$dir"'" 0 1 0 1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"$dir"* ]]
	[[ "$output" == *launchlayer-export-* ]]
	[[ "$output" == *.tar.gz* ]]
	ls "$dir"/launchlayer-export-*.tar.gz >/dev/null
	rm -rf "$tmp"
}

@test "resolve_restore_archive uses backup.conf dir when both args empty" {
	local home xdg backup_dir archive
	home="$(mktemp -d)"
	xdg="$(mktemp -d)"
	backup_dir="$home/conf-backups"
	mkdir -p "$backup_dir" "$xdg/launchlayer"
	archive="$backup_dir/launchlayer-backup-20240601-000000.tar.gz"
	touch -d '2024-06-01 00:00:00' "$archive"
	printf '%s\n' "backup_dir=$backup_dir" "keep=7" > "$xdg/launchlayer/backup.conf"
	run env HOME="$home" XDG_CONFIG_HOME="$xdg" bash -c '
		unset LAUNCHLAYER_BACKUP_DIR LAUNCHLAYER_BACKUP_KEEP
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect prefs
		resolve_restore_archive "" ""
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "$archive" ]]
	rm -rf "$home" "$xdg"
}

@test "default_backup_dir expands tilde paths from backup.conf" {
	local home xdg expected
	home="$(mktemp -d)"
	xdg="$(mktemp -d)"
	expected="$home/custom-backups"
	mkdir -p "$xdg/launchlayer"
	printf '%s\n' "backup_dir=~/custom-backups" "keep=7" > "$xdg/launchlayer/backup.conf"
	run env HOME="$home" XDG_CONFIG_HOME="$xdg" bash -c '
		unset LAUNCHLAYER_BACKUP_DIR LAUNCHLAYER_BACKUP_KEEP
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect prefs
		default_backup_dir
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "$expected" ]]
	rm -rf "$home" "$xdg"
}

@test "default_backup_dir prefers LAUNCHLAYER_BACKUP_DIR over backup.conf" {
	local home xdg env_dir conf_dir
	home="$(mktemp -d)"
	xdg="$(mktemp -d)"
	env_dir="$home/env-backups"
	conf_dir="$home/conf-backups"
	mkdir -p "$xdg/launchlayer"
	printf '%s\n' "backup_dir=$conf_dir" "keep=7" > "$xdg/launchlayer/backup.conf"
	run env HOME="$home" XDG_CONFIG_HOME="$xdg" LAUNCHLAYER_BACKUP_DIR="$env_dir" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli inspect prefs
		default_backup_dir
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "$env_dir" ]]
	[[ "$output" != "$conf_dir" ]]
	rm -rf "$home" "$xdg"
}
