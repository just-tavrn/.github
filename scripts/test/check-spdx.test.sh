#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Tests of scripts/check-spdx.sh on a throwaway repository with one file per header syntax. Run:
# scripts/test/check-spdx.test.sh
set -euo pipefail

src="$(cd "$(dirname "$0")/.." && pwd)/check-spdx.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null
failures=0
n=0
check() { # <name> <expected exit> <grep -E pattern of the output or -> command...
  local name="$1" want="$2" match="$3" status=0
  shift 3
  n=$((n + 1))
  "$@" > "$work/out" 2>&1 || status=$?
  if [ "$status" = "$want" ] && { [ "$match" = - ] || grep -qE -- "$match" "$work/out"; }; then echo "ok $n - $name"; else
    echo "not ok $n - $name (exit $status, want $want)"; sed 's/^/    /' "$work/out"; failures=$((failures + 1)); fi
}

r="$work/repo"
mkdir -p "$r/scripts" "$r/src" "$r/deploy" "$r/site" "$r/vendor"
git -C "$r" init -q
cp "$src" "$r/scripts/check-spdx.sh"
cat > "$r/scripts/spdx-map.sh" <<'MAP'
# SPDX-License-Identifier: MIT
# shellcheck shell=bash disable=SC2034
spdx_files=()
license_for() {
  case "$1" in
    vendor/* | scripts/check-spdx.sh) echo skip ;;
    README.md) echo skip ;;
    *) echo MIT ;;
  esac
}
MAP
printf '#![forbid(unsafe_code)]\n' > "$r/src/lib.rs"
printf '#!/usr/bin/env bash\necho hi\n' > "$r/scripts/run.sh"
printf '# syntax=docker/dockerfile:1\nFROM scratch\n' > "$r/deploy/Dockerfile"
printf 'body {}\n' > "$r/site/a.css"
printf '<p>hi</p>\n' > "$r/site/b.astro"
printf 'name: x\n' > "$r/ci.yml"
printf 'no header\n' > "$r/vendor/x.js"
printf '# readme\n' > "$r/README.md"

check "missing headers are reported" 1 'SPDX check failed: 6 missing, 0 wrong' bash "$r/scripts/check-spdx.sh"
check "--fix inserts them" 0 'inserted 6 SPDX headers' bash "$r/scripts/check-spdx.sh" --fix
check "clean after the fix" 0 'SPDX headers ok' bash "$r/scripts/check-spdx.sh"
check "a Rust inner attribute is no shebang" 0 - grep -qx '// SPDX-License-Identifier: MIT' <(head -n 1 "$r/src/lib.rs")
check "after the shebang" 0 - grep -qx '# SPDX-License-Identifier: MIT' <(sed -n 2p "$r/scripts/run.sh")
check "after the Dockerfile syntax directive" 0 - grep -qx '# SPDX-License-Identifier: MIT' <(sed -n 2p "$r/deploy/Dockerfile")
check "CSS comment" 0 - grep -qxF '/* SPDX-License-Identifier: MIT */' <(head -n 1 "$r/site/a.css")
check "Astro frontmatter" 0 - diff <(head -n 3 "$r/site/b.astro") <(printf -- '---\n// SPDX-License-Identifier: MIT\n---\n')
check "YAML comment" 0 - grep -qx '# SPDX-License-Identifier: MIT' <(head -n 1 "$r/ci.yml")
check "skipped paths stay untouched" 0 - grep -qx 'no header' "$r/vendor/x.js"
sed -i '1s/MIT/Apache-2.0/' "$r/ci.yml"
check "a wrong license is reported" 1 "ci.yml: wrong license header" bash "$r/scripts/check-spdx.sh"
check "outside a git checkout" 2 'not a git checkout' bash -c "mkdir -p '$work/plain/scripts' && cp '$r/scripts/'*.sh '$work/plain/scripts/' && bash '$work/plain/scripts/check-spdx.sh'"

echo "1..$n"
[ "$failures" -eq 0 ] || { echo "$failures of $n failed" >&2; exit 1; }
