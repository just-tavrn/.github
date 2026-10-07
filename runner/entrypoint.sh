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
#   3. hands over to /entrypoint.sh. Everything exported here reaches the jobs.
set -euo pipefail

cache="${TAVRN_CACHE_DIR:-/cache}"
class="${TAVRN_RUNNER_CLASS:-runner}"
slots="${TAVRN_CACHE_SLOTS:-32}"
target_max_gb="${TAVRN_TARGET_MAX_GB:-40}"

log() { echo "tavrn-runner: $*"; }

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
