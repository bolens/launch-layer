# shellcheck shell=bash
# lib/hub/fingerprint.sh — Machine fingerprint for hub similarity matching.

[[ -n "${LAUNCHLAYER_HUB_FINGERPRINT_LOADED:-}" ]] && return 0
LAUNCHLAYER_HUB_FINGERPRINT_LOADED=1

# hub_fingerprint_level_rank — Numeric order for minimal < standard < detailed.
hub_fingerprint_level_rank() {
	case "${1:-minimal}" in
		minimal) printf '1' ;;
		standard) printf '2' ;;
		detailed) printf '3' ;;
		*) printf '1' ;;
	esac
}

# hub_fingerprint_level — Active fingerprint depth from prefs or env override.
hub_fingerprint_level() {
	load_hub_prefs 2>/dev/null || true
	if [[ -n "${LAUNCHLAYER_HUB_FINGERPRINT_LEVEL:-}" ]]; then
		printf '%s\n' "${LAUNCHLAYER_HUB_FINGERPRINT_LEVEL}"
		return 0
	fi
	printf '%s\n' "${HUB_PREFS_FINGERPRINT_LEVEL:-minimal}"
}

# hub_fingerprint_level_at_least — True when current level includes the requested tier.
hub_fingerprint_level_at_least() {
	local want=${1:-minimal} have
	have="$(hub_fingerprint_level)"
	(( $(hub_fingerprint_level_rank "$have") >= $(hub_fingerprint_level_rank "$want") ))
}

# hub_refresh_tier — Bucket refresh rate for stable matching.
hub_refresh_tier() {
	local r=${1:-60}
	[[ "$r" =~ ^[0-9]+$ ]] || r=60
	if (( r >= 144 )); then
		printf 'hi144+\n'
	elif (( r >= 75 )); then
		printf 'mid75_120\n'
	else
		printf 'std60\n'
	fi
}

# hub_vram_tier — Bucket primary GPU VRAM (MB).
hub_vram_tier() {
	local mb=${1:-0}
	[[ "$mb" =~ ^[0-9]+$ ]] || mb=0
	if (( mb >= 16384 )); then
		printf '16gb+\n'
	elif (( mb >= 12288 )); then
		printf '12gb\n'
	elif (( mb >= 8192 )); then
		printf '8gb\n'
	elif (( mb >= 4096 )); then
		printf '4gb\n'
	elif (( mb > 0 )); then
		printf 'lt4gb\n'
	else
		printf 'unknown\n'
	fi
}

# hub_monitor_layout — Bucket connected monitor count.
hub_monitor_layout() {
	local count=${1:-1}
	[[ "$count" =~ ^[0-9]+$ ]] || count=1
	if (( count >= 3 )); then
		printf 'triple+\n'
	elif (( count == 2 )); then
		printf 'dual\n'
	else
		printf 'single\n'
	fi
}

# hub_primary_aspect — Bucket primary display aspect ratio.
hub_primary_aspect() {
	local w=${1:-0} h=${2:-0} ratio
	[[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ && "$h" -gt 0 ]] || {
		printf 'unknown\n'
		return 0
	}
	ratio=$(( (w * 100) / h ))
	if (( ratio >= 230 )); then
		printf '21:9\n'
	elif (( ratio >= 156 && ratio < 170 )); then
		printf '16:10\n'
	elif (( ratio >= 170 && ratio <= 185 )); then
		printf '16:9\n'
	else
		printf 'other\n'
	fi
}

# hub_display_tier — Bucket resolution/refresh into coarse tiers for matching.
hub_display_tier() {
	local w=${1:-0} h=${2:-0} r=${3:-60}
	local pixels=$(( w * h ))

	if (( w >= 5120 || h >= 2880 || pixels >= 12000000 )); then
		printf '5k+\n'
	elif (( w >= 3840 || h >= 2160 || pixels >= 8000000 )); then
		printf '4k\n'
	elif (( w >= 3440 && h >= 1400 )); then
		printf 'ultrawide\n'
	elif (( w >= 2560 || h >= 1440 || pixels >= 3500000 )); then
		printf '1440p\n'
	elif (( w >= 1920 || h >= 1080 || pixels >= 1800000 )); then
		printf '1080p\n'
	else
		printf 'sub1080p\n'
	fi
}

