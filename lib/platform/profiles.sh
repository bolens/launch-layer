# shellcheck shell=bash
# lib/platform/profiles.sh — Auto profile selection and STEAM_ROOT init.

# detect_os_profile — Profile basename for launch.d/profiles/ (empty when none).
detect_os_profile() {
	case "$(detect_os_family)" in
		arch) echo arch-linux ;;
		debian) echo debian ;;
		fedora) echo fedora ;;
		suse) echo suse ;;
		nixos) echo nixos ;;
		alpine) echo alpine ;;
		void) echo void ;;
		gentoo) echo gentoo ;;
		solus) echo solus ;;
		clearlinux) echo clearlinux ;;
		steamos) echo steam-deck ;;
		bsd) echo bsd ;;
		darwin) echo macos ;;
	esac
}

# profile_list_contains — True when profile name is already in a space-separated list.
profile_list_contains() {
	local list=$1 name=$2
	[[ " $list " == *" $name "* ]]
}

# detect_default_profiles — Space-separated auto-selected profile names (layered).
# Names without a matching launch.d/profiles/<name>.env file are fingerprint /
# layering markers only (load_profile_config silently skips missing files).
detect_default_profiles() {
	local -a profiles=()
	local -a seen_profiles=()
	local p vendor

	local profiles_arg="${LAUNCHLAYER_PROFILES:-${STEAM_LAUNCH_PROFILES:-}}"
	if [[ -n "$profiles_arg" ]]; then
		echo "${profiles_arg//,/ }"
		return 0
	fi
	if [[ -n "${LAUNCHLAYER_PROFILE:-${STEAM_LAUNCH_PROFILE:-}}" ]]; then
		echo "${LAUNCHLAYER_PROFILE:-${STEAM_LAUNCH_PROFILE:-}}"
		return 0
	fi

	is_wsl2 && profiles+=(wsl2)
	is_steam_deck && profiles+=(steam-deck)
	is_flatpak_steam && profiles+=(flatpak-steam)
	is_immutable_os && profiles+=(immutable-linux)
	os_profile="$(detect_os_profile 2>/dev/null || true)"
	[[ -n "$os_profile" ]] && profiles+=("$os_profile")
	has_systemd_user || profiles+=(non-systemd)

	local handheld
	handheld="$(detect_handheld_profile 2>/dev/null || true)"
	if [[ -n "$handheld" ]]; then
		profiles+=("$handheld" "handheld")
	fi

	local cpu_vendor
	cpu_vendor="$(detect_cpu_vendor)"
	case "$cpu_vendor" in
		amd) profiles+=(amd-cpu) ;;
		intel) profiles+=(intel-cpu) ;;
	esac

	vendor="$(detect_gpu_vendor)"
	case "$vendor" in
		amd) profiles+=(amd-gpu) ;;
		intel) profiles+=(intel-gpu) ;;
		nvidia) profiles+=(nvidia-desktop) ;;
	esac

	for p in "${profiles[@]}"; do
		profile_list_contains "${seen_profiles[*]}" "$p" && continue
		seen_profiles+=("$p")
	done
	((${#seen_profiles[@]} > 0)) && echo "${seen_profiles[*]}"
}

# detect_default_profile — Legacy single-profile helper (first auto-detected profile).
detect_default_profile() {
	detect_default_profiles | awk '{print $1}'
}

# init_platform_paths — Resolve STEAM_ROOT after explicit overrides are honored.
init_platform_paths() {
	if [[ -z "${STEAM_ROOT:-}" || ! -d "${STEAM_ROOT}/steamapps" ]]; then
		STEAM_ROOT="$(detect_steam_root)"
	fi
	export STEAM_ROOT
}

init_platform_paths
