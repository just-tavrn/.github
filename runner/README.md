# Self-hosted runners

Ephemeral GitHub Actions runners for the `just-tavrn` organization on a test host: a **dedicated
VM** as the isolation boundary, inside it a Docker Compose stack managed from Portainer. Everything the
runners write lives in RAM (tmpfs); the host's disk only holds the VM's system and its container images.

| Path | What it is |
|---|---|
| [vm/make-vm.sh](vm/make-vm.sh) | Creates the VM with KVM/libvirt from the Ubuntu 24.04 cloud image |
| [vm/user-data.yaml](vm/user-data.yaml), [vm/network-config.yaml](vm/network-config.yaml) | cloud-init: Docker Engine, compose plugin, Portainer agent, firewall, resolver |
| [vm/nftables.conf](vm/nftables.conf), [vm/dnsmasq-egress.conf](vm/dnsmasq-egress.conf) | Egress filter of the VM: no LAN, only allowlisted destinations |
| [vm/libvirt-network.xml](vm/libvirt-network.xml) | libvirt network `tavrn-ci` in bridge mode on the host bridge `br-ci` |
| [docker-compose.yml](docker-compose.yml), [.env.example](.env.example) | The runner stack (Portainer stack) and its variables |
| [Dockerfile](Dockerfile), [entrypoint.sh](entrypoint.sh) | The runner image (`ghcr.io/just-tavrn/tavrn-runner`, built by [runner-image.yml](../.github/workflows/runner-image.yml)) |
| [smoke-desktop.sh](smoke-desktop.sh) | Smoke test of the image's desktop toolchain (section [Desktop builds](#desktop-builds)) |

## What runs where

| Jobs | Runner | Why |
|---|---|---|
| gitleaks, CLA, actionlint/shellcheck of this repository | GitHub-hosted (`ubuntu-latest`) | light, need no tools from the image |
| Rust CI, JavaScript CI, container builds (`rust-ci.yml`, `js-ci.yml`, `docker-publish.yml` with `runner: tavrn-heavy`) | self-hosted `tavrn-heavy` | heavy builds and tests; PostgreSQL and Valkey of the stack, caches in RAM |
| Pull requests from forks and from Dependabot of those workflows | GitHub-hosted (automatic fallback) | untrusted code never reaches the VM |
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

## Why a VM

DinD runs **privileged**, and containers share the kernel with whatever runs them: a job that escapes its
container (a compromised dependency, action or image is enough once the repositories are public) is root on
that machine. On the host that would mean its data, its other containers and its LAN. The VM moves
that blast radius into a machine that holds nothing of value, has no shared folders and no host mounts, and
whose network can only reach the internet:

1. **VM boundary** (KVM): an escape from DinD reaches the VM's kernel, not the host's.
2. **Network isolation outside the VM**: the VM sits in a VLAN of its own whose router zone forwards only to
   the WAN. This holds even if an attacker is root in the VM.
3. **Egress filter inside the VM** (defense in depth): nftables rejects every private, loopback and link-local
   destination and lets TCP 80/443 through only to addresses of allowlisted domains (dnsmasq fills the sets).
4. **Ephemeral runners**: one job per container; the work directory, `/tmp` and the home directory are fresh
   tmpfs mounts for every job.

Alternatives considered:

| Option | Why not (for now) |
|---|---|
| Sysbox (unprivileged DinD as a runc replacement) | still a shared kernel; development has slowed since the acquisition by Docker; another runtime to maintain on the host |
| gVisor (`runsc`) | DinD inside gVisor is limited and slow; syscall-heavy Rust builds pay a large overhead |
| Kata Containers | a VM per container is strong isolation, but needs containerd shims and nested DinD tuning; Portainer support is thin |
| Firecracker microVM per job (actuated, self-built orchestrators) | strongest per-job isolation, but commercial or a project of its own (images, networking, scheduling) |
| Actions Runner Controller on Kubernetes | needs a Kubernetes cluster; the same DinD question remains |

