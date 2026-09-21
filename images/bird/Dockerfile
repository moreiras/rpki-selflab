# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# Lab router: BIRD 3.x (Alpine 3.22 -> bird 3.1.4)
# The aspa_check_upstream()/aspa_check_downstream() operators have existed
# in BIRD since version 2.16 (Dec/2024).
FROM alpine:3.22

RUN apk add --no-cache bird tini iproute2 bash tcpdump

# Default paths from the Alpine package, so "birdc" works with no arguments:
#   config: /etc/bird.conf      socket: /run/bird.ctl
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["bird", "-f"]
