#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# Shortcuts to operate the lab.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=../lab.conf
. ./lab.conf
export MODE="${MODE:-local}"
# the panel's host port; docker-compose.yml reads it from the environment
export PANEL_PORT="${PANEL_PORT:-8080}"
LANGUAGE="${LANGUAGE:-pt}"
. ./scripts/i18n.sh

# In local mode, the simulated RIR and the registry panel also come up.
if [ "$MODE" = "local" ]; then
    export COMPOSE_PROFILES=local
fi

# EXPOSE_PORTS=yes also publishes each service's own port on the host (see
# docker-compose.ports.yml). The path separator is pinned to ":" so this
# works the same under Git Bash on Windows, where Compose defaults to ";".
EXPOSE_PORTS="${EXPOSE_PORTS:-no}"
if [ "$EXPOSE_PORTS" = "yes" ]; then
    export COMPOSE_PATH_SEPARATOR=":"
    export COMPOSE_FILE="docker-compose.yml:docker-compose.ports.yml"
fi

PANEL="http://localhost:${PANEL_PORT}"

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

# Host ports the lab publishes, given EXPOSE_PORTS.
lab_ports() {
    if [ "$EXPOSE_PORTS" = "yes" ]; then
        echo "$PANEL_PORT 3000 3001 3323 3324 7681 8081 8323"
    else
        echo "$PANEL_PORT"
    fi
}

# Who holds a host port: prints "lab" if one of the lab's own containers
# publishes it, the container's name if another container does, "host" if
# some other program is listening on it, and nothing if it's free.
port_owner() {
    local port="$1" owner
    owner="$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null \
             | grep -E "[:.]${port}->" | awk '{print $1}' | head -1)"
    if [ -n "$owner" ]; then
        case "$owner" in lab-*) echo "lab" ;; *) echo "$owner" ;; esac
        return
    fi
    # bash's /dev/tcp works on Linux, macOS and Git Bash alike
    if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
        echo "host"
    fi
}

# Refuses to start when a port the lab needs is taken by something else,
# instead of letting "docker compose up" fail halfway through with "port is
# already allocated" and leave the lab half up.
check_ports() {
    local port owner bad=0
    for port in $(lab_ports); do
        owner="$(port_owner "$port")"
        case "$owner" in
          ""|lab) ;;
          host) echo "$(msg port_busy_host) $port" >&2; bad=1 ;;
          *)    echo "$(msg port_busy_container) $port: $owner" >&2; bad=1 ;;
        esac
    done
    if [ "$bad" = 1 ]; then
        echo "$(msg port_busy_hint)" >&2
        return 1
    fi
}

# The observers are deployed in stages (see the guide): none, rov-mark,
# rov-drop, aspa-mark, aspa-drop. Each stage is one complete config file per
# observer, so switching to a stage always lands in the same place no matter
# where you were - which is what makes every command safe to repeat.
#
# observer1 (BIRD) just points the running daemon at the stage's file.
# observer2 and observer3 (OpenBGPD) are restarted with the stage's file: the
# stage name is written to /etc/lab-stage (which survives a container
# restart) and the entrypoint installs that stage's config on the way up. A
# reload is not enough: OpenBGPD negotiates the RFC 9234 role when a session
# opens, and observer3's RTR session keeps the version it negotiated - so
# moving to a stage that adds ASPA (roles + RTR version 2) needs the sessions
# to start over, and starting over is a restart. observer2's entrypoint also
# runs rpki-client before bgpd starts, so it comes back with fresh data.
# openbgpd_stage <container> <stage>
openbgpd_stage() {
    docker exec "$1" sh -c "echo $2 > /etc/lab-stage" >/dev/null 2>&1 || true
    docker restart "$1" >/dev/null 2>&1 || true
    # wait for bgpd to answer before handing control back
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        docker exec "$1" bgpctl show summary >/dev/null 2>&1 && break
        sleep 2
    done
}

