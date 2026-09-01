#!/usr/bin/env bash
# Bump LaunchLayer CLI version strings to VERSION (X.Y.Z, no leading v).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

version=${1:-${VERSION:-}}
version="${version#v}"

if [[ -z "$version" || ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "usage: $0 X.Y.Z   (or make bump-version VERSION=X.Y.Z)" >&2
	exit 1
fi

mapfile -t version_lines < <(sed -n 's/^LAUNCHLAYER_VERSION=//p' lib/cli.sh)
[[ "${#version_lines[@]}" -eq 1 && -n "${version_lines[0]}" ]] || {
	echo "could not read LAUNCHLAYER_VERSION from lib/cli.sh" >&2
	exit 1
}
current=${version_lines[0]}

if [[ "$current" == "$version" ]]; then
	echo "already at $version"
	exit 0
fi

# Rewrite beside the destination so the final rename is atomic and works with
# both GNU and BSD sed. Copying first preserves the executable's file mode.
tmp="$(mktemp lib/.cli-version.XXXXXX)"
trap 'rm -f -- "$tmp"' EXIT
cp -p lib/cli.sh "$tmp"
sed "s/^LAUNCHLAYER_VERSION=.*/LAUNCHLAYER_VERSION=${version}/" lib/cli.sh > "$tmp"
mv -f "$tmp" lib/cli.sh
trap - EXIT

echo "Bumped ${current} → ${version}"
echo "Next: edit CHANGELOG.md, then make check-version"
