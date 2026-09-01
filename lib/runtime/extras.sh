# shellcheck shell=bash
# lib/runtime/extras.sh — First-party optional tools beyond core env tuning / chain.
#
# Special K, ReShade, Depth3D, Conty, FlawlessWidescreen, VR helpers, winetricks,
# block-internet, playtime, and related applies. Uses inject.sh for cache/track.

[[ -n "${LAUNCHLAYER_RUNTIME_EXTRAS_LOADED:-}" ]] && return 0
LAUNCHLAYER_RUNTIME_EXTRAS_LOADED=1

# --- Vulkan / capture / IPC layers (env) ------------------------------------

# apply_vkbasalt_config — Export VKBASALT_CONFIG_FILE / optional log level.
apply_vkbasalt_config() {
	[[ "${VKBASALT:-0}" == "1" ]] || return 0
	if [[ -n "${VKBASALT_CONFIG_FILE:-}" ]]; then
		export VKBASALT_CONFIG_FILE
		debug "VKBASALT_CONFIG_FILE=$VKBASALT_CONFIG_FILE"
	fi
	if [[ -n "${VKBASALT_LOG_LEVEL:-}" ]]; then
		export VKBASALT_LOG_LEVEL
		debug "VKBASALT_LOG_LEVEL=$VKBASALT_LOG_LEVEL"
	fi
}

# apply_lsfg_vk — Enable lsfg-vk; never ships Lossless Scaling DLL (user must own).
apply_lsfg_vk() {
	[[ "${LSFG_VK:-0}" == "1" ]] || return 0
	if ! optional_tool_installed lsfg-vk; then
		warn "LSFG_VK=1 but lsfg-vk not detected — install the Vulkan layer (GPLv3); requires owned Lossless Scaling on Steam"
		return 0
	fi
	# Typical enable: ENABLE_LSFGVK / LSFG_PROCESS — favor documented env when set.
	if [[ -n "${LSFG_PROCESS:-}" ]]; then
		export LSFG_PROCESS
	else
		export ENABLE_LSFGVK="${ENABLE_LSFGVK:-1}"
		export LSFG_PROCESS="${LSFG_PROCESS:-common}"
	fi
	[[ -n "${LSFG_CONFIG_FILE:-}" ]] && export LSFG_CONFIG_FILE
	debug "lsfg-vk enabled (Lossless Scaling DLL must be user-owned — see docs/third-party.md)"
	# Stacking note: combine carefully with MangoHud / vkBasalt / nested Gamescope.
	if [[ "${MANGOHUD:-0}" == "1" || "${VKBASALT:-0}" == "1" || "${GAMESCOPE:-0}" == "1" ]]; then
		debug "LSFG_VK with MangoHud/vkBasalt/Gamescope — layer order conflicts are possible; see docs/third-party.md"
	fi
}

# apply_discord_ipc — WDIB / discord-rpc bridge via known env or PATH marker.
apply_discord_ipc() {
	[[ "${DISCORD_IPC:-0}" == "1" ]] || return 0
	# Bridge is typically a Proton DLL or linux bridge; set PROTON_REMOTE_DEBUG_CMD is wrong.
	# Common: ENABLE_DISCORD_IPC / wine Discord IPC Bridge via WINEDLLOVERRIDES later.
	export DISCORD_IPC_BRIDGE=1
	debug "DISCORD_IPC=1 (ensure wine-discord-ipc-bridge / WDIB is installed — see docs/third-party.md)"
}

# --- Wine / Proton helpers --------------------------------------------------

