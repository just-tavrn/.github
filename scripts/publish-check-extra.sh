# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash
# Repository extras of the shared publication check (sourced by scripts/publish-check.sh).
# The CLA workflow's allowlist names the maintainer account and the bots that never sign: public by nature, so the
# private-pattern search skips exactly that value in that file.
allow_value="babatonga,dependabot[bot],renovate[bot]"
allow_files=(.github/workflows/cla.yml)
