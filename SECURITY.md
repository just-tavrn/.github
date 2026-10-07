# Security policy

Please **do not report security vulnerabilities in public issues, discussions or pull requests.**

## How to report

Use GitHub's **private vulnerability reporting**: open the repository of the affected component, go to the
**Security** tab and choose **Report a vulnerability**. The report is visible only to you and the
maintainers, and we can work on the fix and the advisory together with you there.

| Component | Report in |
|---|---|
| Node server, container image, deployment files | [tavrn-node](https://github.com/just-tavrn/tavrn-node/security/advisories/new) |
| Web client (and later the desktop and mobile apps) | [tavrn-web](https://github.com/just-tavrn/tavrn-web/security/advisories/new) |
| Encryption core, `@tavrn/crypto` | [tavrn-crypto](https://github.com/just-tavrn/tavrn-crypto/security/advisories/new) |
| `@tavrn/sdk`, `@tavrn/e2ee`, `@tavrn/bot` | [tavrn-js](https://github.com/just-tavrn/tavrn-js/security/advisories/new) |
| A flaw in the protocol or the encryption design itself | [tavrn-protocol](https://github.com/just-tavrn/tavrn-protocol/security/advisories/new) |

If you cannot use GitHub, email **`security@tavrn.org`**. *This address is a placeholder: it goes live
together with the project domain. Until then, private vulnerability reporting on GitHub is the way to reach
us.*

Please include:

- the affected component and the version, release tag or commit,
- a description of the issue and its impact (what an attacker can do, under which conditions),
- steps to reproduce or a proof of concept,
- whether the issue is already known to others or public.

## Scope

In scope: the code in the repositories of the [just-tavrn](https://github.com/just-tavrn) organization and
the artifacts built from it (container images, packages, app builds), and the protocol and encryption
design (`PROTOCOL.md`, `ENCRYPTION.md`, `FEDERATION.md` in tavrn-protocol). We are especially interested in:

- anything that lets a node operator, another node or a network attacker read or forge end-to-end encrypted
  content, or impersonate a user or device,
- authentication, session and second-factor bypasses, account takeover,
- permission and moderation bypasses in rooms and channels,
- federation trust issues (forged signatures, cross-node request forgery, SSRF),
- remote code execution, injection, stored cross-site scripting in the web client,
- secrets or private data leaking through logs, APIs or backups.

Out of scope:

- nodes run by other people (report to their operator; we are glad to help if the cause is in our code),
- denial of service by sheer volume, spam, or rate limits that are merely generous,
- findings that need a compromised device, a malicious browser extension or physical access,
- vulnerabilities in dependencies without a demonstrated impact on tavrn (report them upstream; tell us if
  tavrn is affected),
- missing hardening headers or best practices without a concrete attack,
- social engineering of maintainers or users.

## What we promise

- We acknowledge your report within **3 days** and give a first assessment within **10 days**.
- We keep you informed while we work on a fix and aim to release it within **90 days**; critical issues in
  the encryption or authentication are handled first.
- We publish a GitHub security advisory (with a CVE where it applies) once a fix is available, coordinated
  with you, and credit you by name or handle unless you prefer to stay anonymous.
- We will not take legal action against good-faith research that respects this policy: test only against
  your own nodes and accounts, do not access other people's data, and give us reasonable time before
  disclosing.

There is **no bug bounty**: tavrn is a community project without a budget for rewards. We are grateful for
every report and say so publicly in the advisory.

## Supported versions

tavrn is before its first stable release. Security fixes go into the latest release and the `main` branch of
each repository; older releases are not patched. Node operators should follow the releases of tavrn-node.
