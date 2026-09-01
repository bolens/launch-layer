# shellcheck shell=bash
# lib/runtime/inject.sh — Shared download → cache → inject → track → cleanup.
#
# Never vendorizes third-party binaries into the LaunchLayer source tree.
# Artifacts live under XDG data with NOTICE metadata for license compliance.

[[ -n "${LAUNCHLAYER_RUNTIME_INJECT_LOADED:-}" ]] && return 0
LAUNCHLAYER_RUNTIME_INJECT_LOADED=1

# launchlayer_data_dir — User data root for caches and inject tracking.
launchlayer_data_dir() {
	printf '%s/launchlayer' "${XDG_DATA_HOME:-$HOME/.local/share}"
}

# inject_cache_root — Artifact cache (third-party downloads).
inject_cache_root() {
	printf '%s/cache' "$(launchlayer_data_dir)"
}

# inject_track_root — Per-AppID tracked inject manifests.
inject_track_root() {
	printf '%s/inject-track' "$(launchlayer_data_dir)"
}

# inject_tool_cache_dir — Cache directory for one logical tool name.
inject_tool_cache_dir() {
	local tool=$1
	printf '%s/%s' "$(inject_cache_root)" "$tool"
}

# inject_ensure_dirs — Create cache/track directories.
inject_ensure_dirs() {
	mkdir -p "$(inject_cache_root)" "$(inject_track_root)"
}

# inject_store_notice — Write NOTICE for a cached tool (license + upstream URL).
# Args: tool_id version upstream_url license_spdx [extra_note]
inject_store_notice() {
	local tool=$1 version=$2 url=$3 license=$4
	local extra=${5:-}
	local dir notice
	inject_ensure_dirs
	dir="$(inject_tool_cache_dir "$tool")"
	mkdir -p "$dir"
	notice="$dir/NOTICE"
	{
		printf 'Tool: %s\n' "$tool"
		printf 'Version: %s\n' "$version"
		printf 'Upstream: %s\n' "$url"
		printf 'License: %s\n' "$license"
		printf 'Cached by LaunchLayer for local use only — not part of the CC BY-NC-SA source tree.\n'
		[[ -n "$extra" ]] && printf '%s\n' "$extra"
	} > "$notice"
}

# inject_verify_sha256 — Require and verify a SHA-256 digest.
inject_verify_sha256() {
	local file=$1
	local expect=${2:-${INJECT_SHA256:-}}
	local got
	[[ "$expect" =~ ^[0-9A-Fa-f]{64}$ ]] || {
		warn "inject fetch requires a 64-character INJECT_SHA256"
		return 1
	}
	[[ -f "$file" ]] || return 1
	if command_available sha256sum; then
		got="$(sha256sum "$file" | awk '{print $1}')"
	elif command_available shasum; then
		got="$(shasum -a 256 "$file" | awk '{print $1}')"
	else
		warn "inject_verify_sha256: sha256sum/shasum missing — cannot verify $file"
		return 1
	fi
	[[ "${got,,}" == "${expect,,}" ]] || {
		warn "inject checksum mismatch for $file (expected $expect, got $got)"
		return 1
	}
	debug "inject sha256 ok: $file"
	return 0
}

