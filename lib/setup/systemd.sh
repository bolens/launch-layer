# shellcheck shell=bash
# lib/setup/systemd.sh
# systemd_user_dir — User systemd unit directory.
systemd_user_dir() {
	echo "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
}

# systemd_exec_quote — Quote one literal argv item for systemd ExecStart syntax.
systemd_exec_quote() {
	local value=$1
	[[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 1
	value="${value//\\/\\\\}"
	value="${value//\"/\\\"}"
	value="${value//\%/%%}"
	value="${value//\$/\$\$}"
	printf '"%s"' "$value"
}

# install_systemd_user_units — Write maintenance timer/service with resolved script path.
install_systemd_user_units() {
	local unit_dir script script_exec service timer
	unit_dir="$(systemd_user_dir)"
	script="${LAUNCHLAYER_MAIN_SCRIPT:?}"
	script_exec="$(systemd_exec_quote "$script")" || {
		echo "launchlayer: executable path contains a newline and cannot be used in a systemd unit" >&2
		return 1
	}
	mkdir -p "$unit_dir"
	service="$unit_dir/launchlayer-maintenance.service"
	timer="$unit_dir/launchlayer-maintenance.timer"

	cat > "$service" <<EOF
# Managed by launchlayer — safe to remove manually.
[Unit]
Description=Steam launch maintenance (stale cleanup + cache report)

[Service]
Type=oneshot
ExecStart=${script_exec} --run-maintenance
StandardOutput=journal
StandardError=journal
EOF

	if [[ -f "$(launchlayer_share_dir)/systemd/launchlayer-maintenance.timer" ]]; then
		install -Dm644 "$(launchlayer_share_dir)/systemd/launchlayer-maintenance.timer" "$timer"
	else
		cat > "$timer" <<EOF
[Unit]
Description=Periodic launchlayer maintenance

[Timer]
OnBootSec=15min
OnUnitActiveSec=12h
Persistent=true

[Install]
WantedBy=timers.target
EOF
	fi

	if command -v systemctl >/dev/null 2>&1; then
		systemctl --user daemon-reload
		systemctl --user enable --now launchlayer-maintenance.timer 2>/dev/null \
			&& echo "Enabled launchlayer-maintenance.timer" \
			|| echo "Wrote units to $unit_dir (enable manually with systemctl --user enable --now launchlayer-maintenance.timer)"
	else
		echo "Wrote units to $unit_dir"
	fi
	echo "  service: $service"
	echo "  timer:   $timer"
}

# _write_backup_timer_unit — Write user backup timer from saved preferences.
_write_backup_timer_unit() {
	local timer=$1
	load_backup_prefs
	cat > "$timer" <<EOF
# Managed by launchlayer — safe to remove manually.
[Unit]
Description=Periodic LaunchLayer config backup

[Timer]
EOF
	if [[ "$BACKUP_PREFS_TIMER_TYPE" == interval ]]; then
		cat >> "$timer" <<EOF
OnBootSec=${BACKUP_PREFS_ON_BOOT_SEC}
OnUnitActiveSec=${BACKUP_PREFS_ON_UNIT_ACTIVE_SEC}
Persistent=true
EOF
	else
		cat >> "$timer" <<EOF
OnCalendar=${BACKUP_PREFS_ON_CALENDAR}
Persistent=true
RandomizedDelaySec=${BACKUP_PREFS_RANDOMIZED_DELAY_SEC}
EOF
	fi
	cat >> "$timer" <<EOF

[Install]
WantedBy=timers.target
EOF
}

# _backup_timer_schedule_from_unit — Read schedule lines from an installed timer unit.
_backup_timer_schedule_from_unit() {
	local timer=$1
	local calendar interval boot
	calendar="$(grep -E '^OnCalendar=' "$timer" 2>/dev/null | head -1 | cut -d= -f2- || true)"
	interval="$(grep -E '^OnUnitActiveSec=' "$timer" 2>/dev/null | head -1 | cut -d= -f2- || true)"
	boot="$(grep -E '^OnBootSec=' "$timer" 2>/dev/null | head -1 | cut -d= -f2- || true)"
	if [[ -n "$calendar" ]]; then
		printf 'calendar %s\n' "$calendar"
	elif [[ -n "$interval" ]]; then
		printf 'interval boot=%s active=%s\n' "${boot:-15min}" "$interval"
	fi
}

# systemd_backup_units_installed_p — True when backup service and timer unit files exist.
systemd_backup_units_installed_p() {
	local unit_dir
	unit_dir="$(systemd_user_dir)"
	[[ -f "$unit_dir/launchlayer-backup.service" && -f "$unit_dir/launchlayer-backup.timer" ]]
}

# systemd_backup_timer_enabled_p — True when the user backup timer is enabled.
systemd_backup_timer_enabled_p() {
	command -v systemctl >/dev/null 2>&1 \
		&& systemctl --user is-enabled launchlayer-backup.timer >/dev/null 2>&1
}

# systemd_backup_service_enabled_p — True when the oneshot service is enabled for manual start.
systemd_backup_service_enabled_p() {
	local state
	command -v systemctl >/dev/null 2>&1 || return 1
	state="$(systemctl --user is-enabled launchlayer-backup.service 2>/dev/null || true)"
	[[ "$state" == enabled ]]
}

# systemd_backup_timer_brief_state — not_installed, installed, or enabled.
systemd_backup_timer_brief_state() {
	if ! systemd_backup_units_installed_p; then
		printf 'not_installed\n'
	elif systemd_backup_timer_enabled_p; then
		printf 'enabled\n'
	else
		printf 'installed\n'
	fi
}

# enable_systemd_backup_timer — Enable (and install) the backup timer.
enable_systemd_backup_timer() {
	if ! systemd_backup_units_installed_p; then
		install_systemd_backup_units 0
	fi
	if ! command -v systemctl >/dev/null 2>&1; then
		echo "systemctl not found" >&2
		return 1
	fi
	systemctl --user daemon-reload
	systemctl --user enable --now launchlayer-backup.timer \
		&& echo "Enabled launchlayer-backup.timer" \
		|| {
			echo "Failed to enable launchlayer-backup.timer" >&2
			return 1
		}
}

# disable_systemd_backup_timer — Stop and disable the backup timer (units remain on disk).
disable_systemd_backup_timer() {
	if ! command -v systemctl >/dev/null 2>&1; then
		echo "systemctl not found" >&2
		return 1
	fi
	systemctl --user disable --now launchlayer-backup.timer 2>/dev/null \
		&& echo "Disabled launchlayer-backup.timer" \
		|| echo "launchlayer-backup.timer was not enabled"
}

# enable_systemd_backup_service — Enable the oneshot unit for manual systemctl start.
enable_systemd_backup_service() {
	if ! systemd_backup_units_installed_p; then
		install_systemd_backup_units 0
	fi
	if ! command -v systemctl >/dev/null 2>&1; then
		echo "systemctl not found" >&2
		return 1
	fi
	systemctl --user daemon-reload
	systemctl --user enable launchlayer-backup.service \
		&& echo "Enabled launchlayer-backup.service (manual start)" \
		|| {
			echo "Failed to enable launchlayer-backup.service" >&2
			return 1
		}
}

# disable_systemd_backup_service — Disable manual start of the backup oneshot.
disable_systemd_backup_service() {
	if ! command -v systemctl >/dev/null 2>&1; then
		echo "systemctl not found" >&2
		return 1
	fi
	systemctl --user disable launchlayer-backup.service 2>/dev/null \
		&& echo "Disabled launchlayer-backup.service (manual start)" \
		|| echo "launchlayer-backup.service was not enabled"
}

# uninstall_systemd_backup_units — Remove backup timer/service units from the user systemd dir.
uninstall_systemd_backup_units() {
	local unit_dir service timer
	unit_dir="$(systemd_user_dir)"
	service="$unit_dir/launchlayer-backup.service"
	timer="$unit_dir/launchlayer-backup.timer"
	if command -v systemctl >/dev/null 2>&1; then
		systemctl --user disable --now launchlayer-backup.timer 2>/dev/null || true
		systemctl --user disable launchlayer-backup.service 2>/dev/null || true
		systemctl --user stop launchlayer-backup.service 2>/dev/null || true
		systemctl --user reset-failed launchlayer-backup.service 2>/dev/null || true
	fi
	rm -f "$service" "$timer"
	if command -v systemctl >/dev/null 2>&1; then
		systemctl --user daemon-reload
	fi
	echo "Removed launchlayer-backup.service and launchlayer-backup.timer"
}

# install_systemd_backup_units — Write backup timer/service with resolved script path.
install_systemd_backup_units() {
	local unit_dir script script_exec service timer backup_dir enable_now
	unit_dir="$(systemd_user_dir)"
	script="${LAUNCHLAYER_MAIN_SCRIPT:?}"
	script_exec="$(systemd_exec_quote "$script")" || {
		echo "launchlayer: executable path contains a newline and cannot be used in a systemd unit" >&2
		return 1
	}
	enable_now=${1:-1}

	backup_prefs_apply_env
	backup_dir="${LAUNCHLAYER_BACKUP_DIR}"
	mkdir -p "$unit_dir" "$backup_dir"
	service="$unit_dir/launchlayer-backup.service"
	timer="$unit_dir/launchlayer-backup.timer"

	cat > "$service" <<EOF
# Managed by launchlayer — safe to remove manually.
# Retention/pruning: ~/.config/launchlayer/backup.conf (keep, auto_prune)
[Unit]
Description=LaunchLayer config backup and archive pruning

[Service]
Type=oneshot
ExecStart=${script_exec} --run-scheduled-backup
StandardOutput=journal
StandardError=journal
EOF

	_write_backup_timer_unit "$timer"

	if command -v systemctl >/dev/null 2>&1; then
		systemctl --user daemon-reload
		if [[ "$enable_now" == "1" ]]; then
			systemctl --user enable --now launchlayer-backup.timer 2>/dev/null \
				&& echo "Enabled launchlayer-backup.timer" \
				|| echo "Wrote units to $unit_dir (enable manually with systemctl --user enable --now launchlayer-backup.timer)"
		else
			echo "Wrote units to $unit_dir (not enabled — run: launchlayer --backup-timer enable)"
		fi
	else
		echo "Wrote units to $unit_dir"
	fi
	echo "  service: $service"
	echo "  timer:   $timer"
	echo "  backup_dir: $backup_dir"
	echo "  prune: $(backup_prune_summary)"
	echo "  schedule: $(backup_prefs_schedule_summary)"
}

# systemd_backup_status — Report whether backup timer is installed and enabled.
systemd_backup_status() {
	local unit_dir service timer schedule
	unit_dir="$(systemd_user_dir)"
	service="$unit_dir/launchlayer-backup.service"
	timer="$unit_dir/launchlayer-backup.timer"
	load_backup_prefs
	if [[ -f "$service" && -f "$timer" ]]; then
		schedule="$(_backup_timer_schedule_from_unit "$timer")"
		[[ -n "$schedule" ]] || schedule="$(backup_prefs_schedule_summary)"
		if command -v systemctl >/dev/null 2>&1 \
			&& systemctl --user is-enabled launchlayer-backup.timer >/dev/null 2>&1; then
			echo "backup_timer: enabled (launchlayer-backup.timer)"
		else
			echo "backup_timer: installed but timer not enabled ($timer)"
		fi
		grep -qF "$LAUNCHLAYER_MAIN_SCRIPT" "$service" 2>/dev/null \
			&& echo "backup_timer: script path current" \
			|| echo "backup_timer: script path stale — re-run --backup-timer install"
		echo "backup_timer: dir=${BACKUP_PREFS_DIR}"
		echo "backup_timer: prune=$(backup_prune_summary)"
		echo "backup_timer: schedule=$schedule"
		echo "backup_timer: prefs=$(backup_prefs_path)"
	else
		echo "backup_timer: not installed (run --backup-timer install)"
		echo "backup_timer: prefs=$(backup_prefs_path) ($(backup_prefs_schedule_summary), $(backup_prune_summary))"
	fi
}

# handle_backup_timer_subcommand — Install, enable, disable, or show backup timer status.
handle_backup_timer_subcommand() {
	local action=${1:-status} backup_dir="" keep="" schedule="" install_enable=1 prefs_changed=0 arg
	shift || true
	load_backup_prefs
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--dir) backup_dir=${2:-}; shift 2 ;;
			--keep) keep=${2:-}; shift 2 ;;
			--schedule) schedule=${2:-}; shift 2 ;;
			--no-enable) install_enable=0; shift ;;
			*) shift ;;
		esac
	done
	[[ -n "$backup_dir" ]] && { BACKUP_PREFS_DIR="$backup_dir"; prefs_changed=1; }
	[[ -n "$keep" ]] && { BACKUP_PREFS_KEEP="$keep"; prefs_changed=1; }
	if [[ -n "$schedule" ]]; then
		backup_prefs_set_schedule_custom "$schedule" || {
			echo "Invalid --schedule value: $schedule" >&2
			return 1
		}
		prefs_changed=1
	fi
	(( prefs_changed )) && save_backup_prefs
	backup_prefs_apply_env

	case "$action" in
		install)
			install_systemd_backup_units "$install_enable"
			;;
		enable)
			enable_systemd_backup_timer
			;;
		disable)
			disable_systemd_backup_timer
			;;
		enable-service)
			enable_systemd_backup_service
			;;
		disable-service)
			disable_systemd_backup_service
			;;
		uninstall)
			uninstall_systemd_backup_units
			;;
		reinstall)
			install_systemd_backup_units 0
			;;
		status)
			systemd_backup_status
			;;
		*)
			echo "Usage: $0 --backup-timer [install|enable|disable|enable-service|disable-service|uninstall|status|reinstall] [--dir PATH] [--keep N] [--schedule ON_CALENDAR] [--no-enable]" >&2
			return 1
			;;
	esac
}

