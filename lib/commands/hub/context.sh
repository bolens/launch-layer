# shellcheck shell=bash
# lib/commands/hub/context.sh — Shared config loading for hub CLI commands.

[[ -n "${LAUNCHLAYER_COMMANDS_HUB_CONTEXT_LOADED:-}" ]] && return 0
LAUNCHLAYER_COMMANDS_HUB_CONTEXT_LOADED=1

# hub_load_launch_context — Load profile + default/local layers before fingerprinting.
hub_load_launch_context() {
	load_profile_config
	load_config_file "$LAUNCHD_DIR/default.env" 0
	[[ -f "$LAUNCHD_DIR/local.env" ]] && load_config_file "$LAUNCHD_DIR/local.env" 0
	apply_defaults
}

# hub_validate_local_env_file — Lint one .env file before hub publish/apply.
hub_validate_local_env_file() {
	local file=$1 label=${2:-local config}
	local lint_out issues=0

	declare -f validate_single_config_file >/dev/null 2>&1 || return 0
	lint_out="$(validate_single_config_file "$file" 2>&1)" || issues=$?
	if (( issues > 0 )); then
		echo "$label failed validation:" >&2
		printf '%s\n' "$lint_out" >&2
		return 1
	fi
	return 0
}

# Keys that must not arrive via hub download (remote code / local damage).
# Canonical policy: the hub column in share/launchlayer/config-keys.tsv.
HUB_UNTRUSTED_ENV_KEYS=()

# hub_load_untrusted_env_keys — Populate HUB_UNTRUSTED_ENV_KEYS from key metadata.
hub_load_untrusted_env_keys() {
	local key
	HUB_UNTRUSTED_ENV_KEYS=()
	declare -p LAUNCHLAYER_CONFIG_KEY_HUB >/dev/null 2>&1 || {
		echo "launchlayer: Hub trust policy metadata is not loaded" >&2
		return 1
	}
	for key in "${!LAUNCHLAYER_CONFIG_KEY_HUB[@]}"; do
		[[ "${LAUNCHLAYER_CONFIG_KEY_HUB[$key]}" == untrusted ]] \
			&& HUB_UNTRUSTED_ENV_KEYS+=("$key")
	done
}

hub_load_untrusted_env_keys

# hub_is_untrusted_env_key — True when key must be stripped from remote configs.
hub_is_untrusted_env_key() {
	local key=$1 k
	for k in "${HUB_UNTRUSTED_ENV_KEYS[@]}"; do
		[[ "$key" == "$k" ]] && return 0
	done
	return 1
}

# hub_sanitize_remote_env_file — Strip untrusted keys and unsafe INCLUDE lines.
# Writes sanitized content in place. Prints stripped keys to stderr when any.
hub_sanitize_remote_env_file() {
	local file=$1
	local tmp line key value stripped=()
	local include_path

	[[ -f "$file" ]] || return 1
	tmp="$(mktemp)"
	while IFS= read -r line || [[ -n "$line" ]]; do
		local raw="$line"
		local trimmed="${line%%#*}"
		trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
		trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
		if [[ "$trimmed" =~ ^INCLUDE=(.*)$ ]]; then
			include_path="${BASH_REMATCH[1]}"
			include_path="${include_path#"${include_path%%[![:space:]]*}"}"
			include_path="${include_path%"${include_path##*[![:space:]]}"}"
			include_path="${include_path#\"}"; include_path="${include_path%\"}"
			include_path="${include_path#\'}"; include_path="${include_path%\'}"
			if declare -f is_safe_include_path >/dev/null 2>&1 && ! is_safe_include_path "$include_path"; then
				stripped+=("INCLUDE=$include_path")
				continue
			fi
			printf '%s\n' "$raw" >> "$tmp"
			continue
		fi
		if [[ "$trimmed" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
			key="${BASH_REMATCH[1]}"
			value="${BASH_REMATCH[2]}"
			value="${value#\"}"; value="${value%\"}"
			value="${value#\'}"; value="${value%\'}"
			if hub_is_untrusted_env_key "$key" && [[ -n "$value" ]]; then
				stripped+=("$key")
				continue
			fi
		fi
		printf '%s\n' "$raw" >> "$tmp"
	done < "$file"
	cat "$tmp" > "$file"
	rm -f "$tmp"
	if ((${#stripped[@]} > 0)); then
		echo "Stripped untrusted hub keys: ${stripped[*]}" >&2
	fi
	return 0
}

# hub_assert_publish_env_safe — Reject publish of remote-exec / damageful keys.
hub_assert_publish_env_safe() {
	local file=$1
	local line key value include_path bad=()

	[[ -f "$file" ]] || return 1
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%%#*}"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z "$line" ]] && continue
		if [[ "$line" =~ ^INCLUDE=(.*)$ ]]; then
			include_path="${BASH_REMATCH[1]}"
			include_path="${include_path#"${include_path%%[![:space:]]*}"}"
			include_path="${include_path%"${include_path##*[![:space:]]}"}"
			include_path="${include_path#\"}"; include_path="${include_path%\"}"
			include_path="${include_path#\'}"; include_path="${include_path%\'}"
			if declare -f is_safe_include_path >/dev/null 2>&1 && ! is_safe_include_path "$include_path"; then
				bad+=("INCLUDE=$include_path")
			fi
			continue
		fi
		[[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
		key="${BASH_REMATCH[1]}"
		value="${BASH_REMATCH[2]}"
		value="${value#\"}"; value="${value%\"}"
		value="${value#\'}"; value="${value%\'}"
		if hub_is_untrusted_env_key "$key" && [[ -n "$value" ]]; then
			bad+=("$key")
		fi
	done < "$file"
	if ((${#bad[@]} > 0)); then
		echo "Cannot publish config with untrusted keys: ${bad[*]}" >&2
		echo "Remove them locally (or leave empty) before publishing to the hub." >&2
		return 1
	fi
	return 0
}

# hub_validate_config_id — Reject malformed hub config ids before HTTP calls.
hub_validate_config_id() {
	local config_id=$1
	[[ "$config_id" =~ ^[a-z0-9]{10,64}$ ]] || {
		echo "Invalid hub config ID: $config_id" >&2
		return 1
	}
}
