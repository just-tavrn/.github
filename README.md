# just-tavrn/.github

Organization-wide defaults and shared CI of the [tavrn](https://github.com/just-tavrn) project, a
decentralized, end-to-end encrypted community chat. The organization's landing page is
[profile/README.md](profile/README.md).

## What is here

| Path | Purpose |
|---|---|
| [profile/README.md](profile/README.md) | The organization profile shown on github.com/just-tavrn |
| [CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), [SECURITY.md](SECURITY.md), [SUPPORT.md](SUPPORT.md) | Community health files; GitHub shows them for every repository of the organization that has no own copy |
| [CLA.md](CLA.md) | The individual contributor license agreement the CLA bot asks contributors to sign |
| [TRADEMARK.md](TRADEMARK.md) | The trademark policy for the name and logo |
| [.github/ISSUE_TEMPLATE/](.github/ISSUE_TEMPLATE), [.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md) | Default issue forms and pull-request template |
| [.github/workflows/](.github/workflows) | Reusable workflows called by the code repositories (below) |
| [scripts/github-labels.sh](scripts/github-labels.sh) | Creates the common label set in a repository |
| [scripts/github-rulesets.sh](scripts/github-rulesets.sh) | Creates the `main` and release-tag rulesets of a repository (docs/GITHUB.md, step 8) |
| [docs/GITHUB.md](docs/GITHUB.md) | Organization and repository settings the owner sets by hand |
| [runner/](runner/README.md) | Self-hosted runners: the runner VM (`runner/vm/`), the Portainer stack and the runner image |
| [.github/dependabot.yml](.github/dependabot.yml) | Updates of the SHA-pinned actions and the digest-pinned runner images |

## Reusable workflows

Call them from a code repository with `uses: just-tavrn/.github/.github/workflows/<file>@main`. Every
file starts with a commented caller example and documents its inputs.

| Workflow | What it does |
|---|---|
| [cla.yml](.github/workflows/cla.yml) | CLA check with `contributor-assistant/github-action`; signatures in the private `just-tavrn/cla-signatures`, token `CLA_PAT` |
| [rust-ci.yml](.github/workflows/rust-ci.yml) | rustfmt, clippy, tests (optional PostgreSQL service, extra targets and clippy runs), cargo-deny |
| [js-ci.yml](.github/workflows/js-ci.yml) | pnpm install with the frozen lockfile, SPDX and license checks, typecheck, tests, optional build |
| [gitleaks.yml](.github/workflows/gitleaks.yml) | Secret scan of the full history with the gitleaks CLI |
| [docker-publish.yml](.github/workflows/docker-publish.yml) | Container build with provenance and SBOM; pushes to `ghcr.io/just-tavrn/<image>` on main and `v*` tags when asked |
| [e2e.yml](.github/workflows/e2e.yml) | Playwright run on the self-hosted runners `tavrn-e2e`, against a node image, artifact or binary |
| [runner-image.yml](.github/workflows/runner-image.yml) | Builds and publishes the runner image `ghcr.io/just-tavrn/tavrn-runner` (not reusable) |

`rust-ci.yml`, `js-ci.yml` and `docker-publish.yml` take an input `runner`: `ubuntu-latest` (default) or
`tavrn-heavy` for the self-hosted runners ([runner/README.md](runner/README.md)); pull requests from forks
and from Dependabot always fall back to GitHub-hosted runners. Every action is pinned by commit SHA.

All jobs run only when the repository variable `CI_ENABLED` is `true` (the callers check it as well), so
nothing runs on GitHub until the owner switches it on per repository (see [docs/GITHUB.md](docs/GITHUB.md)).
While the repositories are private, callers pass `READ_TOKEN` so the jobs can fetch the protocol submodule
and the git dependencies between the repositories.

## Checks

```bash
scripts/check-spdx.sh      # SPDX headers of workflows and scripts
shellcheck scripts/*.sh runner/*.sh runner/vm/*.sh
actionlint                 # workflow lint (https://github.com/rhysd/actionlint)
```

The same run in [checks.yml](.github/workflows/checks.yml), together with gitleaks.

## License

Documents CC-BY-4.0, workflows and scripts Apache-2.0; see [LICENSE.md](LICENSE.md). Contributions follow
[CONTRIBUTING.md](CONTRIBUTING.md) and the [CLA](CLA.md).