# apply_winetricks_verbs — Run protontricks/winetricks before game (mutate prefix).
apply_winetricks_verbs() {
	local verbs appid tip prefix
	verbs="${WINETRICKS_VERBS:-}"
	[[ -n "$verbs" ]] || return 0
	appid="${steam_app_id:-}"
	[[ -n "$appid" ]] || {
		warn "WINETRICKS_VERBS set but no AppID — skipped"
		return 0
	}
	if [[ "${WINETRICKS_GUI:-0}" == "1" ]]; then
		if command_available protontricks; then
			debug "protontricks --gui $appid"
			protontricks --gui "$appid" || warn "protontricks GUI failed"
		elif command_available winetricks; then
			warn "WINETRICKS_GUI=1 without protontricks — use WINETRICKS_VERBS with silent verbs"
		fi
		return 0
	fi
	if command_available protontricks; then
		# shellcheck disable=SC2086
		protontricks -q "$appid" $verbs || warn "protontricks verbs failed: $verbs"
	elif command_available winetricks; then
		prefix=""
		if declare -f get_compatdata_path_for_appid >/dev/null 2>&1; then
			prefix="$(get_compatdata_path_for_appid "$appid" 2>/dev/null || true)"
			[[ -n "$prefix" && -d "$prefix/pfx" ]] && prefix="$prefix/pfx"
		fi
		[[ -z "$prefix" && -n "${WINEPREFIX:-}" && -d "${WINEPREFIX}" ]] && prefix="$WINEPREFIX"
		if [[ -n "$prefix" && -d "$prefix" ]]; then
			debug "winetricks fallback WINEPREFIX=$prefix verbs=$verbs"
			# shellcheck disable=SC2086
			WINEPREFIX="$prefix" winetricks -q $verbs || warn "winetricks verbs failed: $verbs"
		else
			warn "WINETRICKS_VERBS: protontricks missing and no resolvable WINEPREFIX/compatdata — skipped"
		fi
	else
		tip="$(tool_install_hint protontricks 2>/dev/null || true)"
		warn "WINETRICKS_VERBS set but protontricks/winetricks missing${tip:+ — $tip}"
	fi
}

# apply_winecfg_before — Optionally launch winecfg via protontricks.
apply_winecfg_before() {
	[[ "${WINECFG_BEFORE:-0}" == "1" ]] || return 0
	local appid="${steam_app_id:-}"
	[[ -n "$appid" ]] || return 0
	if command_available protontricks; then
		protontricks "$appid" winecfg || warn "winecfg via protontricks failed"
	else
		warn "WINECFG_BEFORE=1 but protontricks not installed"
	fi
}

# apply_registry_files — Apply REGISTRY_FILES (space-separated) into Proton prefix.
apply_registry_files() {
	local files appid f
	files="${REGISTRY_FILES:-}"
	[[ -n "$files" ]] || return 0
	appid="${steam_app_id:-}"
	[[ -n "$appid" ]] || return 0
	command_available protontricks || {
		warn "REGISTRY_FILES set but protontricks missing"
		return 0
	}
	for f in $files; do
		[[ -f "$f" ]] || {
			warn "REGISTRY_FILES: missing $f"
			continue
		}
		protontricks -q "$appid" regedit "$f" || warn "regedit failed: $f"
	done
}

# apply_wine_fsr — Structured Wine/Proton FSR env (WINE_FULLSCREEN_FSR*).
apply_wine_fsr() {
	[[ "${WINE_FSR:-0}" == "1" ]] || return 0
	export WINE_FULLSCREEN_FSR=1
	[[ -n "${WINE_FSR_STRENGTH:-}" ]] && export WINE_FULLSCREEN_FSR_STRENGTH="$WINE_FSR_STRENGTH"
	[[ -n "${WINE_FSR_MODE:-}" ]] && export WINE_FULLSCREEN_FSR_MODE="$WINE_FSR_MODE"
	debug "WINE_FULLSCREEN_FSR=1"
}

# --- Special K / ReShade / Depth3D ------------------------------------------

