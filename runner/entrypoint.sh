#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Entrypoint of the tavrn runner image (runner/Dockerfile). Runs as root before the image's own /entrypoint.sh
# (which registers the runner and drops to the user "runner"):
#   1. claims a cache slot in the shared RAM cache /cache (runner/README.md, "Caches"): an flock on
#      /cache/slots/<class>-<n>/.lock held for the container's lifetime, so no two runners share a Cargo target
#      directory or tool cache; the Cargo registry, the pnpm store and the Playwright browsers are shared,
#   2. starts a private Valkey on 127.0.0.1:6379 for the cluster tests (TAVRN_TEST_CACHE_URL); private because
#      the outage test kills every client of its Valkey,
#   3. with TAVRN_XWIN=true, downloads the Microsoft CRT and Windows SDK for cargo-xwin into the shared cache
#      once (the Windows build of the desktop app; their license forbids publishing them in the image),
#   4. hands over to /entrypoint.sh. Everything exported here reaches the jobs.
set -euo pipefail

cache="${TAVRN_CACHE_DIR:-/cache}"
class="${TAVRN_RUNNER_CLASS:-runner}"
slots="${TAVRN_CACHE_SLOTS:-32}"
target_max_gb="${TAVRN_TARGET_MAX_GB:-40}"

log() { echo "tavrn-runner: $*"; }

# True when cargo-xwin's marker file lists every architecture of XWIN_ARCH (its first line).
xwin_ready() {
  local arch archs="${XWIN_ARCH:-x86_64}"
  [ -s "$1" ] || return 1
  for arch in ${archs//,/ }; do
    head -n1 "$1" | grep -qw -- "$arch" || return 1
  done
}

if [ "$(id -u)" -ne 0 ]; then
  log "must start as root (the image's entrypoint drops to the user runner); do not set user: in the compose file" >&2
  exit 1
fi

if [ -d "$cache" ] && mountpoint -q "$cache"; then
  install -d -o runner -g runner "$cache/cargo" "$cache/pnpm-store" "$cache/slots"

  slot=""
  for i in $(seq 1 "$slots"); do
    candidate="$cache/slots/$class-$i"
    mkdir -p "$candidate"
    exec 9>>"$candidate/.lock"
    if flock -n 9; then
      slot="$candidate"
      break
    fi
    exec 9>&-
  done
  if [ -z "$slot" ]; then
    log "no free cache slot among $slots for class $class (TAVRN_CACHE_SLOTS)" >&2
    exit 1
  fi
  # fd 9 stays open through exec: the lock lives as long as the container.

  install -d -o runner -g runner "$slot/target" "$slot/toolcache"
  used_gb=$(du -s --block-size=1G "$slot/target" | cut -f1)
  if [ "$used_gb" -gt "$target_max_gb" ]; then
    log "target directory of $(basename "$slot") is ${used_gb} GB (> ${target_max_gb} GB): starting it over"
    rm -rf "$slot/target" && install -d -o runner -g runner "$slot/target"
  fi

  # Playwright browsers of the image, copied once into the shared cache; newer Playwright versions download
  # next to them (Playwright locks the directory itself).
  if [ ! -e "$cache/ms-playwright/.seeded" ] && [ -d /opt/ms-playwright ]; then
    (
      flock 8
      if [ ! -e "$cache/ms-playwright/.seeded" ]; then
        install -d -o runner -g runner "$cache/ms-playwright"
        cp -a /opt/ms-playwright/. "$cache/ms-playwright/"
        chown -R runner:runner "$cache/ms-playwright"
        touch "$cache/ms-playwright/.seeded"
      fi
    ) 8>>"$cache/.seed.lock"
  fi

  # cargo-xwin (runner/README.md, "Desktop builds"): CRT and SDK in $cache/cargo-xwin/xwin, downloaded by the first
  # runner that needs them while the others wait on the lock. Each slot gets a cargo-xwin directory of its own,
  # because cargo-xwin replaces a clang-cl link in it on every build; its xwin/ is the shared download.
  xwin="$cache/cargo-xwin"
  install -d -o runner -g runner "$xwin" "$xwin/xwin" "$slot/cargo-xwin"
  if [ "${TAVRN_XWIN:-false}" = "true" ] && ! xwin_ready "$xwin/xwin/DONE"; then
    (
      flock 7
      if ! xwin_ready "$xwin/xwin/DONE"; then
        log "downloading the Microsoft CRT and Windows SDK for cargo-xwin (${XWIN_ARCH:-}, ${XWIN_VARIANT:-})"
        if env -i PATH="$PATH" XWIN_CACHE_DIR="$xwin" XWIN_ARCH="${XWIN_ARCH:-x86_64}" XWIN_VARIANT="${XWIN_VARIANT:-desktop}" \
          timeout "${TAVRN_XWIN_TIMEOUT:-30m}" gosu runner cargo-xwin cache xwin >/dev/null; then
          log "cargo-xwin cache ready ($(du -sh "$xwin/xwin" | cut -f1))"
        else
          log "cargo-xwin cache download failed: Windows builds will try to download it themselves" >&2
        fi
      fi
    ) 7>>"$cache/.xwin.lock"
  fi
  if [ ! -L "$slot/cargo-xwin/xwin" ]; then
    rm -rf "$slot/cargo-xwin/xwin"
  fi
  ln -sfn "$xwin/xwin" "$slot/cargo-xwin/xwin"

  export XWIN_CACHE_DIR="$slot/cargo-xwin"
  export CARGO_HOME="$cache/cargo"
  export CARGO_TARGET_DIR="$slot/target"
  export RUNNER_TOOL_CACHE="$slot/toolcache"
  export AGENT_TOOLSDIRECTORY="$slot/toolcache"
  export PLAYWRIGHT_BROWSERS_PATH="$cache/ms-playwright"
  export npm_config_store_dir="$cache/pnpm-store"
  export pnpm_config_store_dir="$cache/pnpm-store"
  log "cache slot $(basename "$slot") (target ${used_gb} GB)"
else
  log "no cache volume at $cache: building without caches"
fi

if [ "${TAVRN_VALKEY:-true}" = "true" ]; then
  # A clean environment: the registration credentials must not end up in a process the jobs can inspect.
  env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin gosu runner valkey-server --bind 127.0.0.1 --port 6379 --protected-mode yes --save "" --appendonly no \
    --dir /tmp --logfile /tmp/valkey.log --daemonize yes
  export TAVRN_TEST_CACHE_URL="${TAVRN_TEST_CACHE_URL:-redis://127.0.0.1:6379}"
fi

exec /entrypoint.sh "$@"
