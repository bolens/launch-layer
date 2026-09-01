# shellcheck shell=bash
# lib/steam/detect.sh — Native/anticheat/engine heuristics and game flag resolution.

[[ -n "${LAUNCHLAYER_STEAM_DETECT_LOADED:-}" ]] && return 0
LAUNCHLAYER_STEAM_DETECT_LOADED=1

# game_dir_has_native_launcher — True when a Steam/Linux launcher script is present.
game_dir_has_native_launcher() {
	local game_dir=$1
	[[ -f "$game_dir/launcher.sh" || -f "$game_dir/start.sh" || -f "$game_dir/run.sh" ]]
}

# detect_native_game — Heuristic: should this title run without Proton?
#
# Priority:
#   FORCE_PROTON=1  → always false
#   FORCE_NATIVE=1  → always true
#   native-appids.txt membership
#   launcher.sh / start.sh / run.sh (before .exe check)
#   ELF executable without root-level .exe
detect_native_game() {
	local appid=${1:-$steam_app_id}
	local use_heuristic=${2:-1}
	local game_dir

	[[ "${FORCE_PROTON:-0}" == "1" ]] && return 1
	[[ "${FORCE_NATIVE:-0}" == "1" ]] && return 0
	[[ -n "$appid" ]] || return 1

	appid_in_list_file "$appid" "$LAUNCHD_DIR/native-appids.txt" && return 0
	[[ "$use_heuristic" == "0" ]] && return 1

	game_dir="$(get_game_dir_for_appid "$appid" 2>/dev/null || true)"
	[[ -n "$game_dir" ]] || return 1

	if game_dir_has_native_launcher "$game_dir"; then
		return 0
	fi

	# Root-level Windows executables suggest Proton (ignore nested tool/redist exes).
	if find "$game_dir" -maxdepth 1 -iname '*.exe' -print -quit 2>/dev/null | grep -q .; then
		return 1
	fi

	if find "$game_dir" -maxdepth 2 -type f -perm /111 -print0 2>/dev/null \
		| xargs -0 file 2>/dev/null | grep -q 'ELF.*executable'; then
		return 0
	fi
	return 1
}

# detect_anticheat_in_list — True when AppID is listed in anticheat-appids.txt.
detect_anticheat_in_list() {
	local appid=${1:-$steam_app_id}
	[[ -n "$appid" ]] || return 1
	appid_in_list_file "$appid" "$LAUNCHD_DIR/anticheat-appids.txt"
}

# _detect_anticheat_markers — Return battleye, eac, or empty from install dir markers.
_detect_anticheat_markers() {
	local game_dir=$1
	[[ -n "$game_dir" && -d "$game_dir" ]] || return 0

	if find "$game_dir" -maxdepth 4 \( \
		-type d -iname 'BattlEye' -o -iname 'BEService.exe' \
		\) -print -quit 2>/dev/null | grep -q .; then
		echo battleye
		return 0
	fi
	if find "$game_dir" -maxdepth 3 \( \
		-type d -iname 'EasyAntiCheat' -o -type d -iname 'easyanticheat' \
		\) -print -quit 2>/dev/null | grep -q .; then
		echo eac
		return 0
	fi
	if find "$game_dir" -maxdepth 4 \( \
		-iname 'EasyAntiCheat_EOS.exe' -o -iname 'EasyAntiCheat_Setup.exe' \
		\) -print -quit 2>/dev/null | grep -q .; then
		echo eac
		return 0
	fi
}

# detect_anticheat_filesystem — True when EAC/BattlEye markers exist in the install dir.
detect_anticheat_filesystem() {
	local appid=${1:-$steam_app_id}
	local game_dir markers
	game_dir="$(get_game_dir_for_appid "$appid" 2>/dev/null || true)"
	markers="$(_detect_anticheat_markers "$game_dir")"
	[[ -n "$markers" ]]
}

# detect_anticheat_game — True when listed or install dir contains anticheat markers.
detect_anticheat_game() {
	local appid=${1:-$steam_app_id}
	detect_anticheat_in_list "$appid" && return 0
	detect_anticheat_filesystem "$appid"
}

# detect_anticheat_type — Return eac, battleye, listed, or empty string.
detect_anticheat_type() {
	local appid=${1:-$steam_app_id}
	local game_dir="" fs_type="" in_list=0

	game_dir="$(get_game_dir_for_appid "$appid" 2>/dev/null || true)"
	fs_type="$(_detect_anticheat_markers "$game_dir")"

	detect_anticheat_in_list "$appid" && in_list=1
	if [[ -n "$fs_type" ]]; then
		echo "$fs_type"
		return 0
	fi
	(( in_list )) && echo listed
	return 0
}

