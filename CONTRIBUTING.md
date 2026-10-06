# Contributing to tavrn

Thank you for helping. Bug reports, fixes, translations, documentation and protocol reviews are all welcome.
This guide applies to every repository of the [just-tavrn](https://github.com/just-tavrn) organization.
Please read the [code of conduct](CODE_OF_CONDUCT.md) first; security issues go through the
[security policy](SECURITY.md), never through public issues.

## Where things live

| Repository | Open issues and pull requests here for |
|---|---|
| [tavrn-protocol](https://github.com/just-tavrn/tavrn-protocol) | the specification, `openapi.json`, test vectors, permission bits, anything that changes what goes over the wire |
| [tavrn-crypto](https://github.com/just-tavrn/tavrn-crypto) | the encryption core (Rust, OpenMLS) and its WebAssembly package `@tavrn/crypto` |
| [tavrn-js](https://github.com/just-tavrn/tavrn-js) | `@tavrn/sdk`, `@tavrn/e2ee`, `@tavrn/bot` and the example bots |
| [tavrn-node](https://github.com/just-tavrn/tavrn-node) | the node server, the container image, deployment and operator documentation |
| [tavrn-web](https://github.com/just-tavrn/tavrn-web) | the web client, later the desktop and mobile apps, and the end-to-end tests |
| [.github](https://github.com/just-tavrn/.github) | these organization-wide documents and the shared CI workflows |

- **Not sure where it belongs?** Open a [discussion](https://github.com/just-tavrn/.github/discussions)
  instead of guessing; we move it to the right place.
- **Questions and support** go to Discussions as well (see [SUPPORT.md](SUPPORT.md)), not to issues.
- **Protocol changes start in tavrn-protocol.** A change to the API, the message format, federation or the
  encryption is first proposed and agreed there; the implementations in the node, the SDK and the clients
  follow. The release order is protocol, then crypto and js, then node and web.

## Before you start

- For anything larger than a small fix, open an issue first and describe what you want to change, so we can
  agree on the approach before you spend time on it.
- All repository text (code comments, documentation, commit messages, issues and pull requests) is written
  in **English**. User-facing strings go through the localization files (English and German); you do not need
  to provide the German translation yourself, we help with that.

## Contributor license agreement

Contributions are accepted under the [contributor license agreement](CLA.md) (CLA). You keep the copyright of
your work; the agreement lets the project offer additional licenses next to the open-source ones.

- A **CLA bot** asks you to sign on your **first pull request**: you reply with one comment
  (`I have read the CLA Document and I hereby sign the CLA`). The signature covers all your contributions to
  all tavrn repositories; you sign once.
- A **DCO `Signed-off-by` line is not required.**
- **Our promise ("no rug pull")**: everything published under an OSI-approved license stays available under
  that license, and the source code of tavrn keeps being published under the open-source licenses of its
  repositories. The rights granted with the CLA are used to offer *additional* licenses or terms, never to
  take the open-source versions away. The full text is in [CLA.md](CLA.md#our-promise-no-rug-pull).

## Licenses of the code you touch

Each repository (and in tavrn-js each package) has its own license; the `LICENSE` file at its root is
authoritative. Every source file starts with the SPDX header of its package, for example

```ts
// SPDX-License-Identifier: Apache-2.0
```

and each repository's `scripts/check-spdx.sh --fix` adds missing ones. New dependencies must use a license
from the allow-list of the repository (`deny.toml` for Rust, the JavaScript license check for npm packages).
The crypto core, `@tavrn/e2ee`, the SDK, the bot runtime and the web client must not depend on GPL, LGPL or
AGPL code; the node may.

The name and logo are not covered by the code licenses: forks and derived products follow
[TRADEMARK.md](TRADEMARK.md).

## Development and checks

Each repository's `README.md` describes its prerequisites and setup. Common tools: Rust (`rustup`, the
toolchain is pinned by `rust-toolchain.toml`), Node 24 with pnpm (`corepack enable pnpm`) and
[`just`](https://github.com/casey/just). Repositories that depend on the protocol carry it as a git
submodule: clone with `git clone --recurse-submodules` (or run `git submodule update --init` afterwards).

Every repository has a `just check` recipe that runs the same checks as its CI. Run it before you open a
pull request:

| Repository | Before a pull request | What it covers |
|---|---|---|
| tavrn-protocol | `just check` | schema and test-vector validation, SPDX headers |
| tavrn-crypto | `just check` | rustfmt, clippy (native and `wasm32-unknown-unknown`), tests, `cargo deny`, SPDX headers |
| tavrn-js | `pnpm install && just check` | typecheck, unit tests, JavaScript license check, SPDX headers |
| tavrn-node | `just check` | rustfmt, clippy, tests on SQLite and PostgreSQL (`just test-pg` needs the PostgreSQL test container), `cargo deny`, SPDX headers |
| tavrn-web | `pnpm install && just check`, for UI flows also `just e2e` | typecheck, unit and component tests, JavaScript license check, SPDX headers; Playwright end-to-end tests against a node |

The README of each repository lists the single steps (formatting, linting, tests) if you want to run them
one by one. All repositories also run a secret scan (gitleaks) in CI.

Work test-first: write or extend the test that shows the bug or the new behaviour, then change the code.
Changes to the user interface come with a component test and, for flows, an end-to-end test; the web client
must keep working on phone, tablet and desktop widths. If you change the node's API, regenerate the
specification and propose the change to `openapi.json` in tavrn-protocol.

## Commits

- Write the subject as `<area>: <what changed>` in English, lower case after the colon, without a trailing
  period, for example `federation: retry signed fetches after a key rotation` or
  `docs: explain the reverse-proxy timeouts`. The area is a package, directory or topic of the repository.
- Use the body to explain **why** the change is needed when the subject alone does not say it; wrap it at
  about 100 characters.
- Keep commits focused on one topic. We squash when merging, so the pull request title becomes the commit
  subject: use the same style there.

## Pull requests

- One topic per pull request, with a description of what changed and why, and how you tested it (the pull
  request template asks for it).
- Mark breaking changes clearly (API, protocol, configuration, storage format); they get the
  `breaking-change` label.
- Do not commit secrets, local data (databases, `data-dev/`), `.env` files, key files, test output or editor
  and agent settings; the `.gitignore` of each repository covers the usual ones.
- If you include material you did not write, say so in the pull request and name its origin and license
  (CLA, section 5).