# hub_parse_display — Read w, h, refresh from "WxH@RHz" display strings.
hub_parse_display() {
	local display=${1:-}
	local w=0 h=0 r=60

	if [[ "$display" =~ ^([0-9]+)x([0-9]+)@([0-9]+)Hz$ ]]; then
		w="${BASH_REMATCH[1]}"
		h="${BASH_REMATCH[2]}"
		r="${BASH_REMATCH[3]}"
	fi
	printf '%s %s %s\n' "$w" "$h" "$r"
}

# hub_profiles_array — Split space- or comma-separated profiles into a JSON string array.
hub_profiles_array() {
	local profiles_raw=${1:-}
	local -a parts=()
	local part first=1

	profiles_raw="${profiles_raw//,/ }"
	read -r -a parts <<< "$profiles_raw"
	printf '['
	for part in "${parts[@]}"; do
		part="${part#"${part%%[![:space:]]*}"}"
		part="${part%"${part##*[![:space:]]}"}"
		[[ -n "$part" ]] || continue
		(( first )) || printf ','
		first=0
		json_string "$part"
	done
	printf ']'
}

# hub_has_x3d — True when CPU cores expose unequal L3 cache sizes (X3D / hybrid CCD).
hub_has_x3d() {
	local cpu cache min=0 max=0
	is_linux || return 1
	for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
		[[ -f "$cpu/cache/index3/size" ]] || continue
		cache="$(<"$cpu/cache/index3/size")"
		cache="${cache%K}"
		[[ "$cache" =~ ^[0-9]+$ ]] || continue
		(( cache > max )) && max=$cache
		if (( min == 0 || cache < min )); then
			min=$cache
		fi
	done
	(( max > 0 && min > 0 && max != min ))
}

# hub_has_igpu — True when an integrated GPU is present alongside other GPUs.
hub_has_igpu() {
	local row role
	while IFS=$'\t' read -r _ role _ _ _ _ _; do
		[[ "$role" == integrated ]] && return 0
	done < <(detect_gpus_enumerate 2>/dev/null || true)
	return 1
}

# hub_primary_vram_mb — VRAM (MB) for the primary gaming GPU.
hub_primary_vram_mb() {
	local pri vram
	while IFS=$'\t' read -r _ _ pri _ vram _ _; do
		[[ "$pri" == "1" ]] && [[ "$vram" =~ ^[0-9]+$ ]] && {
			printf '%s\n' "$vram"
			return 0
		}
	done < <(detect_gpus_enumerate 2>/dev/null || true)
	printf '0\n'
}

# hub_display_count — Number of connected displays (best effort).
hub_display_count() {
	local json count
	json="$(detect_displays_json 2>/dev/null || printf '[]')"
	if command -v jq >/dev/null 2>&1; then
		count="$(printf '%s' "$json" | jq 'length' 2>/dev/null || echo 1)"
	elif command -v python3 >/dev/null 2>&1; then
		count="$(printf '%s' "$json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 1)"
	else
		count=1
	fi
	[[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]] || count=1
	printf '%s\n' "$count"
}

