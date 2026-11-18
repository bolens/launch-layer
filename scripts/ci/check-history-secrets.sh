#!/usr/bin/env bash
# Scan the checked-out branch with full ancestry and redacted findings.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."

if [[ $(git rev-parse --is-shallow-repository) != false ]]; then
	printf 'Gitleaks requires a full checkout\n' >&2
	exit 1
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/launchlayer-gitleaks.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
version=8.30.1
archive="$scratch/gitleaks.tar.gz"
checksum=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error --max-time 120 \
	--output "$archive" "https://github.com/gitleaks/gitleaks/releases/download/v$version/gitleaks_${version}_linux_x64.tar.gz"
printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check
tar -xzf "$archive" -C "$scratch" gitleaks
"$scratch/gitleaks" git --redact --no-banner .
