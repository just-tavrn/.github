# SPDX-License-Identifier: Apache-2.0
#
# The list of shared scripts (docs/GITHUB.md "Shared scripts"), sourced by sync-shared.sh and check-shared.sh. Each
# has a configuration file of its own per repository: spdx-map.sh, publish-check-extra.sh (optional), labels.txt
# (optional), js-licenses.config.mjs.
# shellcheck shell=bash disable=SC2034
shared_scripts=(check-spdx.sh publish-check.sh github-labels.sh check-js-licenses.mjs)
# The SPDX header line of a copy (shell or JavaScript comment), the only line a copy may change.
spdx_line_re='^(#|//) SPDX-License-Identifier: [A-Za-z0-9.+-]+$'