# apply_special_k — Phase A env + optional Phase B inject from SPECIAL_K_SOURCE.
apply_special_k() {
	[[ "${SPECIAL_K:-0}" == "1" ]] || return 0
	[[ "${is_native:-0}" == "1" && "${FORCE_PROTON:-0}" != "1" ]] && {
		warn "SPECIAL_K=1 on native game — Proton/Wine only"
		return 0
	}
	local dll="${SPECIAL_K_DLL:-dxgi}"
	local src="${SPECIAL_K_SOURCE:-}"
	local game_dir dest_name arch_dll

	inject_merge_winedlloverrides "$dll"
	dll="${dll%.dll}"

	if [[ -n "${SPECIAL_K_INI:-}" ]]; then
		inject_ensure_ini_key "$SPECIAL_K_INI" UsingWINE true
	fi

	# Phase B: copy from user/cache source into game dir when source set.
	if [[ -n "$src" ]]; then
		game_dir="$(inject_resolve_game_dir 2>/dev/null || true)"
		if [[ -z "$game_dir" ]]; then
			warn "SPECIAL_K_SOURCE set but game install dir not found"
		else
			arch_dll="SpecialK64.dll"
			[[ -f "$src/SpecialK32.dll" && ! -f "$src/SpecialK64.dll" ]] && arch_dll="SpecialK32.dll"
			[[ -f "$src/$arch_dll" ]] || arch_dll=""
			if [[ -z "$arch_dll" ]]; then
				# Accept already-named proxy in source dir
				if [[ -f "$src/${dll}.dll" ]]; then
					inject_copy_renamed "$src/${dll}.dll" "$game_dir" "${dll}.dll" "${steam_app_id:-}" specialk >/dev/null \
						|| warn "SPECIAL_K inject copy failed"
				else
					warn "SPECIAL_K_SOURCE missing SpecialK32/64.dll under $src"
				fi
			else
				dest_name="${dll}.dll"
				inject_copy_renamed "$src/$arch_dll" "$game_dir" "$dest_name" "${steam_app_id:-}" specialk >/dev/null \
					|| warn "SPECIAL_K inject copy failed"
			fi
		fi
	else
		debug "SPECIAL_K=1 without SPECIAL_K_SOURCE — expecting user-placed ${dll}.dll (Phase A)"
	fi

	# UsingWINE in default Document path when possible is game-specific; tip in docs.
	debug "SPECIAL_K enabled dll=$dll"
}

# apply_special_k_fetch — Optional release fetch into SPECIAL_K_SOURCE (mocked via LAUNCHLAYER_FETCH_CMD).
apply_special_k_fetch() {
	[[ "${SPECIAL_K_FETCH:-0}" == "1" ]] || return 0
	local dest ver url archive extracted dll_path
	ver="${SPECIAL_K_VERSION:-stable}"
	dest="$(inject_tool_cache_dir specialk)/$ver"
	mkdir -p "$dest"
	url="${SPECIAL_K_FETCH_URL:-}"
	if [[ -z "$url" ]]; then
		warn "SPECIAL_K_FETCH=1 requires SPECIAL_K_FETCH_URL (see docs/third-party.md) — no default redistrib mirror"
		return 0
	fi
	inject_store_notice specialk "$ver" "https://github.com/SpecialKO/SpecialK" "GPL-3.0" \
		"User-requested download. Source: $url"
	archive="$dest/package.bin"
	if ! inject_fetch_url "$url" "$archive"; then
		warn "SPECIAL_K_FETCH: download failed"
		return 0
	fi
	# Already extracted from a prior run?
	if [[ -f "$dest/extracted/SpecialK64.dll" || -f "$dest/extracted/SpecialK32.dll" ]]; then
		SPECIAL_K_SOURCE="$dest/extracted"
		export SPECIAL_K_SOURCE
		debug "SPECIAL_K_SOURCE=$SPECIAL_K_SOURCE (cache)"
		return 0
	fi
	# Loose DLL dropped next to archive (fetch cmd may copy DLLs directly)
	if [[ -f "$dest/SpecialK64.dll" || -f "$dest/SpecialK32.dll" ]]; then
		SPECIAL_K_SOURCE="$dest"
		export SPECIAL_K_SOURCE
		debug "SPECIAL_K_SOURCE=$SPECIAL_K_SOURCE"
		return 0
	fi
	extracted="$dest/extracted"
	rm -rf "$extracted"
	mkdir -p "$extracted"
	if ! inject_extract_archive "$archive" "$extracted"; then
		warn "SPECIAL_K_FETCH: could not extract $archive — set SPECIAL_K_SOURCE to a directory that already contains SpecialK64.dll"
		return 0
	fi
	dll_path="$(inject_find_file "$extracted" 'SpecialK64.dll' || true)"
	[[ -z "$dll_path" ]] && dll_path="$(inject_find_file "$extracted" 'SpecialK32.dll' || true)"
	if [[ -z "$dll_path" ]]; then
		warn "SPECIAL_K_FETCH: archive extracted but SpecialK32/64.dll not found under $extracted"
		return 0
	fi
	SPECIAL_K_SOURCE="$(dirname "$dll_path")"
	export SPECIAL_K_SOURCE
	debug "SPECIAL_K_SOURCE=$SPECIAL_K_SOURCE"
}

