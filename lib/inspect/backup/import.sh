# shellcheck shell=bash
# lib/inspect/backup/import.sh

[[ -n "${LAUNCHLAYER_BACKUP_IMPORT_LOADED:-}" ]] && return 0
LAUNCHLAYER_BACKUP_IMPORT_LOADED=1

# _tar_archive_members_are_safe — Reject unsafe paths/types and oversized archives.
_tar_archive_members_are_safe() {
	local archive=$1
	local member listing type size rest
	local count=0 total=0
	local max_members=${LAUNCHLAYER_IMPORT_MAX_MEMBERS:-4096}
	local max_bytes=${LAUNCHLAYER_IMPORT_MAX_BYTES:-67108864}

	while IFS= read -r member; do
		[[ -z "$member" ]] && continue
		count=$((count + 1))
		(( count <= max_members )) || return 1
		case "$member" in
			/*)
				return 1
				;;
		esac
		# Reject any parent-directory segment (leading, middle, or trailing).
		if [[ "$member" == *".."* ]]; then
			return 1
		fi
	done < <(tar -tzf "$archive" 2>/dev/null)
	(( count > 0 )) || return 1

	while IFS= read -r listing; do
		[[ -n "$listing" ]] || continue
		type="${listing:0:1}"
		[[ "$type" == "-" || "$type" == "d" ]] || return 1
		read -r _ _ size rest <<< "$listing"
		[[ "$size" =~ ^[0-9]+$ ]] || return 1
		total=$((total + size))
		(( total <= max_bytes )) || return 1
	done < <(LC_ALL=C tar -tvzf "$archive" 2>/dev/null)
	return 0
}

_validate_staged_import_files() {
	local bundle_root=$1 rel src issues=0
	shift
	for rel in "$@"; do
		[[ "$rel" == *.env ]] || continue
		src="$bundle_root/$rel"
		[[ -f "$src" && ! -L "$src" ]] || return 1
		validate_single_config_file "$src" >/dev/null || issues=$((issues + 1))
	done
	(( issues == 0 ))
}

_install_import_file_atomic() {
	local src=$1 dest=$2 tmp
	mkdir -p "$(dirname "$dest")"
	tmp="$(mktemp "$(dirname "$dest")/.launchlayer-import.XXXXXX")" || return 1
	if ! cp "$src" "$tmp" || ! chmod 600 "$tmp" || ! mv -f "$tmp" "$dest"; then
		rm -f "$tmp"
		return 1
	fi
}

# _filter_import_files_by_appid — Keep only games/<AppID>.env when restoring one game.
_filter_import_files_by_appid() {
	local filter_appid=$1
	local -n _files=$2
	local -a kept=() rel want="games/${filter_appid}.env"

	for rel in "${_files[@]}"; do
		[[ "$rel" == "$want" ]] && kept+=("$rel")
	done
	if ((${#kept[@]} == 0)); then
		echo "Archive does not contain $want" >&2
		return 1
	fi
	_files=("${kept[@]}")
}

# import_config — Restore configs from an export/backup tarball.
import_config() (
	local archive=$1 dry_run=${2:-1} mode=${3:-merge} yes=${4:-0} include_local=${5:-1}
	local include_profiles=${6:-1} include_tui=${7:-0} json=${8:-0} filter_appid=${9:-}
	local tmpdir bundle_root rel src dest action
	local -a files=() actions=()
	local -a rollback_dest=() rollback_copy=() rollback_existed=()
	local added=0 replaced=0 skipped=0 applied=0 first=1 entry

	[[ -n "$archive" && -f "$archive" ]] || {
		echo "Usage: $0 --import-config ARCHIVE [--dry-run] [--merge|--replace] [--yes] [--json]" >&2
		return 1
	}
	command_required_or_fail tar "Config import" || return 1
	[[ "$mode" == merge || "$mode" == replace ]] || {
		echo "Import mode must be merge or replace (got: $mode)" >&2
		return 1
	}

	tmpdir="$(mktemp -d)" || return 1
	trap 'rm -rf -- "$tmpdir"' EXIT
	if ! _tar_archive_members_are_safe "$archive"; then
		echo "Archive contains unsafe member paths: $archive" >&2
		return 1
	fi
	# Prefer GNU tar --restrict when available (blocks absolute paths / escape tricks).
	if tar --help 2>&1 | grep -q -- '--restrict'; then
		tar --restrict -xzf "$archive" -C "$tmpdir" || {
			echo "Failed to extract archive: $archive" >&2
			return 1
		}
	else
		tar -xzf "$archive" -C "$tmpdir" || {
			echo "Failed to extract archive: $archive" >&2
			return 1
		}
	fi

	bundle_root="$(_find_config_bundle_root "$tmpdir")" || {
		echo "Archive does not contain a launchlayer config bundle: $archive" >&2
		return 1
	}

	_collect_bundle_import_files "$bundle_root" "$include_local" "$include_profiles" "$include_tui" files
	if ((${#files[@]} == 0)); then
		echo "No importable files found in $archive" >&2
		return 1
	fi
	if [[ -n "$filter_appid" ]]; then
		_filter_import_files_by_appid "$filter_appid" files || return 1
	fi
	if ! _validate_staged_import_files "$bundle_root" "${files[@]}"; then
		echo "Archive contains invalid or unsafe config files: $archive" >&2
		return 1
	fi

	local apply=0
	if [[ "$dry_run" != "1" && "$yes" == "1" ]]; then
		apply=1
	fi

	for rel in "${files[@]}"; do
		if [[ "$rel" == tui.conf ]]; then
			src="$bundle_root/tui.conf"
		elif [[ "$rel" == games/* ]]; then
			if [[ -f "$bundle_root/$rel" ]]; then
				src="$bundle_root/$rel"
			else
				src="$bundle_root/launch.d/$(basename "$rel")"
			fi
		else
			src="$bundle_root/$rel"
		fi
		dest="$(_config_import_destination "$rel")"
		[[ -f "$src" && ! -L "$src" ]] || continue

		if [[ -f "$dest" ]]; then
			if [[ "$mode" == merge ]]; then
				action=skip
				((skipped++)) || true
			else
				action=replace
				((replaced++)) || true
			fi
		else
			action=add
			((added++)) || true
		fi

		actions+=("$rel|$action|$dest")
		if [[ "$apply" == "1" && "$action" != skip ]]; then
			local backup=""
			if [[ -f "$dest" ]]; then
				backup="$(mktemp "$tmpdir/rollback.XXXXXX")" || return 1
				cp "$dest" "$backup" || return 1
				rollback_existed+=(1)
			else
				rollback_existed+=(0)
			fi
			rollback_dest+=("$dest")
			rollback_copy+=("$backup")
			_install_import_file_atomic "$src" "$dest" || {
				echo "Failed to install imported config: $rel" >&2
				local i
				for ((i = ${#rollback_dest[@]} - 1; i >= 0; i--)); do
					if [[ "${rollback_existed[$i]}" == "1" ]]; then
						cp "${rollback_copy[$i]}" "${rollback_dest[$i]}" || true
					else
						rm -f "${rollback_dest[$i]}"
					fi
				done
				return 1
			}
			((applied++)) || true
		fi
	done

	if [[ "$json" == "1" ]]; then
		printf '{"archive":%s,"mode":%s,"dry_run":%s,"added":%s,"replaced":%s,"skipped":%s,"applied":%s,"actions":[' \
			"$(json_string "$archive")" \
			"$(json_string "$mode")" \
			"$(json_bool "$([[ "$apply" == "1" ]] && echo 0 || echo 1)")" \
			"$added" "$replaced" "$skipped" "$applied"
		for entry in "${actions[@]}"; do
			IFS='|' read -r rel action dest <<< "$entry"
			(( first )) || printf ','
			first=0
			printf '{"path":%s,"action":%s,"destination":%s}' \
				"$(json_string "$rel")" \
				"$(json_string "$action")" \
				"$(json_string "$dest")"
		done
		for entry in "${rollback_copy[@]}"; do
			[[ -n "$entry" ]] && rm -f "$entry"
		done
		printf ']}\n'
		return 0
	fi

	if [[ "$apply" == "1" ]]; then
		if [[ -n "$filter_appid" ]]; then
			echo "=== Restore config (games/${filter_appid}.env) ==="
		else
			echo "=== Import config ==="
		fi
	else
		if [[ -n "$filter_appid" ]]; then
			echo "=== Restore config (preview, games/${filter_appid}.env) ==="
		else
			echo "=== Import config (preview) ==="
		fi
	fi
	printf '%-8s %s\n' ACTION PATH
	for entry in "${actions[@]}"; do
		IFS='|' read -r rel action dest <<< "$entry"
		printf '%-8s %s\n' "$action" "$rel"
	done
	echo "Summary: add=$added replace=$replaced skip=$skipped"
	if [[ "$apply" == "1" ]]; then
		echo "Applied $applied file(s)"
		validate_config all 0
	elif (( added + replaced > 0 )); then
		echo "Re-run with --yes to apply (use --replace to overwrite existing files)."
	fi
)