# hub_fingerprint_from_detection — Build normalized fingerprint JSON from live detection.
hub_fingerprint_from_detection() {
	local level profiles w h r display tier refresh_tier deck x3d has_x3d
	local active_output primary_output displays gpus vram_mb layout aspect igpu

	level="$(hub_fingerprint_level)"
	profiles="$(detect_default_profiles 2>/dev/null || true)"
	[[ -n "$profiles" ]] || profiles="${LAUNCHLAYER_PROFILES:-${LAUNCHLAYER_PROFILE:-none}}"
	read -r w h < <(detect_display_resolution 2>/dev/null || echo "0 0")
	r="$(detect_display_refresh 2>/dev/null || echo 60)"
	[[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || read -r w h r < <(hub_parse_display "${LAUNCHLAYER_HUB_DISPLAY:-}")
	display="${w}x${h}@${r}Hz"
	tier="$(hub_display_tier "$w" "$h" "$r")"
	refresh_tier="$(hub_refresh_tier "$r")"
	deck="$(is_steam_deck && echo 1 || echo 0)"
	x3d="$(detect_x3d_cpus 2>/dev/null || echo none)"
	if hub_has_x3d; then has_x3d=1; else has_x3d=0; fi

	printf '{'
	json_object_pair "fingerprint_level" "$(json_string "$level")"
	json_object_pair "gpu_vendor" "$(json_string "$(detect_gpu_vendor)")" 1
	json_object_pair "os_family" "$(json_string "$(detect_os_family)")" 1
	json_object_pair "session_type" "$(json_string "$(detect_session_type)")" 1
	json_object_pair "profiles" "$(hub_profiles_array "$profiles")" 1
	json_object_pair "display_tier" "$(json_string "$tier")" 1
	json_object_pair "refresh_tier" "$(json_string "$refresh_tier")" 1
	json_object_pair "desktop" "$(json_string "$(detect_desktop_session)")" 1
	json_object_pair "has_x3d" "$(json_bool "$has_x3d")" 1
	json_object_pair "vrr" "$(json_bool "$(detect_vrr_enabled && echo 1 || echo 0)")" 1
	json_object_pair "wsl2" "$(json_bool "$(is_wsl2 && echo 1 || echo 0)")" 1
	json_object_pair "flatpak_steam" "$(json_bool "$(is_flatpak_steam && echo 1 || echo 0)")" 1
	json_object_pair "steam_deck" "$(json_bool "$deck")" 1
	json_object_pair "immutable" "$(json_bool "$(is_immutable_os && echo 1 || echo 0)")" 1
	json_object_pair "container" "$(json_bool "$(is_container && echo 1 || echo 0)")" 1

	if hub_fingerprint_level_at_least standard; then
		vram_mb="$(hub_primary_vram_mb)"
		layout="$(hub_monitor_layout "$(hub_display_count)")"
		aspect="$(hub_primary_aspect "$w" "$h")"
		igpu=0
		hub_has_igpu && igpu=1
		json_object_pair "audio" "$(json_string "$(detect_audio_server)")" 1
		json_object_pair "vram_tier" "$(json_string "$(hub_vram_tier "$vram_mb")")" 1
		json_object_pair "monitor_layout" "$(json_string "$layout")" 1
		json_object_pair "primary_aspect" "$(json_string "$aspect")" 1
		json_object_pair "has_igpu" "$(json_bool "$igpu")" 1
		json_object_pair "display" "$(json_string "$display")" 1
		json_object_pair "x3d_cpus" "$(json_string "$x3d")" 1
	fi

	if hub_fingerprint_level_at_least detailed; then
		active_output="$(detect_active_output 2>/dev/null || true)"
		primary_output="$(detect_kwin_primary_output 2>/dev/null || true)"
		[[ -n "$primary_output" ]] || primary_output="$active_output"
		displays="$(detect_displays_json 2>/dev/null || printf '[]')"
		gpus="$(detect_gpus_json 2>/dev/null || printf '[]')"
		json_object_pair "os_pretty" "$(json_string "$(detect_os_pretty_name)")" 1
		json_object_pair "os_id" "$(json_string "$(detect_os_id)")" 1
		json_object_pair "active_output" "$(json_string "${active_output:-}")" 1
		json_object_pair "primary_output" "$(json_string "${primary_output:-}")" 1
		json_object_pair "displays" "$displays" 1
		json_object_pair "gpus" "$gpus" 1
	fi

	printf '}\n'
}

# hub_fingerprint_hash — Stable SHA-256 over match-relevant fingerprint fields.
hub_fingerprint_hash() {
	local json=$1
	local canonical
	local hash_keys='{
			gpu_vendor, os_family, session_type, profiles, display_tier, refresh_tier,
			desktop, has_x3d, vrr, wsl2, flatpak_steam, steam_deck, immutable, container
		} | to_entries | sort_by(.key) | from_entries'
	if command -v jq >/dev/null 2>&1; then
		canonical="$(printf '%s' "$json" | jq -c "$hash_keys" 2>/dev/null || printf '%s' "$json")"
	elif command -v python3 >/dev/null 2>&1; then
		canonical="$(printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
keys = ["gpu_vendor","os_family","session_type","profiles","display_tier","refresh_tier",
        "desktop","has_x3d","vrr","wsl2","flatpak_steam","steam_deck","immutable","container"]
print(json.dumps({k: d.get(k) for k in keys}, sort_keys=True, separators=(",",":")))
' 2>/dev/null || printf '%s' "$json")"
	else
		canonical="$json"
	fi
	printf '%s' "$canonical" | sha256sum | awk '{print $1}'
}
