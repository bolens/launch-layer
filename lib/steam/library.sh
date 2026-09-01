# shellcheck shell=bash
# lib/steam/library.sh — Steam library roots, manifests, and installed-game iteration.

[[ -n "${LAUNCHLAYER_STEAM_LIBRARY_LOADED:-}" ]] && return 0
LAUNCHLAYER_STEAM_LIBRARY_LOADED=1

# Per-process discovery cache. Full scans populate these before invoking their
# callback, avoiding repeated library and manifest walks for each detector.
declare -gA STEAM_MANIFEST_BY_APPID=()
declare -gA STEAM_GAME_DIR_BY_APPID=()

# steam_add_library_root — Append a library root if not already present.
steam_add_library_root() {
	local lib=$1
	local -n _roots_ref=$2
	local r
	[[ -n "$lib" && -d "$lib" ]] || return 0
	for r in "${_roots_ref[@]}"; do
		[[ "$r" == "$lib" ]] && return 0
	done
	_roots_ref+=("$lib")
}

# collect_steam_library_roots — Print all Steam library root paths, one per line.
collect_steam_library_roots() {
	local vdf lib
	local -a roots=()

	steam_add_library_root "$STEAM_ROOT" roots

	vdf="$STEAM_ROOT/steamapps/libraryfolders.vdf"
	if [[ -f "$vdf" ]]; then
		while IFS= read -r lib; do
			steam_add_library_root "$lib" roots
		done < <(parse_libraryfolders_paths "$vdf")
	fi

	printf '%s\n' "${roots[@]}"
}

# steam_library_discovery_available — True when at least one Steam library can be read.
steam_library_discovery_available() {
	local root
	while IFS= read -r root; do
		[[ -d "$root/steamapps" && -r "$root/steamapps" && -x "$root/steamapps" ]] && return 0
	done < <(collect_steam_library_roots)
	return 1
}

# find_app_manifest — Locate appmanifest_<appid>.acf across all library roots.
find_app_manifest() {
	local appid=$1
	local root manifest
	if [[ -n "${STEAM_MANIFEST_BY_APPID[$appid]+x}" ]]; then
		[[ -n "${STEAM_MANIFEST_BY_APPID[$appid]}" ]] || return 1
		printf '%s\n' "${STEAM_MANIFEST_BY_APPID[$appid]}"
		return 0
	fi
	while IFS= read -r root; do
		[[ -n "$root" ]] || continue
		manifest="$root/steamapps/appmanifest_${appid}.acf"
		if [[ -f "$manifest" ]]; then
			STEAM_MANIFEST_BY_APPID["$appid"]="$manifest"
			printf '%s\n' "$manifest"
			return 0
		fi
	done < <(collect_steam_library_roots)
	STEAM_MANIFEST_BY_APPID["$appid"]=""
	return 1
}

# manifest_field — Extract a quoted VDF field value from an app manifest.
manifest_field() {
	local manifest=$1
	local field=$2
	grep -m1 "\"$field\"" "$manifest" 2>/dev/null \
		| sed -n 's/^[[:space:]]*"[^"]*"[[:space:]]*"\([^"]*\)".*/\1/p' || true
}

# read_manifest_game_fields — Parse the three scan fields in one Bash pass.
# Results are returned in MANIFEST_APPID, MANIFEST_NAME, and MANIFEST_INSTALLDIR.
read_manifest_game_fields() {
	local manifest=$1 line key value
	MANIFEST_APPID=""
	MANIFEST_NAME=""
	MANIFEST_INSTALLDIR=""
	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" =~ ^[[:space:]]*\"(appid|name|installdir)\"[[:space:]]*\"([^\"]*)\" ]]; then
			key="${BASH_REMATCH[1]}"
			value="${BASH_REMATCH[2]}"
			case "$key" in
				appid) MANIFEST_APPID="$value" ;;
				name) MANIFEST_NAME="$value" ;;
				installdir) MANIFEST_INSTALLDIR="$value" ;;
			esac
		fi
		[[ -n "$MANIFEST_APPID" && -n "$MANIFEST_NAME" && -n "$MANIFEST_INSTALLDIR" ]] && break
	done < "$manifest"
}

# get_game_name — Return the human-readable name for a Steam AppID.
get_game_name() {
	local appid=$1
	local manifest
	manifest="$(find_app_manifest "$appid" 2>/dev/null || true)"
	[[ -n "$manifest" ]] || return 1
	manifest_field "$manifest" "name"
}

