# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# Routinator, observer1's RPKI validator.
#
# The upstream image, unchanged, plus vim and nano for the panel's terminal.
# The image runs as the unprivileged "routinator" user; packages are added as
# root and the user is restored afterwards. The version is pinned here:
# --enable-aspa and RTR version 2 need 0.14 or later.
FROM nlnetlabs/routinator:v0.15.2

USER root
RUN apk add --no-cache vim nano
USER routinator
