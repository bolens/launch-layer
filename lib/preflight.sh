# shellcheck shell=bash
# shellcheck source=common.sh
# shellcheck source=steam/detect.sh
# lib/preflight.sh — Pre-launch health checks (sysctl, caches, VRAM).

[[ -n "${LAUNCHLAYER_PREFLIGHT_LOADED:-}" ]] && return 0
LAUNCHLAYER_PREFLIGHT_LOADED=1

shader_cache_dirs=()
compatdata_dirs=()
shader_cache_entries=()
compatdata_entries=()

# collect_cache_size_entries — Fill shader_cache_entries and compatdata_entries (path|bytes).
collect_cache_size_entries() {
	local appid=$1 dir size_bytes
	shader_cache_entries=()
	compatdata_entries=()
	[[ -n "$appid" ]] || return 0
	collect_shader_cache_dirs "$appid"
	for dir in "${shader_cache_dirs[@]}"; do
		size_bytes="$(dir_size_bytes "$dir" 2>/dev/null || echo 0)"
		shader_cache_entries+=("${dir}|${size_bytes:-0}")
	done
	collect_compatdata_dirs "$appid"
	for dir in "${compatdata_dirs[@]}"; do
		size_bytes="$(dir_size_bytes "$dir" 2>/dev/null || echo 0)"
		compatdata_entries+=("${dir}|${size_bytes:-0}")
	done
}

# print_cache_dirs_text — Human-readable shader/compat cache listing.
print_cache_dirs_text() {
	local shader_label=${1:-Shader cache} compat_label=${2:-Compatdata}
	local entry path bytes
	echo "$shader_label:"
	if ((${#shader_cache_entries[@]})); then
		for entry in "${shader_cache_entries[@]}"; do
			path="${entry%%|*}"
			bytes="${entry##*|}"
			echo "  $path ($(bytes_to_gb "${bytes:-0}")GB)"
		done
	else
		echo "  (none)"
	fi
	echo "$compat_label:"
	if ((${#compatdata_entries[@]})); then
		for entry in "${compatdata_entries[@]}"; do
			path="${entry%%|*}"
			bytes="${entry##*|}"
			echo "  $path ($(bytes_to_gb "${bytes:-0}")GB)"
		done
	else
		echo "  (none)"
	fi
}

# check_oversized_cache_dirs — Warn (and optionally trim) when cache dirs exceed max_gb.
check_oversized_cache_dirs() {
	local kind=$1 max_gb=$2 trim_enabled=$3
	local -n _dirs_ref
	local dir size_bytes size_gb max_bytes proton_ver
	case "$kind" in
		shader) _dirs_ref=shader_cache_dirs ;;
		compat) _dirs_ref=compatdata_dirs ;;
		*) return 1 ;;
	esac
	max_bytes=$((max_gb * 1024 * 1024 * 1024))
	for dir in "${_dirs_ref[@]}"; do
		if [[ "$kind" == compat && -f "$dir/config_info" ]]; then
			proton_ver="$(grep -m1 '^config/proton/' "$dir/config_info" 2>/dev/null || true)"
			proton_ver="${proton_ver#config/proton/}"
			[[ -n "$proton_ver" ]] && debug "proton prefix: $proton_ver"
		fi
		size_bytes="$(dir_size_bytes "$dir" 2>/dev/null || true)"
		[[ -n "$size_bytes" ]] || continue
		size_gb="$(bytes_to_gb "$size_bytes")"
		if (( size_bytes <= max_bytes )); then
			debug "${kind} cache ok: $dir (${size_gb}GB)"
			continue
		fi
		warn "${kind} cache for AppID $steam_app_id is ${size_gb}GB (> ${max_gb}GB): $dir"
		if [[ "$kind" == shader && "$trim_enabled" == "1" ]]; then
			rm -rf "$dir" && mkdir -p "$dir"
			warn "trimmed shader cache: $dir"
		elif [[ "$kind" == "shader" ]]; then
			warn "set SHADER_CACHE_TRIM=1 in games/${steam_app_id}.env to auto-trim"
		elif [[ "$kind" == compat && "$trim_enabled" == "1" ]]; then
			warn "COMPATDATA_TRIM=1 set but trim is disabled for safety — remove prefix manually if needed"
		fi
	done
}

check_vm_max_map_count() {
	is_linux || return 0
	local required="${VM_MAX_MAP_COUNT_MIN:-$LAUNCHLAYER_VM_MAX_MAP_COUNT_DEFAULT}"
	local current=0
	current="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
	if (( current >= required )); then
		debug "vm.max_map_count=$current"
		return 0
	fi
	if [[ "${VM_MAX_MAP_COUNT_FIX:-0}" == "1" ]] && sudo -n true 2>/dev/null; then
		if sudo -n sysctl -w "vm.max_map_count=$required" >/dev/null 2>&1; then
			debug "vm.max_map_count raised to $required"
			return 0
		fi
	fi
	warn "vm.max_map_count=$current (recommend >= $required for Proton stability)"
	warn "fix: sudo cp $(sysctl_dropin_source) /etc/sysctl.d/ && sudo sysctl --system"
	warn "     or: sudo $LAUNCHLAYER_MAIN_SCRIPT --sysctl install"
}

# collect_app_cache_dirs — Populate shader_cache_dirs or compatdata_dirs for an AppID.
collect_app_cache_dirs() {
	local appid=$1 kind=$2 subdir root
	local -n _dirs_ref
	case "$kind" in
		shader)
			_dirs_ref=shader_cache_dirs
			subdir=shadercache
			;;
		compat)
			_dirs_ref=compatdata_dirs
			subdir=compatdata
			;;
		*)
			return 1
			;;
	esac
	_dirs_ref=()
	[[ -n "$appid" ]] || return 0
	while IFS= read -r root; do
		[[ -n "$root" ]] || continue
		if [[ -d "$root/steamapps/$subdir/$appid" ]]; then
			_dirs_ref+=("$root/steamapps/$subdir/$appid")
		fi
	done < <(collect_steam_library_roots)
}

