#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Copies the shared scripts of this repository (docs/GITHUB.md "Shared scripts") into other checkouts:
#   scripts/sync-shared.sh <repository checkout> ...
# Every shared script a checkout already carries is replaced by the source here; the copy keeps its own SPDX line
# (the license of the repository's scripts). A checkout that has no copy of a script gets none (add it by hand
# once, with its configuration file). scripts/check-shared.sh is the check the CI runs.
# shellcheck disable=SC2154 # shared_scripts and spdx_line_re come from shared-scripts.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$here/shared-scripts.sh"

[ "$#" -gt 0 ] || { echo "usage: scripts/sync-shared.sh <repository checkout> ..." >&2; exit 2; }
for target in "$@"; do
  for name in "${shared_scripts[@]}"; do
    copy="$target/scripts/$name"
    [ -f "$copy" ] || continue
    spdx="$(grep -m 1 -E "$spdx_line_re" "$copy" || true)"
    [ -n "$spdx" ] || { echo "$copy: no SPDX line, not updated" >&2; exit 1; }
    tmp="$(mktemp)"
    SPDX="$spdx" RE="$spdx_line_re" awk '!done && $0 ~ ENVIRON["RE"] { print ENVIRON["SPDX"]; done = 1; next } { print }' \
      "$here/$name" > "$tmp"
    if cmp -s "$tmp" "$copy"; then
      rm -f "$tmp"
    else
      cat "$tmp" > "$copy" && rm -f "$tmp"
      echo "updated $copy"
    fi
  done
done
