# shellcheck shell=bash
# lib/commands/hub/publish.sh — --hub-publish and --hub-update.

[[ -n "${LAUNCHLAYER_COMMANDS_HUB_PUBLISH_LOADED:-}" ]] && return 0
LAUNCHLAYER_COMMANDS_HUB_PUBLISH_LOADED=1

# hub_sync_one_game — Upload one game config; sets HUB_SYNC_RESPONSE and HUB_SYNC_UPDATED.
hub_sync_one_game() {
	local fingerprint=$1 appid=$2 name=$3 content=$4 note=${5:-} config_id=${6:-}
	if [[ -z "$config_id" ]]; then
		config_id="$(hub_find_my_config_id "$appid" "$fingerprint" 2>/dev/null || true)"
	fi
	local payload
	payload="$(hub_publish_payload "$fingerprint" "$appid" "$name" "$content" "$note" "$config_id")"
	HUB_SYNC_RESPONSE="$(hub_curl_json POST /api/publish "$payload" 1)" || return 1
	HUB_SYNC_UPDATED="$(hub_parse_publish_updated "$HUB_SYNC_RESPONSE")"
	return 0
}

# hub_publish_result_message — Human message after publish/update.
hub_publish_result_message() {
	local name=$1 appid=$2 response=$3
	local updated cid
	updated="$(hub_parse_publish_updated "$response")"
	cid="$(hub_parse_publish_config_id "$response")"
	if [[ "$updated" == "1" ]]; then
		echo "Updated hub config for $name ($appid) — id=${cid:-unknown}"
	else
		echo "Published new hub config for $name ($appid) — id=${cid:-unknown}"
	fi
}

# hub_bulk_progress_begin / hub_bulk_progress_end — Keep long bulk hub operations visible.
hub_bulk_progress_begin() {
	local index=$1 action=$2 name=$3 appid=$4
	printf '[%d] %s %s (%s)... ' "$index" "$action" "$name" "$appid" >&2
}

hub_bulk_progress_end() {
	printf '%s\n' "$1" >&2
}

# hub_publish_config — Upload one or more game configs to the hub.
hub_publish_config() {
	local appid="" note="" all_configured=0 json=0 config_id="" arg
	local fingerprint response

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--note) note=${2:-}; shift 2 ;;
			--all-configured) all_configured=1; shift ;;
			--json) json=1; shift ;;
			--config-id) config_id=${2:-}; shift 2 ;;
			*)
				[[ -z "$appid" ]] && appid=$1
				shift
				;;
		esac
	done

	command_required_or_fail curl "Hub publish" || return 1
	hub_require_url || return 1
	load_hub_prefs
	hub_require_privileged_auth || return 1

	hub_load_launch_context
	fingerprint="$(hub_fingerprint_from_detection)"

	if [[ "$all_configured" == "1" ]]; then
		local -a published=() updated=() created=()
		local line id name path content progress=0
		echo "Discovering configured games..." >&2
		while IFS= read -r line; do
			[[ -n "$line" ]] || continue
			id="$(hub_json_get "$line" appid 2>/dev/null || true)"
			[[ "$id" =~ ^[0-9]+$ ]] || continue
			name="$(hub_json_get "$line" name 2>/dev/null || echo "AppID $id")"
			path="$(resolve_appid_env_path "$id" 2>/dev/null || true)"
			[[ -f "$path" ]] || continue
			hub_validate_local_env_file "$path" "Config for $name ($id)" || return 1
			hub_assert_publish_env_safe "$path" || return 1
			content="$(cat "$path")"
			((progress++)) || true
			hub_bulk_progress_begin "$progress" Publishing "$name" "$id"
			if ! hub_sync_one_game "$fingerprint" "$id" "$name" "$content" "$note"; then
				hub_bulk_progress_end failed
				return 1
			fi
			published+=("$id")
			if [[ "$HUB_SYNC_UPDATED" == "1" ]]; then
				updated+=("$id")
				hub_bulk_progress_end updated
			else
				created+=("$id")
				hub_bulk_progress_end created
			fi
		done < <(list_games 1 1 "")

		if [[ "$json" == "1" ]]; then
			printf '{"published":%s,"updated":%s,"created":%s}\n' \
				"$(json_array_strings published)" \
				"$(json_array_strings updated)" \
				"$(json_array_strings created)"
			return 0
		fi
		echo "Synced ${#published[@]} configured game(s) to LaunchLayer Hub (${#updated[@]} updated, ${#created[@]} new)."
		return 0
	fi

	[[ -n "$appid" ]] || {
		echo "Usage: launchlayer --hub-publish APPID|NAME [--note TEXT] [--config-id ID] [--all-configured] [--json]" >&2
		return 1
	}
	if [[ "$appid" =~ ^[0-9]+$ ]]; then
		if declare -f find_app_manifest >/dev/null 2>&1 \
			&& find_app_manifest "$appid" >/dev/null 2>&1 \
			&& ! is_installed_game_appid "$appid"; then
			echo "AppID $appid is an installed Steam tool, not a game." >&2
			return 1
		fi
	else
		appid="$(resolve_appid_arg "$appid")" || return $?
	fi

	local name path content
	name="$(get_game_name "$appid" 2>/dev/null || echo "AppID $appid")"
	path="$(resolve_appid_env_path "$appid")"
	[[ -f "$path" ]] || {
		echo "No config at $path — run --init-appid first" >&2
		return 1
	}
	hub_validate_local_env_file "$path" "Config for $name ($appid)" || return 1
	hub_assert_publish_env_safe "$path" || return 1
	content="$(cat "$path")"
	hub_sync_one_game "$fingerprint" "$appid" "$name" "$content" "$note" "$config_id" || return 1
	response="$HUB_SYNC_RESPONSE"

	if [[ "$json" == "1" ]]; then
		printf '%s\n' "$response"
		return 0
	fi
	hub_publish_result_message "$name" "$appid" "$response"
}

