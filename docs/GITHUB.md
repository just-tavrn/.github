# GitHub settings set by hand

What the organization owner configures in the GitHub web interface for the `just-tavrn` organization and
this repository. Settings that can be set through the API (`gh api`) were applied when the repositories
were created and are listed at the end for reference. Work through the steps in order.

The organization is on the **Free plan**. Two limits matter while the repositories are private:
organization-level secrets and variables are **not available to private repositories** (set them per
repository until the repositories are public), and branch protection, rulesets, secret scanning and
private vulnerability reporting only work on **public** repositories.

## 1. Members and authentication

Organization **Settings**:

1. **Authentication security**: tick **Require two-factor authentication for everyone in the organization**.
   Members and outside collaborators without 2FA are removed, so make sure everyone has it first (still off
   when checked on 2026-10-07).
2. **Member privileges**:
   - **Base permissions**: **Read** (already set when checked on 2026-10-07).
   - **Repository creation**: allow **Private** only; untick **Public** (members may not create public
     repositories; owners still can). Still allowed when checked on 2026-10-07.
   - **Repository forking**: **Allow forking of private repositories** stays unticked (already off).
   - **Pages creation**: untick public and private (nothing is published through Pages).
   - **Admin repository permissions**: untick **Allow members to delete or transfer repositories** and
     **Allow members to change repository visibilities**.
3. **Teams**: create the team **maintainers** (visible). The `CODEOWNERS` files of the code repositories
   request reviews from `@just-tavrn/maintainers`; give the team **Maintain** on every code repository and
   on this repository.
4. **Personal access tokens** → **Settings**: allow access via **fine-grained personal access tokens**
   (required for the tokens in step 3); you may require administrator approval, then approve the tokens
   under **Pending requests**. Restrict access via classic personal access tokens.

## 2. Actions

Organization **Settings** → **Actions** → **General**:

1. **Policies**: **Allow just-tavrn, and select non-just-tavrn, actions and reusable workflows** with
   - **Allow actions created by GitHub** ticked (actions/checkout, setup-node, upload-artifact, download-artifact),
   - **Allow actions by Marketplace verified creators** ticked (docker/*),
   - **Allow specified actions and reusable workflows** (they are not from verified creators):
     ```
     contributor-assistant/github-action@*,
     dtolnay/rust-toolchain@*,
     Swatinem/rust-cache@*,
     pnpm/action-setup@*,
     taiki-e/install-action@*,
     snok/container-retention-policy@*
     ```
   Actions and reusable workflows from `just-tavrn` repositories are always allowed by this policy.
   (`taiki-e/install-action` installs cargo-deny and tauri-driver in tavrn-web's GitHub-hosted desktop builds;
   `snok/container-retention-policy` is the image retention of this repository, "Container images" below.)
   Tick **Require actions to be pinned to a full-length commit SHA** as well once every workflow pins its
   actions. The organization's reusable workflows are not actions: CI callers use them by branch (`@main`),
   release paths by commit (see "Reusable workflows in release paths" below).
2. **Fork pull request workflows from outside collaborators** (applies once public): **Require approval for
   all external contributors**. For private repositories leave **Run workflows from fork pull requests**
   unticked.
3. **Workflow permissions**: **Read repository contents and packages permissions**; untick **Allow GitHub
   Actions to create and approve pull requests**. Workflows that need more (CLA comments, image push) ask
   for it in their `permissions:` block.

This repository: **Settings** → **Actions** → **General** → **Access**: **Accessible from repositories in
the 'just-tavrn' organization** (set through the API at creation; check it). Without it the code
repositories cannot call the reusable workflows while this repository is private.

### Docs-only changes

`rust-ci.yml` and `js-ci.yml` take `skip: true`: the job is reported as skipped without running anything, which counts
as a passed required check. The code repositories compute it in a `changes` job (Markdown files, `docs/` and the
deploy examples count as docs) so a documentation change runs only the cheap hygiene jobs; the website picks the
documentation up through its source submodules (Dependabot bumps them daily).

### Self-hosted routing, time limits, advisories

[`route.yml`](../.github/workflows/route.yml) is the one place of the trust rule that keeps forks, Dependabot,
`dependabot/*` branches and `pull_request_target` off the self-hosted runners; `rust-ci.yml`, `js-ci.yml`,
`docker-publish.yml` and `e2e.yml` take their `runs-on` from it, and so do the jobs of the code repositories that run
on `tavrn-heavy` outside the reusable workflows (tavrn-web's `desktop.yml`, tavrn-js' bot job). Each reusable workflow
has a `timeout-minutes` input (Rust 45, JavaScript 30, image 60, end-to-end 90, gitleaks 10 minutes): a hung test never
holds one of the two heavy runners for GitHub's default of six hours. `rust-ci.yml` checks cargo-deny's bans, licenses
and sources before the build; the RustSec advisories run in `rust-advisories.yml`, called by a scheduled workflow of
each Rust repository, which opens an issue "RustSec advisories" when one appears (labels `security` and
`dependencies`). A temporary exception in `deny.toml` (`[advisories] ignore`) carries `expires YYYY-MM-DD` in its
reason, next to the tracking issue; once that date (UTC) is past, the scheduled run fails and opens the same issue, so
the exception is fixed or reviewed again ([`check-advisory-expiry.py`](../scripts/check-advisory-expiry.py); a
malformed date fails too, an entry without `expires` is not checked).

### Reusable workflows in release paths

A workflow that runs for a release tag and calls a reusable workflow of this repository (tavrn-node's
`release.yml` calls `docker-publish.yml`) pins it by full commit SHA with the date as a comment, so a later
change on `main` here never reaches a release unreviewed:

```yaml
uses: just-tavrn/.github/.github/workflows/docker-publish.yml@<40-character sha> # main of 2026-10-11
```

Bumping it is a pull request in the calling repository: take the commit of `main` here
(`git ls-remote https://github.com/just-tavrn/.github refs/heads/main`), read the diff of the reusable workflow
since the pinned commit (`git log -p <old>..<new> -- .github/workflows/docker-publish.yml`), replace the SHA and
the date, and let the caller's CI run. CI workflows (pull requests, `main`) keep `@main`.

### The `release` environment

Every job that holds a release secret (the updater signing key of tavrn-web, `NPM_TOKEN`,
`CARGO_REGISTRY_TOKEN`) declares `environment: release`. The environment exists in each repository that
publishes (tavrn-protocol, tavrn-crypto, tavrn-js, tavrn-web): deployment only from tags `v*`, a required
reviewer (an organization owner), and those secrets as environment secrets, never as repository secrets (a
repository secret is readable by every workflow of every branch). Such a job runs no dependency code: it
downloads what an earlier job built and only signs or uploads it. Only organization owners can create `v*`
tags (the tag ruleset, step 8).

### Shared scripts

`scripts/check-spdx.sh`, `scripts/publish-check.sh`, `scripts/github-labels.sh` and `scripts/check-js-licenses.mjs`
of this repository are the source of the copies every code repository carries (copies, so `just check` works offline
and no CI job fetches code at run time). A copy is identical to the source apart from its SPDX line; what differs per
repository lives in a configuration file next to it: `scripts/spdx-map.sh` (the license map, in sync with the
repository's LICENSE.md), `scripts/publish-check-extra.sh` (optional), `scripts/labels.txt` (the repository's own
labels) and `scripts/js-licenses.config.mjs` (packages, extra licenses, verified packages, exceptions). The job
"Shared scripts in sync" of each repository (the reusable `shared-scripts.yml`) compares the copies with `main` here
and fails on a difference. To change one: change the source here (with its test in `scripts/test/`), merge, then run
`scripts/sync-shared.sh <checkout> ...` and open the sync pull requests; until they are merged that job fails in the
repositories not yet synced.

## 3. Tokens and secrets

Both tokens are **fine-grained personal access tokens** of the owner account (avatar → **Settings** →
**Developer settings** → **Personal access tokens** → **Fine-grained tokens** → **Generate new token**).
Put a renewal reminder in your calendar before the expiry date.

### `CLA_PAT` (CLA bot)

- **Token name**: `just-tavrn CLA signatures`; **Resource owner**: `just-tavrn`; **Expiration**: at most one year.
- **Repository access**: **Only select repositories** → `just-tavrn/cla-signatures`.
- **Repository permissions**: **Contents: Read and write** (the bot commits `signatures/version2/cla.json`);
  **Metadata: Read-only** (added automatically). Nothing else, no organization or account permissions.
- The comments, the commit status and the re-run of the check on the pull request use the calling
  workflow's own `GITHUB_TOKEN` (`pull-requests: write`, `statuses: write`, `actions: write` in the caller),
  so the token needs no access to the code repositories.

Store it as the **organization secret** `CLA_PAT` (organization **Settings** → **Secrets and variables** →
**Actions** → **New organization secret**, **Repository access: All repositories**). While the
repositories are private (Free plan) organization secrets do not reach them: also add `CLA_PAT` as a
**repository secret** in every repository whose CLA check you want to run before going public, and delete
those copies once the organization secret takes over.

### `TAVRN_READ_PAT` (private phase only)

The repositories reference each other through a git submodule (the protocol) and git dependencies with tags
(crates and npm packages). The job token of one repository cannot read another private repository, so the
callers pass this token as `READ_TOKEN` to the reusable workflows.

- **Token name**: `just-tavrn CI read`; **Resource owner**: `just-tavrn`; **Expiration**: until the
  planned public release.
- **Repository access**: **Only select repositories** → `tavrn-protocol`, `tavrn-crypto`, `tavrn-js`.
- **Repository permissions**: **Contents: Read-only**, **Metadata: Read-only**.
- Store it as a **repository secret** `TAVRN_READ_PAT` in `tavrn-crypto`, `tavrn-js`, `tavrn-node` and
  `tavrn-web`. Delete the token and the secrets once the repositories are public.

### `PUBLISH_CHECK_PRIVATE` (publication hygiene)

`scripts/publish-check.sh` (job "Publication hygiene" in this repository, `tavrn`, `tavrn-website`, `tavrn-protocol`,
`tavrn-crypto`, `tavrn-js`, `tavrn-node` and `tavrn-web`) refuses
private domains, hosts and addresses. The list cannot live in the public script, so the CI reads it from the
secret `PUBLISH_CHECK_PRIVATE`: comma-separated literal strings, the same as the owner's local, untracked
`.publish-check.private` (one string per line). Pull requests opened by Dependabot run with **Dependabot
secrets** only, never with Actions secrets, so the secret must exist as an **Actions secret and a Dependabot
secret** in every one of those repositories:

```sh
grep -v '^#' .publish-check.private | paste -sd, - | gh secret set PUBLISH_CHECK_PRIVATE -R just-tavrn/<repo>
grep -v '^#' .publish-check.private | paste -sd, - | gh secret set PUBLISH_CHECK_PRIVATE -R just-tavrn/<repo> --app dependabot
```

Fallback: without a configured list the script fails, except when `PUBLISH_CHECK_ALLOW_UNCONFIGURED=1`. The
workflows set that variable for Dependabot's pull requests only (`github.event_name == 'pull_request'` and
`github.actor == 'dependabot[bot]'`): the private-pattern step is then skipped with a warning, while the checks
for private paths, the secret patterns and gitleaks still run and still fail. The push to `main` after the merge
runs the full check with the Actions secret, so a missing Dependabot secret delays a finding, it never hides it
on `main`.

### Container images

`docker-publish.yml` pushes to `ghcr.io/just-tavrn/<image>` with the job token. After the first push open the
package (organization → **Packages** → `tavrn-node` → **Package settings**): under **Manage Actions access**
add `tavrn-web` with **Read** (the e2e workflow pulls `tavrn-node:edge` with its own job token and fails with
"denied" until then), and keep the visibility **Private** until the release; then switch it to **Public**.

Retention: every push to `main` leaves a `sha-*` version (its multi-architecture children stay as untagged
versions). `ghcr-retention.yml` of this repository (weekly on Monday 04:17 UTC, and by hand as a dry run by
default) deletes the `sha-*` versions and the orphaned untagged versions of `tavrn-node`, `tavrn-website` and
`tavrn-bot-platform` older than 14 days and keeps every release tag and `edge`; the action protects the children of
kept multi-architecture images. It runs here, so nothing runs in the image repositories; the job token of this
repository cannot touch their packages, so it needs the secret `GHCR_RETENTION_PAT`: a classic personal access
token of an organization owner with the scopes `read:packages` and `delete:packages` only, renewed yearly
(`gh secret set GHCR_RETENTION_PAT -R just-tavrn/.github`). Release tags themselves are never deleted (the tag ruleset forbids it);
old pre-releases of `tavrn-web` and `tavrn-node` are deleted by hand (`gh release delete`, keeping the tag) once
the installers are no longer referenced.

## 4. Variables: switching CI on

Every workflow job checks the variable `CI_ENABLED`; nothing runs on GitHub while it is unset. Per
repository: **Settings** → **Secrets and variables** → **Actions** → **Variables** → **New repository
variable** `CI_ENABLED` = `true`. Switch it on only after the secrets of step 3 exist, one repository at a time
in release-train order: `.github` (this repository), `tavrn-protocol`, `tavrn-crypto`, `tavrn-js`,
`tavrn-node`, `tavrn-web`. Private repositories use the Free plan's Actions minutes (2,000 per month); set it
back to `false` to stop everything.

## 5. Self-hosted runners (test host)

The heavy CI jobs (`tavrn-heavy`: Rust, JavaScript, container builds) and the end-to-end suite (`tavrn-e2e`)
run on ephemeral self-hosted runners: a Docker Compose stack on an isolated machine of the operator's choice.
Stack, credentials, isolation requirements, memory sizing and updates: [runner/README.md](../runner/README.md).
In short:

1. An isolated machine (typically a dedicated VM) in a network segment that reaches only the internet, with an
   egress allowlist (README, "Isolation").
2. A GitHub App (or a fine-grained PAT) with the organization permission **Self-hosted runners: Read and
   write** for the runner registration (README, "Credentials").
3. Make the package `ghcr.io/just-tavrn/tavrn-runner` public after its first build (`runner-image.yml`).
4. The stack `runner/docker-compose.yml` with the variables of `runner/.env.example` (README, "Deploying the
   stack").
5. Organization **Settings** → **Actions** → **Runner groups** → **Default**: the Free plan has no custom
   groups; tick **Allow public repositories** only when the repositories go public. The workflows keep forks
   and Dependabot off the self-hosted runners only as long as their workflow files are unchanged: a fork pull
   request runs its own copy, so the approval of step 2.2 is the real barrier (runner/README.md, "Security").
6. Desktop builds (tavrn-web's Tauri app): the `tavrn-heavy` runners download the Microsoft CRT and Windows SDK
   into their cache at start, under Microsoft's Visual Studio Build Tools license (README, "Desktop builds");
   the machine's egress allowlist needs `aka.ms` and `download.visualstudio.microsoft.com` for it.

## 6. Community: Discussions, labels, profile

1. **Discussions** live in the umbrella repository `just-tavrn/tavrn` (its `docs/GITHUB.md` lists the
   categories); the profile, `CONTRIBUTING.md`, `SUPPORT.md` and every issue chooser link there. Discussions on
   this repository were enabled at creation and are switched off (`gh api -X PATCH repos/just-tavrn/.github
   -F has_discussions=false`), so there is only one place.
2. Once the repositories are public: organization **Settings** → **Discussions** → **Enable discussions for
   this organization**, source repository **tavrn**.
3. Labels: `scripts/github-labels.sh just-tavrn/<repo>` creates the common label set and the lines of
   `scripts/labels.txt` (each code repository runs its own copy with its own list, "Shared scripts" above). Optionally mirror the list under organization
   **Settings** → **Repository defaults** → **Repository labels** so new repositories start with it.
4. The organization profile (`profile/README.md`) and the default community health files (code of conduct,
   contributing, security, support, issue templates, funding) only take effect while this repository is
   **public**. Make `.github` public first when the project goes public. (A members-only profile would need
   a separate `.github-private` repository.)

## 7. Code security

Organization **Settings** → **Code security** → **Configurations** (or **Global settings**):

1. **Dependency graph** and **Dependabot alerts**: **Enable all**, and enable them automatically for new
   repositories. **Dependabot security updates**: enable as well (the repositories carry `dependabot.yml` for
   version updates).
2. Once public: **Secret scanning** with **push protection** and **Private vulnerability reporting**:
   **Enable all**, and automatically for new public repositories (on the Free plan both work only for public
   repositories). `SECURITY.md` points reporters at the **Report a vulnerability** button.
3. **Dependabot** → **Grant Dependabot access to private repositories**: add `.github`, `tavrn-protocol`,
   `tavrn-crypto` and `tavrn-js`. Without it the `github-actions` updates fail with "Dependabot doesn't have
   access" at the reusable workflows of `.github`, and the submodule and git-dependency updates at the private
   protocol, crypto and js repositories. (Dependabot's own secrets, `TAVRN_READ_PAT` and
   `PUBLISH_CHECK_PRIVATE`, cover the CI of its pull requests, not this lookup.)

## 8. When the repositories go public

In this order: make `.github` public, then the code repositories in release-train order. Delete obsolete
release tags and releases first: the tag ruleset of step 1 makes `v*` tags permanent. Per code repository:

1. Rulesets for `main` and the release tags: `scripts/github-rulesets.sh <repo>` creates (or updates) them
   through the API: changes to `main` only through pull requests with every CI check green on the latest
   commit (the check names per repository are in the script), no force pushes and no deletions; admins may
   bypass through a pull request only; `v*` tags can neither be moved nor deleted, and only organization
   owners can create them (a release tag starts the publish jobs). Reviews: `--approvals 1`
   (with a code-owner review) once there is more than one maintainer. Until the repository is public the API
   refuses rulesets on the Free plan, so the same rule holds as a convention: nobody pushes to `main`, every
   change is a pull request, merged branches are deleted (`delete branch on merge` is set everywhere).
2. Turn on secret scanning push protection and private vulnerability reporting (step 7 if not org-wide).
3. Move `CLA_PAT` to the organization secret only, delete `TAVRN_READ_PAT` once the git references have
   become published package versions.
4. `cla-signatures` **stays private** forever.

## Applied through the API

Set when the repositories were created (`gh api -X PATCH repos/just-tavrn/<repo>`):

| Repository | Settings |
|---|---|
| `.github` | private; default branch `main`; issues on; Discussions on (to be switched off, step 6); wiki off; projects off; squash merge only (pull-request title and description as the commit); delete branch on merge; Actions access: organization; default workflow token read-only; labels from `scripts/github-labels.sh` |
| `cla-signatures` | private; default branch `main`; issues off; wiki off; projects off; squash merge only; delete branch on merge; Actions disabled |

## CLA version 2 rollout

Merge the private signature repository preparation and publish the public agreement before switching the
reusable CLA workflow. Seed `signatures/version2/cla.json` with `{"signedContributors": []}`: the pinned
v2.6.1 action compares missing-file errors to the string `"404"`, so its automatic initialization can fail.
See the [pinned source](https://github.com/contributor-assistant/github-action/blob/ca4a40a7d1004f18d9960b404b97e5f30a505a08/src/setupClaCheck.ts).
Version 2 lives in `agreements/cla-v2.md`; never edit that versioned text after signatures exist.
`CLA.md` is an identical readable entry point. Material changes require a new document, signature directory
and explicit signing sentence. Version 1 had no external signatures when version 2 was prepared; do not
copy signatures between versions. All public repositories, including the website, need their own CLA caller.

Keep `CI_ENABLED=true`, configure `CLA_PAT`, and require `cla / Contributor license agreement` in main's
ruleset. The action fails its workflow job for unsigned contributors; it does not emit a separate
`CLA Assistant` commit status. Verify with a non-allowlisted contributor: unsigned PR blocked; version 2
comment accepted; updated PR accepted; signature recognized in another repo. No repository settings or
secrets are changed merely by editing these files. Check the generated rulesets with `--dry-run` before
applying them, and confirm the job name against an actual workflow run.

The controller's identity and private contact are linked through the project imprint. Publish the website's
CLA privacy section before inviting signatures, and ensure the runtime imprint/contact values are correct.
Check the live imprint and privacy URLs during rollout; local files cannot establish their deployed content.