# apply_reshade — Standalone Wine ReShade local inject.
apply_reshade() {
	[[ "${RESHADE:-0}" == "1" ]] || return 0
	local dll="${RESHADE_DLL:-dxgi}"
	local src="${RESHADE_SOURCE:-}"
	local game_dir
	inject_merge_winedlloverrides "$dll"
	dll="${dll%.dll}"
	if [[ -n "$src" ]]; then
		game_dir="$(inject_resolve_game_dir 2>/dev/null || true)"
		if [[ -n "$game_dir" && -f "$src/${dll}.dll" ]]; then
			inject_copy_renamed "$src/${dll}.dll" "$game_dir" "${dll}.dll" "${steam_app_id:-}" reshade >/dev/null \
				|| warn "RESHADE inject failed"
		elif [[ -n "$game_dir" && -f "$src/ReShade64.dll" ]]; then
			inject_copy_renamed "$src/ReShade64.dll" "$game_dir" "${dll}.dll" "${steam_app_id:-}" reshade >/dev/null \
				|| warn "RESHADE inject failed"
		else
			warn "RESHADE=1: set RESHADE_SOURCE to a dir with ReShade DLL (BSD-3-Clause — see docs/third-party.md)"
		fi
	fi
	debug "RESHADE enabled dll=$dll"
}

# apply_reshade_with_special_k — SK + ReShade cohabitation tip / overrides.
apply_reshade_with_special_k() {
	[[ "${SPECIAL_K:-0}" == "1" && "${RESHADE:-0}" == "1" ]] || return 0
	[[ -n "${RESHADE_SK_VERSION:-}" ]] && debug "RESHADE_SK_VERSION=$RESHADE_SK_VERSION (pin for SK cohab)"
}

# apply_optiscaler — Install a user-supplied OptiScaler DLL as one proxy provider.
apply_optiscaler() {
	[[ "${OPTISCALER:-0}" == "1" ]] || return 0
	if [[ "${is_anticheat:-0}" == "1" || -n "${anticheat_type:-}" ]]; then
		warn "OPTISCALER=1 blocked for anti-cheat/online safety"
		return 0
	fi
	local proxy="${OPTISCALER_PROXY:-dxgi}" src="${OPTISCALER_SOURCE:-}"
	local game_dir source_dll
	proxy="${proxy,,}"
	[[ "$proxy" == *.dll ]] && proxy="${proxy%.dll}"
	case "${proxy,,}" in
		dxgi|winmm|version|dbghelp|d3d12|wininet|winhttp|optiscaler|optiscaler.asi) ;;
		*)
			warn "OPTISCALER_PROXY=$proxy unsupported"
			return 0
			;;
	esac
	[[ -n "$src" ]] || {
		warn "OPTISCALER=1 requires user-supplied OPTISCALER_SOURCE"
		return 0
	}
	game_dir="$(inject_resolve_game_dir 2>/dev/null || true)"
	[[ -n "$game_dir" ]] || {
		warn "OPTISCALER=1: game dir not found"
		return 0
	}
	if [[ -f "$src" ]]; then
		source_dll="$src"
	else
		source_dll="$src/OptiScaler.dll"
		[[ -f "$source_dll" ]] || source_dll="$src/OptiScaler.asi"
	fi
	[[ -f "$source_dll" ]] || {
		warn "OPTISCALER_SOURCE missing OptiScaler.dll/OptiScaler.asi"
		return 0
	}
	local dest_name="${proxy}.dll"
	if [[ "$proxy" == optiscaler.asi ]]; then
		dest_name=OptiScaler.asi
	else
		inject_merge_winedlloverrides "$proxy"
	fi
	inject_copy_renamed "$source_dll" "$game_dir" "$dest_name" "${steam_app_id:-}" optiscaler >/dev/null \
		|| warn "OptiScaler inject failed"
	if [[ -n "${OPTISCALER_CONFIG:-}" && -f "${OPTISCALER_CONFIG}" ]]; then
		inject_copy_renamed "$OPTISCALER_CONFIG" "$game_dir" OptiScaler.ini "${steam_app_id:-}" optiscaler >/dev/null \
			|| warn "OptiScaler config copy failed"
	fi
	debug "OptiScaler enabled proxy=$dest_name"
}

