# tavrn

**tavrn is a decentralized, fully open-source community chat**: rooms with text, voice, announcement and
forum channels, roles and permissions, screen sharing, direct messages and friends across all nodes.
Anyone can run a node, and all nodes together form one network where an account on one node can join rooms
on every other. Conversations are end-to-end encrypted with MLS, so node operators can never read along.

> **Status: pre-release.** tavrn is before its first stable release and the encryption code has not been
> audited yet. Start with the [overview](https://github.com/just-tavrn/tavrn).

## Repositories

| Repository | What it is | License |
|---|---|---|
| [tavrn-protocol](https://github.com/just-tavrn/tavrn-protocol) | The protocol: specification, `openapi.json`, test vectors and permission tables; the contract every implementation follows | Apache-2.0 (schemas, vectors), CC-BY-4.0 (prose) |
| [tavrn-crypto](https://github.com/just-tavrn/tavrn-crypto) | The encryption core (Rust, OpenMLS), built natively and as WebAssembly (`@tavrn/crypto`) | MPL-2.0 |
| [tavrn-js](https://github.com/just-tavrn/tavrn-js) | JavaScript packages without UI: the SDK `@tavrn/sdk`, the encryption layer `@tavrn/e2ee` and the bot runtime `@tavrn/bot` | Apache-2.0 (`sdk`, `bot`), MPL-2.0 (`e2ee`) |
| [tavrn-node](https://github.com/just-tavrn/tavrn-node) | The node server (Rust), its container image, deployment examples and operator documentation | AGPL-3.0-only |
| [tavrn-web](https://github.com/just-tavrn/tavrn-web) | The web client (React, TypeScript), later the desktop and mobile shells, and the end-to-end test suite | Apache-2.0 |

This repository ([.github](https://github.com/just-tavrn/.github)) holds the organization-wide
[contributing guide](https://github.com/just-tavrn/.github/blob/main/CONTRIBUTING.md),
[code of conduct](https://github.com/just-tavrn/.github/blob/main/CODE_OF_CONDUCT.md),
[security policy](https://github.com/just-tavrn/.github/blob/main/SECURITY.md),
[contributor license agreement](https://github.com/just-tavrn/.github/blob/main/CLA.md) and the shared
CI workflows.

## Get in touch

- **Questions, ideas, show and tell:** [Discussions](https://github.com/just-tavrn/tavrn/discussions).
- **Bugs and feature requests:** an issue in the repository of the affected component (unsure? start a
  discussion).
- **Security vulnerabilities:** never in public issues; report them privately as described in the
  [security policy](https://github.com/just-tavrn/.github/blob/main/SECURITY.md).
- **Code of conduct concerns:** see the [code of conduct](https://github.com/just-tavrn/.github/blob/main/CODE_OF_CONDUCT.md#enforcement).

## Trademark

The code is open source; the name "tavrn" and the logo are not covered by the code licenses. Running your
own node with the name and logo is fine; distributed forks and hosting businesses under the name need
permission. See the [trademark policy](https://github.com/just-tavrn/.github/blob/main/TRADEMARK.md).
