#!/usr/bin/env bash
# Run hub package-manager commands via Vite+ (vp) when available, else Corepack/pnpm.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/hub"

usage() {
	echo "usage: hub-pm.sh <install|run|exec|audit|lint|…> [args…]" >&2
	exit 2
}

[[ $# -ge 1 ]] || usage
cmd=$1
shift

if command -v vp >/dev/null 2>&1; then
	case "$cmd" in
	install) exec vp install "$@" ;;
	exec) exec vp exec "$@" ;;
	run) exec vp run "$@" ;;
	audit) exec vp pm audit "$@" ;;
	*) exec vp run "$cmd" "$@" ;;
	esac
fi

if ! command -v pnpm >/dev/null 2>&1 && command -v corepack >/dev/null 2>&1; then
	corepack enable >/dev/null 2>&1 || true
fi

if ! command -v pnpm >/dev/null 2>&1; then
	echo "hub-pm.sh: need vp (Vite+) or pnpm (via Corepack: corepack enable)" >&2
	exit 1
fi

case "$cmd" in
install) exec pnpm install "$@" ;;
exec) exec pnpm exec "$@" ;;
run) exec pnpm run "$@" ;;
audit) exec pnpm audit "$@" ;;
*) exec pnpm run "$cmd" "$@" ;;
esac
