#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# Shortcuts to operate the lab.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=../lab.conf
. ./lab.conf
export MODE="${MODE:-local}"
LANGUAGE="${LANGUAGE:-pt}"
. ./scripts/i18n.sh

# In local mode, the simulated RIR and the registry panel also come up.
if [ "$MODE" = "local" ]; then
    export COMPOSE_PROFILES=local
fi

PANEL="http://localhost:8080"

# Cross-platform "open a URL in the browser": macOS has "open", most Linux
# desktops have "xdg-open", and Windows (Git Bash/MSYS) has "start". If none
# of them work (e.g. a headless server), just print the URL.
open_url() {
    if command -v open >/dev/null 2>&1; then
        open "$1" 2>/dev/null && return
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$1" >/dev/null 2>&1 && return
    elif command -v start >/dev/null 2>&1; then
        start "$1" 2>/dev/null && return
    fi
    echo "$1"
}

# The observers are deployed in stages (see the guide): none, rov-mark,
# rov-drop, aspa-mark, aspa-drop. Each stage is one complete config file per
# observer, so switching to a stage always lands in the same place no matter
# where you were - which is what makes every command safe to repeat.
#
# observer1 (BIRD) just points the running daemon at the stage's file.
# observer2 (OpenBGPD) is restarted with the stage's file: the stage name is
# written to /etc/lab-stage (which survives a container restart) and the
# entrypoint installs that stage's config on the way up. A reload is not
# enough: OpenBGPD negotiates the RFC 9234 role when a session opens, and an
# RTR session that's already up keeps the version it negotiated - so moving to
# a stage that adds ASPA (roles + RTR version 2) needs the sessions to start
# over, and starting over is a restart.
observer2_stage() {
    docker exec lab-observer2 sh -c "echo $1 > /etc/lab-stage" >/dev/null 2>&1 || true
    docker restart lab-observer2 >/dev/null 2>&1 || true
    # wait for bgpd to answer before handing control back
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        docker exec lab-observer2 bgpctl show summary >/dev/null 2>&1 && break
        sleep 2
    done
}

stage() {
    docker exec lab-observer2 sh -c \
        "echo $1 > /etc/lab-stage && cp /etc/openbgpd-lab/observer2-$1.conf /etc/bgpd.conf && bgpctl reload" \
        >/dev/null 2>&1 || true
    docker exec lab-observer2 sh -c \
        'bgpctl show summary | awk "NR>1 {print \$1}" \
           | while read -r n; do bgpctl neighbor "$n" clear >/dev/null 2>&1; done' \
        >/dev/null 2>&1 || true
}

stage() {
    docker exec lab-observer1 birdc "configure \"/etc/bird-lab/observer1-$1.conf\"" >/dev/null 2>&1 || true
    observer2_stage "$1"
}

# ---------------------------------------------------------------------------
# Every step command below sets its ENTIRE target state - attacker config,
# peer config, RPKI objects (from step3-rov-mark on), and the observers'
# stage - not just the delta from whatever step ran before it. That's what
# makes "run step9-leak-off, then step3-rov-mark" land exactly where the
# guide says step3 should be, with nothing left over from step9. Preparation
# (creating the CA, getting its certificate from the parent) is the one part
# of the story these commands can't do for you - see krill_ca() below.
# ---------------------------------------------------------------------------

attacker_off()    { docker exec lab-attacker birdc 'configure "/etc/bird.conf"'        >/dev/null 2>&1 || true; }
attacker_simple() { docker exec lab-attacker birdc 'configure "/etc/bird-simple.conf"' >/dev/null 2>&1 || true; }
attacker_posrov() { docker exec lab-attacker birdc 'configure "/etc/bird-posrov.conf"' >/dev/null 2>&1 || true; }
peer_off()        { docker exec lab-peer     birdc 'configure "/etc/bird.conf"'        >/dev/null 2>&1 || true; }
peer_leak()       { docker exec lab-peer     birdc 'configure "/etc/bird-leak.conf"'   >/dev/null 2>&1 || true; }

