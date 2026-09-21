#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The lab-aspa authors
# Trust the lab's internal CA before starting FORT.
#
# FORT fetches the simulated RIR's RRDP over HTTPS, and the RIR's certificate
# is signed by the CA that pki-init generates at runtime. FORT's own
# --http.ca-path expects an OpenSSL hashed directory, so it is simpler to
# install the CA into the system trust store that libcurl already uses.
set -e

if [ -f /pki/ca.pem ]; then
    cp /pki/ca.pem /usr/local/share/ca-certificates/lab-ca.crt
    update-ca-certificates >/dev/null 2>&1 || true
fi

exec "$@"
