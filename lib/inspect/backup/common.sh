# shellcheck shell=bash
# lib/inspect/backup/common.sh

[[ -n "${LAUNCHLAYER_BACKUP_COMMON_LOADED:-}" ]] && return 0
LAUNCHLAYER_BACKUP_COMMON_LOADED=1

# shellcheck shell=bash
# user_tui_config_path — XDG path for TUI preferences (mirrors lib/prefs.sh).
user_tui_config_path() {
	tui_config_path
}

# config_bundle_sha256 — SHA-256 digest for bundle manifest checksums.
config_bundle_sha256() {
	local file=$1
	sha256sum "$file" 2>/dev/null | awk '{print $1}'
}

# _config_bundle_default_output — Timestamped archive path in dir (file or directory).
_config_bundle_default_output() {
	local dir=${1:-.} prefix=${2:-launchlayer-export} ts
	ts="$(date -u +%Y%m%d-%H%M%S)"
	# Path-like targets (e.g. backup_dir from backup.conf) may not exist yet on first export.
	if [[ -d "$dir" || "$dir" == */* ]]; then
		printf '%s/%s-%s.tar.gz' "$dir" "$prefix" "$ts"
	else
		printf '%s-%s.tar.gz' "$prefix" "$ts"
	fi
}

# _config_bundle_resolve_archive_path — Resolve OUTPUT (empty, dir, or file) to a tarball path.
_config_bundle_resolve_archive_path() {
	local output=${1:-} prefix=${2:-launchlayer-export}
	if [[ -n "$output" && -f "$output" ]]; then
		echo "Output path is an existing file: $output" >&2
		return 1
	fi
	[[ -z "$output" ]] && output="$(default_backup_dir)"
	if [[ -d "$output" || ( "$output" == */* && "$output" != *.tar.gz ) ]]; then
		_config_bundle_default_output "$output" "$prefix"
		return 0
	fi
	printf '%s\n' "$output"
}

# _config_bundle_available_output — Add a numeric suffix when an archive path exists.
_config_bundle_available_output() {
	local output=$1 stem candidate n=2
	[[ -e "$output" ]] || { printf '%s\n' "$output"; return 0; }
	stem=${output%.tar.gz}
	candidate="${stem}-${n}.tar.gz"
	while [[ -e "$candidate" ]]; do
		((n++))
		candidate="${stem}-${n}.tar.gz"
	done
	printf '%s\n' "$candidate"
}

# _write_config_bundle_manifest — Write manifest.json into a staging directory.
_write_config_bundle_manifest() {
	local staging=$1 include_local=$2 include_profiles=$3 include_tui=$4
	local -a manifest_files=()
	local rel abs checksum first=1

	collect_managed_config_files "$include_local" "$include_profiles" manifest_files
	if [[ "$include_tui" == "1" && -f "$(user_tui_config_path)" ]]; then
		manifest_files+=("tui.conf")
	fi

	{
		printf '{'
		json_object_pair "format" "$(json_string "launchlayer-config")"
		json_object_pair "version" "$(json_string "$LAUNCHLAYER_VERSION")" 1
		json_object_pair "exported_at" "$(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" 1
		json_object_pair "config_dir" "$(json_string "$CONFIG_DIR")" 1
		printf ',"includes":{"local":%s,"profiles":%s,"tui":%s}' \
			"$(json_bool "$([[ "$include_local" == "1" ]] && echo 1 || echo 0)")" \
			"$(json_bool "$([[ "$include_profiles" == "1" ]] && echo 1 || echo 0)")" \
			"$(json_bool "$([[ "$include_tui" == "1" ]] && echo 1 || echo 0)")"
		printf ',"files":['
		for rel in "${manifest_files[@]}"; do
			if [[ "$rel" == tui.conf ]]; then
				abs="$(user_tui_config_path)"
			else
				abs="$(config_file_abs_from_rel "$rel")"
			fi
			[[ -f "$abs" ]] || continue
			checksum="$(config_bundle_sha256 "$abs")"
			(( first )) || printf ','
			first=0
			printf '{"path":%s,"sha256":%s}' \
				"$(json_string "$rel")" \
				"$(json_string "$checksum")"
		done
		printf ']}\n'
	} > "$staging/manifest.json"
}
# default_backup_dir — Directory for scheduled backups and pruning.
default_backup_dir() {
	if [[ -z "${LAUNCHLAYER_BACKUP_DIR:-}" ]]; then
		load_backup_prefs 2>/dev/null || true
		LAUNCHLAYER_BACKUP_DIR="${BACKUP_PREFS_DIR:-$HOME/launchlayer-backups}"
	fi
	printf '%s\n' "$LAUNCHLAYER_BACKUP_DIR"
}

