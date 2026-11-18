#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/launchlayer-bash-4.3.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
archive="$scratch/bash-4.3.30.tar.gz"
checksum=317881019bbf2262fb814b7dd8e40632d13c3608d2f237800a8828fbb8a640dd

curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error --max-time 120 \
	--output "$archive" https://ftp.gnu.org/gnu/bash/bash-4.3.30.tar.gz
printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check
tar -xzf "$archive" -C "$scratch"
(
	cd -- "$scratch/bash-4.3.30"
	CC=gcc CFLAGS=-std=gnu89 ./configure --prefix="$scratch/install" --without-bash-malloc
	make -j2
	make install
)

cd -- "$root"
minimum_bash="$scratch/install/bin/bash"
find launchlayer lib scripts -type f \( -name '*.sh' -o -name 'launchlayer' \) -print0 |
	xargs -0 -n1 "$minimum_bash" -n
"$minimum_bash" ./launchlayer --version
"$minimum_bash" ./launchlayer --help >/dev/null
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}' |
	"$minimum_bash" ./launchlayer --mcp | grep -q '"name":"launchlayer"'