# apply_depth3d — Depth3D shader path (assist-only; optional user-supplied DEPTH3D_FETCH_URL).
apply_depth3d() {
	[[ "${DEPTH3D:-0}" == "1" ]] || return 0
	local src="${DEPTH3D_SOURCE:-}"
	local url="${DEPTH3D_FETCH_URL:-}"
	local dest archive extracted
	if [[ -z "$src" ]]; then
		src="$(inject_tool_cache_dir depth3d)/shaders"
	fi
	if [[ -n "$url" && ! -d "$src" ]]; then
		dest="$(inject_tool_cache_dir depth3d)"
		mkdir -p "$dest"
		inject_store_notice depth3d user "https://github.com/BlueSkyDefender/Depth3D" "per-author" \
			"User-requested DEPTH3D_FETCH_URL=$url — retain shader author notices"
		archive="$dest/shaders.bin"
		if inject_fetch_url "$url" "$archive"; then
			extracted="$dest/extracted"
			rm -rf "$extracted"
			mkdir -p "$extracted"
			if inject_extract_archive "$archive" "$extracted"; then
				src="$extracted"
			else
				warn "DEPTH3D_FETCH_URL: extract failed — place shaders under $src"
			fi
		fi
	fi
	if [[ -d "$src" ]]; then
		export DEPTH3D_SHADER_PATH="$src"
		debug "DEPTH3D_SHADER_PATH=$src (assist-only — wire into ReShade manually)"
	else
		warn "DEPTH3D=1: place shaders under $src or set DEPTH3D_SOURCE / DEPTH3D_FETCH_URL (assist-only; do not vendor third-party shaders)"
	fi
}

# apply_skif — Optional SKIF path; SKIF_LAUNCH=1 may one-shot via protontricks-launch.
apply_skif_hint() {
	[[ "${SKIF:-0}" == "1" ]] || return 0
	local skif="${SKIF_PATH:-}"
	if [[ -z "$skif" ]]; then
		warn "SKIF=1: set SKIF_PATH to SKIF.exe; launch via Proton outside the Steam %command% chain when possible"
		return 0
	fi
	[[ -f "$skif" ]] || {
		warn "SKIF_PATH not found: $skif"
		return 0
	}
	debug "SKIF_PATH=$skif (Windows GUI — docs/third-party.md)"
	if [[ "${SKIF_LAUNCH:-0}" == "1" ]]; then
		if command_available protontricks-launch && [[ -n "${steam_app_id:-}" ]]; then
			debug "SKIF_LAUNCH=1 — starting SKIF via protontricks-launch"
			protontricks-launch --appid "$steam_app_id" "$skif" &
		else
			warn "SKIF_LAUNCH=1 needs protontricks-launch and AppID — skipped"
		fi
	fi
}

# apply_valveplug — Assist only when targeting a Windows Steam client layout.
apply_valveplug() {
	[[ "${VALVEPLUG:-0}" == "1" ]] || return 0
	local steam_dir="${VALVEPLUG_STEAM_DIR:-}"
	local src="${VALVEPLUG_SOURCE:-}"
	# Native Linux Steam: ValvePlug does not apply.
	if [[ "$(uname -s)" == Linux ]] && [[ -z "$steam_dir" ]]; then
		warn "VALVEPLUG=1: ValvePlug targets Windows Steam clients (archived). On Linux Steam use Controller settings instead — see docs/third-party.md"
		return 0
	fi
	[[ -n "$src" && -f "$src/XInput1_4.dll" && -n "$steam_dir" ]] || {
		warn "VALVEPLUG=1 requires VALVEPLUG_SOURCE/XInput1_4.dll and VALVEPLUG_STEAM_DIR"
		return 0
	}
	inject_copy_renamed "$src/XInput1_4.dll" "$steam_dir" "XInput1_4.dll" "steam" valveplug >/dev/null \
		|| warn "ValvePlug copy failed"
}

# --- FlawlessWidescreen / Conty / specialty / VR / net / playtime ------------

