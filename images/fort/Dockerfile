# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# FORT Validator - the second RPKI validator in the lab (feeds observer2).
#
# Built from source rather than pulled from nicmx/fort-validator because the
# published image is amd64-only; building here keeps the lab native on arm64
# hosts too. FORT_VERSION is the upstream git tag: ASPA and RTR version 2
# only exist from 1.7.0.experimental onwards.
#
# Debian rather than Alpine: FORT includes <sys/queue.h>, a BSD/glibc header
# that musl does not ship.
FROM debian:bookworm-slim AS build

ARG FORT_VERSION=1.7.0.experimental

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool pkg-config git ca-certificates \
        libcurl4-openssl-dev libxml2-dev libjansson-dev libssl-dev \
        libmicrohttpd-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch "${FORT_VERSION}" \
        https://github.com/NICMx/FORT-validator.git . \
    && ./autogen.sh \
    && ./configure --prefix=/usr/local \
    && make -j"$(nproc)" \
    && make install

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4 libxml2 libjansson4 libssl3 libmicrohttpd12 \
        ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/bin/fort /usr/local/bin/fort
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["fort", "--help"]