# Finds the lab's one Krill CA and checks it actually finished Preparation:
# an active parent (the RFC 6492 delegation, local RIR or beta.registro.br),
# the AS number and prefixes lab.conf expects, and a working repository
# (RFC 8181) - without that last one, objects get created but never reach
# the validators, which is indistinguishable from "nothing published" on the
# panel. Prints the CA's handle on success; on failure, prints a diagnosis
# (in the configured language) and returns non-zero, so every step from
# step3-rov-mark on can bail out cleanly before touching anything.
krill_ca() {
    local handles n handle info repo
    handles="$(docker exec lab-krill krillc list 2>/dev/null | sed '/^$/d')"
    n="$(printf '%s\n' "$handles" | grep -c . || true)"
    if [ "$n" = "0" ]; then
        echo "$(msg krill_no_ca)" >&2
        return 1
    fi
    if [ "$n" -gt 1 ]; then
        echo "$(msg krill_multiple_ca) ($(printf '%s' "$handles" | tr '\n' ' '))" >&2
        return 1
    fi
    handle="$handles"
    info="$(docker exec lab-krill krillc show --ca "$handle" 2>&1 || true)"
    repo="$(docker exec lab-krill krillc repo status --ca "$handle" 2>&1 || true)"
    if printf '%s\n' "$info" | grep -q "^Handle: .* Kind: RFC 6492 Parent" \
        && printf '%s\n' "$info" | grep -q "ASNs: AS${ORIGIN_ASN}\$" \
        && printf '%s\n' "$info" | grep -qF "IPv4: ${ORIGIN_V4}" \
        && printf '%s\n' "$info" | grep -qF "IPv6: ${ORIGIN_V6}" \
        && printf '%s\n' "$repo" | grep -q "^Status: success"; then
        echo "$handle"
        return 0
    fi
    echo "$(msg krill_not_ready) ($handle)" >&2
    return 1
}

# Creates both ROAs if they're not there yet ("krillc roas update --add" is
# safe to repeat - Krill treats a duplicate as a no-op, not an error).
ensure_roas() {
    docker exec lab-krill krillc roas update --ca "$1" \
        --add "${ORIGIN_V4}-${ORIGIN_V4_MAXLEN} => ${ORIGIN_ASN}" >/dev/null 2>&1 || true
    docker exec lab-krill krillc roas update --ca "$1" \
        --add "${ORIGIN_V6}-${ORIGIN_V6_MAXLEN} => ${ORIGIN_ASN}" >/dev/null 2>&1 || true
}

# Sets the ASPA object to EXACTLY the given providers ("krillc aspas add"
# replaces the whole object, so this works whether it's growing the list
# (step5 -> step6) or shrinking it back (jumping to step5 after step6 ran).
# set_aspa <ca> <provider-asn> [<provider-asn> ...]
set_aspa() {
    local ca="$1"; shift
    local list; list="$(IFS=,; echo "$*")"
    list="$(echo "$list" | sed 's/,/, /g')"
    docker exec lab-krill krillc aspas add --ca "$ca" \
        --aspa "${ORIGIN_ASN} => ${list}" >/dev/null 2>&1 || true
}

# Restarts Routinator and FORT so a just-published ROA/ASPA reaches them
# immediately, instead of waiting for their next poll (up to a couple of
# minutes). Every step from step3-rov-mark on calls this right after
# touching RPKI objects, before switching the observers' stage.
refresh_validators() {
    docker compose restart routinator fort >/dev/null 2>&1 || true
    sleep 8
}