# apply_flawless_widescreen — Co-launch FWS when FLAWLESS_WIDESCREEN / FWS=1 (no automated redistrib).
apply_flawless_widescreen() {
	[[ "${FLAWLESS_WIDESCREEN:-0}" == "1" || "${FWS:-0}" == "1" ]] || return 0
	local bin="${FWS_PATH:-}"
	if [[ -z "$bin" ]]; then
		bin="$(command -v FlawlessWidescreen.exe 2>/dev/null || true)"
	fi
	if [[ -z "$bin" ]]; then
		inject_refuse_proprietary_redistrib FlawlessWidescreen "proprietary freeware — provide FWS_PATH"
		return 0
	fi
	export FWS_PATH="$bin"
	debug "FlawlessWidescreen path=$bin"
	# Ensure vcrun2010 when user did not already list it in WINETRICKS_VERBS.
	if [[ "${WINETRICKS_VERBS:-}" != *vcrun2010* ]]; then
		if [[ -z "${WINETRICKS_VERBS:-}" ]]; then
			WINETRICKS_VERBS="vcrun2010"
		else
			WINETRICKS_VERBS="${WINETRICKS_VERBS} vcrun2010"
		fi
		export WINETRICKS_VERBS
		debug "FWS: added vcrun2010 to WINETRICKS_VERBS"
	fi
	# Soft co-start: only when PRE_LAUNCH_CMD empty (never stomp user hooks).
	if [[ "${FWS_COLAUNCH:-1}" == "1" ]]; then
		if [[ -n "${PRE_LAUNCH_CMD:-}" ]]; then
			warn "FWS_COLAUNCH=1 but PRE_LAUNCH_CMD already set — not overriding; start FWS manually"
		elif command_available protontricks-launch && [[ -n "${steam_app_id:-}" ]]; then
			# PRE_LAUNCH_CMD is eval'd by run_pre_launch_cmd; embedded quotes protect $bin.
			# shellcheck disable=SC2089
			PRE_LAUNCH_CMD="protontricks-launch --appid ${steam_app_id} \"$bin\" &"
			# shellcheck disable=SC2090
			export PRE_LAUNCH_CMD
			debug "PRE_LAUNCH_CMD set for FWS co-launch"
		else
			warn "FWS_COLAUNCH=1 needs protontricks-launch and AppID — skipped"
		fi
	fi
}

# resolve_conty_bin — Print conty binary if Conty wrap enabled.
resolve_conty_bin() {
	[[ "${CONTY:-0}" == "1" ]] || return 1
	if command_available conty; then
		printf '%s' conty
		return 0
	fi
	[[ -n "${CONTY_PATH:-}" && -x "${CONTY_PATH}" ]] && {
		printf '%s' "$CONTY_PATH"
		return 0
	}
	return 1
}

# resolve_obs_vkcapture_bin — obs-gamecapture or obs-vkcapture.
resolve_obs_vkcapture_bin() {
	[[ "${OBS_VKCAPTURE:-0}" == "1" ]] || return 1
	if command_available obs-gamecapture; then
		printf '%s' obs-gamecapture
		return 0
	fi
	if command_available obs-vkcapture; then
		printf '%s' obs-vkcapture
		return 0
	fi
	return 1
}

# resolve_replay_bin — ReplaySorcery or gpu-screen-recorder wrapper preference.
resolve_replay_bin() {
	[[ "${REPLAY_CAPTURE:-0}" == "1" ]] || return 1
	local prefer="${REPLAY_TOOL:-auto}"
	case "$prefer" in
		gpu-screen-recorder|gsr)
			command_available gpu-screen-recorder && {
				printf '%s' gpu-screen-recorder
				return 0
			}
			;;
		replay-sorcery|replaysorcery)
			command_available replay-sorcery && {
				printf '%s' replay-sorcery
				return 0
			}
			;;
		auto|*)
			if command_available gpu-screen-recorder; then
				printf '%s' gpu-screen-recorder
				return 0
			fi
			if command_available replay-sorcery; then
				printf '%s' replay-sorcery
				return 0
			fi
			;;
	esac
	return 1
}

# resolve_discord_ipc_bin — Optional PATH wrapper for Discord IPC.
resolve_discord_ipc_bin() {
	[[ "${DISCORD_IPC:-0}" == "1" ]] || return 1
	command_available discord-ipc-bridge && {
		printf '%s' discord-ipc-bridge
		return 0
	}
	command_available wine-discord-ipc-bridge && {
		printf '%s' wine-discord-ipc-bridge
		return 0
	}
	return 1
}

# apply_block_internet — Attempt network isolation (best-effort; needs privileges).
apply_block_internet() {
	[[ "${BLOCK_INTERNET:-0}" == "1" ]] || return 0
	# Prefer unshare -n when available (user namespaces); otherwise warn.
	if command_available unshare && unshare -n true 2>/dev/null; then
		export LAUNCHLAYER_BLOCK_INTERNET_WRAP=unshare
		debug "BLOCK_INTERNET=1 — chain will prepend unshare -n -r when supported"
	else
		warn "BLOCK_INTERNET=1: unshare -n not available — install iproute/util-linux user namespaces or use a firewall wrapper"
	fi
}