stage() {
    docker exec lab-observer1 birdc "configure \"/etc/bird-lab/observer1-$1.conf\"" >/dev/null 2>&1 || true
    # the two OpenBGPD observers restart side by side
    openbgpd_stage lab-observer2 "$1" &
    openbgpd_stage lab-observer3 "$1" &
    wait
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

# The origin and both providers never change during the story, but the extra
# exercises load other files into them by hand (origin-extra-b.conf, say).
# Reloading their own /etc/bird.conf on every step command means a skipped
# "undo" can't leak into the next step. Unchanged config: no session resets.
transit_base() {
    for r in origin provider-a provider-b; do
        docker exec "lab-$r" birdc 'configure "/etc/bird.conf"' >/dev/null 2>&1 || true
    done
}

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

# Restarts Routinator and FORT (and runs rpki-client on observer2) so a
# just-published ROA/ASPA reaches them
# immediately, instead of waiting for their next poll (up to a couple of
# minutes). Every step from step3-rov-mark on calls this right after
# touching RPKI objects, before switching the observers' stage.
#
# Restarting Routinator drops observer1's RTR session, and BIRD then sits in
# Transport-Error until its retry timer fires (up to 10 minutes), validating
# with the old objects meanwhile - so restart BIRD's RTR protocol too, the
# same way "refresh" does. observer2 runs rpki-client now (rpki-refresh
# reloads bgpd if the data changed). observer3 needs nothing here: every step
# command restarts it when it sets the stage.
refresh_validators() {
    docker compose restart routinator fort >/dev/null 2>&1 || true
    docker exec lab-observer2 rpki-refresh >/dev/null 2>&1 || true
    sleep 8
    docker exec lab-observer1 birdc restart routinator >/dev/null 2>&1 || true
}

# What the CA publishes right now, and when Krill last talked to its
# repository: taken before a step touches the RPKI objects, so
# wait_published() can tell whether anything changed.
objects_state() {
    docker exec lab-krill krillc roas list --ca "$1" 2>/dev/null
    docker exec lab-krill krillc aspas list --ca "$1" 2>/dev/null
}
last_contact() {
    docker exec lab-krill krillc repo status --ca "$1" 2>/dev/null | sed -n 's/^Last contacted: //p'
}

# Krill publishes a new or changed object a second or two after the API call
# returns. Restarting the validators before that makes them validate the old
# repository and then sit on it until their next refresh, two minutes later.
# So when the objects did change, wait for Krill's next exchange with its
# repository (and a moment for the repository to write it out) first.
# wait_published <ca> <objects_state before> <last_contact before>
wait_published() {
    local i
    [ "$(objects_state "$1")" = "$2" ] && return 0
    for i in $(seq 1 20); do
        [ "$(last_contact "$1")" != "$3" ] && break
        sleep 1
    done
    sleep 3
}

# Removes every ROA and the ASPA object from the CA, keeping the CA itself
# (and so the Preparation) intact: the way back to Step 1's "no ROAs, no
# ASPA" without a reset.
clean_objects() {
    local ca="$1" line customer
    docker exec lab-krill krillc roas list --ca "$ca" 2>/dev/null | sed '/^$/d' \
      | while IFS= read -r line; do
            docker exec lab-krill krillc roas update --ca "$ca" --remove "$line" >/dev/null 2>&1 || true
        done
    docker exec lab-krill krillc aspas list --ca "$ca" 2>/dev/null \
      | sed -n 's/^\(AS[0-9]*\) =>.*/\1/p' \
      | while IFS= read -r customer; do
            docker exec lab-krill krillc aspas remove --ca "$ca" --customer "$customer" >/dev/null 2>&1 || true
        done
}

# ./scripts/lab.sh doctor: checks the things that most often go wrong before
# or while the lab runs, and says what to do about each one.
doctor() {
    local ok="  [ok]  " warn="  [!!]  " bad="  [XX]  " port owner mem free running expected ca
    echo "$(msg doc_title)"
    if ! command -v docker >/dev/null 2>&1; then
        echo "${bad}$(msg doc_no_docker)"; return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "${bad}$(msg doc_no_daemon)"; return 1
    fi
    echo "${ok}Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
    if docker compose version >/dev/null 2>&1; then
        echo "${ok}$(docker compose version 2>/dev/null | head -1)"
    else
        echo "${bad}$(msg doc_no_compose)"; return 1
    fi
    mem="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)"
    if [ "${mem:-0}" -lt 2000000000 ] 2>/dev/null; then
        echo "${warn}$(msg doc_low_mem) ($((mem / 1048576)) MiB)"
    else
        echo "${ok}$(msg doc_mem) $((mem / 1048576)) MiB"
    fi
    free="$(df -Pk . 2>/dev/null | awk 'NR==2 {print $4}')"
    if [ -n "$free" ] && [ "$free" -lt 4000000 ]; then
        echo "${warn}$(msg doc_low_disk) ($((free / 1024)) MiB)"
    fi
    case "$MODE" in
      local) echo "${ok}MODE=local" ;;
      beta)  echo "${warn}MODE=beta - $(msg beta_warning)" ;;
      *)     echo "${bad}MODE=$MODE - $(msg doc_bad_mode)" ;;
    esac
    for port in $(lab_ports); do
        owner="$(port_owner "$port")"
        case "$owner" in
          lab) echo "${ok}$(msg doc_port_lab) $port" ;;
          "")  echo "${ok}$(msg doc_port_free) $port" ;;
          host) echo "${bad}$(msg port_busy_host) $port" ;;
          *)   echo "${bad}$(msg port_busy_container) $port: $owner" ;;
        esac
    done
    expected="$(docker compose config --services 2>/dev/null | grep -cvE '^(pki-init|tal-init)$')"
    running="$(docker compose ps --status running --services 2>/dev/null | grep -c .)"
    if [ "$running" = 0 ]; then
        echo "${warn}$(msg doc_not_running)"
        return 0
    fi
    if [ "$running" -lt "$expected" ]; then
        echo "${warn}$(msg doc_some_down) ($running/$expected)"
        docker compose ps -a --format '      {{.Name}}  {{.State}}' 2>/dev/null | grep -vE 'running|lab-pki-init|lab-tal-init'
    else
        echo "${ok}$(msg doc_all_up) ($running/$expected)"
    fi
    if curl -s -o /dev/null -m 5 http://localhost:${PANEL_PORT}/; then
        echo "${ok}$(msg doc_panel_ok) $PANEL"
    else
        echo "${bad}$(msg doc_panel_bad) $PANEL"
    fi
    if curl -s -o /dev/null -m 5 http://krill.localhost:${PANEL_PORT}/; then
        echo "${ok}http://krill.localhost:${PANEL_PORT}"
    else
        echo "${warn}$(msg doc_vhost_bad)"
    fi
    if docker exec lab-observer2 true >/dev/null 2>&1; then
        local rc counts
        rc="$(docker exec lab-observer2 cat /run/rpki-client.status 2>/dev/null | cut -d' ' -f1)"
        # VRPs and ASPAs in the file bgpd includes
        counts="$(docker exec lab-observer2 sh -c \
            'f=/var/db/rpki-client/openbgpd; echo "$(grep -c source-as $f) VRP, $(grep -c customer-as $f) ASPA"' \
            2>/dev/null)"
        if [ "$rc" = ok ]; then
            echo "${ok}$(msg doc_rpki_client_ok) ($counts)"
        else
            echo "${warn}$(msg doc_rpki_client_bad)"
        fi
    fi
    if ca="$(krill_ca 2>/dev/null)"; then
        echo "${ok}$(msg doc_prep_ok) ($ca)"
    else
        echo "${warn}$(msg doc_prep_missing)"
    fi
}

