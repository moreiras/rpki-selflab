# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# observer2's router: OpenBGPD 8.8 (Alpine 3.22).
#
# OpenBGPD is the lab's second BGP implementation. Unlike BIRD, it computes
# the RPKI verdicts natively into two per-route attributes - ovs (origin
# validation state, RFC 6811) and avs (ASPA validation state) - so no
# community-marking convention is needed to read them back.
#
# ASPA support and "rtr ... min-version 2" require OpenBGPD 8.x.
FROM alpine:3.22

RUN apk add --no-cache openbgpd tini bash iproute2 tcpdump

# bgpd drops privileges to _bgpd and chroots into /var/empty. The Alpine
# package ships neither, so create them here or bgpd exits with
# "unknown user _bgpd".
RUN addgroup -S _bgpd \
    && adduser -S -D -H -h /var/empty -s /sbin/nologin -G _bgpd -g _bgpd _bgpd \
    && mkdir -p /var/empty

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["bgpd", "-d", "-v"]