# inject_fetch_url — Download URL to dest path (honors LAUNCHLAYER_FETCH_CMD for tests).
# Returns 1 on failure. Does not overwrite unless LAUNCHLAYER_FETCH_FORCE=1.
# INJECT_SHA256 is mandatory for remote content.
inject_fetch_url() {
	local url=$1 final_dest=$2
	local dir dest max_bytes=${LAUNCHLAYER_INJECT_MAX_DOWNLOAD_BYTES:-268435456}
	[[ -n "$url" && -n "$final_dest" ]] || return 1
	[[ "${INJECT_SHA256:-}" =~ ^[0-9A-Fa-f]{64}$ ]] || {
		warn "refusing unchecked download: set INJECT_SHA256 for $url"
		return 1
	}
	[[ "$max_bytes" =~ ^[1-9][0-9]*$ ]] || max_bytes=268435456
	dir="$(dirname "$final_dest")"
	mkdir -p "$dir"
	if [[ -f "$final_dest" && "${LAUNCHLAYER_FETCH_FORCE:-0}" != "1" ]]; then
		debug "inject cache hit: $final_dest"
		inject_file_within_limit "$final_dest" "$max_bytes" || return 1
		inject_verify_sha256 "$final_dest" || return 1
		return 0
	fi
	dest="$(mktemp "$dir/.inject-download.XXXXXX")" || return 1
	if [[ -n "${LAUNCHLAYER_FETCH_CMD:-}" ]]; then
		# shellcheck disable=SC2086
		eval "$LAUNCHLAYER_FETCH_CMD" || {
			rm -f "$dest"
			return 1
		}
		inject_file_within_limit "$dest" "$max_bytes" || {
			rm -f "$dest"
			return 1
		}
		inject_verify_sha256 "$dest" || {
			rm -f "$dest"
			return 1
		}
		chmod 600 "$dest"
		mv -f "$dest" "$final_dest"
		return 0
	fi
	if command_available curl; then
		curl -fsSL --connect-timeout 15 --max-filesize "$max_bytes" -o "$dest" "$url" || {
			rm -f "$dest"
			return 1
		}
	elif command_available wget; then
		wget -q --quota="$max_bytes" -O "$dest" "$url" || {
			rm -f "$dest"
			return 1
		}
	else
		warn "inject_fetch_url: curl/wget missing — cannot fetch $url"
		rm -f "$dest"
		return 1
	fi
	inject_file_within_limit "$dest" "$max_bytes" || {
		rm -f "$dest"
		return 1
	}
	inject_verify_sha256 "$dest" || {
		rm -f "$dest"
		return 1
	}
	chmod 600 "$dest"
	mv -f "$dest" "$final_dest"
	debug "inject fetched: $url → $final_dest"
}

inject_file_within_limit() {
	local file=$1 max_bytes=$2 size
	[[ -f "$file" && "$max_bytes" =~ ^[1-9][0-9]*$ ]] || return 1
	size="$(wc -c < "$file" 2>/dev/null || true)"
	[[ "$size" =~ ^[0-9]+$ && "$size" -le "$max_bytes" ]] || {
		warn "inject fetch exceeds byte limit ($max_bytes): $file"
		return 1
	}
}

# inject_refuse_proprietary_redistrib — Warn and return 1 (caller should use user-supplied path).
inject_refuse_proprietary_redistrib() {
	local tool=$1 reason=${2:-EULA/redistribution not permitted}
	warn "$tool: automated download refused ($reason) — set a user-supplied path instead"
	return 1
}

# inject_extract_archive — Extract zip/7z/tar into dest_dir. Returns 1 on failure.
inject_extract_archive() {
	local archive=$1 dest_dir=$2
	[[ -f "$archive" && -n "$dest_dir" ]] || return 1
	inject_archive_members_are_safe "$archive" || {
		warn "inject_extract: unsafe archive members: $archive"
		return 1
	}
	mkdir -p "$dest_dir"
	case "${archive,,}" in
		*.zip)
			command_available unzip || {
				warn "inject_extract: unzip missing for $archive"
				return 1
			}
			unzip -qo "$archive" -d "$dest_dir" || return 1
			;;
		*.7z)
			if command_available 7z; then
				7z x -y -o"$dest_dir" "$archive" >/dev/null || return 1
			elif command_available 7za; then
				7za x -y -o"$dest_dir" "$archive" >/dev/null || return 1
			else
				warn "inject_extract: 7z missing for $archive"
				return 1
			fi
			;;
		*.tar|*.tar.gz|*.tgz|*.tar.xz|*.tar.bz2)
			command_available tar || return 1
			tar -xf "$archive" -C "$dest_dir" || return 1
			;;
		*)
			# Magic: zip PK header
			if command_available unzip && [[ "$(head -c 2 "$archive" 2>/dev/null || true)" == PK ]]; then
				unzip -qo "$archive" -d "$dest_dir" || return 1
			else
				warn "inject_extract: unknown archive type: $archive"
				return 1
			fi
			;;
	esac
	return 0
}

