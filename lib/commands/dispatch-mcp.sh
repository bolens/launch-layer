# shellcheck shell=bash
# lib/commands/dispatch-mcp.sh — Local read-only MCP stdio server.

[[ -n "${LAUNCHLAYER_DISPATCH_MCP_LOADED:-}" ]] && return 0
LAUNCHLAYER_DISPATCH_MCP_LOADED=1

dispatch_mcp_subcommand() {
	local verb=${1:-}
	shift || true
	[[ "$verb" == "--mcp" ]] || return 1
	local privacy=standard
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--privacy)
				privacy=${2:-}
				shift 2
				;;
			*)
				echo "Usage: $(cli_basename) --mcp [--privacy standard|redacted]" >&2
				return 2
				;;
		esac
	done
	case "$privacy" in
		standard|redacted) ;;
		*)
			echo "launchlayer: MCP privacy must be standard or redacted" >&2
			return 2
			;;
	esac
	if ! command -v python3 >/dev/null 2>&1; then
		echo "launchlayer: --mcp requires python3" >&2
		return 1
	fi
	export LAUNCHLAYER_MCP_SERVER_VERSION="$LAUNCHLAYER_VERSION"
	export LAUNCHLAYER_MCP_PRIVACY_MODE="$privacy"
	exec python3 "$SCRIPT_DIR/scripts/launchlayer-mcp.py"
}
