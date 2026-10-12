# Self-hosted runners

Ephemeral GitHub Actions runners for the `just-tavrn` organization: a Docker Compose stack (runners, Docker-in-Docker,
PostgreSQL) and the runner image. Everything the runners write lives in RAM (tmpfs); the disk of the machine only
holds its system and the container images. Where and how the stack runs is the operator's choice; the section
[Isolation](#isolation) says what that choice has to provide.

| Path | What it is |
|---|---|
| [docker-compose.yml](docker-compose.yml), [.env.example](.env.example) | The runner stack and its variables |
| [Dockerfile](Dockerfile), [entrypoint.sh](entrypoint.sh) | The runner image (`ghcr.io/just-tavrn/tavrn-runner`, built by [runner-image.yml](../.github/workflows/runner-image.yml)) |
| [smoke-desktop.sh](smoke-desktop.sh) | Smoke test of the image's desktop toolchain (section [Desktop builds](#desktop-builds)) |

## What runs where

| Jobs | Runner | Why |
|---|---|---|
| gitleaks, CLA, actionlint/shellcheck of this repository | GitHub-hosted (`ubuntu-latest`) | light, need no tools from the image |
| Rust CI, JavaScript CI, container builds (`rust-ci.yml`, `js-ci.yml`, `docker-publish.yml` with `runner: tavrn-heavy`) | self-hosted `tavrn-heavy` | heavy builds and tests; PostgreSQL and Valkey of the stack, caches in RAM |
| Pull requests from forks and from Dependabot of those workflows | GitHub-hosted (automatic fallback) | untrusted code never reaches the runner machine |
| End-to-end suite (`e2e.yml`) | self-hosted `tavrn-e2e` | Chromium, livekit-server, ffmpeg in the image; skipped for forks and Dependabot |
| Desktop app of tavrn-web (`apps/desktop`, Tauri 2): Linux natively, Windows cross-compiled | self-hosted `tavrn-heavy` | WebKitGTK, NSIS, LLVM and cargo-xwin in the image, the Windows SDK in the cache ([Desktop builds](#desktop-builds)) |

A caller selects the self-hosted class with one input:

```yaml
jobs:
  rust:
    if: ${{ vars.CI_ENABLED == 'true' }}
    uses: just-tavrn/.github/.github/workflows/rust-ci.yml@main
    with:
      runner: tavrn-heavy
      postgres: true
```

## Isolation

DinD runs **privileged**, and containers share the kernel with whatever runs them: a job that escapes its
container (a compromised dependency, action or image is enough once the repositories are public) is root on
that machine. Run the stack on a machine that holds nothing of value and whose network can only reach the
internet, typically a dedicated VM:

1. **A boundary around the Docker host** (a VM, or a physical machine of its own): an escape from DinD reaches
   that machine's kernel, nothing else. No shared folders, no host mounts, nothing on it but this stack.
2. **Network isolation outside the machine**: its own network segment whose router forwards only to the
   internet, not to your LAN, other segments or the router's own services beyond DNS. This holds even if an
   attacker is root on the machine.
3. **Egress filter on the machine** (defense in depth): reject every private, loopback and link-local
   destination and let TCP 80/443 through only to allowlisted destinations (GitHub and its Actions service and
   blob storage, ghcr.io, crates.io and rustup, npm and Node.js, Playwright downloads, Microsoft's Visual Studio
   download server for the [desktop builds](#desktop-builds), Docker Hub, the distribution mirrors, the sources
   of tavrn's `deploy/Dockerfile`). CDNs and shared storage make such a list a narrowing, not a seal; its main
   job together with the private-range block is to keep your LAN unreachable.
4. **Ephemeral runners** (this stack): one job per container; the work directory, `/tmp` and the home directory
   are fresh tmpfs mounts for every job.

Alternatives considered for the container runtime:

| Option | Why not (for now) |
|---|---|
| Sysbox (unprivileged DinD as a runc replacement) | still a shared kernel; development has slowed since the acquisition by Docker; another runtime to maintain |
| gVisor (`runsc`) | DinD inside gVisor is limited and slow; syscall-heavy Rust builds pay a large overhead |
| Kata Containers | a VM per container is strong isolation, but needs containerd shims and nested DinD tuning |
| Firecracker microVM per job (actuated, self-built orchestrators) | strongest per-job isolation, but commercial or a project of its own (images, networking, scheduling) |
| Actions Runner Controller on Kubernetes | needs a Kubernetes cluster; the same DinD question remains |

One isolated machine plus ephemeral containers is simple and keeps everything else out of reach. On it, jobs are
separated by containers only, which is acceptable because only trusted events get the self-hosted runners
(section [Security](#security)). Running the stack on a machine that also holds other things is acceptable only
while every repository is private and every committer is trusted.

## Deploying the stack

1. **Credentials** (section [Credentials](#credentials)): create the GitHub App or the token first.
2. **Image**: after `runner-image.yml` ran on `main`, open the package
   `ghcr.io/just-tavrn/tavrn-runner` and set its visibility to **Public** (it contains no secrets; private
   packages count against the Free plan's 500 MB package storage and would need registry credentials on the
   machine). Take the digest from the workflow run's summary or with
   `docker buildx imagetools inspect ghcr.io/just-tavrn/tavrn-runner:edge`.
3. On the Docker host: copy [docker-compose.yml](docker-compose.yml) and [.env.example](.env.example) as `.env`
   (mode 600: it holds the credential), set `RUNNER_IMAGE` to the digest from step 2 and exactly one credential
   method. `DIND_DNS` is the resolver the job containers inside DinD use (the Docker host's own resolver on its
   `docker0` address, or a public one they are allowed to reach). Any tool that drives Docker Compose (a stack
   manager with a web interface works the same way) is fine; the file needs no changes.
4. `docker compose -p tavrn-runner --env-file .env up -d`. After about a minute:
   ```bash
   gh api orgs/just-tavrn/actions/runners \
     --jq '.runners[] | [.name, .status, .busy, ([.labels[].name] | join(","))] | @tsv'
   ```
   shows `tavrn-heavy-…` (two) and `tavrn-e2e-…` (one) as `online`.

**Scaling**: change `RUNNER_HEAVY_REPLICAS` / `RUNNER_E2E_REPLICAS` in `.env` and run `up -d` again. Keep the
memory budget below in mind.

**Logs**: `docker compose -p tavrn-runner logs -f runner-heavy` (registration and job names). A job's own log is
on GitHub.

**Updating**: the image is pinned by digest. A new image appears on every change of `runner/Dockerfile` (also
Dependabot's base image bumps) and weekly. Set the new digest in `RUNNER_IMAGE` and run `up -d` again (it
pulls and recreates the containers). The runners have automatic updates disabled; GitHub stops sending jobs to a runner version older
than about 30 days after a newer release, so update at least monthly. An update recreates the containers and
cancels running jobs: check `busy` in the runner list first. Let the machine install its security updates
unattended and reboot when needed.

**Reboot**: all tmpfs content (caches, DinD images, the test database) is gone, by design. Docker starts the
stack again (`restart: unless-stopped`), the runners register anew, the first builds are cold. Nothing needs
restoring.

### Credentials

The image fetches a fresh registration token at every container start (ephemeral runners re-register after
each job), so it needs a credential for the API endpoint
`POST /orgs/just-tavrn/actions/runners/registration-token`:

| Method | Variables | Assessment |
|---|---|---|
| GitHub App (recommended) | `APP_ID`, `APP_PRIVATE_KEY` (PEM on one line, `\n` for line breaks), `APP_LOGIN` (empty = `ORG_NAME`) | Organization permission **Self-hosted runners: Read and write** only; owned by the organization, not a person; issues one-hour tokens |
| Fine-grained PAT | `ACCESS_TOKEN` | Resource owner `just-tavrn`, organization permission **Self-hosted runners: Read and write**, nothing else (GitHub lists both runner token endpoints for fine-grained tokens); expires after at most a year; may need approval under the organization's PAT policy |
| Classic PAT | `ACCESS_TOKEN` | needs `admin:org`, i.e. full organization administration: avoid |
| Registration token | `RUNNER_TOKEN` | valid for one hour, so ephemeral runners fail to re-register afterwards: only for a first test |

GitHub App: organization **Settings** → **Developer settings** → **GitHub Apps** → **New GitHub App**; no
webhook, no callback; **Organization permissions** → **Self-hosted runners: Read and write**; **Where can this
GitHub App be installed: Only on this account**. Generate a private key, then **Install App** on `just-tavrn`.

The entrypoint un-exports the credential before the runner starts, and the jobs (user `runner`, sudo blocked
by `no-new-privileges`) cannot read it from the root-owned processes of their own container. It lives in the
stack's `.env` and in the container configuration of the Docker host, and **a job can reach it anyway**
through the privileged DinD (section [Security](#security), "What remains"): treat it as exposed to every job
that runs on these runners, keep its permission at **Self-hosted runners** only, and rotate it if the machine
is ever suspected compromised.

## Memory

Every size is an upper limit, not a reservation. What a container writes to its tmpfs counts against its own
`mem_limit`; what the runners write to the shared cache volume counts against the runner while it runs and
against no limit after the container restarts. Defaults for a machine with 512 GB of memory:

| Item | Default | Worst case |
|---|---|---|
| `runner-heavy` ×2: processes + `/_work` (64 GB) + `/tmp` (16 GB) + home (4 GB) | `RUNNER_HEAVY_MEMORY=128g` | 256 GB |
| `runner-e2e` ×1: processes + `/_work` (32 GB) + `/tmp` + home | `RUNNER_E2E_MEMORY=48g` | 48 GB |
| `dind`: daemon, job containers, `/var/lib/docker` (32 GB) | `DIND_MEMORY=48g` | 48 GB |
| `postgres`: data (16 GB), shared buffers (2 GB), `/dev/shm` (1 GB) | `POSTGRES_MEMORY=24g` | 24 GB |
| shared cache volume (Cargo registry, pnpm store, browsers, one target directory per runner) | `RUNNER_CACHE_SIZE=128g` | 128 GB |
| System, Docker, housekeeping | | ~4 GB |
| **Sum** | | **~508 GB** |

Realistic use is far lower: a Rust target directory of the tavrn workspace is 20–40 GB
(`RUNNER_TARGET_MAX_GB=40` restarts one that grows beyond), a checkout with `node_modules` 2–5 GB, a test run
10–20 GB of processes. On a larger machine raise replicas or limits; keep the sum of the worst-case column
below the machine's memory, because a machine without swap answers overcommit with the OOM killer.

## Caches

`/cache` is one tmpfs volume shared by all runners and kept mounted by the `housekeeping` service, so it
survives the restart after every job (Docker discards a tmpfs volume when no container uses it):

- `/cache/cargo` (`CARGO_HOME`: registry and git checkouts) and `/cache/pnpm-store` are shared; both tools lock
  them for concurrent use. `/cache/cargo/bin` is not on `PATH` and is emptied at every start: the tools of the
  image live in root-owned directories (`/opt/cargo/bin`, `/usr/local/bin`); a job that needs `cargo install`
  installs into `$RUNNER_TEMP` (`cargo install --root "$RUNNER_TEMP/tools" …`) and calls the tool by path.
- `/cache/ms-playwright` is seeded once from the image's Chromium; other Playwright versions download beside it.
- `/cache/cargo-xwin/xwin` holds the Microsoft CRT and Windows SDK of the Windows desktop build, downloaded once
  by the entrypoint of the first `tavrn-heavy` runner (section [Desktop builds](#desktop-builds)).
- `/cache/slots/<class>-<n>/target`: each runner container holds an exclusive `flock` on one slot for its
  lifetime, so two jobs never share a Cargo target directory at the same time. The tool cache of `setup-*`
  actions (`RUNNER_TOOL_CACHE`) is not shared: it lives in the job's work directory, a fresh tmpfs.

The `toolchain` and `extra-targets` inputs of `rust-ci.yml` and the `node-version` inputs are checked against
the image on self-hosted runners, not installed (an install would write to the container layer on disk);
rebuild the image for a new Rust or Node.js release. The `services:` PostgreSQL of `rust-ci.yml` only runs on
GitHub-hosted runners; self-hosted jobs always get `TAVRN_TEST_DATABASE_URL` (the stack's PostgreSQL) and
`TAVRN_TEST_CACHE_URL` (a private Valkey in every runner container: the cluster outage test kills all clients
of its Valkey, which would break parallel jobs on a shared one).

Every job also gets `TAVRN_TEST_TIMEOUT_FACTOR` (`RUNNER_TEST_TIMEOUT_FACTOR`, default 3): the test suites
multiply each limit they wait for an event or a condition by it (tavrn-node's integration tests, the Playwright
suites of tavrn-web), so a runner whose CPUs another job shares gets more time where the tests wait, and nowhere
else (fixed delays and "nothing arrives within" windows stay as they are). On a developer machine the factor is
1. A flaky wait is fixed in the test (wait for the event, not for time); the factor is not the fix.

The node tests create one database `t_<ulid>` per test node on that PostgreSQL (about 14 MB each, on the tmpfs
of `POSTGRES_DATA_SIZE`). They clean up after themselves: a test node drops its database when it goes away, so
a run only holds the databases of the tests running at that moment; and before creating one, the tests drop
the `t_*` databases older than `TAVRN_TEST_DB_MAX_AGE_SECS` (default 20 minutes), the leftovers of cancelled
or crashed runs. The `housekeeping` service is the backstop: every 10 minutes it drops `t_*` databases older
than `TEST_DB_MAX_AGE_HOURS` (default 1).

The image's ffmpeg is a static GPL build from BtbN (with libwebp). That is fine for tooling that runs the tests
and is never distributed with tavrn; the node image builds its own LGPL ffmpeg (`deploy/Dockerfile`).

## Desktop builds

The desktop app of tavrn-web (`apps/desktop`, a Tauri 2 shell) builds on `tavrn-heavy`: for Linux natively, for
Windows by cross-compilation as Tauri documents it
([Build Windows apps on Linux](https://v2.tauri.app/distribute/windows-installer/#build-windows-apps-on-linux-and-macos),
experimental upstream). What the image adds for it:

| Purpose | In the image |
|---|---|
| Linux build and bundles (deb, AppImage) | `libwebkit2gtk-4.1-dev`, `libgtk-3-dev`, `libayatana-appindicator3-dev`, `librsvg2-dev`, `patchelf`, `xdg-utils`, `file` |
| WebDriver tests of the Linux build | `webkit2gtk-driver` (`WebKitWebDriver`), `xvfb` (`xvfb-run`), `tauri-driver` (`TAURI_DRIVER_VERSION`), `xdotool` (the smoke test presses global hotkeys through the X server), `gnome-keyring` (Secret Service round trip of the keychain test inside `dbus-run-session`) |
| Windows build | Rust target `x86_64-pc-windows-msvc`, `cargo-xwin` (`CARGO_XWIN_VERSION`), LLVM 21 from apt.llvm.org (`LLVM_VERSION`; `clang` as `clang-cl`, `lld-link`, `llvm-lib`, `llvm-rc`, all under their plain names through `update-alternatives`), `nsis` (`makensis`); `XWIN_ARCH=x86_64`, `XWIN_VARIANT=desktop`. The Microsoft STL needs clang 19 or newer, the native voice engine's libwebrtc (Linux build) clang 21 or newer, so the distribution's LLVM 18 is not installed |

```bash
pnpm tauri build --bundles deb,appimage                                                    # Linux
pnpm tauri build --runner cargo-xwin --target x86_64-pc-windows-msvc --bundles nsis        # Windows
xvfb-run -a <WebDriver test command>                                                       # tauri-driver + WebKitWebDriver
```

Limits of the Windows route:

- **NSIS only, no MSI**: the MSI bundler needs WiX, which runs only on Windows. Build an MSI on a Windows runner
  if one is ever needed.
- **x86_64 only**: the cache holds the x86_64 libraries; ARM64 needs `XWIN_ARCH=x86_64,aarch64` in the image and
  the `aarch64-pc-windows-msvc` target.
- **No Windows execution**: no Wine in the image, so Windows binaries are built but not run or tested here.
- **Signing**: Tauri signs on Linux only through a custom `signCommand` (its docs use relic); nothing is
  set up for it.
- **WebView2 install mode**: keep `bundle.windows.webviewInstallMode` at `downloadBootstrapper` (the default) or
  `skip`. `embedBootstrapper` and `offlineInstaller` download the WebView2 installer from Microsoft at build time,
  which the egress filter blocks.
- C and C++ code of dependencies compiles with `clang-cl` against the downloaded SDK; crates that need MSVC-only
  tools (the `ml64` assembler, `cl.exe` itself) do not build.
- The Tauri bundler downloads its helpers at build time from GitHub (allowlisted): `nsis_tauri_utils.dll` for NSIS,
  `linuxdeploy` and `AppRun` for the AppImage (run with `APPIMAGE_EXTRACT_AND_RUN`, no FUSE needed).

### The Microsoft CRT and Windows SDK

cargo-xwin links against the Microsoft C runtime (CRT) and the Windows SDK: headers and import libraries that
[xwin](https://github.com/Jake-Shadle/xwin) (built into cargo-xwin) downloads from Microsoft's Visual Studio
download server (`download.visualstudio.microsoft.com`, manifest through `aka.ms/vs/17/release/channel`): the
x86_64 desktop libraries, without debug libraries, about 630 MB unpacked.

**Terms.** They are part of the Visual Studio Build Tools and come under Microsoft's license terms for them
(xwin links them as <https://go.microsoft.com/fwlink/?LinkId=2086102>; cargo-xwin accepts them without asking,
running it means accepting them). The terms allow copying the files onto "Build Devices", including virtual
machines and containers on machines that are owned by you or dedicated solely to your use, to compile, build and
verify applications; they forbid sharing or publishing the software, and tie the use rights to a license of Visual
Studio Community, Professional or Enterprise (Community is free for open-source projects). Hence:

- **The files are not in the image.** `ghcr.io/just-tavrn/tavrn-runner` is a public package, and putting them
  in it would publish them.
- The entrypoint of a `tavrn-heavy` runner (`TAVRN_XWIN=true` in the stack) downloads them with
  `cargo-xwin cache xwin` into `/cache/cargo-xwin/xwin` before the runner registers: once per boot of the
  machine, by the first runner, while the others wait on a lock (about 7 minutes on a home line). The jobs get
  `XWIN_CACHE_DIR` pointing at a cargo-xwin directory of their cache slot whose `xwin/` links to that download,
  so a build never downloads the SDK. If the download failed (logged as `cargo-xwin cache download failed`),
  cargo-xwin tries again during the job.
- Never upload `/cache/cargo-xwin` (or a target directory with the SDK) as an artifact or an Actions cache.
- Outside the stack (no `/cache` volume), cargo-xwin downloads them into `~/.cache/cargo-xwin` on first use.

### Smoke test

[smoke-desktop.sh](smoke-desktop.sh) scaffolds a minimal Tauri 2 app (create-tauri-app, vanilla template) and
builds it for both targets: deb and AppImage, a start of the Linux binary under Xvfb, and the NSIS installer with
cargo-xwin. Run it in a new image before pinning its digest (network needed; it downloads the SDK itself when no
prepared `XWIN_CACHE_DIR` exists):

```bash
docker run --rm --user runner --entrypoint /smoke-desktop.sh \
  -v "$PWD/runner/smoke-desktop.sh:/smoke-desktop.sh:ro" ghcr.io/just-tavrn/tavrn-runner:edge
```

## Security

**On GitHub** (organization **Settings**):

1. **Actions** → **General** → **Approval for running fork pull request workflows from contributors**:
   **Require approval for all external contributors**.
2. **Actions** → **General** → **Workflow permissions**: **Read repository contents and packages
   permissions** (the default `GITHUB_TOKEN` is read-only; workflows ask for more in `permissions:`).
3. **Actions** → **Runner groups**: on the Free plan only the group **Default** exists; restricting runners to
   selected repositories needs custom groups (Team plan). By default a group serves **private repositories
   only**; when the repositories go public, tick **Allow public repositories** in the group's settings (on the
   Team plan: a group `tavrn` limited to the code repositories and to selected workflows).
4. Secrets that reach self-hosted jobs: `TAVRN_READ_PAT` (read-only, private phase) and the job's own
   `GITHUB_TOKEN`. No other long-lived secret belongs on these runners.

**In the workflows**:

- The reusable workflows only pick a self-hosted runner for trusted events and fall back to `ubuntu-latest`
  otherwise; `e2e.yml` skips the job instead:
  ```yaml
  github.event_name != 'pull_request_target' && github.actor != 'dependabot[bot]' &&
  (github.event_name != 'pull_request' ||
   (github.event.pull_request.head.repo.full_name == github.repository &&
    github.event.pull_request.user.login != 'dependabot[bot]'))
  ```
  Dependabot pull requests are treated like fork pull requests: they bring new third-party code (build scripts,
  install scripts) and run on GitHub-hosted runners.
- Every action is pinned by commit SHA with the version as a comment; Dependabot
  ([.github/dependabot.yml](../.github/dependabot.yml)) updates the pins and the image digests of
  `runner/Dockerfile` and `runner/docker-compose.yml`.
- The guards also refuse branches named `dependabot/*`, whatever the event. A **manual dispatch**
  (`gh workflow run <workflow> --ref <branch>`) is a trusted event otherwise: it runs that branch's code, and its
  workflow files, on the runners as if a maintainer had written it. Only dispatch branches whose diff you have
  read, never a contributor's or a bot's branch you have not reviewed.
- Nothing that is released is built here: release tags run on GitHub-hosted runners only, the node's `edge`
  image is built on `ubuntu-latest`, and GitHub-hosted image builds never import a cache a self-hosted build
  wrote (`docker-publish.yml`: Actions cache only from GitHub-hosted runs, scope `<image>-hosted`; tag builds
  without any cache).

**What the guards do not cover (public repositories)**: a pull request runs the workflow files of its own
branch. A fork can therefore change `.github/workflows/*.yml` and ask for `runs-on: [self-hosted, tavrn-heavy]`
directly; the expressions above only keep the unchanged workflows off the runners. Once **Allow public
repositories** is ticked, the barrier against such a pull request is the approval setting of step 1: nothing
of an external contributor runs until a maintainer approves the run. Before approving, read the diff: never
approve a run of a fork pull request that touches `.github/`, scripts the CI executes (`justfile`,
`scripts/`, `build.rs`, `package.json` scripts, Dockerfiles) or the lockfiles, unless you would run that code on
the runner machine yourself; when in doubt, push the change to a branch of the repository after review instead.
The machine's isolation (its own network segment, egress allowlist, ephemeral containers, no secrets but the
read-only `TAVRN_READ_PAT`) limits the damage of a mistake; it does not make approving untrusted code safe.

**In the stack**: ephemeral runners, `no-new-privileges` (no sudo), no Docker socket of the host in any
container, DinD only on the internal network with TLS client certificates and no published port, PostgreSQL
only on the internal network, no published ports at all. Never publish DinD's port 2376 or mount the host's
Docker socket into a runner.

**In the image**: a runner container is restarted, not recreated, after each job, so its layer outlives the
job. Nothing the job user can write is on `PATH`, and the image hands nothing of its own to that user: the
runner's binaries (`/actions-runner/bin`, `externals`) and the base image's tools are root-owned, a build-time
check fails when the job user owns or may write anything else outside the tmpfs mounts, and the entrypoint puts
the top-level runner files back from a root-owned copy before the base entrypoint runs `config.sh` as root
(it refuses to start, and asks for `docker compose up -d --force-recreate`, when `bin/` or `externals/` were
swapped). `/var/tmp`, `/run/lock` and `/opt/hostedtoolcache` are emptied at every start.

**What remains** (the runners are one trust domain; everything that reaches them must be code you would run on
the machine yourself):

- **DinD is privileged and shared.** Every job gets `DOCKER_HOST`; `docker run --privileged` (or a bind mount of
  `/`) against DinD is root in the DinD container and from there root on the machine: the other runners, their
  caches, the PostgreSQL data and the runner credential (section [Credentials](#credentials)). DinD's image and
  build cache (including `RUN --mount=type=cache` mounts) are shared by all jobs.
- **The shared cache is writable by every job**: the Cargo registry and git checkouts (extracted crate sources
  are not re-verified), the pnpm store, the Playwright browsers and the target directory of a slot (build-script
  output and compiled artefacts, reused by the next job in that slot). A job can plant code that later jobs
  run. A stack restart empties all of it (tmpfs). Cargo configuration in the shared `CARGO_HOME`
  (`/cache/cargo/config.toml`, which could set a `rustc-wrapper`, a linker or a registry for every job) and
  `/cache/cargo/bin` are removed whenever a runner starts; a job running at the same time could still plant one
  for the jobs running beside it until the next start.
- **Roadmap**: one DinD per runner container (or rootless DinD / Sysbox) so a job cannot reach the machine or
  the other runners, per-job caches restored read-only, and the runner credential outside the container
  environment. Until then: only trusted events, and no secret on these runners besides the read-only
  `TAVRN_READ_PAT` and the job's own `GITHUB_TOKEN`.

**User namespaces for Chromium's sandbox**: the Electron desktop app's tests (tavrn-web, job "Desktop (Linux,
Electron)") start the app with Chromium's sandbox on, which needs unprivileged user namespaces (the setuid helper
is ruled out by `no-new-privileges`). Docker's default seccomp profile denies them, so the runner services run with
`seccomp=unconfined` (`docker-compose.yml`); `no-new-privileges` and the default AppArmor profile stay, and only
trusted events reach these runners. Ubuntu 24.04 additionally restricts user namespaces to AppArmor profiles that
allow them, so the Docker host needs `kernel.apparmor_restrict_unprivileged_userns=0`:

```bash
printf 'kernel.apparmor_restrict_unprivileged_userns = 0\n' | sudo tee /etc/sysctl.d/60-userns.conf
sudo sysctl --system
```

then recreate the stack. Check from a job (or `docker exec` into a runner): `unshare -U true` must succeed. Without it the job skips the app's tests with a warning and still builds the packages.

## Troubleshooting

| Symptom | Check |
|---|---|
| Runner containers restart in a loop, nothing on GitHub | logs: `401`/`403` at "Obtaining the token" = wrong credential or missing permission; "All of APP_ID, APP_PRIVATE_KEY and APP_LOGIN must be specified" = mixed methods |
| Jobs stay queued | labels (`tavrn-heavy`, `tavrn-e2e`), runner group allows the repository (public repositories!), runner version older than 30 days (update the image) |
| `Cannot connect to the Docker daemon at tcp://dind:2376` | `dind` healthy? Restart `dind`; `housekeeping` keeps the TLS material, so the runners' client certificates stay valid |
| Downloads fail with "connection refused" or hang | the machine's egress filter: add the destination to its allowlist; DinD containers need `DIND_DNS` pointing at a resolver they can reach |
| `docker pull` in a job fails with `lookup … on 127.0.0.11:53: server misbehaving` (SERVFAIL) | the inner daemon's bridge shadows the resolver address: `docker exec tavrn-runner-dind-1 ip addr show docker0` must not show 172.17.0.1 (the stack sets `--bip 10.200.0.1/16`); redeploy the stack after updating the compose file |
| Container killed with exit code 137 | OOM: tmpfs content counts against `mem_limit`; raise the limit or lower the tmpfs sizes |
| `no space left on device` in a build | `RUNNER_WORK_SIZE`, `RUNNER_CACHE_SIZE`, `DIND_STORAGE_SIZE` or `POSTGRES_DATA_SIZE` (count the `t_*` databases: `docker exec tavrn-runner-postgres-1 psql -U tavrn -d postgres -Atc "SELECT count(*) FROM pg_database WHERE datname LIKE 't\\_%'"`; lower `TEST_DB_MAX_AGE_HOURS`) |
| `rustup` tries to install a toolchain | the repository pins a version the image lacks: rebuild the image with `RUST_TOOLCHAIN` set accordingly |
