# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0
#
# Self-hosted GitHub Actions runner image for the tavrn organization (runner/README.md). One image for both
# runner classes (tavrn-heavy: Rust/JS/docker jobs, tavrn-e2e: Playwright). Base: myoung34/github-runner, which
# registers the runner with an access token or a GitHub App, supports ephemeral runners and deregisters on exit.
#
# Pinned tool versions; keep them in sync with the code repositories:
#   Node 24 + pnpm (package.json "packageManager"), Playwright (e2e lockfile), livekit-server (justfile,
#   deploy/Dockerfile), wasm-bindgen-cli (Cargo.lock), cargo-deny / gitleaks / actionlint (reusable workflows),
#   cargo-xwin / tauri-driver (the desktop app of tavrn-web, apps/desktop).
# The Rust toolchain follows rust-toolchain.toml of the code repositories (channel stable, rustfmt, clippy,
# wasm32-unknown-unknown) as of the image build; rebuild the image to pick up a new stable release.

# Valkey for the cluster tests (TAVRN_TEST_CACHE_URL), one private instance per runner container.
FROM valkey/valkey:8.1.10@sha256:640c5e62cea04b6d6f2084232651d0cc70362d31f4f805e7be94dbed6855e8f2 AS valkey
# livekit-server for the voice tests, the same release the node image ships.
FROM livekit/livekit-server:v1.13.7@sha256:6fd3b7088874c4d119160dd688798dfec852bc014786d392caad15f6f63912a3 AS livekit

# Base image (Dependabot keeps tag and digest current; the runner version is the tag).
FROM myoung34/github-runner:2.338.0-ubuntu-noble@sha256:2112bde2ee92b7480babfbe3043d0461e322b97ca01e6ac94698895f3dc1f528

ARG NODE_VERSION=24.21.0
ARG PNPM_VERSION=12.9.1
ARG PLAYWRIGHT_VERSION=1.63.0
ARG RUST_TOOLCHAIN=stable
ARG JUST_VERSION=1.58.0
ARG CARGO_DENY_VERSION=0.20.2
ARG CARGO_SWEEP_VERSION=0.8.0
ARG WASM_BINDGEN_VERSION=0.2.129
ARG GITLEAKS_VERSION=8.30.1
ARG ACTIONLINT_VERSION=1.7.12
ARG CARGO_XWIN_VERSION=0.23.1
ARG TAURI_DRIVER_VERSION=2.1.0
# BtbN static ffmpeg (GPL build, with libwebp): tooling for the media tests only, never redistributed with tavrn.
ARG FFMPEG_ASSET=ffmpeg-n8.1-latest-linux64-gpl-8.1.tar.xz

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    COREPACK_HOME=/opt/corepack \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    PATH=/cache/cargo/bin:/opt/cargo/bin:/opt/node/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# System packages: PostgreSQL client, shellcheck; drop the Docker daemon (the runners use the stack's DinD
# through DOCKER_HOST, only the CLI, buildx and compose stay) and Ubuntu's Node 18.
RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client shellcheck xz-utils procps \
    && apt-get purge -y docker-ce containerd.io nodejs \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && docker --version && docker buildx version

# Node 24 (official tarball, checksum verified) with pnpm through corepack.
RUN cd /tmp \
    && file="node-v${NODE_VERSION}-linux-x64.tar.xz" \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${file}" \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | grep " ${file}\$" | sha256sum -c - \
    && mkdir -p /opt/node && tar -xJf "$file" -C /opt/node --strip-components=1 && rm "$file" \
    && corepack enable --install-directory /opt/node/bin pnpm \
    && corepack install --global "pnpm@${PNPM_VERSION}" \
    && chmod -R a+rX "$COREPACK_HOME" \
    && node --version && pnpm --version