case "${1:-help}" in
  doctor)
      doctor ;;
  clean-objects)
      ca="$(krill_ca)" || exit 1
      before="$(objects_state "$ca")"; contact="$(last_contact "$ca")"
      clean_objects "$ca"
      wait_published "$ca" "$before" "$contact"
      refresh_validators
      echo "$(msg clean_objects_ok)" ;;
  up)
      check_ports || exit 1
      if [ "$MODE" = "beta" ]; then
          echo "MODE=beta - $(msg beta_warning)"
      fi
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
      transit_base; attacker_off; peer_off
      stage none
      # web/nginx.conf is bind-mounted, so Compose doesn't notice when it
      # changes (after a git pull, say); have nginx re-read it every time
      docker exec lab-web nginx -s reload >/dev/null 2>&1 || true
      echo
      echo "MODE=$MODE  LANGUAGE=$LANGUAGE"
      if [ "$MODE" = "local" ]; then
          printf '%-13s%s   %s\n' "$(msg lbl_registry)" "http://registry.localhost:${PANEL_PORT}" "$(msg note_registry)"
      fi
      printf '%-13s%s\n' "$(msg lbl_panel)" "$PANEL"
      printf '%-13s%s   %s\n' "$(msg lbl_krill)" "http://krill.localhost:${PANEL_PORT}" "$(msg note_krill)"
      printf '%-13s%s\n' "$(msg lbl_routinator)" "http://routinator.localhost:${PANEL_PORT}"
      printf '%-13s%s\n' "$(msg lbl_console)" "http://console.localhost:${PANEL_PORT}"
      ;;
  down)     docker compose down ;;
  reset)    docker compose down -v ;;         # also removes Krill's CA
  status)   docker compose ps ;;
  logs)     shift; docker compose logs -f "$@" ;;
  panel)    open_url "$PANEL" ;;
  registry)
      if [ "$MODE" = "local" ]; then
          open_url "http://registry.localhost:${PANEL_PORT}"
      else
          open_url "https://beta.registro.br/login/"
      fi ;;
  refresh)
      echo "$(msg refreshing)"
      # an object created a moment ago may not be in the repository yet
      # (see wait_published); give Krill a few seconds before restarting
      sleep 3
      docker compose restart routinator fort
      # observer2 validates on its own host: run rpki-client now
      docker exec lab-observer2 rpki-refresh >/dev/null 2>&1 || true
      # Neither router recovers quickly on its own when its RTR cache restarts.
      # BIRD gets stuck in Transport-Error, and OpenBGPD leaves the session
      # closed until its retry timer fires. BIRD can restart just the RTR
      # protocol; bgpctl has no equivalent (its commands are fib/flowspec/log/
      # neighbor/network/reload/show), and "reload" does not re-open RTR, so
      # observer3 gets a daemon restart instead.
      sleep 8
      docker exec lab-observer1 birdc restart routinator >/dev/null 2>&1 || true
      docker restart lab-observer3 >/dev/null 2>&1 || true
      echo "$(msg refreshed_ok)" ;;

  # ------------------------------------------------------- the guide's story -
  # AS666 and peer are silent by default, and the observers start with no
  # validation at all; these commands step through the story. Every one of
  # them is safe to repeat.
  step1-clean)
      transit_base; attacker_off; peer_off
      stage none
      echo "$(msg step1_clean_ok)" ;;
  step2-hijack-simple)
      transit_base; peer_off
      stage none
      attacker_simple
      echo "$(msg step2_hijack_simple_ok)" ;;
  step3-rov-mark)
      ca="$(krill_ca)" || exit 1
      transit_base
      before="$(objects_state "$ca")"; contact="$(last_contact "$ca")"
      ensure_roas "$ca"
      wait_published "$ca" "$before" "$contact"
      refresh_validators
      attacker_simple; peer_off
      stage rov-mark
      echo "$(msg step3_rov_mark_ok)" ;;
  step4-hijack-posrov)
      ca="$(krill_ca)" || exit 1
      transit_base
      before="$(objects_state "$ca")"; contact="$(last_contact "$ca")"
      ensure_roas "$ca"
      wait_published "$ca" "$before" "$contact"
      refresh_validators
      peer_off
      stage rov-mark
      attacker_posrov
      echo "$(msg step4_hijack_posrov_ok)" ;;
  step5-aspa-mark)
      ca="$(krill_ca)" || exit 1
      transit_base
      before="$(objects_state "$ca")"; contact="$(last_contact "$ca")"
      ensure_roas "$ca"
      set_aspa "$ca" "$PROVIDER_A_ASN"
      wait_published "$ca" "$before" "$contact"
      refresh_validators
      attacker_posrov; peer_off
      stage aspa-mark
      echo "$(msg step5_aspa_mark_ok)" ;;
  step6-add-provider-b)
      ca="$(krill_ca)" || exit 1
      transit_base
      before="$(objects_state "$ca")"; contact="$(last_contact "$ca")"
      ensure_roas "$ca"
      set_aspa "$ca" "$PROVIDER_A_ASN" "$PROVIDER_B_ASN"
      wait_published "$ca" "$before" "$contact"
      refresh_validators
      attacker_posrov; peer_off
      stage aspa-mark
      echo "$(msg step6_add_provider_b_ok)" ;;
  step7-leak-on)
      ca="$(krill_ca)" || exit 1
      transit_base
      before="$(objects_state "$ca")"; contact="$(last_contact "$ca")"
      ensure_roas "$ca"
      set_aspa "$ca" "$PROVIDER_A_ASN" "$PROVIDER_B_ASN"
      wait_published "$ca" "$before" "$contact"
      refresh_validators
      attacker_posrov
      stage aspa-mark
      peer_leak
      echo "$(msg step7_leak_on_ok)" ;;
  step8-drop)
      ca="$(krill_ca)" || exit 1
      transit_base
      before="$(objects_state "$ca")"; contact="$(last_contact "$ca")"
      ensure_roas "$ca"
      set_aspa "$ca" "$PROVIDER_A_ASN" "$PROVIDER_B_ASN"
      wait_published "$ca" "$before" "$contact"
      refresh_validators
      attacker_posrov; peer_leak
      stage aspa-drop
      echo "$(msg step8_drop_ok)" ;;
  step9-leak-off)
      ca="$(krill_ca)" || exit 1
      transit_base
      before="$(objects_state "$ca")"; contact="$(last_contact "$ca")"
      ensure_roas "$ca"
      set_aspa "$ca" "$PROVIDER_A_ASN" "$PROVIDER_B_ASN"
      wait_published "$ca" "$before" "$contact"
      refresh_validators
      attacker_posrov
      stage aspa-drop
      peer_off
      echo "$(msg step9_leak_off_ok)" ;;
  step9-hijack-off)
      ca="$(krill_ca)" || exit 1
      transit_base
      before="$(objects_state "$ca")"; contact="$(last_contact "$ca")"
      ensure_roas "$ca"
      set_aspa "$ca" "$PROVIDER_A_ASN" "$PROVIDER_B_ASN"
      wait_published "$ca" "$before" "$contact"
      refresh_validators
      peer_off
      stage aspa-drop
      attacker_off
      echo "$(msg step9_hijack_off_ok)" ;;

  *)
      lab_help
      ;;
esac
