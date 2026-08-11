# shellcheck shell=bash
# lib/hardware/cpu.sh

[[ -n "${LAUNCHLAYER_HARDWARE_LOADED:-}" ]] && return 0
LAUNCHLAYER_HARDWARE_LOADED=1
# format_taskset_cpus — Collapse a sorted CPU list into taskset ranges (e.g. 0-7,16-23).
format_taskset_cpus() {
	local -a cpus=()
	local cpu start prev
	local -a ranges=()

	for cpu in "$@"; do
		[[ "$cpu" =~ ^[0-9]+$ ]] && cpus+=("$cpu")
	done
	[[ ${#cpus[@]} -gt 0 ]] || { default_online_cpus; return; }

	mapfile -t cpus < <(printf '%s\n' "${cpus[@]}" | sort -n)
	start=${cpus[0]}
	prev=$start

	for cpu in "${cpus[@]:1}"; do
		if (( cpu == prev + 1 )); then
			prev=$cpu
			continue
		fi
		if (( start == prev )); then ranges+=("$start"); else ranges+=("$start-$prev"); fi
		start=$cpu
		prev=$cpu
	done
	if (( start == prev )); then ranges+=("$start"); else ranges+=("$start-$prev"); fi
	IFS=','; echo "${ranges[*]}"
}

# compute_x3d_cpus — Scan sysfs for the L3 CCD with the largest cache.
compute_x3d_cpus() {
	local cpu cache max_cache
	local -a cpus=()

	max_cache=0
	for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
		[[ -f "$cpu/cache/index3/size" ]] || continue
		cache="$(<"$cpu/cache/index3/size")"
		cache="${cache%K}"
		[[ "$cache" =~ ^[0-9]+$ ]] || continue
		(( cache > max_cache )) && max_cache=$cache
	done

	if (( max_cache == 0 )); then
		default_online_cpus
		return 0
	fi

	for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
		[[ -f "$cpu/cache/index3/size" ]] || continue
		cache="$(<"$cpu/cache/index3/size")"
		cache="${cache%K}"
		[[ "$cache" == "$max_cache" ]] || continue
		cpus+=("${cpu##*cpu}")
	done

	if [[ ${#cpus[@]} -eq 0 ]]; then
		default_online_cpus
		return 0
	fi

	format_taskset_cpus "${cpus[@]}"
}

# read_max_l3_cache_kb — Return largest L3 cache size (KB) seen on this host.
read_max_l3_cache_kb() {
	local cpu cache max_cache=0
	for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
		[[ -f "$cpu/cache/index3/size" ]] || continue
		cache="$(<"$cpu/cache/index3/size")"
		cache="${cache%K}"
		[[ "$cache" =~ ^[0-9]+$ ]] || continue
		(( cache > max_cache )) && max_cache=$cache
	done
	echo "$max_cache"
}

# detect_x3d_cpus — V-Cache CCD range with stale-cache invalidation.
detect_x3d_cpus() {
	local result max_l3 cpu_count cached_l3 cached_count stale=0

	max_l3="$(read_max_l3_cache_kb)"
	cpu_count="$(nproc_portable)"

	if [[ -f "$X3D_CPUS_CACHE_FILE" && -f "$X3D_CPUS_META_FILE" ]]; then
		read -r cached_l3 cached_count < "$X3D_CPUS_META_FILE" 2>/dev/null || stale=1
		if [[ "$cached_l3" != "$max_l3" || "$cached_count" != "$cpu_count" ]]; then
			stale=1
		fi
		if (( stale == 0 )); then
			cat "$X3D_CPUS_CACHE_FILE"
			return 0
		fi
		debug "x3d cpu cache stale — refreshing"
	fi

	result="$(compute_x3d_cpus)"
	if mkdir -p "$STATE_DIR" 2>/dev/null; then
		printf '%s\n' "$result" > "$X3D_CPUS_CACHE_FILE" 2>/dev/null || true
		printf '%s %s\n' "$max_l3" "$cpu_count" > "$X3D_CPUS_META_FILE" 2>/dev/null || true
	fi
	echo "$result"
}

# detect_intel_p_cores — Read sysfs for Intel P-cores if hybrid CPU.
detect_intel_p_cores() {
	if [[ -f /sys/devices/cpu_core/cpus ]]; then
		cat /sys/devices/cpu_core/cpus
	else
		default_online_cpus
	fi
}