One VM plus ephemeral containers is simple, managed from the existing Portainer, and keeps the host and LAN
out of reach. Inside the VM, jobs are separated by containers only, which is acceptable because only trusted
events get the self-hosted runners (section [Security](#security)).

## 1. Host network

Run the VM in a **VLAN and firewall zone of its own that can only reach the internet**: no forwarding to the
LAN or other VLANs, no access to the router itself except DNS (and DHCP if the VM takes a lease). The LAN may
reach the zone for administration (SSH, Portainer agent). On OpenWrt that is a `bridge-vlan` with the VLAN
tagged on the port towards the host, an interface with a static address in that VLAN, and a firewall zone
with input and forward `DROP`, a forwarding to `wan` only, a forwarding from `lan`, and a rule that accepts
DNS (port 53) from the zone. A managed switch on the way must carry the VLAN tagged on both trunk ports.
Do not reuse an existing guest or IoT network: the runners would share it with other devices.

The examples below use placeholders: `CI_VLAN` (for example `50`), `CI_SUBNET` (for example `10.100.0.0/24`,
router `.1`, VM `.10`), `<host-bridge>` or `<uplink>` (the host's bridge or NIC that receives the tagged
frames). The VM uses a static address and the router as DNS resolver by default.

On the host, a VLAN interface and a bridge `br-ci` **without host address**, so the VM cannot talk to the host
(`/etc/netplan/60-ci.yaml`, mode 600; here `CI_VLAN=50`):

```yaml
network:
  version: 2
  vlans:
    vlan50:
      id: 50
      link: <host-bridge>    # or <uplink>; it must be defined in netplan as well
  bridges:
    br-ci:
      interfaces: [vlan50]
      parameters:
        stp: false
      dhcp4: false
      dhcp6: false
      link-local: []
```

Apply with `netplan try` (or `netplan generate && netplan apply` where `try` is not supported). On hosts whose
interfaces live in NetworkManager only, create the same with `nmcli` (bridge without IPv4/IPv6, a VLAN
connection on the parent device as its port). Verify with `ip -d link show vlan50` (802.1Q id, master
`br-ci`), `ip -4 addr show br-ci` (no address), `bridge link show` (ports of `br-ci`) and `bridge vlan show`.

make-vm.sh defines the libvirt network `tavrn-ci` on `br-ci` from [vm/libvirt-network.xml](vm/libvirt-network.xml)
(bridge mode: no NAT, no libvirt DHCP or DNS) and refuses to run while `br-ci` has a host IPv4 address.

Docker on the host loads `br_netfilter`, which sends bridged frames through the host's `FORWARD` chain whose
policy Docker sets to `DROP`. Let the CI bridge pass (persist it, for example in a small systemd unit that runs
after `docker.service`):

```bash
iptables -I DOCKER-USER -i br-ci -o br-ci -j ACCEPT
```

> **Host routing check.** Docker's default address pools on a busy host often cover large private ranges (for
> example `192.168.16.0/20`–`192.168.208.0/20`). If `ip route get <VM address>` on the host answers with a
> Docker bridge instead of your router, add a more specific route for the CI subnet via the router (a netplan
> `routes:` entry on the host bridge), or the host and its Portainer server will never reach the VM.

## 2. The VM

On the host, as root (packages: `apt install qemu-kvm libvirt-daemon-system virtinst qemu-utils`):

```bash
git clone https://github.com/just-tavrn/.github tavrn-dot-github && cd tavrn-dot-github
CI_SUBNET=10.100.0.0/24 \
ADMIN_CIDR=192.0.2.0/24 \
SSH_PUBKEY_FILE=/root/.ssh/id_ed25519.pub \
AGENT_SECRET="$(openssl rand -hex 24)" \
VM_RAM_GB=512 VM_VCPUS=32 \
runner/vm/make-vm.sh
```

- `ADMIN_CIDR`: the LAN network (or the single address) of the admin machine and the Portainer server; only
  it reaches SSH (22) and the Portainer agent (9001) of the VM.
- `AGENT_SECRET`: optional, but recommended; the Portainer **server** must run with the same `AGENT_SECRET`.
- `PORTAINER_AGENT_IMAGE`: defaults to `portainer/agent:2.45.1` pinned by digest; use your server's version.
- `VM_DISK_GB` (default 64): system and container images only; jobs never write to it.
- `CI_SUBNET` (a /24; the default `10.100.0.0/24` is only an example) sets the defaults `VM_IP_CIDR=<.10>/24`,
  `VM_GATEWAY=<.1>` and `DNS_UPSTREAM=<.1>` (the router; the only private address the VM's firewall lets it
  talk to, DNS only). `VM_IP_CIDR=dhcp` takes a lease instead; `DNS_UPSTREAM=9.9.9.9,149.112.112.112` uses public
  resolvers instead of the router. `DRY_RUN=1` only renders the cloud-init files.

Follow the first boot with `virsh console tavrn-ci`, then `ssh ciadmin@<VM address>` and
`cloud-init status --wait`. Check the isolation from inside the VM:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://api.github.com    # 200
curl -sS -m 5 http://<a LAN address> || echo blocked              # blocked (any private address)
curl -sS -m 5 http://<router address> || echo blocked               # blocked (router: DNS only)
curl -sS -m 5 https://example.org || echo blocked                   # blocked (not allowlisted)
sudo journalctl -k | grep tavrn-egress | tail                         # what was rejected
```

The allowlist ([vm/dnsmasq-egress.conf](vm/dnsmasq-egress.conf)) covers GitHub (including the Actions
service and its Azure blob storage), ghcr.io, crates.io and rustup, npm and Node.js, Playwright downloads,
Microsoft's Visual Studio download server (the Windows SDK of the [desktop builds](#desktop-builds)),
Docker Hub, the Ubuntu/Debian/Alpine mirrors and the sources of tavrn's `deploy/Dockerfile`. CDNs host many
sites on the same addresses, and `blob.core.windows.net` / `storage.googleapis.com` are shared storage, so the
allowlist narrows exfiltration but does not close it; its main job together with the private-range block is to
keep the LAN and the host unreachable. A new destination: add the domain, `sudo systemctl restart dnsmasq`, and
add it to the file in this repository.

## 3. The stack in Portainer

1. **Credentials** (section [Credentials](#credentials)): create the GitHub App or the token first.
2. **Image**: after `runner-image.yml` ran on `main`, open the package
   `ghcr.io/just-tavrn/tavrn-runner` and set its visibility to **Public** (it contains no secrets; private
   packages count against the Free plan's 500 MB package storage and would need registry credentials in the
   VM). Take the digest from the workflow run's summary or with
   `docker buildx imagetools inspect ghcr.io/just-tavrn/tavrn-runner:edge`.
3. Portainer → **Environments** → **Add environment** → **Docker Standalone** → **Agent**: name `tavrn-ci`,
   environment address `<VM address>:9001` → **Connect**.
4. In the environment `tavrn-ci`: **Stacks** → **Add stack**, name `tavrn-runner`, build method
   **Repository**: URL `https://github.com/just-tavrn/.github`, reference `refs/heads/main`, compose path
   `runner/docker-compose.yml`; while the repository is private, enable authentication with a fine-grained PAT
   that has **Contents: Read-only** on `just-tavrn/.github`. (Or build method **Web editor** and paste the file.)
5. **Environment variables** → **Advanced mode**: paste [.env.example](.env.example), set `RUNNER_IMAGE` to
   the digest from step 2 and exactly one credential method.
6. **Deploy the stack**. After about a minute:
   ```bash
   gh api orgs/just-tavrn/actions/runners \
     --jq '.runners[] | [.name, .status, .busy, ([.labels[].name] | join(","))] | @tsv'
   ```
   shows `tavrn-heavy-…` (two) and `tavrn-e2e-…` (one) as `online`.

**Scaling**: change `RUNNER_HEAVY_REPLICAS` / `RUNNER_E2E_REPLICAS` in the stack's variables → **Update the
stack**. Keep the memory budget below in mind.

**Logs**: Portainer → **Containers** → `tavrn-runner-runner-heavy-1` → **Logs** (registration and job names),
or in the VM `docker compose -p tavrn-runner logs -f runner-heavy`. A job's own log is on GitHub.

**Updating**: the image is pinned by digest. A new image appears on every change of `runner/Dockerfile` (also
Dependabot's base image bumps) and weekly. Set the new digest in `RUNNER_IMAGE` → **Update the stack**
(re-pull). The runners have automatic updates disabled; GitHub stops sending jobs to a runner version older
than about 30 days after a newer release, so update at least monthly. An update recreates the containers and
cancels running jobs: check `busy` in the runner list first. The VM itself installs security updates
unattended and reboots at 04:30 when needed.

**Reboot**: all tmpfs content (caches, DinD images, the test database) is gone, by design. Docker starts the
stack again, the runners register anew, the first builds are cold. Nothing needs restoring. The host starts
the VM automatically (`--autostart`).

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
by `no-new-privileges`) cannot read it from the root-owned processes. It lives in Portainer's stack variables
and in the container configuration of the VM; rotate it if the VM is ever suspected compromised.

## Memory

Every size is an upper limit, not a reservation. What a container writes to its tmpfs counts against its own
`mem_limit`; what the runners write to the shared cache volume counts against the runner while it runs and
against no limit after the container restarts. Defaults for a 512 GB VM:

| Item | Default | Worst case |
|---|---|---|
| `runner-heavy` ×2: processes + `/_work` (64 GB) + `/tmp` (16 GB) + home (4 GB) | `RUNNER_HEAVY_MEMORY=128g` | 256 GB |
| `runner-e2e` ×1: processes + `/_work` (32 GB) + `/tmp` + home | `RUNNER_E2E_MEMORY=48g` | 48 GB |
| `dind`: daemon, job containers, `/var/lib/docker` (32 GB) | `DIND_MEMORY=48g` | 48 GB |
| `postgres`: data (16 GB), shared buffers (2 GB), `/dev/shm` (1 GB) | `POSTGRES_MEMORY=24g` | 24 GB |
| shared cache volume (Cargo registry, pnpm store, browsers, one target directory per runner) | `RUNNER_CACHE_SIZE=128g` | 128 GB |
| VM system, Docker, housekeeping | | ~4 GB |
| **Sum** | | **~508 GB** |

Realistic use is far lower: a Rust target directory of the tavrn workspace is 20–40 GB
(`RUNNER_TARGET_MAX_GB=40` restarts one that grows beyond), a checkout with `node_modules` 2–5 GB, a test run
10–20 GB of processes. On a larger host, give the VM more memory and raise replicas or limits; keep
the sum of the worst-case column below the VM's memory, because a VM without swap answers overcommit with the
OOM killer (inside the VM, never on the host).

## Caches

`/cache` is one tmpfs volume shared by all runners and kept mounted by the `housekeeping` service, so it
survives the restart after every job (Docker discards a tmpfs volume when no container uses it):

- `/cache/cargo` (`CARGO_HOME`: registry, git checkouts, `cargo install`ed tools) and `/cache/pnpm-store` are
  shared; both tools lock them for concurrent use.
- `/cache/ms-playwright` is seeded once from the image's Chromium; other Playwright versions download beside it.
- `/cache/cargo-xwin/xwin` holds the Microsoft CRT and Windows SDK of the Windows desktop build, downloaded once
  by the entrypoint of the first `tavrn-heavy` runner (section [Desktop builds](#desktop-builds)).
- `/cache/slots/<class>-<n>/target` and `…/toolcache`: each runner container holds an exclusive `flock` on
  one slot for its lifetime, so two jobs never share a Cargo target directory.

The `toolchain` and `extra-targets` inputs of `rust-ci.yml` and the `node-version` inputs are checked against
the image on self-hosted runners, not installed (an install would write to the container layer on disk);
rebuild the image for a new Rust or Node.js release. The `services:` PostgreSQL of `rust-ci.yml` only runs on
GitHub-hosted runners; self-hosted jobs always get `TAVRN_TEST_DATABASE_URL` (the stack's PostgreSQL) and
`TAVRN_TEST_CACHE_URL` (a private Valkey in every runner container: the cluster outage test kills all clients
of its Valkey, which would break parallel jobs on a shared one).

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
| Windows build | Rust target `x86_64-pc-windows-msvc`, `cargo-xwin` (`CARGO_XWIN_VERSION`), `clang` (as `clang-cl`), `lld` (`lld-link`), `llvm` (`llvm-lib`, `llvm-rc`), `nsis` (`makensis`); `XWIN_ARCH=x86_64`, `XWIN_VARIANT=desktop` |

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
  `cargo-xwin cache xwin` into `/cache/cargo-xwin/xwin` before the runner registers: once per VM boot, by the
  first runner, while the others wait on a lock (about 7 minutes on a test machine's home line). The jobs get
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
   only**; when the repositories go public, tick **Allow public repositories** in the group's settings and rely
   on the workflow guards below (on the Team plan: a group `tavrn` limited to the code repositories).
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
- Self-hosted jobs share the RAM cache (target directories, registry); a trusted job could poison it for the
  next one. Acceptable because only trusted events get these runners; clear it with a stack restart if in doubt.

**In the stack**: ephemeral runners, `no-new-privileges` (no sudo), no Docker socket of the VM in any
container, DinD only on the internal network with TLS client certificates and no published port, PostgreSQL
only on the internal network, no published ports at all. Never publish DinD's port 2376 or mount the VM's
Docker socket into a runner.

## Stack directly on a host (not recommended once the repositories are public)

The compose file runs unchanged on any Docker host: set `DIND_DNS` to a resolver the containers can reach
(for example `9.9.9.9`), scale the sizes to the host, and deploy it as above. Privileged DinD then means that a
job escaping its container is root **on that host** with its LAN in reach. Acceptable only while every
repository is private and every committer is trusted.

## Troubleshooting

| Symptom | Check |
|---|---|
| Runner containers restart in a loop, nothing on GitHub | logs: `401`/`403` at "Obtaining the token" = wrong credential or missing permission; "All of APP_ID, APP_PRIVATE_KEY and APP_LOGIN must be specified" = mixed methods |
| Jobs stay queued | labels (`tavrn-heavy`, `tavrn-e2e`), runner group allows the repository (public repositories!), runner version older than 30 days (update the image) |
| `Cannot connect to the Docker daemon at tcp://dind:2376` | `dind` healthy? Restart `dind`; `housekeeping` keeps the TLS material, so the runners' client certificates stay valid |
| Downloads fail with "connection refused" or hang | `sudo journalctl -k \| grep tavrn-egress` in the VM; add the domain to `dnsmasq-egress.conf`; DinD containers need `DIND_DNS=172.17.0.1` |
| `docker pull` in a job fails with `lookup … on 127.0.0.11:53: server misbehaving` (SERVFAIL) | the inner daemon's bridge shadows the resolver address: `docker exec tavrn-runner-dind-1 ip addr show docker0` must not show 172.17.0.1 (the stack sets `--bip 10.200.0.1/16`); redeploy the stack after updating the compose file |
| Container killed with exit code 137 | OOM: tmpfs content counts against `mem_limit`; raise the limit or lower the tmpfs sizes |
| `no space left on device` in a build | `RUNNER_WORK_SIZE`, `RUNNER_CACHE_SIZE`, `DIND_STORAGE_SIZE` or `POSTGRES_DATA_SIZE` (count the `t_*` databases: `docker exec tavrn-runner-postgres-1 psql -U tavrn -d postgres -Atc "SELECT count(*) FROM pg_database WHERE datname LIKE 't\\_%'"`; lower `TEST_DB_MAX_AGE_HOURS`) |
| VM has no network | Docker's `br_netfilter` on the host: the `DOCKER-USER` rule above; the VLAN tagged on both trunk ports of a managed switch; `bridge link show` lists the VLAN interface and the VM's `vnetN` in `br-ci` |
| Lookups fail in the VM | the router accepts DNS from the CI zone and its resolver answers on that interface; in the VM `dig @<router address> github.com` |
| `rustup` tries to install a toolchain | the repository pins a version the image lacks: rebuild the image with `RUST_TOOLCHAIN` set accordingly |
