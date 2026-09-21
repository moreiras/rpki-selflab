#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The lab-aspa authors
# ---------------------------------------------------------------------------
# Puts into /tals the TAL that BOTH validators (Routinator and FORT) will
# use. Which TAL depends on the MODE chosen in lab.conf:
#
#   MODE=local  -> the simulated RIR's trust anchor, inside the lab
#   MODE=beta   -> Registro.br's test anchor (needs Internet)
# ---------------------------------------------------------------------------
set -eu

. /lab/lab.conf
MODE="${MODE:-local}"
LANGUAGE="${LANGUAGE:-pt}"
. /usr/local/bin/i18n.sh

rm -f /tals/*.tal

case "$MODE" in
  beta)
      URL="https://rpki-test-ta.beta.registro.br/ta/ta.tal"
      msg tal_beta
      curl -fsS -o /tals/ta.tal "$URL"
      ;;
  local)
      URL="https://rir.lab:3000/ta/ta.tal"
      msg tal_local
      i=0
      until curl -fsS --cacert /pki/ca.pem -o /tals/ta.tal "$URL" 2>/dev/null; do
          i=$((i + 1))
          if [ "$i" -ge 60 ]; then
              msg tal_timeout >&2
              exit 1
          fi
          sleep 2
      done
      ;;
  *)
      msg tal_bad_mode >&2
      exit 1
      ;;
esac

msg tal_installed
head -3 /tals/ta.tal