# apply_openvr_api_provider — Tracked openvr_api.dll and optional config swap.
apply_openvr_api_provider() {
	local provider=$1 src=$2 config_name=${3:-}
	local game_dir api
	game_dir="$(inject_resolve_game_dir 2>/dev/null || true)"
	[[ -n "$game_dir" ]] || {
		warn "$provider: game dir not found"
		return 0
	}
	api="$(find "$game_dir" -name 'openvr_api.dll' 2>/dev/null | head -1 || true)"
	[[ -n "$api" ]] || {
		warn "$provider: no openvr_api.dll under game dir"
		return 0
	}
	if [[ -f "$src/openvr_api.dll" ]]; then
		inject_copy_renamed "$src/openvr_api.dll" "$(dirname "$api")" openvr_api.dll \
			"${steam_app_id:-}" "$provider" >/dev/null || warn "$provider DLL copy failed"
		if [[ -n "$config_name" && -f "$src/$config_name" ]]; then
			inject_copy_renamed "$src/$config_name" "$(dirname "$api")" "$config_name" \
				"${steam_app_id:-}" "$provider" >/dev/null || warn "$provider config copy failed"
		fi
		debug "$provider installed over $api"
	else
		warn "$provider: place openvr_api.dll under $src (see docs/third-party.md)"
	fi
}

# apply_openvr_fsr — Tracked openvr_api.dll swap when enabled.
apply_openvr_fsr() {
	[[ "${OPENVR_FSR:-0}" == "1" ]] || return 0
	apply_openvr_api_provider openvr_fsr \
		"${OPENVR_FSR_SOURCE:-$(inject_tool_cache_dir openvr_fsr)}" openvr_mod.cfg
}

# apply_opencomposite — Replace a game's OpenVR client with OpenComposite.
apply_opencomposite() {
	[[ "${OPENCOMPOSITE:-0}" == "1" ]] || return 0
	local source_dir="${OPENCOMPOSITE_SOURCE:-}"
	[[ -n "$source_dir" ]] || {
		warn "OPENCOMPOSITE=1 requires user-supplied OPENCOMPOSITE_SOURCE"
		return 0
	}
	apply_openvr_api_provider opencomposite "$source_dir" opencomposite.ini
}

# apply_geo11 — Assist-only: Geo-11 stereo path/env marker (no DLL inject).
apply_geo11() {
	[[ "${GEO11:-0}" == "1" ]] || return 0
	local src="${GEO11_SOURCE:-$(inject_tool_cache_dir geo11)}"
	export GEO11_PATH="$src"
	debug "GEO11=1 assist-only path=$src (install Geo-11 yourself — see docs/third-party.md)"
	[[ -d "$src" ]] || warn "GEO11=1: set GEO11_SOURCE to your Geo-11 install (assist-only; LaunchLayer does not inject)"
	[[ "${GEO11_SBS_VR:-0}" == "1" ]] && export SBS_VR=1
}

# apply_sbs_vr — Assist-only: side-by-side VR companion markers (does not start player).
apply_sbs_vr() {
	[[ "${SBS_VR:-0}" == "1" ]] || return 0
	if ! command_available lsusb && [[ "${SBS_VR_REQUIRE_HMD:-1}" == "1" ]]; then
		debug "SBS_VR: lsusb missing — skipping HMD probe"
	elif [[ "${SBS_VR_REQUIRE_HMD:-1}" == "1" ]] && command_available lsusb; then
		if ! lsusb 2>/dev/null | grep -qiE 'HTC|Oculus|Valve|Virtual Reality|VIVE|Index|Pico'; then
			warn "SBS_VR=1: no HMD detected via lsusb — continuing (set SBS_VR_REQUIRE_HMD=0 to silence)"
		fi
	fi
	export SBS_VR_PLAYER="${SBS_VR_PLAYER:-vr-video-player}"
	debug "SBS_VR=1 assist-only player hint=$SBS_VR_PLAYER (start externally)"
}

# apply_flat2vr — Assist-only: Flat2VR UE4 path hint (no inject).
apply_flat2vr() {
	[[ "${FLAT2VR:-0}" == "1" ]] || return 0
	local src="${FLAT2VR_SOURCE:-$(inject_tool_cache_dir flat2vr)}"
	export FLAT2VR_PATH="$src"
	debug "FLAT2VR=1 assist-only path=$src"
	[[ -d "$src" ]] || warn "FLAT2VR=1: set FLAT2VR_SOURCE (assist-only; LaunchLayer does not inject)"
}

