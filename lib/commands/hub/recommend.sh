# shellcheck shell=bash
# lib/commands/hub/recommend.sh — --hub-recommend and --hub-search.

[[ -n "${LAUNCHLAYER_COMMANDS_HUB_RECOMMEND_LOADED:-}" ]] && return 0
LAUNCHLAYER_COMMANDS_HUB_RECOMMEND_LOADED=1

# hub_recommend_configs — Find community configs from similar machines.
hub_recommend_configs() {
	local appid="" limit=10 json=0 arg
	local fingerprint payload response

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--limit) limit=${2:-10}; shift 2 ;;
			--json) json=1; shift ;;
			*)
				[[ -z "$appid" ]] && appid=$1
				shift
				;;
		esac
	done

	[[ -n "$appid" ]] || {
		echo "Usage: launchlayer --hub-recommend APPID|NAME [--limit N] [--json]" >&2
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

	command_required_or_fail curl "Hub recommend" || return 1
	hub_require_url || return 1
	load_hub_prefs

	hub_load_launch_context
	fingerprint="$(hub_fingerprint_from_detection)"
	payload="$(hub_recommend_payload "$fingerprint" "$appid" "$limit")"
	response="$(hub_curl_json POST /api/recommend "$payload")" || return 1

	if [[ "$json" == "1" ]]; then
		if command -v jq >/dev/null 2>&1; then
			printf '%s\n' "$response" | jq . 2>/dev/null || printf '%s\n' "$response"
		else
			printf '%s\n' "$response"
		fi
		return 0
	fi

	local name
	name="$(get_game_name "$appid" 2>/dev/null || echo "AppID $appid")"
	cli_section "Hub recommendations for $name ($appid)"
	hub_format_recommend_response_cli "$response" || printf '%s\n' "$response"
}

# hub_search_machines — List machines most similar to the current fingerprint.
hub_search_machines() {
	local limit=10 json=0 arg
	local fingerprint payload response

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--limit) limit=${2:-10}; shift 2 ;;
			--json) json=1; shift ;;
			*) shift ;;
		esac
	done

	command_required_or_fail curl "Hub search" || return 1
	hub_require_url || return 1
	load_hub_prefs

	hub_load_launch_context
	fingerprint="$(hub_fingerprint_from_detection)"
	payload="$(printf '{"fingerprint":%s,"limit":%s}' "$fingerprint" "$limit")"
	response="$(hub_curl_json POST /api/similar-machines "$payload")" || return 1

	if [[ "$json" == "1" ]]; then
		if command -v jq >/dev/null 2>&1; then
			printf '%s\n' "$response" | jq . 2>/dev/null || printf '%s\n' "$response"
		else
			printf '%s\n' "$response"
		fi
		return 0
	fi

	cli_section "Similar machines"
	if command -v jq >/dev/null 2>&1; then
		printf '%s\n' "$response" | jq -r '.results[]? | "\(.similarity)%  \(.machine_label // .gpu_vendor)  \(.display // "")  \(.profiles | join(", "))"' 2>/dev/null \
			|| printf '%s\n' "$response"
	else
		printf '%s\n' "$response"
	fi
}