case "${1:-help}" in
  up)
      ./scripts/generate-config.sh
      # LAB_NO_BUILD=1 (used inside the prebuilt virtual machine, which has the
      # images already and may have no Internet) skips rebuilding them.
      if [ -n "${LAB_NO_BUILD:-}" ]; then
          docker compose up -d
      else
          docker compose up -d --build
      fi
      # A container that was already running (or whose image didn't change)
      # is left alone by "compose up" - so without this, AS666, the peer,
      # and the observers' stage could all still be wherever a previous
      # session left them. "up" always lands on the same clean baseline as
      # step1-clean, the same way the panel and the guide describe it.
      attacker_off; peer_off
      stage none
      echo
      echo "MODE=$MODE  LANGUAGE=$LANGUAGE"
      if [ "$MODE" = "local" ]; then
          printf '%-13s%s   %s\n' "$(msg lbl_registry)" "http://registry.localhost:8080" "$(msg note_registry)"
      fi
      printf '%-13s%s\n' "$(msg lbl_panel)" "$PANEL"
      printf '%-13s%s   %s\n' "$(msg lbl_krill)" "http://krill.localhost:8080" "$(msg note_krill)"
      printf '%-13s%s\n' "$(msg lbl_routinator)" "http://routinator.localhost:8080"
      printf '%-13s%s\n' "$(msg lbl_console)" "http://console.localhost:8080"
      ;;
  down)     docker compose down ;;
  reset)    docker compose down -v ;;         # also removes Krill's CA
  status)   docker compose ps ;;
  logs)     shift; docker compose logs -f "$@" ;;
  panel)    open_url "$PANEL" ;;
  registry)
      if [ "$MODE" = "local" ]; then
          open_url "http://registry.localhost:8080"
      else
          open_url "https://beta.registro.br/login/"
      fi ;;
  refresh)
      echo "$(msg refreshing)"
      docker compose restart routinator fort
      # Neither router recovers quickly on its own when its RTR cache restarts.
      # BIRD gets stuck in Transport-Error, and OpenBGPD leaves the session
      # closed until its retry timer fires. BIRD can restart just the RTR
      # protocol; bgpctl has no equivalent (its commands are fib/flowspec/log/
      # neighbor/network/reload/show), and "reload" does not re-open RTR, so
      # observer2 gets a daemon restart instead.
      sleep 8
      docker exec lab-observer1 birdc restart routinator >/dev/null 2>&1 || true
      docker restart lab-observer2 >/dev/null 2>&1 || true
      echo "$(msg refreshed_ok)" ;;

  # ------------------------------------------------------- the guide's story -
  # AS666 and peer are silent by default, and the observers start with no
  # validation at all; these commands step through the story. Every one of
  # them is safe to repeat.
  step1-clean)
      attacker_off; peer_off
      stage none
      echo "$(msg step1_clean_ok)" ;;
  step2-hijack-simple)
      peer_off
      stage none
      attacker_simple
      echo "$(msg step2_hijack_simple_ok)" ;;
  step3-rov-mark)
      ca="$(krill_ca)" || exit 1
      ensure_roas "$ca"
      refresh_validators
      attacker_simple; peer_off
      stage rov-mark
      echo "$(msg step3_rov_mark_ok)" ;;
  step4-hijack-posrov)
      ca="$(krill_ca)" || exit 1
      ensure_roas "$ca"
      refresh_validators
      peer_off
      stage rov-mark
      attacker_posrov
      echo "$(msg step4_hijack_posrov_ok)" ;;
  step5-aspa-mark)
      ca="$(krill_ca)" || exit 1
      ensure_roas "$ca"
      set_aspa "$ca" "$PROVIDER_A_ASN"
      refresh_validators
      attacker_posrov; peer_off
      stage aspa-mark
      echo "$(msg step5_aspa_mark_ok)" ;;
  step6-add-provider-b)
      ca="$(krill_ca)" || exit 1
      ensure_roas "$ca"
      set_aspa "$ca" "$PROVIDER_A_ASN" "$PROVIDER_B_ASN"
      refresh_validators
      attacker_posrov; peer_off
      stage aspa-mark
      echo "$(msg step6_add_provider_b_ok)" ;;
  step7-leak-on)
      ca="$(krill_ca)" || exit 1
      ensure_roas "$ca"
      set_aspa "$ca" "$PROVIDER_A_ASN" "$PROVIDER_B_ASN"
      refresh_validators
      attacker_posrov
      stage aspa-mark
      peer_leak
      echo "$(msg step7_leak_on_ok)" ;;
  step8-drop)
      ca="$(krill_ca)" || exit 1
      ensure_roas "$ca"
      set_aspa "$ca" "$PROVIDER_A_ASN" "$PROVIDER_B_ASN"
      refresh_validators
      attacker_posrov; peer_leak
      stage aspa-drop
      echo "$(msg step8_drop_ok)" ;;
  step9-leak-off)
      ca="$(krill_ca)" || exit 1
      ensure_roas "$ca"
      set_aspa "$ca" "$PROVIDER_A_ASN" "$PROVIDER_B_ASN"
      refresh_validators
      attacker_posrov
      stage aspa-drop
      peer_off
      echo "$(msg step9_leak_off_ok)" ;;
  step9-hijack-off)
      ca="$(krill_ca)" || exit 1
      ensure_roas "$ca"
      set_aspa "$ca" "$PROVIDER_A_ASN" "$PROVIDER_B_ASN"
      refresh_validators
      peer_off
      stage aspa-drop
      attacker_off
      echo "$(msg step9_hijack_off_ok)" ;;

  *)
      lab_help
      ;;
esac