# inject_archive_member_is_safe — Reject absolute and parent-traversing members.
inject_archive_member_is_safe() {
	local member=${1//\\//} part
	[[ -n "$member" && "$member" != /* ]] || return 1
	while [[ "$member" == ./* ]]; do member="${member#./}"; done
	[[ -n "$member" ]] || return 0
	local old_ifs=$IFS
	IFS=/
	for part in $member; do
		[[ "$part" != ".." ]] || {
			IFS=$old_ifs
			return 1
		}
	done
	IFS=$old_ifs
	return 0
}

# inject_archive_members_are_safe — List members before extraction and validate each.
inject_archive_members_are_safe() {
	local archive=$1 member listed=0 seven_zip_entries=0 count=0
	local max_members=${LAUNCHLAYER_INJECT_MAX_MEMBERS:-4096}
	local -a list_cmd=()
	[[ "$max_members" =~ ^[1-9][0-9]*$ ]] || max_members=4096
	inject_archive_contains_links "$archive" && return 1
	inject_archive_expanded_size_is_safe "$archive" || return 1
	case "${archive,,}" in
		*.zip) list_cmd=(unzip -Z1 "$archive") ;;
		*.7z)
			if command_available 7z; then
				list_cmd=(7z l -slt "$archive")
			elif command_available 7za; then
				list_cmd=(7za l -slt "$archive")
			else
				return 1
			fi
			;;
		*.tar|*.tar.gz|*.tgz|*.tar.xz|*.tar.bz2) list_cmd=(tar -tf "$archive") ;;
		*)
			if command_available unzip && [[ "$(head -c 2 "$archive" 2>/dev/null || true)" == PK ]]; then
				list_cmd=(unzip -Z1 "$archive")
			else
				return 1
			fi
			;;
	esac
	while IFS= read -r member || [[ -n "$member" ]]; do
		[[ "${archive,,}" == *.7z ]] && {
			if [[ "$member" == ---------- ]]; then
				seven_zip_entries=1
				continue
			fi
			(( seven_zip_entries == 1 )) || continue
			[[ "$member" == "Path = "* ]] || continue
			member="${member#Path = }"
		}
		listed=1
		count=$((count + 1))
		(( count <= max_members )) || return 1
		inject_archive_member_is_safe "$member" || return 1
	done < <("${list_cmd[@]}" 2>/dev/null) || return 1
	(( listed == 1 ))
}

inject_archive_expanded_size_is_safe() {
	local archive=$1 line size total=0
	local max_bytes=${LAUNCHLAYER_INJECT_MAX_EXPANDED_BYTES:-536870912}
	[[ "$max_bytes" =~ ^[1-9][0-9]*$ ]] || max_bytes=536870912
	case "${archive,,}" in
		*.tar|*.tar.gz|*.tgz|*.tar.xz|*.tar.bz2)
			while IFS= read -r line; do
				read -r _ _ size _ <<< "$line"
				[[ "$size" =~ ^[0-9]+$ ]] || return 1
				total=$((total + size))
				(( total <= max_bytes )) || return 1
			done < <(LC_ALL=C tar -tvf "$archive" 2>/dev/null)
			;;
		*.zip)
			while IFS= read -r line; do
				[[ "$line" == [-dfl]* ]] || continue
				read -r _ _ _ size _ <<< "$line"
				[[ "$size" =~ ^[0-9]+$ ]] || return 1
				total=$((total + size))
				(( total <= max_bytes )) || return 1
			done < <(unzip -Z -l "$archive" 2>/dev/null)
			;;
		*.7z)
			local seven_zip=""
			if command_available 7z; then seven_zip=7z; elif command_available 7za; then seven_zip=7za; else return 1; fi
			while IFS= read -r line; do
				[[ "$line" == "Size = "* ]] || continue
				size="${line#Size = }"
				[[ "$size" =~ ^[0-9]+$ ]] || return 1
				total=$((total + size))
				(( total <= max_bytes )) || return 1
			done < <("$seven_zip" l -slt "$archive" 2>/dev/null)
			;;
		*)
			[[ "$(head -c 2 "$archive" 2>/dev/null || true)" == PK ]] || return 1
			while IFS= read -r line; do
				[[ "$line" == [-dfl]* ]] || continue
				read -r _ _ _ size _ <<< "$line"
				[[ "$size" =~ ^[0-9]+$ ]] || return 1
				total=$((total + size))
				(( total <= max_bytes )) || return 1
			done < <(unzip -Z -l "$archive" 2>/dev/null)
			;;
	esac
	return 0
}

# inject_archive_contains_links — Reject archive links before extracting files.
inject_archive_contains_links() {
	local archive=$1
	case "${archive,,}" in
		*.tar|*.tar.gz|*.tgz|*.tar.xz|*.tar.bz2)
			tar -tvf "$archive" 2>/dev/null \
				| awk 'substr($1, 1, 1) == "l" || substr($1, 1, 1) == "h" { found=1 } END { exit !found }'
			;;
		*.zip)
			unzip -Z -l "$archive" 2>/dev/null \
				| awk 'substr($1, 1, 1) == "l" { found=1 } END { exit !found }'
			;;
		*.7z)
			local seven_zip=""
			if command_available 7z; then seven_zip=7z; elif command_available 7za; then seven_zip=7za; else return 0; fi
			"$seven_zip" l -slt "$archive" 2>/dev/null \
				| awk -F' = ' '/^(Symbolic Link|Hard Link) = / && length($2) { found=1 } END { exit !found }'
			;;
		*)
			if [[ "$(head -c 2 "$archive" 2>/dev/null || true)" == PK ]]; then
				unzip -Z -l "$archive" 2>/dev/null \
					| awk 'substr($1, 1, 1) == "l" { found=1 } END { exit !found }'
			else
				return 1
			fi
			;;
	esac
}

# inject_find_file — Find first matching filename under dir (maxdepth 6).
inject_find_file() {
	local dir=$1 name=$2
	[[ -d "$dir" && -n "$name" ]] || return 1
	find "$dir" -maxdepth 6 -type f -name "$name" 2>/dev/null | head -1
}

# inject_track_file — Record a file path installed for appid+tool for later cleanup.
inject_track_file() {
	local appid=$1 tool=$2 path=$3
	local manifest
	[[ -n "$appid" && -n "$tool" && -n "$path" ]] || return 1
	inject_track_identifiers_are_safe "$appid" "$tool" || return 1
	[[ "$path" == /* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
	inject_ensure_dirs
	manifest="$(inject_track_root)/${appid}-${tool}.txt"
	touch "$manifest"
	grep -Fxq "$path" "$manifest" 2>/dev/null || printf '%s\n' "$path" >> "$manifest"
}

# inject_track_operation — Persist one reversible operation before replacement.
inject_track_operation() {
	local appid=$1 tool=$2 operation=$3 dest=$4 backup=${5:-}
	local manifest lock_file lock_fd=""
	inject_track_identifiers_are_safe "$appid" "$tool" || return 1
	[[ "$operation" == create || "$operation" == replace ]] || return 1
	[[ "$dest" == /* && "$dest" != *$'\t'* && "$dest" != *$'\n'* && "$dest" != *$'\r'* ]] || return 1
	if [[ "$operation" == replace ]]; then
		[[ "$backup" == "${dest}.ll-bak" ]] || return 1
	else
		backup=""
	fi
	inject_ensure_dirs || return 1
	manifest="$(inject_track_root)/${appid}-${tool}.txt"
	lock_file="${manifest}.lock"
	if command_available flock; then
		exec {lock_fd}> "$lock_file" || return 1
		flock "$lock_fd" || { exec {lock_fd}>&-; return 1; }
	fi
	printf '%s\t%s\t%s\n' "$operation" "$dest" "$backup" >> "$manifest" || {
		[[ -n "$lock_fd" ]] && { flock -u "$lock_fd" || true; exec {lock_fd}>&-; }
		return 1
	}
	[[ -n "$lock_fd" ]] && { flock -u "$lock_fd" || true; exec {lock_fd}>&-; }
}

# inject_track_identifiers_are_safe — Keep manifest names inside the track root.
inject_track_identifiers_are_safe() {
	local appid=$1 tool=$2
	[[ "$appid" =~ ^([0-9]+|steam)$ && "$tool" =~ ^[a-z0-9_]+$ ]]
}

# inject_cleanup_tracked — Restore *.ll-bak then remove other tracked inject files.
inject_cleanup_tracked() {
	local appid=$1 tool=$2
	local manifest path orig operation backup lock_file lock_fd=""
	local -a restored=()
	inject_track_identifiers_are_safe "$appid" "$tool" || return 1
	manifest="$(inject_track_root)/${appid}-${tool}.txt"
	[[ -f "$manifest" ]] || return 0
	lock_file="${manifest}.lock"
	if command_available flock; then
		exec {lock_fd}> "$lock_file" || return 1
		flock "$lock_fd" || { exec {lock_fd}>&-; return 1; }
	fi
	# Structured manifests are replayed in reverse operation order.
	if grep -qE $'^(create|replace)\t' "$manifest" 2>/dev/null; then
		while IFS=$'\t' read -r operation path backup; do
			if [[ "$operation" == /* && -z "$path" ]]; then
				path=$operation
				if [[ "$path" == *.ll-bak && -f "$path" ]]; then
					mv -f "$path" "${path%.ll-bak}"
				elif [[ -f "$path" || -L "$path" ]]; then
					rm -f "$path"
				fi
				continue
			fi
			[[ "$path" == /* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || continue
			case "$operation" in
				replace)
					[[ "$backup" == "${path}.ll-bak" ]] || continue
					[[ -f "$backup" ]] && mv -f "$backup" "$path"
					;;
				create) [[ -f "$path" || -L "$path" ]] && rm -f "$path" ;;
			esac
		done < <(awk 'BEGIN { ORS="" } { lines[NR]=$0 } END { for (i=NR; i>0; i--) print lines[i] "\n" }' "$manifest")
		rm -f "$manifest"
		[[ -n "$lock_fd" ]] && { flock -u "$lock_fd" || true; exec {lock_fd}>&-; }
		return 0
	fi
	# Pass 1: restore backups
	while IFS= read -r path || [[ -n "$path" ]]; do
		[[ -n "$path" ]] || continue
		if [[ "$path" == *.ll-bak ]]; then
			orig="${path%.ll-bak}"
			if [[ -f "$path" ]]; then
				mv -f "$path" "$orig" && debug "inject restored: $orig"
				restored+=("$orig")
			fi
		fi
	done < "$manifest"
	# Pass 2: remove inject copies that were not just restored from a backup
	while IFS= read -r path || [[ -n "$path" ]]; do
		[[ -n "$path" ]] || continue
		[[ "$path" == *.ll-bak ]] && continue
		local skip=0 r
		for r in "${restored[@]+"${restored[@]}"}"; do
			[[ "$path" == "$r" ]] && {
				skip=1
				break
			}
		done
		(( skip )) && continue
		if [[ -f "$path" || -L "$path" ]]; then
			rm -f "$path" && debug "inject cleaned: $path"
		fi
	done < "$manifest"
	rm -f "$manifest"
	[[ -n "$lock_fd" ]] && { flock -u "$lock_fd" || true; exec {lock_fd}>&-; }
}

# inject_cleanup_launch_tracks — Clean known inject tools for the current AppID.
inject_cleanup_launch_tracks() {
	local appid=${1:-${steam_app_id:-}}
	[[ -n "$appid" ]] || return 0
	local tool
	for tool in specialk reshade optiscaler openvr_fsr opencomposite; do
		inject_cleanup_tracked "$appid" "$tool"
	done
	inject_cleanup_tracked steam valveplug
}

# inject_proxy_name_is_safe — Accept only a proxy DLL leaf name.
inject_proxy_name_is_safe() {
	local proxy=${1,,}
	[[ "$proxy" =~ ^[a-z0-9_+-]+(\.dll)?$ ]]
}

# inject_proxy_slot — Normalize a Windows proxy DLL name for conflict checks.
inject_proxy_slot() {
	local slot=${1,,}
	slot="${slot%.dll}.dll"
	printf '%s\n' "$slot"
}

# inject_provider_claims — Print enabled injector claims as slot<TAB>provider.
inject_provider_claims() {
	[[ "${SPECIAL_K:-0}" == "1" ]] \
		&& printf '%s\t%s\n' "$(inject_proxy_slot "${SPECIAL_K_DLL:-dxgi}")" "Special K"
	[[ "${RESHADE:-0}" == "1" ]] \
		&& printf '%s\t%s\n' "$(inject_proxy_slot "${RESHADE_DLL:-dxgi}")" "ReShade"
	if [[ "${OPTISCALER:-0}" == "1" ]]; then
		if [[ "${OPTISCALER_PROXY:-dxgi}" == "OptiScaler.asi" || "${OPTISCALER_PROXY:-dxgi}" == "optiscaler.asi" ]]; then
			printf 'optiscaler.asi\tOptiScaler\n'
		else
			printf '%s\t%s\n' "$(inject_proxy_slot "${OPTISCALER_PROXY:-dxgi}")" "OptiScaler"
		fi
	fi
	[[ "${OPENVR_FSR:-0}" == "1" ]] && printf 'openvr_api.dll\tOpenVR FSR\n'
	[[ "${OPENCOMPOSITE:-0}" == "1" ]] && printf 'openvr_api.dll\tOpenComposite\n'
	return 0
}

# inject_provider_conflict_errors — Report proxy DLL slots with multiple owners.
inject_provider_conflict_errors() {
	local slot provider
	local -A owners=()
	while IFS=$'\t' read -r slot provider; do
		[[ -n "$slot" ]] || continue
		if [[ -n "${owners[$slot]:-}" ]]; then
			printf 'injector conflict on %s: %s and %s are both enabled\n' \
				"$slot" "${owners[$slot]}" "$provider"
		else
			owners[$slot]="$provider"
		fi
	done < <(inject_provider_claims)
}

# inject_copy_renamed — Copy src to dest_dir/dest_name; bak existing; track when appid set.
inject_copy_renamed() {
	local src=$1 dest_dir=$2 dest_name=$3
	local appid=${4:-} tool=${5:-}
	local dest tmp backup_created=0
	[[ -f "$src" && -n "$dest_dir" && -n "$dest_name" ]] || return 1
	[[ "$dest_name" =~ ^[A-Za-z0-9._+-]+$ && "$dest_name" != "." && "$dest_name" != ".." ]] || return 1
	mkdir -p "$dest_dir"
	dest="${dest_dir%/}/$dest_name"
	[[ -e "$dest" && "$src" -ef "$dest" ]] && return 1
	[[ ! -e "$dest" || -f "$dest" ]] || return 1
	tmp="$(mktemp "${dest_dir%/}/.launchlayer-inject.XXXXXX")" || return 1
	cp -f "$src" "$tmp" || {
		rm -f "$tmp"
		return 1
	}
	if [[ -f "$dest" ]]; then
		if [[ ! -f "${dest}.ll-bak" ]]; then
			cp -f "$dest" "${dest}.ll-bak" || {
				rm -f "$tmp"
				return 1
			}
			backup_created=1
		fi
		if [[ -n "$appid" && -n "$tool" ]] \
			&& ! inject_track_operation "$appid" "$tool" replace "$dest" "${dest}.ll-bak"; then
			rm -f "$tmp"
			(( backup_created == 1 )) && rm -f "${dest}.ll-bak"
			return 1
		fi
	elif [[ -n "$appid" && -n "$tool" ]]; then
		if ! inject_track_operation "$appid" "$tool" create "$dest"; then
			rm -f "$tmp"
			return 1
		fi
	fi
	mv -f "$tmp" "$dest" || {
		rm -f "$tmp"
		[[ -n "$appid" && -n "$tool" ]] && inject_cleanup_tracked "$appid" "$tool"
		return 1
	}
	printf '%s\n' "$dest"
}

# inject_merge_winedlloverrides — Merge dll=n,b into WINEDLLOVERRIDES (no clobber).
inject_merge_winedlloverrides() {
	local dll=$1
	local entry existing
	[[ -n "$dll" ]] || return 0
	dll="${dll%.dll}"
	entry="${dll}=n,b"
	existing="${WINEDLLOVERRIDES:-}"
	if [[ -z "$existing" ]]; then
		export WINEDLLOVERRIDES="$entry"
		return 0
	fi
	case ";${existing};" in
		*";${dll}="*|*"${dll}="*) ;;
		*)
			export WINEDLLOVERRIDES="${existing};${entry}"
			;;
	esac
	debug "WINEDLLOVERRIDES=$WINEDLLOVERRIDES"
}

# inject_ensure_ini_key — Ensure key=value exists in an INI-like file.
inject_ensure_ini_key() {
	local file=$1 key=$2 value=$3 appid=${4:-} tool=${5:-}
	local tmp
	[[ -n "$file" && -n "$key" ]] || return 1
	mkdir -p "$(dirname "$file")"
	tmp="$(mktemp "$(dirname "$file")/.launchlayer-ini.XXXXXX")" || return 1
	if [[ -f "$file" ]] && grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null; then
		awk -v k="$key" -v v="$value" '
			BEGIN { done=0 }
			$0 ~ "^[[:space:]]*" k "[[:space:]]*=" {
				print k "=" v
				done=1
				next
			}
			{ print }
			END { if (!done) print k "=" v }
		' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
	else
		[[ -f "$file" ]] && cp -f "$file" "$tmp"
		printf '%s=%s\n' "$key" "$value" >> "$tmp" || { rm -f "$tmp"; return 1; }
	fi
	if [[ -n "$appid" && -n "$tool" ]]; then
		inject_copy_renamed "$tmp" "$(dirname "$file")" "$(basename "$file")" "$appid" "$tool" >/dev/null || {
			rm -f "$tmp"
			return 1
		}
		rm -f "$tmp"
	else
		mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
	fi
}

# inject_resolve_game_dir — Best-effort Steam game install directory for AppID.
inject_resolve_game_dir() {
	local appid="${steam_app_id:-}"
	local dir=""
	[[ -n "$appid" ]] || return 1
	if declare -f get_game_dir_for_appid >/dev/null 2>&1; then
		dir="$(get_game_dir_for_appid "$appid" 2>/dev/null || true)"
	fi
	[[ -n "$dir" && -d "$dir" ]] || return 1
	printf '%s\n' "$dir"
}

# gamescope_session_active — True when already inside gamescope/Deck gamemode.
gamescope_session_active() {
	local desktop
	desktop="$(detect_desktop_session 2>/dev/null || true)"
	[[ "$desktop" == gamescope ]] && return 0
	[[ "${XDG_CURRENT_DESKTOP:-}" == *gamescope* ]] && return 0
	[[ -n "${STEAMDeck:-}${STEAMDECK:-}" ]] && [[ "${XDG_CURRENT_DESKTOP:-}" == *gamescope* ]] && return 0
	return 1
}
