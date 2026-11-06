#!/usr/bin/env bash
# Use the repository's ordinary validation entry points in disposable CI.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
case ${1:-} in
	shell)
		apt-get update
		apt-get install --yes --no-install-recommends bats ca-certificates curl git jq make parallel python3 shellcheck
		make check check-pages BATS_JOBS=2
		;;
	hub)
		apt-get update
		apt-get install --yes --no-install-recommends bash ca-certificates git
		manager=$(node -p 'require("./hub/package.json").packageManager')
		[[ $manager =~ ^pnpm@[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Expected an exact pnpm version\n' >&2; exit 1; }
		npm install --global "$manager" --ignore-scripts --no-audit
		bash scripts/hub-pm.sh install --frozen-lockfile
		bash scripts/hub-pm.sh lint
		bash scripts/hub-pm.sh test
		bash scripts/hub-pm.sh test:coverage
		;;
	*) printf 'Usage: scripts/woodpecker-linux.sh {shell|hub}\n' >&2; exit 2 ;;
esac
