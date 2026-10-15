#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Tests of scripts/publish-check.sh: each case builds a throwaway git repository with a copy of the script and checks
# the exit code and the findings. gitleaks is replaced by a stub that finds nothing (its own rules are not under
# test). Run: scripts/test/publish-check.test.sh
set -euo pipefail

src="${PUBLISH_CHECK_SCRIPT:-$(cd "$(dirname "$0")/../.." && pwd)/scripts/publish-check.sh}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
printf '#!/bin/sh\nexit 0\n' > "$work/bin/gitleaks"
chmod +x "$work/bin/gitleaks"
export PATH="$work/bin:$PATH"
unset PUBLISH_CHECK_PRIVATE PUBLISH_CHECK_ALLOW_UNCONFIGURED
# No global git configuration (a global excludes file would hide the files under test).
export GIT_CONFIG_GLOBAL=/dev/null

failures=0
n=0

# A fresh repository under $work/<name>/repo (the parent holds no pattern list) with the script in scripts/.
repo() {
  local r="$work/$1/repo"
  mkdir -p "$r/scripts"
  cp "$src" "$r/scripts/publish-check.sh"
  git -C "$r" init -q
  echo "$r"
}

# expect <name> <exit code> <grep -E pattern the output must match or "-"> <grep -F string the output must NOT contain or "-"> -- command...
expect() {
  local name="$1" want="$2" match="$3" absent="$4"
  shift 5
  n=$((n + 1))
  local out status=0
  out="$("$@" 2>&1)" || status=$?
  local ok=1
  [ "$status" = "$want" ] || ok=0
  if [ "$match" != - ] && ! grep -qE -- "$match" <<< "$out"; then ok=0; fi
  if [ "$absent" != - ] && grep -qF -- "$absent" <<< "$out"; then ok=0; fi
  if [ "$ok" = 1 ]; then
    echo "ok $n - $name"
  else
    echo "not ok $n - $name (exit $status, want $want)"
    printf '%s\n' "$out" | sed 's/^/    /'
    failures=$((failures + 1))
  fi
}

# A multi-word pattern from PUBLISH_CHECK_PRIVATE keeps its inner space (surrounding spaces are trimmed).
r="$(repo multiword)"
printf 'line one\nAcme Corp Example\n' > "$r/notes.txt"
expect "multi-word pattern from the environment" 1 'private domain/address in notes.txt:2' 'Acme Corp' -- \
  env PUBLISH_CHECK_PRIVATE=" Acme Corp , other.invalid" bash "$r/scripts/publish-check.sh" "$r"
printf 'AcmeCorp\n' > "$r/notes.txt"
expect "the pattern is not squeezed to its letters" 0 'publish-check: ok' - -- \
  env PUBLISH_CHECK_PRIVATE="Acme Corp" bash "$r/scripts/publish-check.sh" "$r"

# Pattern lists: one string per line, comments skipped, surrounding spaces trimmed, a last line without newline.
r="$(repo lists)"
printf '# a comment\n  private.invalid  \nsecond.invalid' > "$r/.publish-check.private"
echo ".publish-check.private" > "$r/.gitignore"
printf 'see second.invalid here\n' > "$r/a file: with spaces.md"
expect "pattern list with spaces and no final newline" 1 'private domain/address in a file: with spaces.md:1' 'second.invalid' -- \
  bash "$r/scripts/publish-check.sh" "$r"

# Without any pattern the check fails, unless the CI allows it for Dependabot.
r="$(repo unconfigured)"
printf 'hello\n' > "$r/README.md"
expect "no patterns configured" 1 'no private domains or addresses configured' - -- bash "$r/scripts/publish-check.sh" "$r"
expect "no patterns, allowed for Dependabot" 0 'private-pattern check skipped' - -- \
  env PUBLISH_CHECK_ALLOW_UNCONFIGURED=1 bash "$r/scripts/publish-check.sh" "$r"

# Secret patterns: file and line, never the text; documented examples pass.
r="$(repo secrets)"
key="AKIA""ABCDEFGHIJKLMNOP"
printf 'a\nb\naws = %s\n' "$key" > "$r/config.txt"
printf 'aws = AKIAIOSFODNN7EXAMPLE\n' > "$r/docs.md"
expect "secret pattern" 1 'possible secret in config.txt:3' "$key" -- \
  env PUBLISH_CHECK_PRIVATE=nothing.invalid bash "$r/scripts/publish-check.sh" "$r"
expect "only one finding per file" 1 '^publish-check: 1 problem' - -- \
  env PUBLISH_CHECK_PRIVATE=nothing.invalid bash "$r/scripts/publish-check.sh" "$r"

# Paths that never belong in a public repository.
r="$(repo paths)"
printf 'X=1\n' > "$r/.env"
printf 'X=\n' > "$r/.env.example"
expect "environment file" 1 'environment file: \.env$' 'environment file: .env.example' -- \
  env PUBLISH_CHECK_PRIVATE=nothing.invalid bash "$r/scripts/publish-check.sh" "$r"

# scripts/publish-check-extra.sh: an allowed literal value in the listed files only; the dots are literal.
r="$(repo extra)"
cat > "$r/scripts/publish-check-extra.sh" <<'EOF'
# shellcheck shell=bash disable=SC2034
# (the strings are split, or this file would contain them itself)
extra_patterns=("node.example.""org" "example.""org")
allow_value="node.example.""org"
allow_files=("README.md")
EOF
printf 'default: https://node.example.org\n' > "$r/README.md"
expect "allowed value in an allowed file" 0 'publish-check: ok' - -- bash "$r/scripts/publish-check.sh" "$r"
printf 'default: https://node.example.org\nmail: someone@example.org\n' > "$r/README.md"
expect "another private string next to the allowed value" 1 'private domain/address in README.md:2' 'someone' -- \
  bash "$r/scripts/publish-check.sh" "$r"
printf 'default: https://nodeXexampleXorg and example.org\n' > "$r/README.md"
expect "the allowed value is a literal, not a regular expression" 1 'private domain/address in README.md:1' - -- \
  bash "$r/scripts/publish-check.sh" "$r"
printf 'https://node.example.org\n' > "$r/README.md"
printf 'https://node.example.org\n' > "$r/page.md"
expect "the allowed value in any other file" 1 'private domain/address in page.md:1' - -- \
  bash "$r/scripts/publish-check.sh" "$r"

echo "1..$n"
if [ "$failures" -gt 0 ]; then
  echo "$failures of $n failed" >&2
  exit 1
fi
