#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Smoke test of the desktop toolchain in the runner image (runner/README.md, "Desktop builds"): scaffolds a
# minimal Tauri 2 app and builds it for Linux (deb, AppImage; then starts it under Xvfb for a few seconds) and for
# Windows (NSIS installer, cross-compiled with cargo-xwin). Runs inside the image as the user runner, like a job:
#
#   docker run --rm --user runner --entrypoint /smoke-desktop.sh \
#     -v "$PWD/runner/smoke-desktop.sh:/smoke-desktop.sh:ro" <image> [all|linux|windows]
#
# Needs network for the scaffold (npm, crates.io) and for the Tauri bundler's tools (GitHub). cargo-xwin takes the
# Microsoft CRT and Windows SDK from XWIN_CACHE_DIR when the entrypoint prepared it there; otherwise it downloads
# them itself (accepting Microsoft's license, see the README). SMOKE_DIR keeps the project between runs.
set -euo pipefail

what="${1:-all}"
dir="${SMOKE_DIR:-$(mktemp -d)}"
create_version="${CREATE_TAURI_APP_VERSION:-4.7.4}"
name=desktop-smoke
app="$dir/$name"

log() { echo "smoke-desktop: $*"; }
fail() { echo "smoke-desktop: FAIL: $*" >&2; exit 1; }

case "$what" in
  all | linux | windows) ;;
  *) fail "usage: $0 [all|linux|windows]" ;;
esac

if [ ! -f "$app/package.json" ]; then
  log "scaffolding a Tauri 2 app in $app (create-tauri-app $create_version)"
  mkdir -p "$dir"
  (cd "$dir" && pnpm dlx "create-tauri-app@${create_version}" "$name" \
    --template vanilla --manager pnpm --identifier org.example.desktopsmoke --yes)
fi
cd "$app"
pnpm install --prefer-offline
target="${CARGO_TARGET_DIR:-$app/src-tauri/target}"

if [ "$what" != windows ]; then
  log "Linux build (deb, AppImage)"
  pnpm tauri build --bundles deb,appimage
  deb=$(ls "$target"/release/bundle/deb/*.deb) || fail "no .deb bundle"
  appimage=$(ls "$target"/release/bundle/appimage/*.AppImage) || fail "no AppImage bundle"
  log "starting the Linux build under Xvfb for 5 seconds"
  status=0
  timeout 5 xvfb-run -a "$target/release/$name" || status=$?
  # 124: still running when the timeout stopped it, i.e. it started.
  [ "$status" -eq 124 ] || fail "the app exited with status $status under Xvfb"
  command -v WebKitWebDriver tauri-driver >/dev/null || fail "WebKitWebDriver or tauri-driver missing"
fi

if [ "$what" != linux ]; then
  if [ -n "${XWIN_CACHE_DIR:-}" ] && [ -s "$XWIN_CACHE_DIR/xwin/DONE" ]; then
    log "Windows build: CRT and SDK from $XWIN_CACHE_DIR/xwin"
  else
    log "Windows build: no prepared XWIN_CACHE_DIR, cargo-xwin downloads the CRT and SDK"
  fi
  pnpm tauri build --runner cargo-xwin --target x86_64-pc-windows-msvc --bundles nsis
  exe="$target/x86_64-pc-windows-msvc/release/$name.exe"
  setup=$(ls "$target"/x86_64-pc-windows-msvc/release/bundle/nsis/*-setup.exe) || fail "no NSIS installer"
  file "$exe" | grep -q 'PE32+ executable.*x86-64' || fail "$exe is not a 64-bit Windows executable"
  file "$setup" | grep -q 'PE32' || fail "$setup is not a Windows executable"
fi

log "OK"
for f in "${deb:-}" "${appimage:-}" "${exe:-}" "${setup:-}"; do
  [ -n "$f" ] && log "  $(du -h "$f" | cut -f1)  $f ($(file -b "$f" | cut -c1-60))"
done
exit 0
