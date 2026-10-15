# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash
# Repository extras of the shared publication check (sourced by scripts/publish-check.sh).
# The CLA workflow's allowlist names the maintainer account and the bots that never sign: public by nature, so the
# private-pattern search skips exactly that value in that file. The value is read from the workflow, so this file
# repeats nothing.
# shellcheck disable=SC2034
allow_value="$(sed -n 's/^ *allowlist: *//p' .github/workflows/cla.yml | head -n 1)"
# shellcheck disable=SC2034
allow_files=(.github/workflows/cla.yml)
