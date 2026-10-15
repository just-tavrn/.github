#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Tests of scripts/sync-shared.sh and scripts/check-shared.sh on a throwaway checkout whose copies carry another
# SPDX line. Run: scripts/test/shared-scripts.test.sh
set -euo pipefail

scripts="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0
n=0
check() { # <name> <expected exit> command...
  local name="$1" want="$2" status=0
  shift 2
  n=$((n + 1))
  "$@" > "$work/out" 2>&1 || status=$?
  if [ "$status" = "$want" ]; then echo "ok $n - $name"; else
    echo "not ok $n - $name (exit $status, want $want)"; sed 's/^/    /' "$work/out"; failures=$((failures + 1)); fi
}

mkdir -p "$work/repo/scripts"
# An MPL-2.0 repository with an outdated copy of two shared scripts and none of the others.
printf '#!/usr/bin/env bash\n# SPDX-License-Identifier: MPL-2.0\necho old\n' > "$work/repo/scripts/check-spdx.sh"
printf '// SPDX-License-Identifier: MPL-2.0\nconsole.log("old");\n' > "$work/repo/scripts/check-js-licenses.mjs"

check "an outdated copy fails" 1 bash "$scripts/check-shared.sh" "$work/repo"
check "sync" 0 bash "$scripts/sync-shared.sh" "$work/repo"
check "in sync after the sync" 0 bash "$scripts/check-shared.sh" "$work/repo"
check "the copy keeps its SPDX line" 0 grep -qx '# SPDX-License-Identifier: MPL-2.0' "$work/repo/scripts/check-spdx.sh"
check "the JavaScript copy keeps its SPDX line" 0 grep -qx '// SPDX-License-Identifier: MPL-2.0' "$work/repo/scripts/check-js-licenses.mjs"
check "no copy is added" 1 test -e "$work/repo/scripts/publish-check.sh"
check "everything but the SPDX line is the source" 0 \
  diff <(grep -v 'SPDX-License-Identifier: ' "$scripts/check-spdx.sh") <(grep -v 'SPDX-License-Identifier: ' "$work/repo/scripts/check-spdx.sh")
echo "# local change" >> "$work/repo/scripts/check-spdx.sh"
check "a local change fails" 1 bash "$scripts/check-shared.sh" "$work/repo"
check "a checkout without shared scripts fails" 1 bash "$scripts/check-shared.sh" "$work"

echo "1..$n"
[ "$failures" -eq 0 ] || { echo "$failures of $n failed" >&2; exit 1; }
