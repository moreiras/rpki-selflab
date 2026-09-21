#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# ---------------------------------------------------------------------------
# Shared message catalog for this image's scripts (generate-pki.sh, tal-init.sh).
# POSIX sh (Alpine's ash has no associative arrays), so a case statement.
#
# Usage:  . /usr/local/bin/i18n.sh ; msg some_key
# ---------------------------------------------------------------------------

msg() {
    key="$1"
    case "${LANGUAGE:-pt}:${key}" in

      pt:pki_exists)     echo "PKI já existe em $PKI - nada a fazer." ;;
      es:pki_exists)     echo "La PKI ya existe en $PKI - nada que hacer." ;;
      en:pki_exists)     echo "PKI already exists at $PKI - nothing to do." ;;

      pt:pki_making_ca)  echo "==> Gerando a CA interna do laboratório" ;;
      es:pki_making_ca)  echo "==> Generando la CA interna del laboratorio" ;;
      en:pki_making_ca)  echo "==> Generating the lab's internal CA" ;;

      pt:pki_making_cert) echo "==> Gerando o certificado de ${NAME}" ;;
      es:pki_making_cert) echo "==> Generando el certificado de ${NAME}" ;;
      en:pki_making_cert) echo "==> Generating the certificate for ${NAME}" ;;

      pt:pki_done)       echo "==> Pronto" ;;
      es:pki_done)       echo "==> Listo" ;;
      en:pki_done)       echo "==> Done" ;;

      pt:tal_beta)       echo "MODE=beta - buscando o TAL em ${URL}" ;;
      es:tal_beta)       echo "MODE=beta - buscando el TAL en ${URL}" ;;
      en:tal_beta)       echo "MODE=beta - fetching the TAL from ${URL}" ;;

      pt:tal_local)      echo "MODE=local - aguardando o RIR do laboratório em ${URL}" ;;
      es:tal_local)      echo "MODE=local - esperando al RIR del laboratorio en ${URL}" ;;
      en:tal_local)      echo "MODE=local - waiting for the lab's RIR at ${URL}" ;;

      pt:tal_timeout)    echo "O RIR não respondeu em 2 minutos. Veja: docker logs lab-rir" ;;
      es:tal_timeout)    echo "El RIR no respondió en 2 minutos. Vea: docker logs lab-rir" ;;
      en:tal_timeout)    echo "The RIR didn't respond within 2 minutes. See: docker logs lab-rir" ;;

      pt:tal_bad_mode)   echo "MODE inválido no lab.conf: '${MODE}' (use local ou beta)" ;;
      es:tal_bad_mode)   echo "MODE inválido en lab.conf: '${MODE}' (use local o beta)" ;;
      en:tal_bad_mode)   echo "Invalid MODE in lab.conf: '${MODE}' (use local or beta)" ;;

      pt:tal_installed)  echo "TAL instalado:" ;;
      es:tal_installed)  echo "TAL instalado:" ;;
      en:tal_installed)  echo "TAL installed:" ;;

      *) echo "$key" ;;
    esac
}