# resolve_appid_query — Resolve numeric AppID or case-insensitive name fragment.
# Prints AppID on stdout; returns 1 if not found, 2 if ambiguous.
resolve_appid_query() {
	local query=$1
	local -a matches=() match

	if [[ "$query" =~ ^[0-9]+$ ]]; then
		is_installed_game_appid "$query" || {
			echo "AppID $query not found in installed Steam libraries." >&2
			return 1
		}
		echo "$query"
		return 0
	fi

	_resolve_appid_name_match() {
		local appid=$1 name=$2 _manifest=$3
		game_name_matches_grep "$name" "$query" || return 0
		matches+=("$appid")
	}
	foreach_installed_game _resolve_appid_name_match

	if ((${#matches[@]} == 0)); then
		echo "No installed game matching: $query" >&2
		return 1
	fi
	if ((${#matches[@]} > 1)); then
		echo "Multiple games match '$query':" >&2
		for match in "${matches[@]}"; do
			printf '  %s (%s)\n' "$match" "$(get_game_name "$match" 2>/dev/null || echo unknown)" >&2
		done
		echo "Use the numeric AppID." >&2
		return 2
	fi
	echo "${matches[0]}"
}

# get_installdir — Return the installdir field from an app manifest.
get_installdir() {
	local appid=$1
	local manifest
	manifest="$(find_app_manifest "$appid" 2>/dev/null || true)"
	[[ -n "$manifest" ]] || return 1
	manifest_field "$manifest" "installdir"
}

# find_game_dir — Resolve installdir to an absolute common/ path.
find_game_dir() {
	local installdir=$1
	local root
	while IFS= read -r root; do
		[[ -n "$root" ]] || continue
		if [[ -d "$root/steamapps/common/$installdir" ]]; then
			echo "$root/steamapps/common/$installdir"
			return 0
		fi
	done < <(collect_steam_library_roots)
	return 1
}

# get_game_dir_for_appid — Resolve install directory for an AppID.
get_game_dir_for_appid() {
	local appid=$1 installdir
	if [[ -n "${STEAM_GAME_DIR_BY_APPID[$appid]+x}" ]]; then
		[[ -n "${STEAM_GAME_DIR_BY_APPID[$appid]}" ]] || return 1
		printf '%s\n' "${STEAM_GAME_DIR_BY_APPID[$appid]}"
		return 0
	fi
	installdir="$(get_installdir "$appid" 2>/dev/null || true)"
	if [[ -z "$installdir" ]]; then
		STEAM_GAME_DIR_BY_APPID["$appid"]=""
		return 1
	fi
	local game_dir
	game_dir="$(find_game_dir "$installdir" 2>/dev/null || true)"
	STEAM_GAME_DIR_BY_APPID["$appid"]="$game_dir"
	[[ -n "$game_dir" ]] || return 1
	printf '%s\n' "$game_dir"
}

# find_all_app_manifests — Print one app manifest path per unique AppID.
find_all_app_manifests() {
	local root manifest filename appid
	declare -A seen_appids=()
	while IFS= read -r root; do
		[[ -n "$root" ]] || continue
		[[ -d "$root/steamapps" ]] || continue
		while IFS= read -r manifest; do
			[[ -n "$manifest" ]] || continue
			filename="${manifest##*/}"
			appid="${filename#appmanifest_}"
			appid="${appid%.acf}"
			[[ "$appid" =~ ^[0-9]+$ ]] || continue
			[[ -n "${seen_appids[$appid]+x}" ]] && continue
			seen_appids[$appid]=1
			echo "$manifest"
		done < <(find "$root/steamapps" -maxdepth 1 -name 'appmanifest_*.acf' -print 2>/dev/null || true)
	done < <(collect_steam_library_roots)
}

# is_skippable_steam_package — True for Steam runtimes, SDKs, and tool entries.
is_skippable_steam_package() {
	local name=$1 game_dir=${2:-}
	[[ -n "$game_dir" && -f "$game_dir/toolmanifest.vdf" ]] \
		|| [[ "$name" == *Runtime* || "$name" == *Redistribut* || "$name" == *SDK* || "$name" == Proton* ]]
}

# is_installed_game_appid — True for an installed game, false for tools and runtimes.
is_installed_game_appid() {
	local appid=$1 manifest name installdir game_dir
	manifest="$(find_app_manifest "$appid" 2>/dev/null || true)"
	[[ -n "$manifest" ]] || return 1
	read_manifest_game_fields "$manifest"
	name="$MANIFEST_NAME"
	installdir="$MANIFEST_INSTALLDIR"
	game_dir="${manifest%/*}/common/$installdir"
	[[ -n "$name" ]] || return 1
	! is_skippable_steam_package "$name" "$game_dir"
}

# game_name_matches_grep — True when name matches a case-insensitive grep pattern (or pattern empty).
game_name_matches_grep() {
	local name=$1 pattern=$2
	[[ -z "$pattern" || "${name,,}" == *"${pattern,,}"* ]]
}

# foreach_installed_game — Invoke callback(appid, name, manifest) for each installed game.
foreach_installed_game() {
	local callback=$1 manifest appid name installdir game_dir
	[[ "$(type -t "$callback")" == function ]] || return 1
	while IFS= read -r manifest; do
		[[ -n "$manifest" ]] || continue
		read_manifest_game_fields "$manifest"
		appid="$MANIFEST_APPID"
		name="$MANIFEST_NAME"
		installdir="$MANIFEST_INSTALLDIR"
		[[ -n "$appid" && -n "$name" ]] || continue
		STEAM_MANIFEST_BY_APPID["$appid"]="$manifest"
		game_dir="${manifest%/*}/common/$installdir"
		if [[ -n "$installdir" && -d "$game_dir" ]]; then
			STEAM_GAME_DIR_BY_APPID["$appid"]="$game_dir"
		else
			STEAM_GAME_DIR_BY_APPID["$appid"]=""
		fi
		is_skippable_steam_package "$name" "$game_dir" && continue
		"$callback" "$appid" "$name" "$manifest" || return $?
	done < <(find_all_app_manifests | LC_ALL=C sort -u)
}
