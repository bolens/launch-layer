# shellcheck shell=bash
# lib/commands/dispatch.sh — Top-level CLI verb router (handle_subcommand).

[[ -n "${LAUNCHLAYER_DISPATCH_LOADED:-}" ]] && return 0
LAUNCHLAYER_DISPATCH_LOADED=1

# handle_subcommand — Dispatch utility verbs; return 0 if handled, 1 if unknown.
handle_subcommand() {
	local verb=${1:-}
	shift || true

	dispatch_mcp_subcommand "$verb" "$@" && return 0
	dispatch_launch_subcommand "$verb" "$@" && return 0
	dispatch_config_subcommand "$verb" "$@" && return 0
	dispatch_setup_subcommand "$verb" "$@" && return 0
	dispatch_hub_subcommand "$verb" "$@" && return 0
	dispatch_tui_subcommand "$verb" "$@" && return 0

	case "$verb" in
		--help|-h)
			print_help
			;;
		--version|-V)
			print_version
			;;
		*)
			return 1
			;;
	esac
}
