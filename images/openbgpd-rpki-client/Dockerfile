# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# observer2: OpenBGPD 8.8 + rpki-client 9.5 on the same host (Alpine 3.22).
#
# The OpenBSD way of feeding a router: rpki-client validates the repository
# and writes a ready-made bgpd.conf fragment (/var/db/rpki-client/openbgpd,
# with a roa-set and an aspa-set), the router "include"s it, and a periodic
# job runs rpki-client again and reloads bgpd. No RTR session involved.
#
# RTRTR is here only for the guide's extra exercise E, which serves the same
# rpki-client output over RTR. It is copied from NLnet Labs' multi-arch image.
# StayRTR, the usual companion of rpki-client, was the first choice, but its
# releases (0.6.4) only speak RTR versions 0 and 1, which carry no ASPA.
FROM nlnetlabs/rtrtr:v0.3.3 AS rtrtr

FROM alpine:3.22

# vim and nano: students edit configurations from the panel's terminals.
# libgcc: the amd64 build of rtrtr links libgcc_s dynamically (the arm64 one
# is static), and without it rtrtr doesn't even start.
RUN apk add --no-cache openbgpd rpki-client ca-certificates tini bash iproute2 \
        tcpdump vim nano libgcc

# bgpd drops privileges to _bgpd and chroots into /var/empty. The Alpine
# package ships neither (see images/openbgpd/Dockerfile).
RUN addgroup -S _bgpd \
    && adduser -S -D -H -h /var/empty -s /sbin/nologin -G _bgpd -g _bgpd _bgpd \
    && mkdir -p /var/empty

COPY --from=rtrtr /usr/local/bin/rtrtr /usr/local/bin/rtrtr
COPY entrypoint.sh rpki-refresh rpki-rtr /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/rpki-refresh /usr/local/bin/rpki-rtr

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["bgpd", "-d", "-v"]
