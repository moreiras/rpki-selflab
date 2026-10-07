# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# Krill, the RPKI CA: the holder's CA (service "krill") and, in MODE=local,
# the simulated registry's CA (service "rir").
#
# The upstream image, unchanged, plus vim and nano for the panel's
# "Terminal (krillc)". The Krill version is pinned here: in 0.16 the web UI
# manages both ROAs and ASPAs, and the guide's krillc subcommands (roas,
# aspas, bulk) assume 0.16's names.
FROM nlnetlabs/krill:v0.16.0

RUN apk add --no-cache vim nano
