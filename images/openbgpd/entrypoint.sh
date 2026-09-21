#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# Installs the current deployment stage's configuration and starts OpenBGPD.
#
# Stages (one file each, openbgpd/observer2-<stage>.conf):
#   none        plain BGP, no validation deployed
#   rov-mark    ROV deployed, marking only
#   rov-drop    ROV dropping the invalid ones
#   aspa-mark   ROV dropping + ASPA verification marking
#   aspa-drop   ROV dropping + ASPA verification dropping
#
# The lab switches stages at runtime (see scripts/lab.sh): it writes the stage
# name to /etc/lab-stage, copies the stage's file over /etc/bgpd.conf and
# reloads. Writing /etc/lab-stage is what lets a container restart (for
# instance "lab.sh refresh") come back in the same stage instead of falling
# back to the STAGE default below.
set -e

STAGE="${STAGE:-none}"
[ -f /etc/lab-stage ] && STAGE="$(cat /etc/lab-stage)"
cp "/etc/openbgpd-lab/observer2-${STAGE}.conf" /etc/bgpd.conf

# bgpd needs its privilege-separation home to exist
mkdir -p /var/empty

exec "$@"