# collect_shader_cache_dirs — Find shadercache/<appid> dirs across all libraries.
collect_shader_cache_dirs() {
	collect_app_cache_dirs "$1" shader
}

# collect_compatdata_dirs — Find compatdata/<appid> prefix dirs.
collect_compatdata_dirs() {
	collect_app_cache_dirs "$1" compat
}

# sum_cache_dirs_gb — Sum rounded GB for all cache dirs of a given kind.
sum_cache_dirs_gb() {
	local appid=$1 kind=$2 dir total=0 size_gb
	collect_app_cache_dirs "$appid" "$kind"
	case "$kind" in
		shader)
			for dir in "${shader_cache_dirs[@]}"; do
				size_gb="$(dir_size_gb "$dir")"
				(( total += size_gb ))
			done
			;;
		compat)
			for dir in "${compatdata_dirs[@]}"; do
				size_gb="$(dir_size_gb "$dir")"
				(( total += size_gb ))
			done
			;;
	esac
	echo "$total"
}

# cache_check_due — Return 0 when a rate-limited cache check should run.
cache_check_due() {
	local stamp_file=$1 interval_hours=$2 last now
	[[ -f "$stamp_file" && "$interval_hours" =~ ^[0-9]+$ && "$interval_hours" -gt 0 ]] || return 0
	last="$(<"$stamp_file")"
	now="$(date +%s)"
	[[ "$last" =~ ^[0-9]+$ ]] && (( now - last < interval_hours * 3600 )) && return 1
	return 0
}

# cache_check_stamp_file — Path to last-check timestamp for shader or compat cache.
cache_check_stamp_file() {
	local kind=$1 appid=$2
	case "$kind" in
		shader) echo "$STATE_DIR/shader-cache-check-${appid}.stamp" ;;
		compat) echo "$STATE_DIR/compatdata-check-${appid}.stamp" ;;
	esac
}

# shader_cache_stamp_file — Path to the last-check timestamp for an appid.
shader_cache_stamp_file() {
	cache_check_stamp_file shader "$1"
}

