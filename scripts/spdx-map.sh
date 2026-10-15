# SPDX-License-Identifier: Apache-2.0
#
# The license map of scripts/check-spdx.sh (sourced by it; LICENSE.md): every script and workflow of this repository
# is Apache-2.0. Documents, templates and small configuration files get their license from LICENSE.md and carry no
# header.
# shellcheck shell=bash disable=SC2034 # spdx_files is read by check-spdx.sh

# Every file; license_for decides.
spdx_files=()

license_for() {
  case "$1" in
    .github/workflows/*.yml | scripts/*.sh | scripts/*.mjs) echo Apache-2.0 ;;
    runner/Dockerfile | runner/*.sh | runner/*.yml | runner/*.conf | runner/*.yaml) echo Apache-2.0 ;;
    *) echo skip ;;
  esac
}