# Playwright: Chromium and its system libraries only (the e2e jobs run the chromium, mobile-android and
# tablet-chromium projects). The entrypoint seeds the shared cache from here.
RUN npx --yes "playwright@${PLAYWRIGHT_VERSION}" install --with-deps chromium \
    && chmod -R a+rX "$PLAYWRIGHT_BROWSERS_PATH" \
    && rm -rf /root/.npm /var/lib/apt/lists/*

# Rust (rustup, checksum verified) with the components and the target of rust-toolchain.toml.
RUN cd /tmp \
    && base="https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu" \
    && curl -fsSLO "$base/rustup-init" \
    && echo "$(curl -fsSL "$base/rustup-init.sha256" | cut -d' ' -f1)  rustup-init" | sha256sum -c - \
    && chmod +x rustup-init \
    && ./rustup-init -y --no-modify-path --profile minimal --default-toolchain "$RUST_TOOLCHAIN" \
        --component rustfmt,clippy --target wasm32-unknown-unknown \
    && rm rustup-init \
    && cargo --version && cargo clippy --version && rustfmt --version

# Rust tools: release binaries where upstream publishes checksums, cargo-sweep from source.
RUN cd /tmp \
    && gh="https://github.com" \
    && curl -fsSLO "$gh/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && curl -fsSL "$gh/casey/just/releases/download/${JUST_VERSION}/SHA256SUMS" | grep " just-${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz\$" | sha256sum -c - \
    && tar -xzf "just-${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz" just && install -m 0755 just /usr/local/bin/just \
    && deny="cargo-deny-${CARGO_DENY_VERSION}-x86_64-unknown-linux-musl" \
    && curl -fsSLO "$gh/EmbarkStudios/cargo-deny/releases/download/${CARGO_DENY_VERSION}/${deny}.tar.gz" \
    && echo "$(curl -fsSL "$gh/EmbarkStudios/cargo-deny/releases/download/${CARGO_DENY_VERSION}/${deny}.tar.gz.sha256" | cut -d' ' -f1)  ${deny}.tar.gz" | sha256sum -c - \
    && tar -xzf "${deny}.tar.gz" && install -m 0755 "${deny}/cargo-deny" /usr/local/bin/cargo-deny \
    && wb="wasm-bindgen-${WASM_BINDGEN_VERSION}-x86_64-unknown-linux-musl" \
    && curl -fsSLO "$gh/wasm-bindgen/wasm-bindgen/releases/download/${WASM_BINDGEN_VERSION}/${wb}.tar.gz" \
    && echo "$(curl -fsSL "$gh/wasm-bindgen/wasm-bindgen/releases/download/${WASM_BINDGEN_VERSION}/${wb}.tar.gz.sha256sum" | cut -d' ' -f1)  ${wb}.tar.gz" | sha256sum -c - \
    && tar -xzf "${wb}.tar.gz" && install -m 0755 "${wb}/wasm-bindgen" /usr/local/bin/wasm-bindgen \
    && cargo install --locked --root /usr/local "cargo-sweep@${CARGO_SWEEP_VERSION}" \
    && rm -rf /tmp/* "$CARGO_HOME/registry" "$CARGO_HOME/git" \
    && just --version && cargo deny --version && wasm-bindgen --version && cargo sweep --version

# Lint and scan tools of the workflows.
RUN cd /tmp \
    && gh="https://github.com" \
    && gl="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    && curl -fsSLO "$gh/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${gl}" \
    && curl -fsSL "$gh/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_checksums.txt" | grep " ${gl}\$" | sha256sum -c - \
    && tar -xzf "$gl" gitleaks && install -m 0755 gitleaks /usr/local/bin/gitleaks \
    && al="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
    && curl -fsSLO "$gh/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/${al}" \
    && curl -fsSL "$gh/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_checksums.txt" | grep " ${al}\$" | sha256sum -c - \
    && tar -xzf "$al" actionlint && install -m 0755 actionlint /usr/local/bin/actionlint \
    && rm -rf /tmp/* \
    && gitleaks version && actionlint --version

# Static ffmpeg with libwebp for the media pipeline tests (TAVRN_MEDIA_FFMPEG=auto finds it in PATH).
RUN cd /tmp \
    && base="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest" \
    && curl -fsSLO "$base/${FFMPEG_ASSET}" \
    && curl -fsSL "$base/checksums.sha256" | grep " ${FFMPEG_ASSET}\$" | sha256sum -c - \
    && tar -xJf "${FFMPEG_ASSET}" --strip-components=2 --wildcards '*/bin/ffmpeg' \
    && install -m 0755 ffmpeg /usr/local/bin/ffmpeg && rm -rf /tmp/* \
    && ffmpeg -hide_banner -encoders | grep -c libwebp_anim

