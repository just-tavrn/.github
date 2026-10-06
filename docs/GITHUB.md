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
   Members and outside collaborators without 2FA are removed, so make sure everyone has it first.
2. **Member privileges**:
   - **Base permissions**: **Read**.
   - **Repository creation**: allow **Private** only; untick **Public** (members may not create public
     repositories; owners still can).
   - **Repository forking**: untick **Allow forking of private repositories**.
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
     pnpm/action-setup@*
     ```
   Actions and reusable workflows from `just-tavrn` repositories are always allowed by this policy.
2. **Fork pull request workflows from outside collaborators** (applies once public): **Require approval for
   all external contributors**. For private repositories leave **Run workflows from fork pull requests**
   unticked.
3. **Workflow permissions**: **Read repository contents and packages permissions**; untick **Allow GitHub
   Actions to create and approve pull requests**. Workflows that need more (CLA comments, image push) ask
   for it in their `permissions:` block.

This repository: **Settings** → **Actions** → **General** → **Access**: **Accessible from repositories in
the 'just-tavrn' organization** (set through the API at creation; check it). Without it the code
repositories cannot call the reusable workflows while this repository is private.

## 3. Tokens and secrets

Both tokens are **fine-grained personal access tokens** of the owner account (avatar → **Settings** →
**Developer settings** → **Personal access tokens** → **Fine-grained tokens** → **Generate new token**).
Put a renewal reminder in your calendar before the expiry date.

### `CLA_PAT` (CLA bot)

- **Token name**: `just-tavrn CLA signatures`; **Resource owner**: `just-tavrn`; **Expiration**: at most one year.
- **Repository access**: **Only select repositories** → `just-tavrn/cla-signatures`.
- **Repository permissions**: **Contents: Read and write** (the bot commits `signatures/version1/cla.json`);
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

### Container images

`docker-publish.yml` pushes to `ghcr.io/just-tavrn/<image>` with the job token. After the first push open the
package (organization → **Packages** → `tavrn-node` → **Package settings**): under **Manage Actions access**
add `tavrn-web` with **Read** (the e2e workflow pulls the image with its own job token), and keep the
visibility **Private** until the release; then switch it to **Public**.

## 4. Variables: switching CI on

Every workflow job checks the variable `CI_ENABLED`; nothing runs on GitHub while it is unset. Per
repository: **Settings** → **Secrets and variables** → **Actions** → **Variables** → **New repository
variable** `CI_ENABLED` = `true`. Switch it on only after the secrets of step 3 exist, one repository at a time
in release-train order: `.github` (this repository), `tavrn-protocol`, `tavrn-crypto`, `tavrn-js`,
`tavrn-node`, `tavrn-web`. Private repositories use the Free plan's Actions minutes (2,000 per month); set it
back to `false` to stop everything.

## 5. Self-hosted runner `tavrn-e2e` (test host)

The end-to-end suite (`e2e.yml`) runs on a runner on the owner's test host, labelled `tavrn-e2e`.

1. On the test host (Linux x64), install `git`, `curl`, Docker, Node 24 and pnpm (`corepack enable pnpm`).
   Create a dedicated user without sudo rights, for example `github-runner`, and add it to the `docker`
   group (that group is root-equivalent: use a host or VM that serves nothing else of value).
2. Install the browser system dependencies once as root: `npx -y playwright install-deps chromium`.
3. Organization **Settings** → **Actions** → **Runner groups**: if the plan offers custom groups, create
   `tavrn-e2e` with **Selected repositories: tavrn-web** and **Allow public repositories** unticked;
   otherwise the runner goes into the **Default** group.
4. Organization **Settings** → **Actions** → **Runners** → **New runner** → **New self-hosted runner** →
   **Linux**, **x64**. Run the shown download and checksum commands as `github-runner` in
   `/opt/actions-runner`, then configure with the shown token:
   ```bash
   ./config.sh --url https://github.com/just-tavrn --token <TOKEN> \
     --name tavrn-e2e-1 --labels tavrn-e2e --runnergroup tavrn-e2e --work _work --unattended
   sudo ./svc.sh install github-runner
   sudo ./svc.sh start
   ```
   (`--runnergroup Default` when step 3 was not possible.)
5. Check that the runner shows **Idle** with the labels `self-hosted`, `Linux`, `X64`, `tavrn-e2e`.
6. Keep the runner off fork pull requests: the e2e callers run on pushes to `main` and by hand
   (`workflow_dispatch`), never on `pull_request` events of forks. A self-hosted runner executes the code it
   is given on the test host.

## 6. Community: Discussions, labels, profile

1. **Discussions** on this repository are enabled (API). Create the categories **Q&A** (answers marked),
   **Ideas**, **Show and tell** and **Announcements** (maintainers only).
2. Once this repository is public: organization **Settings** → **Discussions** → **Enable discussions for
   this organization**, source repository **.github**.
3. Labels: `scripts/github-labels.sh just-tavrn/<repo>` creates the common label set (applied to this
   repository; the code repositories have their own copy). Optionally mirror the list under organization
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

## 8. When the repositories go public

In this order: make `.github` public, then the code repositories in release-train order. Per code repository:

1. Branch protection for `main` (a ruleset under **Settings** → **Rules**): require a pull request with one
   approval from code owners, require the status checks (CI jobs, gitleaks, CLA), require a linear history,
   block force pushes and deletions.
2. Turn on secret scanning push protection and private vulnerability reporting (step 7 if not org-wide).
3. Move `CLA_PAT` to the organization secret only, delete `TAVRN_READ_PAT` once the git references have
   become published package versions.
4. `cla-signatures` **stays private** forever.

## Applied through the API

Set when the repositories were created (`gh api -X PATCH repos/just-tavrn/<repo>`):

| Repository | Settings |
|---|---|
| `.github` | private; default branch `main`; issues on; Discussions on; wiki off; projects off; squash merge only (pull-request title and description as the commit); delete branch on merge; Actions access: organization; default workflow token read-only; labels from `scripts/github-labels.sh` |
| `cla-signatures` | private; default branch `main`; issues off; wiki off; projects off; squash merge only; delete branch on merge; Actions disabled |