# apply_specialty_runtime — Boxtron / Luxtorpeda / Roberta markers for OVERRIDE_PROTON.
apply_specialty_runtime() {
	case "${SPECIALTY_RUNTIME:-}" in
		boxtron|BOXTRON)
			: "${OVERRIDE_PROTON:=boxtron}"
			debug "SPECIALTY_RUNTIME=boxtron"
			;;
		luxtorpeda|LUXTORPEDA)
			: "${OVERRIDE_PROTON:=Luxtorpeda}"
			debug "SPECIALTY_RUNTIME=luxtorpeda"
			;;
		roberta|ROBERTA)
			: "${OVERRIDE_PROTON:=roberta}"
			debug "SPECIALTY_RUNTIME=roberta"
			;;
		"") ;;
		*)
			warn "SPECIALTY_RUNTIME=${SPECIALTY_RUNTIME} unknown (boxtron|luxtorpeda|roberta)"
			;;
	esac
}

# playtime_log_path — Playtime log file.
playtime_log_path() {
	printf '%s/playtime.log' "${STATE_DIR}"
}

# playtime_record_start — Record session start epoch when PLAYTIME_LOG=1.
playtime_record_start() {
	[[ "${PLAYTIME_LOG:-0}" == "1" ]] || return 0
	LAUNCHLAYER_PLAYTIME_START="$(date +%s)"
	export LAUNCHLAYER_PLAYTIME_START
}

# playtime_record_end — Append netto seconds to playtime.log.
playtime_record_end() {
	local end start dur appid
	[[ "${PLAYTIME_LOG:-0}" == "1" ]] || return 0
	start="${LAUNCHLAYER_PLAYTIME_START:-}"
	[[ -n "$start" ]] || return 0
	end="$(date +%s)"
	dur=$((end - start))
	appid="${steam_app_id:-unknown}"
	mkdir -p "$(dirname "$(playtime_log_path)")"
	printf '%s appid=%s seconds=%s\n' "$(date -Iseconds)" "$appid" "$dur" >> "$(playtime_log_path)"
}

# crash_guess_maybe_prompt — Opt-in short retry prompt after non-zero exit.
crash_guess_maybe_prompt() {
	local code=$1
	[[ "${CRASH_GUESS:-0}" == "1" ]] || return 0
	(( code != 0 )) || return 0
	[[ -t 0 && -t 1 ]] || return 0
	local timeout="${CRASH_GUESS_TIMEOUT:-}"
	# CRASH_GUESS=1 with unset/0 timeout defaults to 5s (not STL wait-menu).
	if [[ -z "$timeout" || "$timeout" == "0" ]]; then
		timeout=5
	fi
	local ans=""
	read -r -t "$timeout" -p "LaunchLayer: exit $code — retry? [y/N] " ans || true
	[[ "${ans,,}" == y* ]] || return 0
	warn "CRASH_GUESS retry requested — re-invoke from Steam or CLI"
}

# apply_launch_extras_pre — Extra applies before chain build / wine mutate steps.
apply_launch_extras_pre() {
	apply_vkbasalt_config
	apply_lsfg_vk
	apply_discord_ipc
	apply_specialty_runtime
	apply_wine_fsr
	apply_special_k_fetch
	apply_block_internet
	apply_depth3d
	apply_skif_hint
}

# apply_launch_extras_inject — Game-dir mutating steps (after game dir resolvable).
apply_launch_extras_inject() {
	local conflict
	conflict="$(inject_provider_conflict_errors)"
	if [[ -n "$conflict" ]]; then
		while IFS= read -r conflict; do warn "$conflict"; done <<< "$conflict"
		return 1
	fi
	apply_special_k
	apply_reshade
	apply_reshade_with_special_k
	apply_optiscaler
	apply_valveplug
	apply_flawless_widescreen
	apply_openvr_fsr
	apply_opencomposite
	apply_geo11
	apply_sbs_vr
	apply_flat2vr
}

# apply_launch_extras_wine — Prefix tools before exec.
apply_launch_extras_wine() {
	apply_winetricks_verbs
	apply_winecfg_before
	apply_registry_files
}