# Desktop app (Tauri 2, runner/README.md "Desktop builds"): WebKitGTK and GTK development files for the Linux
# build and its deb/AppImage bundles, WebKitWebDriver and Xvfb for WebDriver tests, NSIS and LLVM (clang as
# clang-cl, lld-link, llvm-lib, llvm-rc) for the Windows build with cargo-xwin.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev patchelf xdg-utils file \
        webkit2gtk-driver xvfb xdotool gnome-keyring nsis clang lld llvm \
    && rm -rf /var/lib/apt/lists/* \
    && command -v WebKitWebDriver xvfb-run xdotool gnome-keyring-daemon lld-link llvm-lib llvm-rc >/dev/null \
    && makensis -VERSION && clang --version | head -n1

# Windows target and the Tauri tools: cargo-xwin (release binary, checksum verified) and tauri-driver (WebDriver
# bridge to WebKitWebDriver). The Microsoft CRT and Windows SDK that cargo-xwin needs are not part of the image:
# their license forbids publishing them, so the entrypoint downloads them into the runners' cache (README).
RUN cd /tmp \
    && rustup target add x86_64-pc-windows-msvc \
    && xw="cargo-xwin-v${CARGO_XWIN_VERSION}.x86_64-unknown-linux-musl.tar.gz" \
    && curl -fsSLO "https://github.com/rust-cross/cargo-xwin/releases/download/v${CARGO_XWIN_VERSION}/${xw}" \
    && echo "$(curl -fsSL "https://github.com/rust-cross/cargo-xwin/releases/download/v${CARGO_XWIN_VERSION}/${xw}.sha256" | cut -d' ' -f1)  ${xw}" | sha256sum -c - \
    && tar -xzf "$xw" cargo-xwin && install -m 0755 cargo-xwin /usr/local/bin/cargo-xwin \
    && cargo install --locked --root /usr/local "tauri-driver@${TAURI_DRIVER_VERSION}" \
    && rm -rf /tmp/* "$CARGO_HOME/registry" "$CARGO_HOME/git" \
    && cargo xwin --version && command -v tauri-driver

# cargo-xwin: x86_64 desktop libraries only; the entrypoint's download and the jobs must ask for the same set.
ENV XWIN_ARCH=x86_64 \
    XWIN_VARIANT=desktop

COPY --from=livekit /livekit-server /usr/local/bin/livekit-server
COPY --from=valkey /usr/local/bin/valkey-server /usr/local/bin/valkey-cli /usr/local/bin/
COPY --chmod=0755 entrypoint.sh /usr/local/bin/tavrn-runner-entrypoint

RUN livekit-server --version && valkey-server --version

# The stack mounts tmpfs over the work directory, /tmp, the home directory and /cache (runner/docker-compose.yml).
ENV RUNNER_WORKDIR=/_work \
    DISABLE_AUTO_UPDATE=true \
    RUN_AS_ROOT=false \
    UNSET_CONFIG_VARS=true

ENTRYPOINT ["/usr/local/bin/tavrn-runner-entrypoint"]
CMD ["./bin/Runner.Listener", "run", "--startuptype", "service"]
