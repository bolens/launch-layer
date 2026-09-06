#!/usr/bin/env bash
# Partition complete Bats files; tests within a file keep their shared state.
set -euo pipefail

if (($# < 4)) || [[ ! $1 =~ ^(unit|integration)$ ]] ||
	[[ ! $2 =~ ^[0-9]{1,2}$ || ! $3 =~ ^[0-9]{1,2}$ ]]; then
	printf 'usage: run-bats-shard.sh unit|integration INDEX COUNT COMMAND [ARGS...]\n' >&2
	exit 2
fi
suite=$1
index=$((10#$2))
count=$((10#$3))
shift 3
if ((count < 1 || index >= count)); then
	printf 'shard index must be smaller than the positive shard count\n' >&2
	exit 2
fi
cd "$(dirname "${BASH_SOURCE[0]}")/.."
LC_ALL=C
shopt -s nullglob
files=(test/"$suite"/*.bats)
selected=()
for ((i = 0; i < ${#files[@]}; i++)); do
	if ((i % count == index)); then
		selected+=("${files[i]}")
	fi
done
if ((${#selected[@]} == 0)); then
	printf 'shard contains no Bats files; reduce the shard count\n' >&2
	exit 2
fi
exec "$@" "${selected[@]}"
