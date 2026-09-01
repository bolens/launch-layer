# shellcheck shell=bash
# lib/inspect/maintenance.sh
# init_unconfigured — Scaffold games/<AppID>.env for games without one.
init_unconfigured() {
	local preset=${1:-} dry_run=${2:-0} eac_only=${3:-0}
	local chosen created=0 skipped=0

	if [[ "$dry_run" == "1" ]]; then
		echo "=== Init unconfigured (dry-run) ==="
		[[ -n "$preset" ]] && echo "Forced preset: $preset"
		[[ "$eac_only" == "1" ]] && echo "Scope: anticheat titles only"
		printf '%-10s %-12s %s\n' APPID PRESET NAME
	fi

	_init_unconfigured_one() {
		local appid=$1 name=$2 _manifest=$3
		cli_scan_progress_tick
		if appid_env_exists "$appid"; then
			((skipped++)) || true
			return 0
		fi
		if [[ "$eac_only" == "1" ]] && ! detect_anticheat_game "$appid"; then
			((skipped++)) || true
			return 0
		fi

		chosen="$preset"
		[[ -n "$chosen" ]] || chosen="$(suggest_preset_for_appid "$appid")"

		if [[ "$dry_run" == "1" ]]; then
			printf '%-10s %-12s %s\n' "$appid" "$chosen" "$name"
		else
			write_appid_env_scaffold "$appid" "$name" "$chosen"
			echo "Created $(appid_env_write_path "$appid") (preset: $chosen)"
		fi
		((created++)) || true
	}

	cli_scan_progress_begin "Scanning installed games"
	foreach_installed_game _init_unconfigured_one || true
	cli_scan_progress_end

	if [[ "$dry_run" == "1" ]]; then
		if (( created == 0 )); then
			echo "No new configs needed — every matching game already has a per-game .env"
		else
			echo "Would create $created config(s) under $GAMES_DIR/"
		fi
	fi
	echo "Done: created=$created skipped=$skipped"
}

# prune_uninstalled_configs — Remove per-game .env for games no longer installed.
prune_uninstalled_configs() {
	local dry_run=${1:-0} yes=${2:-0} json=${3:-0}
	local -A installed=() seen_orphans=()
	local -a orphans=()
	local removed=0 scanned=0
	local file appid name path entry

	if ! steam_library_discovery_available; then
		if [[ "$json" == "1" ]]; then
			printf '{"error":"steam_library_unavailable","message":"No readable Steam library was found; no configs were removed."}\n'
		else
			echo "No readable Steam library was found; refusing to classify configs as uninstalled." >&2
		fi
		return 1
	fi

	_collect_prune_installed() {
		installed["$1"]=1
	}

	cli_scan_progress_begin "Scanning installed games"
	if ! foreach_installed_game _collect_prune_installed; then
		cli_scan_progress_end
		echo "Steam inventory failed; no configs were removed." >&2
		return 1
	fi
	cli_scan_progress_end

	_prune_scan_file() {
		local file=$1
		[[ -f "$file" ]] || return 0
		appid="$(basename "$file" .env)"
		[[ "$appid" =~ ^[0-9]+$ ]] || return 0
		[[ -n "${seen_orphans[$appid]+x}" ]] && return 0
		((scanned++)) || true
		[[ -n "${installed[$appid]+x}" ]] && return 0
		name="$(config_file_display_name "$file" "$appid")"
		seen_orphans["$appid"]=1
		orphans+=("$appid|$name|$file")
	}

	for file in "$GAMES_DIR"/[0-9]*.env; do
		_prune_scan_file "$file"
	done

	local delete=0
	if [[ "$yes" == "1" && "$dry_run" != "1" ]]; then
		delete=1
	fi

	if [[ "$json" == "1" ]]; then
		printf '{"dry_run":%s,"scanned":%s,"orphans":[' \
			"$(json_bool "$([[ "$delete" == "1" ]] && echo 0 || echo 1)")" \
			"$scanned"
		local first=1 o_appid o_name o_path
		for entry in "${orphans[@]}"; do
			IFS='|' read -r o_appid o_name o_path <<< "$entry"
			(( first )) || printf ','
			first=0
			printf '{"appid":%s,"name":%s,"path":%s}' \
				"$(json_string "$o_appid")" \
				"$(json_string "$o_name")" \
				"$(json_string "$o_path")"
			if [[ "$delete" == "1" ]]; then
				rm -f "$o_path"
				((removed++)) || true
			fi
		done
		printf '],"removed":%s}\n' "$removed"
		return 0
	fi

	if [[ "$dry_run" == "1" || "$delete" != "1" ]]; then
		echo "=== Prune uninstalled (dry-run) ==="
		if ((${#orphans[@]} == 0)); then
			echo "No orphan configs — every per-game .env matches an installed game"
		else
			printf '%-10s %s\n' APPID NAME
			for entry in "${orphans[@]}"; do
				IFS='|' read -r appid name path <<< "$entry"
				printf '%-10s %s\n' "$appid" "$name"
			done
			echo "Would remove ${#orphans[@]} config(s) under $GAMES_DIR"
		fi
		if [[ "$delete" != "1" && ${#orphans[@]} -gt 0 ]]; then
			echo "Re-run with --yes to delete (or --dry-run to preview only)."
		fi
		echo "Done: removed=$removed scanned=$scanned"
		return 0
	fi

	for entry in "${orphans[@]}"; do
		IFS='|' read -r appid name path <<< "$entry"
		rm -f "$path"
		echo "Removed $path ($name)"
		((removed++)) || true
	done
	echo "Done: removed=$removed scanned=$scanned"
}

# edit_appid_config — Open or create per-game .env in $EDITOR.
edit_appid_config() {
	local query=$1 appid editor path
	[[ -n "$query" ]] || {
		echo "Usage: $0 --edit-appid APPID|NAME" >&2
		return 1
	}
	appid="$(resolve_appid_query "$query")" || return $?
	path="$(resolve_appid_env_path "$appid")"
	if ! appid_env_exists "$appid"; then
		init_appid_config "$appid" "" 0 || return 1
		path="$(appid_env_write_path "$appid")"
	fi
	editor="${EDITOR:-${VISUAL:-nano}}"
	"$editor" "$path"
}
