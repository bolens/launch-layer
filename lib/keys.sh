# shellcheck shell=bash
# lib/keys.sh — Single source of truth for launch.d config key names.
#
# Sourced after lib/common.sh. Used by config reset, summaries, and validation.

[[ -n "${LAUNCHLAYER_KEYS_LOADED:-}" ]] && return 0
LAUNCHLAYER_KEYS_LOADED=1

# Canonical key metadata is shipped as data so validation, TUI placement, summary
# output, and Hub trust policy can share one registry.
LAUNCHLAYER_CONFIG_KEYS=()
LAUNCHLAYER_SUMMARY_KEYS=()
declare -gA LAUNCHLAYER_CONFIG_KEY_KIND=()
declare -gA LAUNCHLAYER_CONFIG_KEY_TUI=()
declare -gA LAUNCHLAYER_CONFIG_KEY_HUB=()

launchlayer_load_config_key_metadata() {
	local file candidate key kind tui summary hub
	file=""
	for candidate in \
		"$(launchlayer_share_dir)/config-keys.tsv" \
		"${LIB_DIR:+$LIB_DIR/../share/launchlayer/config-keys.tsv}" \
		"${SCRIPT_DIR:+$SCRIPT_DIR/share/launchlayer/config-keys.tsv}"; do
		if [[ -r "$candidate" ]]; then
			file="$candidate"
			break
		fi
	done
	[[ -r "$file" ]] || {
		echo "launchlayer: missing config key metadata" >&2
		return 1
	}
	while IFS=$'\t' read -r key kind tui summary hub; do
		[[ -n "$key" && "$key" != \#* ]] || continue
		[[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || {
			echo "launchlayer: invalid config key metadata entry: $key" >&2
			return 1
		}
		LAUNCHLAYER_CONFIG_KEY_KIND["$key"]=$kind
		LAUNCHLAYER_CONFIG_KEY_TUI["$key"]=$tui
		LAUNCHLAYER_CONFIG_KEY_HUB["$key"]=$hub
		[[ "$key" == INCLUDE ]] || LAUNCHLAYER_CONFIG_KEYS+=("$key")
		[[ "$summary" == 1 ]] && LAUNCHLAYER_SUMMARY_KEYS+=("$key")
	done < "$file"
	((${#LAUNCHLAYER_CONFIG_KEYS[@]} > 0)) || {
		echo "launchlayer: config key metadata is empty: $file" >&2
		return 1
	}
}

launchlayer_load_config_key_metadata || return 1

config_key_kind() {
	printf '%s' "${LAUNCHLAYER_CONFIG_KEY_KIND[$1]:-unknown}"
}

config_key_tui_surface() {
	printf '%s' "${LAUNCHLAYER_CONFIG_KEY_TUI[$1]:-hidden}"
}

config_key_hub_policy() {
	printf '%s' "${LAUNCHLAYER_CONFIG_KEY_HUB[$1]:-trusted}"
}

# known_config_key — Return 0 if key is a recognized launch.d setting.
known_config_key() {
	local key=$1
	[[ -n "${LAUNCHLAYER_CONFIG_KEY_KIND[$key]+x}" ]] && return 0
	case "$key" in
		PROTON_*|DXVK_*|VKD3D_*|__GL_*|__VK_*|WINE*|STEAM_*|SDL_*|MESA_*|mesa_*|RADV_*|AMD_*|INTEL_*) return 0 ;;
	esac
	return 1
}
