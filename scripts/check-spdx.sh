#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Checks that every script and workflow of this repository carries its SPDX header (LICENSE.md):
# `# SPDX-License-Identifier: <id>` as the first line, or the second line after a shebang.
# Documents, templates and small configuration files get their license from LICENSE.md and carry no header.
# Usage: scripts/check-spdx.sh [--fix]   (--fix inserts missing headers; wrong ones are only reported)
set -euo pipefail
cd "$(dirname "$0")/.."

fix=0
[ "${1:-}" = "--fix" ] && fix=1

# Expected license per path (first match wins). Keep in sync with LICENSE.md.
license_for() {
  case "$1" in
    .github/workflows/*.yml | scripts/*.sh) echo Apache-2.0 ;;
    *) echo skip ;;
  esac
}

files=()
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mapfile -d '' files < <(git ls-files -z --cached --others --exclude-standard)
else
  mapfile -d '' files < <(find . -type f -not -path './.git/*' -printf '%P\0')
fi

missing=0
wrong=0
fixed=0
for file in "${files[@]}"; do
  [ -f "$file" ] || continue
  expected=$(license_for "$file")
  [ "$expected" = skip ] && continue
  header="# SPDX-License-Identifier: $expected"
  line=1
  [[ "$(head -n 1 "$file")" == '#!'* ]] && line=2
  actual=$(sed -n "${line}p" "$file")
  [ "$actual" = "$header" ] && continue
  if [[ "$actual" == '# SPDX-License-Identifier:'* ]]; then
    echo "$file: wrong license header '$actual' (expected '$header')" >&2
    wrong=$((wrong + 1))
    continue
  fi
  if [ "$fix" = 1 ]; then
    tmp=$(mktemp)
    if [ "$line" = 2 ]; then
      { head -n 1 "$file"; echo "$header"; tail -n +2 "$file"; } > "$tmp"
    else
      { echo "$header"; cat "$file"; } > "$tmp"
    fi
    cat "$tmp" > "$file" && rm -f "$tmp"
    fixed=$((fixed + 1))
  else
    echo "$file: missing '$header'" >&2
    missing=$((missing + 1))
  fi
done

[ "$fixed" -gt 0 ] && echo "inserted $fixed SPDX headers"
if [ "$missing" -gt 0 ] || [ "$wrong" -gt 0 ]; then
  echo "SPDX check failed: $missing missing, $wrong wrong (run scripts/check-spdx.sh --fix for missing headers)" >&2
  exit 1
fi
echo "SPDX headers ok"