# check_shader_cache — Warn on oversized shader caches; optionally trim them.
#
# Rate-limited by SHADER_CACHE_CHECK_INTERVAL_HOURS to avoid du on every launch.
check_shader_cache() {
	[[ "${SHADER_CACHE_CHECK:-1}" == "1" ]] || return 0
	[[ -n "$steam_app_id" ]] || return 0
	local stamp_file interval
	interval="${SHADER_CACHE_CHECK_INTERVAL_HOURS:-24}"
	stamp_file="$(shader_cache_stamp_file "$steam_app_id")"
	if ! cache_check_due "$stamp_file" "$interval"; then
		debug "shader cache check skipped (checked within ${interval}h)"
		return 0
	fi
	collect_shader_cache_dirs "$steam_app_id"
	[[ ${#shader_cache_dirs[@]} -gt 0 ]] || return 0
	check_oversized_cache_dirs shader "${SHADER_CACHE_MAX_GB:-10}" "${SHADER_CACHE_TRIM:-0}"
	mkdir -p "$STATE_DIR"
	date +%s > "$stamp_file"
}

# compatdata_stamp_file — Path to the last compatdata check timestamp.
compatdata_stamp_file() {
	cache_check_stamp_file compat "$1"
}

# check_compatdata — Warn on oversized Proton prefixes (trim disabled for safety).
check_compatdata() {
	[[ "${COMPATDATA_CHECK:-1}" == "1" ]] || return 0
	[[ -n "$steam_app_id" ]] || return 0
	[[ "$is_native" == "1" && "${FORCE_PROTON:-0}" != "1" ]] && return 0

	local dir stamp_file interval
	interval="${SHADER_CACHE_CHECK_INTERVAL_HOURS:-24}"
	stamp_file="$(compatdata_stamp_file "$steam_app_id")"
	if ! cache_check_due "$stamp_file" "$interval"; then
		return 0
	fi

	collect_compatdata_dirs "$steam_app_id"
	[[ ${#compatdata_dirs[@]} -gt 0 ]] || return 0
	check_oversized_cache_dirs compat "${COMPATDATA_MAX_GB:-50}" "${COMPATDATA_TRIM:-0}"
	mkdir -p "$STATE_DIR"
	date +%s > "$stamp_file"
}

# check_vram_available — Warn when GPU reports free VRAM below threshold.
check_vram_available() {
	local min_mb="${VRAM_PREFLIGHT_MIN_MB:-0}"
	local free_mb=""
	[[ "$min_mb" =~ ^[0-9]+$ && "$min_mb" -gt 0 ]] || return 0
	free_mb="$(gpu_vram_free_mb 2>/dev/null || true)"
	[[ "$free_mb" =~ ^[0-9]+$ ]] || return 0
	if (( free_mb < min_mb )); then
		warn "GPU VRAM free ${free_mb}MB < ${min_mb}MB — close other apps or enable VRAM_HOGS=1"
	fi
}

# check_gpu_power — Warn when NVIDIA GPU is not in a performance p-state.
check_gpu_power() {
	local pstate=""
	[[ "${GPU_POWER_CHECK:-0}" == "1" ]] || return 0
	[[ "$(detect_gpu_vendor)" == nvidia ]] || return 0
	optional_tool_installed nvidia-smi || return 0
	pstate="$( { nvidia-smi --query-gpu=pstate --format=csv,noheader 2>/dev/null || true; } | head -1 | tr -d ' ')"
	[[ -n "$pstate" ]] || return 0
	if [[ "$pstate" != "P0" ]]; then
		warn "GPU pstate is $pstate (expected P0 for gaming)"
	fi
}

# check_disk_space — Warn when Steam library partitions are low on free space.
check_disk_space() {
	local min_gb=${DISK_PREFLIGHT_MIN_GB:-0} root avail_gb
	[[ "$min_gb" =~ ^[0-9]+$ && "$min_gb" -gt 0 ]] || return 0
	while IFS= read -r root; do
		[[ -n "$root" ]] || continue
		[[ -d "$root" ]] || continue
		avail_gb="$(df_avail_gb "$root" 2>/dev/null || true)"
		[[ "$avail_gb" =~ ^[0-9]+$ ]] || continue
		if (( avail_gb < min_gb )); then
			warn "Low disk space on $root: ${avail_gb}GB free (< ${min_gb}GB)"
		fi
	done < <(collect_steam_library_roots)
}

# check_gpu_vram_processes — Warn when other processes hold significant GPU memory.
check_gpu_vram_processes() {
	local min_mb=${GPU_VRAM_PROCESS_MIN_MB:-0} line proc_mb proc_name total_mb=0
	[[ "$min_mb" =~ ^[0-9]+$ && "$min_mb" -gt 0 ]] || return 0
	[[ "$(detect_gpu_vendor)" == nvidia ]] || return 0
	command -v nvidia-smi >/dev/null 2>&1 || return 0

	while IFS= read -r line; do
		[[ -z "$line" || "$line" == *"Not Found"* ]] && continue
		proc_mb="$(printf '%s' "$line" | awk -F, '{gsub(/ /, "", $3); print $3}')"
		proc_name="$(printf '%s' "$line" | awk -F, '{gsub(/^ /, "", $2); print $2}')"
		[[ "$proc_mb" =~ ^[0-9]+$ ]] || continue
		(( proc_mb < min_mb )) && continue
		warn "GPU process using ${proc_mb}MB: $proc_name"
		total_mb=$((total_mb + proc_mb))
	done < <(nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory \
		--format=csv,noheader,nounits 2>/dev/null || true)

	if (( total_mb >= min_mb )); then
		debug "gpu compute apps total ~${total_mb}MB"
	fi
}

# check_concurrent_launch — Warn when another launch session is still active.
check_concurrent_launch() {
	local active_pid=""
	[[ "${CONCURRENT_LAUNCH_GUARD:-1}" == "1" ]] || return 0
	[[ "$DRY_RUN" == "1" ]] && return 0
	[[ -f "$ACTIVE_LAUNCH_PID_FILE" ]] || return 0
	active_pid="$(<"$ACTIVE_LAUNCH_PID_FILE")"
	[[ "$active_pid" =~ ^[0-9]+$ ]] || return 0
	if kill -0 "$active_pid" 2>/dev/null; then
		warn "Another game launch is active (pid=$active_pid)"
	fi
}