# hub_update_config — Update existing shared config(s) for this machine fingerprint.
hub_update_config() {
	local config_id="" appid="" note="" all_configured=0 json=0 only_existing=1
	local fingerprint name path content hub_config response
	local -a updated=() skipped=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--note) note=${2:-}; shift 2 ;;
			--all-configured) all_configured=1; shift ;;
			--json) json=1; shift ;;
			--include-new) only_existing=0; shift ;;
			*)
				if [[ -z "$config_id" && -z "$appid" ]]; then
					if [[ "$1" =~ ^[0-9]+$ ]]; then
						appid=$1
					else
						config_id=$1
					fi
				fi
				shift
				;;
		esac
	done

	command_required_or_fail curl "Hub update" || return 1
	hub_require_url || return 1
	load_hub_prefs
	hub_require_privileged_auth || return 1

	hub_load_launch_context
	fingerprint="$(hub_fingerprint_from_detection)"

	if [[ "$all_configured" == "1" ]]; then
		local line id existing_id progress=0
		echo "Discovering configured games..." >&2
		while IFS= read -r line; do
			[[ -n "$line" ]] || continue
			id="$(hub_json_get "$line" appid 2>/dev/null || true)"
			[[ "$id" =~ ^[0-9]+$ ]] || continue
			name="$(hub_json_get "$line" name 2>/dev/null || echo "AppID $id")"
			path="$(resolve_appid_env_path "$id" 2>/dev/null || true)"
			[[ -f "$path" ]] || continue
			hub_validate_local_env_file "$path" "Config for $name ($id)" || return 1
			hub_assert_publish_env_safe "$path" || return 1
			((progress++)) || true
			hub_bulk_progress_begin "$progress" Updating "$name" "$id"
			existing_id="$(hub_find_my_config_id "$id" "$fingerprint" 2>/dev/null || true)"
			if [[ -z "$existing_id" ]]; then
				if [[ "$only_existing" == "1" ]]; then
					skipped+=("$id")
					hub_bulk_progress_end skipped
					continue
				fi
				content="$(cat "$path")"
				if ! hub_sync_one_game "$fingerprint" "$id" "$name" "$content" "$note"; then
					hub_bulk_progress_end failed
					return 1
				fi
				updated+=("$id")
				hub_bulk_progress_end created
				continue
			fi
			content="$(cat "$path")"
			if ! hub_sync_one_game "$fingerprint" "$id" "$name" "$content" "$note" "$existing_id"; then
				hub_bulk_progress_end failed
				return 1
			fi
			updated+=("$id")
			hub_bulk_progress_end updated
		done < <(list_games 1 1 "")

		if [[ "$json" == "1" ]]; then
			printf '{"updated":%s,"skipped":%s}\n' \
				"$(json_array_strings updated)" \
				"$(json_array_strings skipped)"
			return 0
		fi
		echo "Updated ${#updated[@]} shared hub config(s)."
		((${#skipped[@]})) && echo "Skipped ${#skipped[@]} game(s) with no existing hub config (use --include-new to publish them)."
		return 0
	fi

	if [[ -n "$appid" ]]; then
		if declare -f find_app_manifest >/dev/null 2>&1 \
			&& find_app_manifest "$appid" >/dev/null 2>&1 \
			&& ! is_installed_game_appid "$appid"; then
			echo "AppID $appid is an installed Steam tool, not a game." >&2
			return 1
		fi
		config_id="$(hub_find_my_config_id "$appid" "$fingerprint" 2>/dev/null || true)"
		[[ -n "$config_id" ]] || {
			echo "No shared hub config for $appid on this machine — use --hub-publish to create one." >&2
			return 1
		}
	elif [[ -z "$config_id" ]]; then
		echo "Usage: launchlayer --hub-update APPID|NAME|CONFIG_ID [--all-configured] [--note TEXT] [--include-new] [--json]" >&2
		return 1
	fi

	hub_config="$(hub_curl_json GET "/api/config/${config_id}")" || return 1
	appid="$(hub_json_get "$hub_config" appid)"
	[[ -n "$appid" ]] || {
		echo "Hub config $config_id is missing appid metadata." >&2
		return 1
	}

	name="$(get_game_name "$appid" 2>/dev/null || hub_json_get "$hub_config" game_name)"
	path="$(resolve_appid_env_path "$appid")"
	[[ -f "$path" ]] || {
		echo "No local config at $path — run --init-appid first" >&2
		return 1
	}
	hub_validate_local_env_file "$path" "Config for $name ($appid)" || return 1
	hub_assert_publish_env_safe "$path" || return 1
	content="$(cat "$path")"
	hub_sync_one_game "$fingerprint" "$appid" "$name" "$content" "$note" "$config_id" || return 1
	response="$HUB_SYNC_RESPONSE"

	if [[ "$json" == "1" ]]; then
		printf '%s\n' "$response"
		return 0
	fi
	hub_publish_result_message "$name" "$appid" "$response"
}