# _engine_collect_scan_roots — game_dir plus macOS .app bundle innards for marker scans.
_engine_collect_scan_roots() {
	local game_dir=$1 app
	printf '%s\n' "$game_dir"
	while IFS= read -r app; do
		[[ -d "$app/Contents" ]] || continue
		printf '%s\n' \
			"$app/Contents" \
			"$app/Contents/MacOS" \
			"$app/Contents/Frameworks" \
			"$app/Contents/Resources" \
			"$app/Contents/PlugIns"
	done < <(find "$game_dir" -maxdepth 2 -type d -name '*.app' 2>/dev/null)
}

# Engine rules issue many bounded find queries against the same tree. Build one
# depth-6 index and evaluate their small predicate grammar in Bash.
_ENGINE_INDEX_GAME_DIR=""
_ENGINE_INDEX_PATHS=()
_ENGINE_INDEX_NAMES=()
_ENGINE_INDEX_DEPTHS=()
_ENGINE_INDEX_TYPES=()
_ENGINE_INDEX_EXECS=()
_ENGINE_INDEX_COMPLETE=1

_engine_index_build() {
	local game_dir=$1 root path rel depth slashes type executable stop=0
	local max_entries=${LAUNCHLAYER_ENGINE_INDEX_MAX_ENTRIES:-50000}
	[[ "$max_entries" =~ ^[1-9][0-9]*$ ]] || max_entries=50000
	_ENGINE_INDEX_GAME_DIR="$game_dir"
	_ENGINE_INDEX_PATHS=()
	_ENGINE_INDEX_NAMES=()
	_ENGINE_INDEX_DEPTHS=()
	_ENGINE_INDEX_TYPES=()
	_ENGINE_INDEX_EXECS=()
	_ENGINE_INDEX_COMPLETE=1
	while IFS= read -r root; do
		[[ -d "$root" ]] || continue
		while IFS= read -r -d '' path; do
			if (( ${#_ENGINE_INDEX_PATHS[@]} >= max_entries )); then
				_ENGINE_INDEX_COMPLETE=0
				stop=1
				break
			fi
			if [[ "$path" == "$root" ]]; then
				rel=""
				depth=0
			else
				rel="${path#"$root"/}"
				slashes="${rel//[^\/]/}"
				depth=$(( ${#slashes} + 1 ))
			fi
			if [[ -d "$path" ]]; then
				type=d
			elif [[ -f "$path" ]]; then
				type=f
			else
				type=o
			fi
			executable=0
			[[ -x "$path" ]] && executable=1
			_ENGINE_INDEX_PATHS+=("$path")
			_ENGINE_INDEX_NAMES+=("${path##*/}")
			_ENGINE_INDEX_DEPTHS+=("$depth")
			_ENGINE_INDEX_TYPES+=("$type")
			_ENGINE_INDEX_EXECS+=("$executable")
		done < <(find "$root" -maxdepth 6 -print0 2>/dev/null)
		(( stop )) && break
	done < <(_engine_collect_scan_roots "$game_dir")
}

_engine_index_entry_matches() {
	local idx=$1
	shift
	local token pattern actual
	while (( $# > 0 )); do
		token=$1
		shift
		case "$token" in
			-type)
				(( $# > 0 )) || return 1
				[[ "${_ENGINE_INDEX_TYPES[$idx]}" == "$1" ]] || return 1
				shift
				;;
			-name|-iname|-path|-ipath)
				(( $# > 0 )) || return 1
				pattern=$1
				shift
				case "$token" in
					-name|-iname) actual="${_ENGINE_INDEX_NAMES[$idx]}" ;;
					*) actual="${_ENGINE_INDEX_PATHS[$idx]}" ;;
				esac
				if [[ "$token" == -iname || "$token" == -ipath ]]; then
					actual="${actual,,}"
					pattern="${pattern,,}"
				fi
				# shellcheck disable=SC2053 # Marker rules intentionally use find-style globs.
				[[ "$actual" == $pattern ]] || return 1
				;;
			-perm)
				(( $# > 0 )) || return 1
				[[ "$1" == /111 && "${_ENGINE_INDEX_EXECS[$idx]}" == 1 ]] || return 1
				shift
				;;
			*) return 1 ;;
		esac
	done
	return 0
}

# _engine_find — Query the shared engine index using the find predicates used below.
_engine_encode_clause() {
	local output_var=$1 item result=""
	shift
	for item in "$@"; do
		[[ -z "$result" ]] || result+=$'\034'
		result+="$item"
	done
	printf -v "$output_var" '%s' "$result"
}

_engine_find() {
	local game_dir=$1 maxdepth=$2
	shift 2
	[[ "$_ENGINE_INDEX_GAME_DIR" == "$game_dir" ]] || _engine_index_build "$game_dir"
	if [[ "$_ENGINE_INDEX_COMPLETE" != 1 ]]; then
		_engine_find_legacy "$game_dir" "$maxdepth" "$@"
		return $?
	fi

	local -a prefix=() clause=()
	local -a clauses=()
	local token in_group=0 encoded idx
	local -a predicate=()
	for token in "$@"; do
		case "$token" in
			'(') in_group=1 ;;
			')')
				if [[ ${#clause[@]} -gt 0 ]]; then
					_engine_encode_clause encoded "${clause[@]}"
					clauses+=("$encoded")
				fi
				clause=()
				in_group=0
				;;
			-o)
				_engine_encode_clause encoded "${clause[@]}"
				clauses+=("$encoded")
				clause=()
				;;
			*)
				if (( in_group )); then clause+=("$token"); else prefix+=("$token"); fi
				;;
		esac
	done
	if [[ ${#clauses[@]} -eq 0 ]]; then
		_engine_encode_clause encoded "${prefix[@]}"
		clauses+=("$encoded")
		prefix=()
	elif [[ ${#clause[@]} -gt 0 ]]; then
		_engine_encode_clause encoded "${clause[@]}"
		clauses+=("$encoded")
	fi

	for (( idx = 0; idx < ${#_ENGINE_INDEX_PATHS[@]}; idx++ )); do
		(( ${_ENGINE_INDEX_DEPTHS[$idx]} <= maxdepth )) || continue
		for encoded in "${clauses[@]}"; do
			IFS=$'\034' read -r -a predicate <<< "$encoded"
			_engine_index_entry_matches "$idx" "${prefix[@]}" "${predicate[@]}" && return 0
		done
	done
	return 1
}

_engine_find_legacy() {
	local game_dir=$1 maxdepth=$2 root
	shift 2
	while IFS= read -r root; do
		[[ -d "$root" ]] || continue
		find "$root" -maxdepth "$maxdepth" "$@" -print -quit 2>/dev/null | grep -q . && return 0
	done < <(_engine_collect_scan_roots "$game_dir")
	return 1
}

# _engine_has_packr_manifest — True when a Packr/libGDX launch json exists at install root.
_engine_has_packr_manifest() {
	local game_dir=$1 json
	for json in "$game_dir"/*.json; do
		[[ -f "$json" ]] || continue
		grep -q '"mainClass"' "$json" 2>/dev/null \
			&& grep -q '"classPath"' "$json" 2>/dev/null && return 0
	done
	return 1
}

# _detect_engine_markers — Return engine id from install dir markers, or empty.
_detect_engine_markers() {
	local game_dir=$1
	[[ -n "$game_dir" && -d "$game_dir" ]] || return 0
	_engine_index_build "$game_dir"

	# Source 2 (CS2, Dota 2, Half-Life: Alyx, etc.)
	if _engine_find "$game_dir" 4 -iname 'gameinfo.gi'; then
		echo source2
		return 0
	fi
	# Source 1 (TF2, Portal, L4D2, etc.)
	if _engine_find "$game_dir" 4 -iname 'gameinfo.txt'; then
		echo source
		return 0
	fi
	# Unreal Engine (UE4+ Engine/Binaries; UE3 sibling Binaries + Engine/Shaders; CookedPCConsole)
	if _engine_find "$game_dir" 3 -type d -path '*/Engine/Binaries' \
		|| { _engine_find "$game_dir" 3 -type d -path '*/Engine/Shaders' \
			&& _engine_find "$game_dir" 2 -type d -name 'Binaries'; } \
		|| _engine_find "$game_dir" 3 -type d -name 'CookedPCConsole'; then
		echo unreal
		return 0
	fi
	# Blizzard (Overwatch, Diablo — CASC storage + proprietary launcher stack)
	if _engine_find "$game_dir" 3 -iname 'Overwatch_loader.dll' \
		|| _engine_find "$game_dir" 2 -type d -path '*/cache/casc3' \
		|| { _engine_find "$game_dir" 2 -type d -name 'BlizzardBrowser' \
			&& _engine_find "$game_dir" 3 -iname 'vivoxsdk.dll'; }; then
		echo blizzard
		return 0
	fi
	# Solar2D / Corona (Coromon, etc.)
	if _engine_find "$game_dir" 4 \( \
		-iname 'CoronaLabs.Corona.Native.dll' -o -iname 'libcorona.so' \
		-o -iname 'libcorona.dylib' -o -iname 'resource.car' \
		\) \
		|| { _engine_find "$game_dir" 3 -iname 'CoronaLabs.Corona.Native.dll' \
			&& _engine_find "$game_dir" 3 -iname 'lua.dll'; }; then
		echo solar2d
		return 0
	fi
	# Defold (game.arcd + game.arci bundle, or dmengine runtime)
	if _engine_find "$game_dir" 3 \( -iname 'game.arcd' -o -iname 'game.dmanifest' \) \
		&& _engine_find "$game_dir" 3 -iname 'game.arci'; then
		echo defold
		return 0
	fi
	if _engine_find "$game_dir" 3 \( \
		-iname 'dmengine.exe' -o -iname 'dmengine' -o -iname 'dmengine_*' \
		-o -iname 'libdmengine.so' -o -iname 'libdmengine.dylib' \
		\); then
		echo defold
		return 0
	fi
	# Unity IL2CPP (before Unity — IL2CPP builds also ship UnityPlayer)
	if _engine_find "$game_dir" 3 \( \
		-iname 'GameAssembly.dll' -o -iname 'GameAssembly.so' -o -iname 'GameAssembly.dylib' \
		-o -type d -name 'il2cpp_data' \
		\); then
		echo unity-il2cpp
		return 0
	fi
	# Unity (Mono or native desktop builds)
	if _engine_find "$game_dir" 3 \( \
		-iname 'UnityPlayer.so' -o -iname 'UnityPlayer.dll' -o -iname 'UnityPlayer.dylib' \
		\); then
		echo unity
		return 0
	fi
	# Unity Windows/Proton exports (_Data bundle without root UnityPlayer)
	if _engine_find "$game_dir" 2 -type d -name '*_Data' \
		&& { _engine_find "$game_dir" 3 -path '*_Data/Managed/*' \
			|| _engine_find "$game_dir" 2 -path '*_Data/globalgamemanagers'; }; then
		echo unity
		return 0
	fi
	# Godot (shared libs, editor-style binary, or export bundle)
	if _engine_find "$game_dir" 3 \( \
		-iname 'libgodot*.so' -o -iname 'libgodot*.dylib' \
		-o -iname 'Godot*.exe' -o -iname 'Godot*.app' \
		-o -iname 'steamsdk-godot.dll' -o -iname 'libGodotFmod*.dll' \
		\); then
		echo godot
		return 0
	fi
	# Godot export heuristic: executable + .pck bundle(s) near install root
	if _engine_find "$game_dir" 2 -name '*.pck' \
		&& _engine_find "$game_dir" 1 -type f \( \
			-perm /111 -o -iname '*.exe' -o -iname '*.x86_64' -o -iname '*.app' \
			\) \
		&& [[ "$(find "$game_dir" -maxdepth 2 -name '*.pck' 2>/dev/null | wc -l)" -le 3 ]]; then
		echo godot
		return 0
	fi
	# Godot Windows export (companion .console.exe + Steam API wrapper)
	if _engine_find "$game_dir" 1 -iname '*.console.exe' \
		&& _engine_find "$game_dir" 1 -iname 'steam_api*.dll'; then
		echo godot
		return 0
	fi
	# CryEngine
	if _engine_find "$game_dir" 4 \( \
		-iname 'CryEngine.dll' -o -iname 'CrySystem.dll' -o -iname 'CryGame.dll' \
		-o -iname 'CryEngine.so' -o -iname 'CrySystem.so' -o -iname 'CryEngine.dylib' \
		\); then
		echo cryengine
		return 0
	fi
	# Frostbite (Battlefield, etc.)
	if _engine_find "$game_dir" 5 -type d -iname 'Frostbite' \
		|| _engine_find "$game_dir" 4 -iname 'Engine.BuildInfo*.dll'; then
		echo frostbite
		return 0
	fi
	# REDengine (Witcher, Cyberpunk)
	if _engine_find "$game_dir" 2 -type d -name 'r4game' \
		|| _engine_find "$game_dir" 5 \( \
			-iname 'REDEngine*.dll' -o -iname 'REDEngine*.so' -o -iname 'REDEngine*.dylib' \
			\); then
		echo redengine
		return 0
	fi
	# Creation Engine (Bethesda)
	if _engine_find "$game_dir" 2 -type d -name 'Data' \
		&& _engine_find "$game_dir" 2 \( -path '*/Data/*.ba2' -o -path '*/Data/*.bsa' \); then
		echo creation
		return 0
	fi
	# RAGE / Rockstar (GTA V, RDR2 — .rpf archives)
	if _engine_find "$game_dir" 5 -iname '*.rpf'; then
		echo rage
		return 0
	fi
	# Anvil / AnvilNext (Ubisoft — .forge archives)
	if _engine_find "$game_dir" 4 -iname '*.forge'; then
		echo anvil
		return 0
	fi
	# GameMaker Studio (Windows, Linux, and macOS exports)
	if _engine_find "$game_dir" 2 \( \
		-iname 'data.win' -o -iname 'game.unx' -o -iname 'game.ios' \
		\) \
		|| { _engine_find "$game_dir" 2 -iname 'options.ini' \
			&& _engine_find "$game_dir" 2 -iname 'audiogroup*.dat'; }; then
		echo gamemaker
		return 0
	fi
	# Ren'Py
	if _engine_find "$game_dir" 2 -type d -name 'renpy' \
		|| _engine_find "$game_dir" 2 -iname '*.rpa'; then
		echo renpy
		return 0
	fi
	# RPG Maker (XP/VX/Ace/MV/MZ) — before NW.js (MV/MZ uses NW.js runtime)
	if _engine_find "$game_dir" 4 -path '*/System/RPG_RT.exe' \
		|| _engine_find "$game_dir" 4 -path '*/www/js/rpg_managers.js' \
		|| _engine_find "$game_dir" 2 -iname 'Game.rpgproj'; then
		echo rpgmaker
		return 0
	fi
	# Electron (Chromium wrapper — common for indie/web-tech ports)
	if _engine_find "$game_dir" 4 \( \
		-path '*/resources/app.asar' -o -path '*/Resources/app.asar' \
		\); then
		echo electron
		return 0
	fi
	# NW.js (standalone Node-WebKit — not RPG Maker/Electron)
	if _engine_find "$game_dir" 3 \( \
		-iname 'nw.exe' -o -iname 'nw' -o -iname 'nwjs.exe' -o -iname 'nwjs' \
		-o -iname 'libnw.so' -o -iname 'libnw.dylib' -o -iname 'nw.dll' \
		-o -iname '*.nw' \
		\); then
		echo nwjs
		return 0
	fi
	# Custom C++ (PICO PARK — original HLSL/GFX shader tree, not Unity export)
	if _engine_find "$game_dir" 5 -path '*/resource/shader/hlsl/*' \
		&& _engine_find "$game_dir" 5 -path '*/resource/shader/gfx/*'; then
		echo custom-cpp
		return 0
	fi
	# Custom C++ (Farlands — glsl330 shaders + packed resources.dat)
	if _engine_find "$game_dir" 3 -path '*/shaders/glsl330/*' \
		&& _engine_find "$game_dir" 3 -path '*/res/resources.dat'; then
		echo custom-cpp
		return 0
	fi
	# HashLink / Haxe (Dead Cells, etc.)
	if _engine_find "$game_dir" 2 -iname 'hlboot.dat' \
		&& _engine_find "$game_dir" 2 \( \
			-iname 'libhl.so' -o -iname 'libhl.dylib' -o -iname 'detect.hl' \
			\); then
		echo hashlink
		return 0
	fi
	# SFML (Dreadmyst, etc.)
	if _engine_find "$game_dir" 3 \( \
		-iname 'sfml-graphics-2.dll' -o -iname 'sfml-graphics-2.so' \
		-o -iname 'sfml-window-2.dll' -o -iname 'sfml-window-2.so' \
		-o -iname 'sfml-system-2.dll' -o -iname 'sfml-system-2.so' \
		\); then
		echo sfml
		return 0
	fi
	# Serious Engine (Serious Sam Fusion — UserCfg.lua + .gro archives)
	if _engine_find "$game_dir" 2 -iname 'UserCfg.lua' \
		&& _engine_find "$game_dir" 2 -type d -name 'Content' \
		&& _engine_find "$game_dir" 3 -iname '*.gro'; then
		echo serious
		return 0
	fi
	# Hammerwatch / SSBD-style (TiltedEngine, res + Galaxy SDK, scenarios or PACKAGER)
	if _engine_find "$game_dir" 2 -iname 'TiltedEngine.dll' \
		|| { _engine_find "$game_dir" 2 -iname 'assets.bin' \
			&& _engine_find "$game_dir" 2 -iname 'Hammerwatch.bin.*'; } \
		|| { _engine_find "$game_dir" 2 -type d -name 'res' \
			&& _engine_find "$game_dir" 1 -iname 'libGalaxy64.so' \
			&& { _engine_find "$game_dir" 1 -iname 'PACKAGER' \
				|| _engine_find "$game_dir" 2 -type d -name 'scenarios' \
				|| _engine_find "$game_dir" 1 -type f -name 'HWR' -perm /111; }; }; then
		echo hammerwatch
		return 0
	fi
	# Titan Engine (Grim Dawn — Engine.dll + game/database layout)
	if _engine_find "$game_dir" 2 -iname 'Engine.dll' \
		&& _engine_find "$game_dir" 2 \( \
			-iname 'Grim Dawn.exe' -o -type d -name 'Database' \
			\); then
		echo titan
		return 0
	fi
	# Aleph One (Classic Marathon trilogy — alephone + scenario/map assets)
	if _engine_find "$game_dir" 2 \( \
		-type f -name 'alephone' -perm /111 -o -iname 'alephone.exe' \
		\) \
		&& _engine_find "$game_dir" 2 \( \
			-iname 'Map.scen' -o -iname 'Map.sceA' -o -iname 'classic_marathon_launcher' \
			-o -iname 'Coriolis Loop.sceA' \
			\); then
		echo alephone
		return 0
	fi
	# Buny engine (Star Wars: Bounty Hunter remaster — TangoPC + .buny archives)
	if _engine_find "$game_dir" 2 -iname 'TangoPC.exe' \
		&& _engine_find "$game_dir" 2 -iname 'data.buny'; then
		echo buny
		return 0
	fi
	# No Man's Sky (GAMEDATA + Binaries layout)
	if _engine_find "$game_dir" 1 -type d -name 'GAMEDATA' \
		&& _engine_find "$game_dir" 1 -type d -name 'Binaries'; then
		echo nms
		return 0
	fi
	# .NET desktop (MAUI games, SkiaSharp utilities)
	if _engine_find "$game_dir" 3 -iname 'Microsoft.Maui.Controls.resources.dll' \
		|| { _engine_find "$game_dir" 2 -iname 'libSkiaSharp.so' \
			&& _engine_find "$game_dir" 2 -iname 'libHarfBuzzSharp.so'; }; then
		echo dotnet
		return 0
	fi
	# Haemimont native (Victor Vran — Packs + SDL2 + title binary)
	if _engine_find "$game_dir" 1 -type d -name 'Packs' \
		&& _engine_find "$game_dir" 1 -iname 'libSDL2*' \
		&& _engine_find "$game_dir" 1 -type f -name 'VictorVran' -perm /111; then
		echo custom-cpp
		return 0
	fi
	# GDevelop (gdjs HTML5 runtime)
	if _engine_find "$game_dir" 5 \( \
		-path '*/gdjs-*/Runtime/*' -o -path '*/gdjs/Runtime/*' \
		-o -iname 'libGD*.so' -o -iname 'libGD*.dylib' \
		\); then
		echo gdevelop
		return 0
	fi
	# MonoGame / FNA / XNA / OpenFL
	if _engine_find "$game_dir" 4 \( \
		-iname 'MonoGame.Framework.dll' -o -iname 'MonoGame.Framework.dll.so' \
		-o -iname 'FNA.dll' -o -iname 'FNA.dll.so' -o -iname 'FNA3D.dll' \
		-o -iname 'libFNA.so' -o -iname 'libFNA.dylib' \
		-o -iname 'liblime*.so' -o -iname 'liblime*.dylib' -o -iname 'libopenfl*.so' \
		-o -iname 'libopenfl*.dylib' -o -iname 'lime.ndll' \
		\); then
		echo monogame
		return 0
	fi
	if _engine_find "$game_dir" 3 -type d -name 'Content' \
		&& _engine_find "$game_dir" 4 -path '*/Content/*.xnb'; then
		echo monogame
		return 0
	fi
	# MonoGame / XNA (.spritefont assets — Touhou Crawl, etc.)
	if _engine_find "$game_dir" 4 -iname '*.spritefont'; then
		echo monogame
		return 0
	fi
	# Cocos2d-x
	if _engine_find "$game_dir" 4 \( \
		-iname 'libcocos2d*.so' -o -iname 'libcocos2d*.dylib' -o -iname 'cocos2d.dll' \
		\); then
		echo cocos2d
		return 0
	fi
	# libGDX / Packr (Kakele Online and similar JRE-bundled jar launches)
	if [[ -d "$game_dir/jre" ]] \
		&& _engine_find "$game_dir" 1 -iname '*.jar' \
		&& _engine_has_packr_manifest "$game_dir"; then
		echo libgdx
		return 0
	fi
	if _engine_find "$game_dir" 4 \( \
		-iname 'gdx*.jar' -o -path '*/libs/gdx*.jar' -o -path '*/libgdx*.jar' \
		\); then
		echo libgdx
		return 0
	fi
	# Java / LWJGL (bundled JRE launchers — Minecraft, etc.)
	if _engine_find "$game_dir" 6 \( \
		-path '*/runtime/*/bin/java' -o -path '*/runtime/bin/java' \
		-o -path '*/jre/bin/java' -o -path '*/lib/lwjgl*.jar' \
		-o -iname 'lwjgl*.jar' -o -path '*/libraries/org/lwjgl/*' \
		\); then
		echo java
		return 0
	fi
	# Clickteam Fusion
	if _engine_find "$game_dir" 3 \( \
		-iname '*.ccn' -o -path '*/Extensions/*.mfx' -o -iname 'Fusion*.exe' \
		\); then
		echo fusion
		return 0
	fi
	# Panda3D
	if _engine_find "$game_dir" 4 \( \
		-iname 'libpanda*.so' -o -iname 'libpanda*.dylib' -o -iname 'panda3d.dll' \
		-o -iname 'libpanda*.dll' \
		\); then
		echo panda3d
		return 0
	fi
	# Torque Game Engine
	if _engine_find "$game_dir" 3 \( \
		-iname 'torque.exe' -o -iname 'torque' -o -iname 'libtorque*.so' \
		-o -iname 'libtorque*.dylib' -o -iname 'TorqueGame.exe' \
		\) \
		|| { _engine_find "$game_dir" 2 -name 'main.cs' \
			&& _engine_find "$game_dir" 3 -iname '*torque*'; }; then
		echo torque
		return 0
	fi
	# LÖVE
	if _engine_find "$game_dir" 3 \( \
		-iname 'love.dll' -o -iname 'love.so' -o -iname 'love.dylib' -o -iname '*.love' \
		\); then
		echo love2d
		return 0
	fi
	# Adobe AIR (legacy desktop ports)
	if _engine_find "$game_dir" 4 -path '*/META-INF/AIR/application.xml' \
		|| _engine_find "$game_dir" 3 -type d -path '*/META-INF/AIR'; then
		echo adobe-air
		return 0
	fi
	# Build Engine (Duke Nukem 3D, Blood, etc.)
	if _engine_find "$game_dir" 2 -iname '*.grp'; then
		echo build
		return 0
	fi
	# id Tech (Quake/Doom classic — pk3/pk4 archives)
	if _engine_find "$game_dir" 2 \( -iname '*.pk4' -o -iname '*.pk3' \); then
		echo idtech
		return 0
	fi
	# ScummVM-packaged titles
	if _engine_find "$game_dir" 3 \( \
		-iname 'scummvm.exe' -o -iname 'scummvm' -o -iname 'scummvm*.AppImage' \
		-o -iname 'ScummVM.app' \
		\); then
		echo scummvm
		return 0
	fi
	# DOSBox (classic DOS re-releases — TES Arena, etc.)
	if _engine_find "$game_dir" 3 \( \
		-iname 'DOSBox.exe' -o -iname 'dosbox.exe' -o -iname 'dosbox' \
		\) \
		|| _engine_find "$game_dir" 2 -type d -iname 'DOSBox*'; then
		echo dosbox
		return 0
	fi
	# OGRE (Torchlight II, etc. — CEGUI + OctreeSceneManager render plugin)
	if _engine_find "$game_dir" 3 \( \
		-iname 'RenderSystem_GL.so' -o -iname 'RenderSystem_GL.dll' \
		-o -iname 'RenderSystem_Direct3D9.dll' \
		\) \
		&& _engine_find "$game_dir" 3 \( \
			-iname 'Plugin_OctreeSceneManager.so' -o -iname 'Plugin_OctreeSceneManager.dll' \
			-o -iname 'libCEGUIFalagardWRBase.so' -o -iname 'libCEGUIFalagardWRBase.dll' \
			\); then
		echo ogre
		return 0
	fi
	# SDL2 + FMOD (custom indie stack — KarmaZoo, etc.)
	if _engine_find "$game_dir" 2 \( \
		-iname 'SDL2.dll' -o -iname 'SDL2.so' -o -iname 'libSDL2*.so' -o -iname 'libSDL2*.dylib' \
		\) \
		&& _engine_find "$game_dir" 2 \( \
			-iname 'fmodstudio.dll' -o -iname 'fmodstudioL.dll' \
			-o -iname 'libfmodstudio.so' -o -iname 'libfmodstudio*.dylib' \
			\); then
		echo sdl2
		return 0
	fi
	# OpenLara / Aspyr Tomb Raider classic remasters (I-III and IV-VI collections)
	if _engine_find "$game_dir" 2 \( \
		-iname 'tomb123.exe' -o -iname 'tomb456.exe' \
		\) \
		|| { _engine_find "$game_dir" 2 -iname 'PlayFabCore.Win32.dll' \
			&& _engine_find "$game_dir" 3 \( \
				-iname 'tomb1.dll' -o -iname 'tomb2.dll' -o -iname 'tomb3.dll' \
				-o -iname 'tomb4.dll' -o -iname 'tomb5.dll' -o -iname 'tomb6.dll' \
				\) \
			&& _engine_find "$game_dir" 3 -path '*/ITEM/*.TRM'; }; then
		echo openlara
		return 0
	fi
	# GOG wrapper ports (Jam engine — Leisure Suit Larry: Magna Cum Laude, etc.)
	if _engine_find "$game_dir" 2 -iname 'goggame-*.dll' \
		&& _engine_find "$game_dir" 3 -type d -path '*/Data/JamFiles'; then
		echo gog
		return 0
	fi
	# Godot embedded single-exe export (pck inside exe — Metal Goose, etc.)
	if [[ "$(find "$game_dir" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)" -le 3 ]] \
		&& _engine_find "$game_dir" 1 -iname '*.exe'; then
		local _godot_exe
		while IFS= read -r _godot_exe; do
			[[ -f "$_godot_exe" ]] || continue
			grep -aq 'Godot Engine' "$_godot_exe" 2>/dev/null && {
				echo godot
				return 0
			}
		done < <(find "$game_dir" -maxdepth 1 -type f -iname '*.exe' 2>/dev/null)
	fi
}

# detect_engine_hint — Return detected engine id, or unknown.
detect_engine_hint() {
	local appid=${1:-$steam_app_id}
	local game_dir engine
	game_dir="$(get_game_dir_for_appid "$appid" 2>/dev/null || true)"
	engine="$(_detect_engine_markers "$game_dir")"
	if [[ -n "$engine" ]]; then
		echo "$engine"
	else
		echo unknown
	fi
}

# detect_dlss_present — True when DLSS/NVNGX libraries are in the install dir.
detect_dlss_present() {
	local appid=${1:-$steam_app_id}
	local game_dir
	game_dir="$(get_game_dir_for_appid "$appid" 2>/dev/null || true)"
	[[ -n "$game_dir" && -d "$game_dir" ]] || return 1
	find "$game_dir" -maxdepth 3 \( \
		-iname 'nvngx.dll' -o -iname 'nvngx_dlss.dll' -o -iname 'sl.dlss.dll' \
		\) -print -quit 2>/dev/null | grep -q .
}

# get_compatdata_path_for_appid — Print first compatdata prefix path for an AppID.
get_compatdata_path_for_appid() {
	local appid=$1
	collect_compatdata_dirs "$appid"
	[[ ${#compatdata_dirs[@]} -gt 0 ]] && echo "${compatdata_dirs[0]}"
}

# get_proton_tool_for_appid — Read Proton/compatibility tool name from prefix config_info.
get_proton_tool_for_appid() {
	local appid=$1 dir
	dir="$(get_compatdata_path_for_appid "$appid" 2>/dev/null || true)"
	[[ -n "$dir" && -f "$dir/config_info" ]] || return 1
	head -1 "$dir/config_info" 2>/dev/null | tr -d '[:space:]'
}

# suggest_preset_for_appid — Auto-select standard, competitive, or native preset.
suggest_preset_for_appid() {
	local appid=$1
	if detect_native_game "$appid"; then
		echo native
	elif detect_anticheat_game "$appid"; then
		echo competitive
	else
		echo standard
	fi
}

# resolve_game_flags — Populate is_native, is_anticheat, engine, and name globals.
resolve_game_flags() {
	is_native=0
	is_anticheat=0
	anticheat_type=""
	game_engine_hint="unknown"

	detect_native_game "$steam_app_id" && is_native=1
	detect_anticheat_game "$steam_app_id" && is_anticheat=1
	anticheat_type="$(detect_anticheat_type "$steam_app_id")"
	game_engine_hint="$(detect_engine_hint "$steam_app_id")"
	steam_game_name="$(get_game_name "$steam_app_id" 2>/dev/null || true)"
}
