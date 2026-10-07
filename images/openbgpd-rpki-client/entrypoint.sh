#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# observer2: validate with rpki-client, install the current stage's
# configuration and start OpenBGPD, with rpki-client re-run periodically.
#
# Stages (one file each, openbgpd/observer2-<stage>.conf): none, rov-mark,
# rov-drop, aspa-mark, aspa-drop - the same as observer3's (see
# images/openbgpd/entrypoint.sh, also for /etc/lab-stage). Every stage but
# "none" includes /var/db/rpki-client/openbgpd.
set -e

STAGE="${STAGE:-none}"
[ -f /etc/lab-stage ] && STAGE="$(cat /etc/lab-stage)"
cp "/etc/openbgpd-lab/observer2-${STAGE}.conf" /etc/bgpd.conf

# rpki-client fetches the repository over HTTPS, and the simulated RIR's
# certificate is signed by the lab's internal CA (pki-init): trust it.
if [ -f /pki/ca.pem ]; then
    cp /pki/ca.pem /usr/local/share/ca-certificates/lab-ca.crt
    update-ca-certificates >/dev/null 2>&1 || true
fi

# bgpd refuses a configuration whose include is missing, so start from empty
# sets; the first rpki-client run below replaces them.
OUT=/var/db/rpki-client
if [ ! -s "$OUT/openbgpd" ]; then
    printf 'roa-set {\n}\n\naspa-set {\n}\n' > "$OUT/openbgpd"
fi

# validate once before bgpd starts, so the first routes are already tested
# against the current objects
rpki-refresh --no-reload || true

# the lab's stand-in for the cron job of a real deployment
INTERVAL="${RPKI_CLIENT_INTERVAL:-120}"
( while sleep "$INTERVAL"; do rpki-refresh || true; done ) &

# bgpd needs its privilege-separation home to exist
mkdir -p /var/empty

exec "$@"