# default_backup_keep — Archive retention count from preferences.
default_backup_keep() {
	if [[ -z "${LAUNCHLAYER_BACKUP_KEEP:-}" ]]; then
		load_backup_prefs 2>/dev/null || true
		LAUNCHLAYER_BACKUP_KEEP="${BACKUP_PREFS_KEEP:-7}"
	fi
	printf '%s\n' "$LAUNCHLAYER_BACKUP_KEEP"
}

# list_backup_archives — Newest-first launchlayer backup/export archives in dir.
list_backup_archives() {
	local dir=${1:-$(default_backup_dir)}
	local -a archives=() file

	[[ -d "$dir" ]] || return 1
	for file in "$dir"/launchlayer-backup-*.tar.gz "$dir"/launchlayer-export-*.tar.gz; do
		[[ -f "$file" ]] || continue
		archives+=("$file")
	done
	((${#archives[@]} == 0)) && return 1
	ls -1t "${archives[@]}"
}

# latest_backup_archive — Newest launchlayer backup/export archive in dir.
latest_backup_archive() {
	list_backup_archives "${1:-$(default_backup_dir)}" | head -1
}

# resolve_restore_filter_appid — Normalize APPID|NAME filter for per-game restore.
resolve_restore_filter_appid() {
	local query=$1
	[[ -n "$query" ]] || return 1
	if [[ "$query" =~ ^[0-9]+$ ]]; then
		printf '%s\n' "$query"
		return 0
	fi
	if declare -F resolve_appid_arg >/dev/null 2>&1; then
		resolve_appid_arg "$query"
		return $?
	fi
	echo "Invalid AppID filter: $query (use numeric AppID or install Steam metadata)" >&2
	return 1
}
# _find_config_bundle_root — Locate manifest.json or launch.d/ inside an extracted archive.
_find_config_bundle_root() {
	local extract_dir=$1 sub

	if [[ -f "$extract_dir/manifest.json" || -d "$extract_dir/launch.d" || -d "$extract_dir/games" ]]; then
		printf '%s\n' "$extract_dir"
		return 0
	fi
	for sub in "$extract_dir"/*; do
		[[ -d "$sub" ]] || continue
		if [[ -f "$sub/manifest.json" || -d "$sub/launch.d" || -d "$sub/games" ]]; then
			printf '%s\n' "$sub"
			return 0
		fi
	done
	return 1
}

# _config_import_destination — Map bundle-relative path to absolute destination.
_config_import_destination() {
	local rel=$1
	if [[ "$rel" == tui.conf ]]; then
		user_tui_config_path
	elif [[ "$rel" == games/* ]]; then
		printf '%s/%s\n' "$GAMES_DIR" "$(basename "$rel")"
	elif [[ "$rel" == launch.d/* ]]; then
		printf '%s/%s\n' "$CONFIG_DIR" "$rel"
	else
		printf '%s/%s\n' "$CONFIG_DIR" "$rel"
	fi
}

# _collect_bundle_import_files — List bundle-relative paths available for import.
_collect_bundle_import_files() {
	local bundle_root=$1 include_local=$2 include_profiles=$3 include_tui=$4
	local -n _out=$5
	local file base

	_out=()
	for file in "$bundle_root"/games/*.env "$bundle_root"/launch.d/*.env "$bundle_root"/launch.d/*.txt; do
		[[ -f "$file" ]] || continue
		base="$(basename "$file")"
		if [[ "$base" =~ ^[0-9]+\.env$ ]]; then
			_out+=("games/$base")
			continue
		fi
		[[ "$base" == local.env && "$include_local" != "1" ]] && continue
		_out+=("launch.d/$base")
	done
	if [[ "$include_profiles" == "1" && -d "$bundle_root/launch.d/profiles" ]]; then
		for file in "$bundle_root"/launch.d/profiles/*.env; do
			[[ -f "$file" ]] || continue
			_out+=("launch.d/profiles/$(basename "$file")")
		done
	fi
	if [[ -d "$bundle_root/launch.d/presets" ]]; then
		for file in "$bundle_root"/launch.d/presets/*.env; do
			[[ -f "$file" ]] || continue
			_out+=("launch.d/presets/$(basename "$file")")
		done
	fi
	if [[ "$include_tui" == "1" && -f "$bundle_root/tui.conf" ]]; then
		_out+=("tui.conf")
	fi
}
