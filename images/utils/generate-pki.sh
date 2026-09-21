#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# ---------------------------------------------------------------------------
# Why this exists:
#
# Every RPKI URI is HTTPS - RRDP, the TA certificate, RFC 6492 and RFC 8181.
# A browser accepts a self-signed certificate with one click, but Routinator
# and the student's Krill don't have that button: they validate TLS and give
# up.
#
# So the lab has its own certificate authority. It signs the RIR's
# certificate, and its own certificate is handed to whoever needs to trust it:
#   - Routinator      --rrdp-root-cert /pki/ca.pem
#   - FORT            installed into its system trust store at startup
#   - student's Krill KRILL_HTTPS_ROOT_CERTS=/pki/ca.pem
#   - the RIR panel (Python)
# ---------------------------------------------------------------------------
set -eu

[ -f /lab/lab.conf ] && . /lab/lab.conf
LANGUAGE="${LANGUAGE:-pt}"
. /usr/local/bin/i18n.sh

PKI=/pki
NAME="${RIR_HOSTNAME:-rir.lab}"

if [ -f "$PKI/ca.pem" ] && [ -f "$PKI/rir.crt" ]; then
    msg pki_exists
    openssl x509 -in "$PKI/rir.crt" -noout -subject -dates -ext subjectAltName
    exit 0
fi

mkdir -p "$PKI"
cd "$PKI"

msg pki_making_ca
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout ca.key -out ca.pem \
    -subj "/CN=RPKI Lab - internal CA/O=rpki-selflab" 2>/dev/null

msg pki_making_cert
openssl req -newkey rsa:2048 -nodes \
    -keyout rir.key -out rir.csr \
    -subj "/CN=${NAME}/O=rpki-selflab" 2>/dev/null

cat > rir.ext <<EOF
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:${NAME}, DNS:lab-rir, DNS:rir, DNS:localhost, IP:127.0.0.1
EOF

openssl x509 -req -in rir.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
    -out rir.crt -days 3650 -sha256 -extfile rir.ext 2>/dev/null

rm -f rir.csr rir.ext
chmod 644 ca.pem rir.crt rir.key

msg pki_done
openssl x509 -in rir.crt -noout -subject -dates -ext subjectAltName
