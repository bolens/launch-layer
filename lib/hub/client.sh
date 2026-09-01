# shellcheck shell=bash
# lib/hub/client.sh — HTTP client for the LaunchLayer Hub API.

[[ -n "${LAUNCHLAYER_HUB_CLIENT_LOADED:-}" ]] && return 0
LAUNCHLAYER_HUB_CLIENT_LOADED=1

# hub_http_limits — Validate and publish bounded HTTP client limits.
hub_http_limits() {
	HUB_HTTP_CONNECT_TIMEOUT=${HUB_CONNECT_TIMEOUT_SEC:-5}
	HUB_HTTP_REQUEST_TIMEOUT=${HUB_REQUEST_TIMEOUT_SEC:-30}
	HUB_HTTP_MAX_RESPONSE_BYTES=${HUB_MAX_RESPONSE_BYTES:-131072}
	[[ "$HUB_HTTP_CONNECT_TIMEOUT" =~ ^[0-9]+$ ]] \
		&& (( HUB_HTTP_CONNECT_TIMEOUT >= 1 && HUB_HTTP_CONNECT_TIMEOUT <= 60 )) || {
		echo "HUB_CONNECT_TIMEOUT_SEC must be an integer from 1 to 60" >&2
		return 1
	}
	[[ "$HUB_HTTP_REQUEST_TIMEOUT" =~ ^[0-9]+$ ]] \
		&& (( HUB_HTTP_REQUEST_TIMEOUT >= 1 && HUB_HTTP_REQUEST_TIMEOUT <= 300 )) || {
		echo "HUB_REQUEST_TIMEOUT_SEC must be an integer from 1 to 300" >&2
		return 1
	}
	[[ "$HUB_HTTP_MAX_RESPONSE_BYTES" =~ ^[0-9]+$ ]] \
		&& (( HUB_HTTP_MAX_RESPONSE_BYTES >= 1024 && HUB_HTTP_MAX_RESPONSE_BYTES <= 4194304 )) || {
		echo "HUB_MAX_RESPONSE_BYTES must be an integer from 1024 to 4194304" >&2
		return 1
	}
}

# hub_curl_status_error — Report a bounded curl transport failure.
hub_curl_status_error() {
	local status=$1 url=$2
	if (( status == 63 )); then
		echo "Hub response exceeded ${HUB_HTTP_MAX_RESPONSE_BYTES} bytes: $url" >&2
	elif (( status == 28 )); then
		echo "Hub request timed out after ${HUB_HTTP_REQUEST_TIMEOUT}s: $url" >&2
	else
		echo "Hub request failed: $url" >&2
	fi
}

# hub_fetch_publish_auth_required — 1 when hub GET /api/auth reports token required.
hub_fetch_publish_auth_required() {
	local url tmp code body curl_status=0
	load_hub_prefs
	hub_http_limits || return 1
	url="${HUB_PREFS_URL%/}/api/auth"
	tmp="$(mktemp)"
	trap 'rm -f "'"$tmp"'"' RETURN
	code="$(curl -sS -o "$tmp" -w '%{http_code}' \
		--connect-timeout "$HUB_HTTP_CONNECT_TIMEOUT" \
		--max-time "$HUB_HTTP_REQUEST_TIMEOUT" \
		--max-filesize "$HUB_HTTP_MAX_RESPONSE_BYTES" \
		"$url" 2>/dev/null)" || curl_status=$?
	if (( curl_status != 0 )); then
		echo 0
		return 0
	fi
	if [[ "$code" != "200" ]]; then
		echo 0
		return 0
	fi
	body="$(cat "$tmp")"
	case "$body" in
		*'"publish_auth_required":true'* | *'"publish_auth_required": true'*) echo 1 ;;
		*) echo 0 ;;
	esac
}

# hub_require_privileged_auth — Fail when hub requires token but hub.conf has none.
hub_require_privileged_auth() {
	local required
	load_hub_prefs
	required="$(hub_fetch_publish_auth_required)"
	if [[ "$required" == "1" && -z "${HUB_PREFS_PUBLISH_TOKEN:-}" ]]; then
		echo "This hub requires publish_token in $(hub_config_path) (must match Convex HUB_PUBLISH_TOKEN)." >&2
		return 1
	fi
	return 0
}

# hub_format_published_at — Format hub published_at (Unix ms) for display.
hub_format_published_at() {
	local ms=${1:-0} sec
	[[ "$ms" =~ ^[0-9]+$ ]] && (( ms > 0 )) || {
		echo "unknown"
		return 0
	}
	sec=$((ms / 1000))
	if date -u -d "@$sec" '+%Y-%m-%d' 2>/dev/null; then
		return 0
	fi
	date -u -r "$sec" '+%Y-%m-%d' 2>/dev/null || printf '%s' "$sec"
}

