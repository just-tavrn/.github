#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Tests of scripts/check-advisory-expiry.py on throwaway deny.toml files, with a fixed date. Run:
# scripts/test/check-advisory-expiry.test.sh
set -euo pipefail

src="$(cd "$(dirname "$0")/.." && pwd)/check-advisory-expiry.py"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
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
deny() { # <file> <reason>: a deny.toml with a plain-string ignore and one entry with that reason
  printf '[advisories]\nignore = [\n  "RUSTSEC-2026-0001",\n  { id = "RUSTSEC-2026-0387", reason = "%s" },\n]\n' "$2" > "$1"
}
run() { python3 -I "$src" --today 2026-10-27 "$@"; }

deny "$work/past.toml" "crypto-bigint 0.5.5 only; tracking https://example.org/24; expires 2026-10-26"
deny "$work/today.toml" "temporary; expires 2026-10-27"
deny "$work/future.toml" "crypto-bigint 0.5.5 only; tracking https://example.org/24; expires 2026-12-26"
deny "$work/none.toml" "unmaintained build-time macro crate"
deny "$work/malformed.toml" "temporary; expires 2026-13-01"
deny "$work/text.toml" "temporary; expires soon"
printf '[advisories]\nyanked = "deny"\n' > "$work/empty.toml"
printf '[graph]\nall-features = true\n' > "$work/noadvisories.toml"
printf '[advisories\n' > "$work/broken.toml"

check "a past date fails" 1 "::error file=$work/past.toml::.*RUSTSEC-2026-0387 expired on 2026-10-26" run "$work/past.toml"
check "the expiry day itself passes" 0 'RUSTSEC-2026-0387 excepted until 2026-10-27' run "$work/today.toml"
check "a future date passes" 0 'RUSTSEC-2026-0387 excepted until 2026-12-26' run "$work/future.toml"
check "no expiry passes" 0 - run "$work/none.toml"
check "an impossible date fails" 1 "malformed expiry date '2026-13-01'" run "$work/malformed.toml"
check "a non-date fails" 1 "malformed expiry date 'soon'" run "$work/text.toml"
check "no ignore list passes" 0 - run "$work/empty.toml" "$work/noadvisories.toml"
check "invalid TOML fails" 1 "::error file=$work/broken.toml::cannot read" run "$work/broken.toml"
check "a missing file fails" 1 'cannot read' run "$work/missing.toml"
check "every file is reported" 1 "file=$work/malformed.toml" run "$work/past.toml" "$work/future.toml" "$work/malformed.toml"
check "both errors counted" 0 - test "$(grep -c '^::error' "$work/out")" = 2
check "today (UTC) by default" 1 'expired on 2000-01-01' bash -c "printf '[advisories]\nignore = [{ id = \"X\", reason = \"expires 2000-01-01\" }]\n' > '$work/old.toml' && python3 -I '$src' '$work/old.toml'"

echo "1..$n"
[ "$failures" -eq 0 ] || { echo "$failures of $n failed" >&2; exit 1; }
