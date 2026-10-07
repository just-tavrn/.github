#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Branch and tag rulesets of the just-tavrn repositories (docs/GITHUB.md, step 8). Idempotent: creates or
# updates the rulesets "main" and "release tags" of every repository named (default: all code repositories
# and this one). Needs `gh` authenticated as a repository admin.
#
# Rulesets are not available on private repositories of the Free plan (the API answers 403 "Upgrade to
# GitHub Pro or make this repository public"); run this when a repository goes public, or after a plan
# upgrade.
#
#   scripts/github-rulesets.sh [--approvals N] [--dry-run] [repo ...]
#
# "main": changes only through pull requests (N approving reviews, default 0 while the maintainers are one
# person; stale reviews are dismissed, review threads must be resolved, merge or squash), every CI check of
# the repository must pass on the latest commit, no force pushes, no deletion. Repository admins may bypass
# the rules through a pull request only (a merge while the CI runner is down), never with a direct push.
# "release tags": v* tags cannot be moved or deleted, not even by admins.
set -euo pipefail

org="just-tavrn"
approvals=0
dry_run=0
repos=()
while [ $# -gt 0 ]; do
  case "$1" in
    --approvals) approvals="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) repos+=("$1"); shift ;;
  esac
done
if [ ${#repos[@]} -eq 0 ]; then
  repos=(.github tavrn tavrn-protocol tavrn-crypto tavrn-js tavrn-node tavrn-web)
fi

# The required status checks per repository: the check names of its CI jobs, the secret scan and the CLA
# check (reusable workflows appear as "<job> / <job name>"). A job that is skipped by its `if:` counts as
# passed, so the gate on CI_ENABLED and the private-only skips do not block merges.
gitleaks="gitleaks / Secret scan (gitleaks)"
cla="cla / Contributor license agreement"
contexts() {
  case "$1" in
    .github)
      printf '%s\n' "Lint (actionlint, shellcheck, SPDX)" "$gitleaks" ;;
    tavrn)
      printf '%s\n' "Markdown lint, links, SPDX headers, shellcheck" "Publication hygiene" "$gitleaks" "$cla" ;;
    tavrn-protocol)
      printf '%s\n' "Schemas, test vectors, SPDX headers, package" "Publication hygiene" "$gitleaks" "$cla" ;;
    tavrn-crypto)
      printf '%s\n' "Rust / Rust (fmt, clippy, test)" "WebAssembly package / JavaScript (install, typecheck, test)" "$gitleaks" "$cla" ;;
    tavrn-js)
      printf '%s\n' "JavaScript / JavaScript (install, typecheck, test)" "Bot integration tests (real nodes)" "Publication hygiene" "$gitleaks" "$cla" ;;
    tavrn-node)
      printf '%s\n' "Rust / Rust (fmt, clippy, test)" "Container image / Container image (tavrn-node)" "SPDX headers, publication hygiene, perf report" "$gitleaks" "$cla" ;;
    tavrn-web)
      printf '%s\n' "JavaScript / JavaScript (install, typecheck, test)" "End-to-end / End-to-end (Playwright)" "Publication hygiene" "$gitleaks" "$cla" ;;
    *) echo "unknown repository $1" >&2; exit 1 ;;
  esac
}

github_actions_app=15368

# JSON array of {context, integration_id} for the repository's checks (names contain no quotes or backslashes).
checks_json() {
  local first=1 c
  printf '['
  while IFS= read -r c; do
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"context":"%s","integration_id":%s}' "$c" "$github_actions_app"
  done < <(contexts "$1")
  printf ']'
}

branch_ruleset() {
  local code_owners=false
  [ "$approvals" -gt 0 ] && code_owners=true
  cat <<JSON
{
  "name": "main", "target": "branch", "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request" } ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": $approvals,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": $code_owners,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["merge", "squash"] } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false,
        "required_status_checks": $(checks_json "$1") } }
  ]
}
JSON
}

tag_ruleset() {
  cat <<'JSON'
{
  "name": "release tags", "target": "tag", "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" }, { "type": "update" } ]
}
JSON
}

apply() { # repo name json
  local repo="$1" name="$2" body="$3" id
  if [ "$dry_run" = 1 ]; then
    echo "== $repo: $name"; printf '%s\n' "$body"; return
  fi
  id="$(gh api "repos/$org/$repo/rulesets" --jq ".[] | select(.name == \"$name\") | .id" 2>/dev/null || true)"
  if [ -n "$id" ]; then
    printf '%s' "$body" | gh api -X PUT "repos/$org/$repo/rulesets/$id" --input - >/dev/null
    echo "$repo: ruleset '$name' updated (#$id)"
  else
    printf '%s' "$body" | gh api -X POST "repos/$org/$repo/rulesets" --input - >/dev/null
    echo "$repo: ruleset '$name' created"
  fi
}

for repo in "${repos[@]}"; do
  apply "$repo" "main" "$(branch_ruleset "$repo")"
  apply "$repo" "release tags" "$(tag_ruleset)"
done