# handle_backup_prefs_subcommand — Manage backup.conf (show, reset, set, set-schedule).
handle_backup_prefs_subcommand() {
	local action=${1:-show} json=0 reinstall=0
	shift || true
	load_backup_prefs
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--json) json=1; shift ;;
			--reinstall-timer) reinstall=1; shift ;;
			*) break ;;
		esac
	done

	case "$action" in
		show)
			show_backup_prefs "$json"
			;;
		reset)
			reset_backup_prefs || return $?
			if [[ "$reinstall" == "1" ]]; then
				local was_enabled=0
				if command -v systemctl >/dev/null 2>&1 \
					&& systemctl --user is-enabled launchlayer-backup.timer >/dev/null 2>&1; then
					was_enabled=1
				fi
				install_systemd_backup_units "$was_enabled"
			fi
			;;
		set-schedule)
			local preset=${1:-} arg2=${2:-} arg3=${3:-}
			case "$preset" in
				daily)
					backup_prefs_set_schedule_daily "${arg2:-03:15}" || return 1
					;;
				weekly)
					backup_prefs_set_schedule_weekly "${arg2:-Sun}" "${arg3:-03:15}" || return 1
					;;
				interval)
					backup_prefs_set_schedule_interval "${arg2:-12h}" "${arg3:-15min}" || return 1
					;;
				custom)
					backup_prefs_set_schedule_custom "$arg2" || return 1
					;;
				*)
					echo "Usage: $0 --backup-prefs set-schedule {daily|weekly|interval|custom} [args...]" >&2
					return 1
					;;
			esac
			save_backup_prefs
			echo "Updated schedule: $(backup_prefs_schedule_summary)"
			;;
		set)
			local key=${1:-} val=${2:-}
			[[ -n "$key" && -n "$val" ]] || {
				echo "Usage: $0 --backup-prefs set KEY VALUE" >&2
				echo "Keys: dir, keep, auto_prune, delay, include_local, include_profiles, include_tui" >&2
				echo "  keep: non-negative integer (0=unlimited retention)" >&2
				return 1
			}
			backup_prefs_set_key "$key" "$val" || return $?
			save_backup_prefs
			echo "Set $key=$val"
			;;
		*)
			echo "Usage: $0 --backup-prefs {show|reset|set|set-schedule} [args...] [--json] [--reinstall-timer]" >&2
			return 1
			;;
	esac
}

# systemd_user_status — Report whether maintenance timer is installed.
systemd_user_status() {
	local unit_dir service timer
	unit_dir="$(systemd_user_dir)"
	service="$unit_dir/launchlayer-maintenance.service"
	timer="$unit_dir/launchlayer-maintenance.timer"
	if [[ -f "$service" && -f "$timer" ]]; then
		if command -v systemctl >/dev/null 2>&1 \
			&& systemctl --user is-enabled launchlayer-maintenance.timer >/dev/null 2>&1; then
			echo "systemd: enabled (launchlayer-maintenance.timer)"
		else
			echo "systemd: installed but timer not enabled ($timer)"
		fi
		grep -qF "$LAUNCHLAYER_MAIN_SCRIPT" "$service" 2>/dev/null \
			&& echo "systemd: script path current" \
			|| echo "systemd: script path stale — re-run --install-systemd"
	else
		echo "systemd: not installed (run --install-systemd)"
	fi
}
