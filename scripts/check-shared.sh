#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Checks that the shared scripts of a checkout are identical to the source in this repository (docs/GITHUB.md
# "Shared scripts"), apart from their SPDX line:
#   scripts/check-shared.sh <repository checkout>
# Run by the reusable workflow shared-scripts.yml in every code repository. On a difference it prints the diff and
# the fix: scripts/sync-shared.sh <checkout> (a change belongs in the source here first).
# shellcheck disable=SC2154 # shared_scripts and spdx_line_re come from shared-scripts.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$here/shared-scripts.sh"

[ "$#" -eq 1 ] || { echo "usage: scripts/check-shared.sh <repository checkout>" >&2; exit 2; }
target="$1"
strip() { grep -v -E "$spdx_line_re" "$1" || true; }
drift=0
checked=0
for name in "${shared_scripts[@]}"; do
  copy="$target/scripts/$name"
  [ -f "$copy" ] || continue
  checked=$((checked + 1))
  if ! grep -q -E "$spdx_line_re" "$copy"; then
    echo "::error file=scripts/$name::scripts/$name has no SPDX line"
    drift=$((drift + 1))
    continue
  fi
  if ! diff -u --label "just-tavrn/.github scripts/$name" --label "scripts/$name" <(strip "$here/$name") <(strip "$copy"); then
    echo "::error file=scripts/$name::scripts/$name differs from the shared source in just-tavrn/.github (run its scripts/sync-shared.sh on this checkout; change the source first)"
    drift=$((drift + 1))
  fi
done
[ "$checked" -gt 0 ] || { echo "::error::no shared script found under $target/scripts"; exit 1; }
[ "$drift" -eq 0 ] || exit 1
echo "shared scripts in sync ($checked checked)"
