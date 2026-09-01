# shellcheck shell=bash
# lib/inspect/backup/export.sh

[[ -n "${LAUNCHLAYER_BACKUP_EXPORT_LOADED:-}" ]] && return 0
LAUNCHLAYER_BACKUP_EXPORT_LOADED=1

# export_config — Pack managed launch.d files (and optional TUI prefs) into a tarball.
export_config() {
	local output=${1:-} include_local=${2:-0} include_profiles=${3:-1} include_tui=${4:-0} json=${5:-0}
	local output_prefix=${6:-launchlayer-export}
	local -a files=()
	local staging tmpdir rel abs output_abs output_tmp file_count tui_path
	local generated_output=0 lock_fd="" status=0
	local -a tar_members=(manifest.json)

	command_required_or_fail tar "Config export" || return 1

	if [[ "$output" != *.tar.gz ]]; then
		generated_output=1
		output="$(_config_bundle_resolve_archive_path "$output" "$output_prefix")" || return 1
	fi
	mkdir -p "$(dirname "$output")"
	output_abs="$(cd "$(dirname "$output")" 2>/dev/null && pwd)/$(basename "$output")" \
		|| output_abs="$output"

	collect_managed_config_files "$include_local" "$include_profiles" files
	tui_path="$(user_tui_config_path)"
	[[ "$include_tui" == "1" && -f "$tui_path" ]] && files+=("tui.conf")

	if ((${#files[@]} == 0)); then
		echo "No config files to export under $LAUNCHD_DIR" >&2
		return 1
	fi

	tmpdir="$(mktemp -d)"
	trap 'rm -rf "'"$tmpdir"'"' RETURN
	staging="$tmpdir/staging"
	mkdir -p "$staging/launch.d/profiles" "$staging/launch.d/presets" "$staging/games"

	file_count=0
	for rel in "${files[@]}"; do
		if [[ "$rel" == tui.conf ]]; then
			cp "$tui_path" "$staging/tui.conf"
			tar_members+=(tui.conf)
			((file_count++)) || true
			continue
		fi
		abs="$(config_file_abs_from_rel "$rel")"
		[[ -f "$abs" ]] || continue
		if [[ "$rel" == games/* ]]; then
			mkdir -p "$staging/games"
		else
			mkdir -p "$(dirname "$staging/$rel")"
		fi
		if [[ "$rel" == games/* ]]; then
			cp "$abs" "$staging/games/$(basename "$rel")"
			tar_members+=("games/$(basename "$rel")")
		else
			cp "$abs" "$staging/$rel"
			tar_members+=("$rel")
		fi
		((file_count++)) || true
	done

	_write_config_bundle_manifest "$staging" "$include_local" "$include_profiles" "$include_tui"

	if (( generated_output )) && command -v flock >/dev/null 2>&1; then
		exec {lock_fd}>"$(dirname "$output_abs")/.launchlayer-archive.lock" || return 1
		flock "$lock_fd" || { exec {lock_fd}>&-; return 1; }
	fi
	if (( generated_output )); then
		output_abs="$(_config_bundle_available_output "$output_abs")"
	fi
	output_tmp="$(mktemp "$(dirname "$output_abs")/.launchlayer-export.XXXXXX")" || status=$?
	if (( status != 0 )); then
		if [[ -n "$lock_fd" ]]; then
			flock -u "$lock_fd" || true
			exec {lock_fd}>&-
		fi
		return "$status"
	fi
	(
		umask 077
		cd "$staging" || exit 1
		tar -czf "$output_tmp" "${tar_members[@]}"
	) || {
		rm -f "$output_tmp"
		if [[ -n "$lock_fd" ]]; then
			flock -u "$lock_fd" || true
			exec {lock_fd}>&-
		fi
		return 1
	}
	chmod 600 "$output_tmp" || status=$?
	if (( status == 0 )); then
		mv -f "$output_tmp" "$output_abs" || status=$?
	fi
	if (( status != 0 )); then
		rm -f "$output_tmp"
	fi
	if [[ -n "$lock_fd" ]]; then
		flock -u "$lock_fd" || true
		exec {lock_fd}>&-
	fi
	(( status == 0 )) || return "$status"

	if [[ "$json" == "1" ]]; then
		printf '{"output":%s,"file_count":%s,"includes":{"local":%s,"profiles":%s,"tui":%s}}\n' \
			"$(json_string "$output_abs")" \
			"$file_count" \
			"$(json_bool "$([[ "$include_local" == "1" ]] && echo 1 || echo 0)")" \
			"$(json_bool "$([[ "$include_profiles" == "1" ]] && echo 1 || echo 0)")" \
			"$(json_bool "$([[ "$include_tui" == "1" ]] && echo 1 || echo 0)")"
		return 0
	fi

	echo "=== Export config ==="
	echo "Wrote $output_abs ($file_count file(s))"
	echo "Includes: local=$([[ "$include_local" == "1" ]] && echo yes || echo no) profiles=$([[ "$include_profiles" == "1" ]] && echo yes || echo no) tui=$([[ "$include_tui" == "1" ]] && echo yes || echo no)"
}

# backup_config — Timestamped export alias (defaults to backup_dir from backup.conf).
backup_config() {
	local output=${1:-} include_local=${2:-1} include_profiles=${3:-1} include_tui=${4:-0} json=${5:-0}
	export_config "$output" "$include_local" "$include_profiles" "$include_tui" "$json" launchlayer-backup
}
# prune_backup_archives — Remove oldest launchlayer-backup-*.tar.gz files beyond --keep.
# keep=0 means unlimited retention (no files removed).
prune_backup_archives() {
	local dir=${1:-$(default_backup_dir)} keep=${2:-$(default_backup_keep)}
	local dry_run=${3:-0} json=${4:-0}
	local -a archives=() sorted=() to_remove=()
	local removed=0 scanned=0 file first=1

	[[ "$keep" =~ ^[0-9]+$ ]] || keep=7
	if [[ "$keep" == "0" ]]; then
		if [[ "$json" == "1" ]]; then
			printf '{"dir":%s,"keep":0,"dry_run":%s,"scanned":%s,"removed":0,"files":[],"policy":%s}\n' \
				"$(json_string "$dir")" \
				"$(json_bool "$([[ "$dry_run" == "1" ]] && echo 1 || echo 0)")" \
				"$(json_number_or_string "$( [[ -d "$dir" ]] && find "$dir" -maxdepth 1 -name 'launchlayer-backup-*.tar.gz' 2>/dev/null | wc -l || echo 0 )")" \
				"$(json_string "unlimited retention")"
			return 0
		fi
		echo "=== Prune backups $( [[ "$dry_run" == "1" ]] && echo '(dry-run)' ) ==="
		echo "dir=$dir keep=0 (unlimited retention — no files removed)"
		echo "Done: removed=0"
		return 0
	fi
	[[ -d "$dir" ]] || {
		if [[ "$json" == "1" ]]; then
			printf '{"dir":%s,"keep":%s,"scanned":0,"removed":0,"files":[]}\n' \
				"$(json_string "$dir")" "$keep"
			return 0
		fi
		echo "=== Prune backups (dry-run) ==="
		echo "Backup directory does not exist: $dir"
		echo "Done: removed=0 scanned=0"
		return 0
	}

	for file in "$dir"/launchlayer-backup-*.tar.gz; do
		[[ -f "$file" ]] || continue
		archives+=("$file")
	done
	scanned=${#archives[@]}
	if (( scanned > keep )); then
		mapfile -t sorted < <(ls -1t "${archives[@]}" 2>/dev/null)
		to_remove=("${sorted[@]:keep}")
	fi

	if [[ "$json" == "1" ]]; then
		printf '{"dir":%s,"keep":%s,"dry_run":%s,"scanned":%s,"removed":%s,"files":[' \
			"$(json_string "$dir")" "$keep" \
			"$(json_bool "$([[ "$dry_run" == "1" ]] && echo 1 || echo 0)")" \
			"$scanned" "${#to_remove[@]}"
		for file in "${to_remove[@]}"; do
			(( first )) || printf ','
			first=0
			printf '%s' "$(json_string "$file")"
			if [[ "$dry_run" != "1" ]]; then
				rm -f "$file"
				((removed++)) || true
			fi
		done
		printf ']}\n'
		return 0
	fi

	if [[ "$dry_run" == "1" ]]; then
		echo "=== Prune backups (dry-run) ==="
	else
		echo "=== Prune backups ==="
	fi
	echo "dir=$dir keep=$keep scanned=$scanned"
	if ((${#to_remove[@]} == 0)); then
		echo "No archives to prune"
	else
		for file in "${to_remove[@]}"; do
			if [[ "$dry_run" == "1" ]]; then
				echo "would remove: $file"
			else
				rm -f "$file"
				echo "Removed $file"
				((removed++)) || true
			fi
		done
	fi
	echo "Done: removed=$removed scanned=$scanned"
}

# run_scheduled_backup — Backup configs then optionally prune old archives (systemd oneshot).
# Reads live ~/.config/launchlayer/backup.conf (keep, auto_prune, includes).
run_scheduled_backup() {
	local dir=${1:-} keep=${2:-} json=${3:-0}
	local include_local include_profiles include_tui auto_prune

	load_backup_prefs
	[[ -z "$dir" ]] && dir="${BACKUP_PREFS_DIR}"
	[[ -z "$keep" ]] && keep="${BACKUP_PREFS_KEEP}"
	include_local="${BACKUP_PREFS_INCLUDE_LOCAL:-1}"
	include_profiles="${BACKUP_PREFS_INCLUDE_PROFILES:-1}"
	include_tui="${BACKUP_PREFS_INCLUDE_TUI:-0}"
	auto_prune="${BACKUP_PREFS_AUTO_PRUNE:-1}"

	mkdir -p "$dir"
	backup_config "$dir" "$include_local" "$include_profiles" "$include_tui" "$json" || return $?
	if [[ "$auto_prune" == "1" ]]; then
		prune_backup_archives "$dir" "$keep" 0 "$json"
	else
		if [[ "$json" == "1" ]]; then
			printf '{"prune_skipped":true,"reason":%s}\n' "$(json_string "auto_prune=0")"
		else
			echo "Skipping prune (auto_prune=0 in $(backup_prefs_path))"
		fi
	fi
}