# hub_jq_recommend_cli_filter — jq program for CLI recommend listings.
hub_jq_recommend_cli_filter() {
	cat <<'JQ'
.results[]? | ((.published_at // 0) / 1000 | strftime("%Y-%m-%d")) as $updated | "\(.similarity)%  \(.machine_label // .gpu_vendor)  updated \($updated)  \(.note // "")  id=\(.config_id)"
JQ
}

# hub_jq_recommend_picker_filter — jq program for TUI picker rows (config_id TAB label).
hub_jq_recommend_picker_filter() {
	cat <<'JQ'
.results[]? | ((.published_at // 0) / 1000 | strftime("%Y-%m-%d")) as $updated | "\(.config_id)\t\(.similarity)% match · \(.machine_label // .gpu_vendor // "unknown") · updated \($updated) · \(.note // "-")"
JQ
}

# hub_format_recommend_response_cli — Print human-readable recommend lines from JSON.
hub_format_recommend_response_cli() {
	local response=$1
	if command -v jq >/dev/null 2>&1; then
		printf '%s\n' "$response" | jq -r "$(hub_jq_recommend_cli_filter)" 2>/dev/null
		return $?
	fi
	HUB_JSON_RESPONSE=$response python3 -c '
import json, os
from datetime import datetime, timezone

def fmt(ms):
    if not isinstance(ms, (int, float)) or ms <= 0:
        return "unknown"
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime("%Y-%m-%d")

data = json.loads(os.environ["HUB_JSON_RESPONSE"])
for row in data.get("results") or []:
    updated = fmt(row.get("published_at"))
    sim = row.get("similarity", 0)
    label = row.get("machine_label") or row.get("gpu_vendor") or "unknown"
    note = row.get("note") or ""
    cid = row.get("config_id", "")
    print(f"{sim}%  {label}  updated {updated}  {note}  id={cid}")
' 2>/dev/null
}

# hub_curl_json — HTTP JSON call; pass privileged=1 for publish/delete (auth enforced).
hub_curl_json() {
	local method=$1 path=$2 body=${3:-} privileged=${4:-0}
	local url tmp code curl_status=0
	hub_require_url || return 1
	load_hub_prefs
	hub_http_limits || return 1
	if [[ "$privileged" == "1" ]]; then
		hub_require_privileged_auth || return 1
	fi
	url="${HUB_PREFS_URL%/}${path}"
	tmp="$(mktemp)"
	trap 'rm -f "'"$tmp"'"' RETURN

	if [[ "$method" == POST ]]; then
		if [[ -n "${HUB_PREFS_PUBLISH_TOKEN:-}" ]]; then
			code="$(curl -sS -o "$tmp" -w '%{http_code}' -X POST \
				--connect-timeout "$HUB_HTTP_CONNECT_TIMEOUT" \
				--max-time "$HUB_HTTP_REQUEST_TIMEOUT" \
				--max-filesize "$HUB_HTTP_MAX_RESPONSE_BYTES" \
				-H 'Content-Type: application/json' \
				-H "Authorization: Bearer ${HUB_PREFS_PUBLISH_TOKEN}" \
				-d "$body" "$url")" || curl_status=$?
		else
			code="$(curl -sS -o "$tmp" -w '%{http_code}' -X POST \
				--connect-timeout "$HUB_HTTP_CONNECT_TIMEOUT" \
				--max-time "$HUB_HTTP_REQUEST_TIMEOUT" \
				--max-filesize "$HUB_HTTP_MAX_RESPONSE_BYTES" \
				-H 'Content-Type: application/json' \
				-d "$body" "$url")" || curl_status=$?
		fi
	else
		code="$(curl -sS -o "$tmp" -w '%{http_code}' \
			--connect-timeout "$HUB_HTTP_CONNECT_TIMEOUT" \
			--max-time "$HUB_HTTP_REQUEST_TIMEOUT" \
			--max-filesize "$HUB_HTTP_MAX_RESPONSE_BYTES" \
			"$url")" || curl_status=$?
	fi
	if (( curl_status != 0 )); then
		hub_curl_status_error "$curl_status" "$url"
		return 1
	fi

	if [[ "$code" =~ ^2 ]]; then
		cat "$tmp"
		return 0
	fi

	if [[ "$code" == "401" && "$privileged" == "1" ]]; then
		echo "Hub action unauthorized — publish_token in $(hub_config_path) must match Convex HUB_PUBLISH_TOKEN" >&2
	fi

	echo "Hub error ($code): $(cat "$tmp" 2>/dev/null)" >&2
	return 1
}

# hub_settings_json_for_publish — Hub API expects {key,value} only (no source layer).
hub_settings_json_for_publish() {
	local raw=${1:-[]}
	if command -v jq >/dev/null 2>&1; then
		printf '%s' "$raw" | jq -c '[.[] | {key, value}]' 2>/dev/null && return 0
	fi
	if command -v python3 >/dev/null 2>&1; then
		HUB_SETTINGS_RAW=$raw python3 -c '
import json, os
data = json.loads(os.environ["HUB_SETTINGS_RAW"])
print(json.dumps([{"key": item["key"], "value": item["value"]} for item in data], separators=(",", ":")))
' 2>/dev/null && return 0
	fi
	printf '%s' "$raw"
}

# hub_publish_payload — Build JSON body for publishing one game config.
hub_publish_payload() {
	local fingerprint=$1 appid=$2 game_name=$3 env_content=$4 note=${5:-} config_id=${6:-}
	local settings_json detection_json preset=""
	local config_path

	config_path="$(resolve_appid_env_path "$appid" 2>/dev/null || true)"
	if [[ -f "$config_path" ]]; then
		while IFS= read -r line || [[ -n "$line" ]]; do
			[[ "$line" =~ ^[[:space:]]*# ]] && continue
			[[ "$line" == INCLUDE=* ]] && preset="${line#INCLUDE=}" && continue
		done < "$config_path"
	fi

	prepare_launch_context "$appid" 2>/dev/null || true
	settings_json="$(hub_settings_json_for_publish "$(collect_effective_settings_json 2>/dev/null || printf '[]')")"
	detection_json="$(printf '{"native":%s,"anticheat":%s,"engine":%s}' \
		"$(json_bool "${is_native:-0}")" \
		"$(json_bool "${is_anticheat:-0}")" \
		"$(json_string "${game_engine_hint:-}")")"

	printf '{"fingerprint":'
	printf '%s' "$fingerprint"
	printf ',"fingerprint_hash":%s' "$(json_string "$(hub_fingerprint_hash "$fingerprint")")"
	json_object_pair "machine_label" "$(json_string "${HUB_PREFS_MACHINE_LABEL:-}")" 1
	json_object_pair "appid" "$(json_string "$appid")" 1
	json_object_pair "game_name" "$(json_string "$game_name")" 1
	json_object_pair "env_content" "$(json_string "$env_content")" 1
	json_object_pair "preset" "$(json_string "$preset")" 1
	json_object_pair "note" "$(json_string "$note")" 1
	if [[ -n "$config_id" ]]; then
		json_object_pair "config_id" "$(json_string "$config_id")" 1
	fi
	printf ',"settings":'
	printf '%s' "$settings_json"
	printf ',"detection":'
	printf '%s' "$detection_json"
	printf ',"launchlayer_version":%s}\n' "$(json_string "$LAUNCHLAYER_VERSION")"
}

# hub_my_config_payload — Lookup existing config for this machine fingerprint + appid.
hub_my_config_payload() {
	local fingerprint=$1 appid=$2
	printf '{"fingerprint_hash":%s,"appid":%s}\n' \
		"$(json_string "$(hub_fingerprint_hash "$fingerprint")")" \
		"$(json_string "$appid")"
}

# hub_find_my_config_id — Return config_id when this machine already published appid.
hub_find_my_config_id() {
	local appid=$1 fingerprint=${2:-} payload response cid
	[[ -n "$appid" ]] || return 1
	[[ -n "$fingerprint" ]] || fingerprint="$(hub_fingerprint_from_detection)"
	payload="$(hub_my_config_payload "$fingerprint" "$appid")"
	response="$(hub_curl_json POST /api/my-config "$payload")" || return 1
	cid="$(hub_json_get "$response" config_id 2>/dev/null || true)"
	[[ -n "$cid" && "$cid" != "null" ]] || return 1
	printf '%s\n' "$cid"
}

# hub_parse_publish_updated — Print 1 when publish response updated an existing config.
hub_parse_publish_updated() {
	local response=$1
	if command -v jq >/dev/null 2>&1; then
		printf '%s' "$response" | jq -er '.updated == true' >/dev/null 2>&1 && {
			echo 1
			return 0
		}
		echo 0
		return 0
	fi
	case "$response" in
		*'"updated":true'* | *'"updated": true'*) echo 1 ;;
		*) echo 0 ;;
	esac
}

# hub_parse_publish_config_id — Read config_id from publish response JSON.
hub_parse_publish_config_id() {
	local response=$1
	hub_json_get "$response" config_id 2>/dev/null || true
}

# hub_delete_payload — Build JSON body for deleting a shared config.
hub_delete_payload() {
	local config_id=$1 fingerprint=${2:-}
	[[ -n "$fingerprint" ]] || fingerprint="$(hub_fingerprint_from_detection)"
	printf '{"config_id":%s,"fingerprint_hash":%s}\n' \
		"$(json_string "$config_id")" \
		"$(json_string "$(hub_fingerprint_hash "$fingerprint")")"
}

# hub_recommend_payload — Build JSON body for recommendation request.
hub_recommend_payload() {
	local fingerprint=$1 appid=$2 limit=${3:-10}
	printf '{"fingerprint":'
	printf '%s' "$fingerprint"
	printf ',"fingerprint_hash":%s,"appid":%s,"limit":%s}\n' \
		"$(json_string "$(hub_fingerprint_hash "$fingerprint")")" \
		"$(json_string "$appid")" \
		"$limit"
}
