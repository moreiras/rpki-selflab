#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The lab-aspa authors
# Opens a terminal inside the container requested by the panel:
#   http://localhost:7681?arg=<node>&arg=<mode>
node="${1:-}"
mode="${2:-shell}"

[ -f /lab/lab.conf ] && . /lab/lab.conf
LANGUAGE="${LANGUAGE:-pt}"

banner() {
    echo
    echo "  ===================================================================="
    echo "   $1"
    echo "  ===================================================================="
    echo "   $2"
    echo
}

t_console() {
    case "$LANGUAGE" in
      es) echo "Consola del laboratorio" ;;
      en) echo "Lab console" ;;
      *)  echo "Console do laboratório" ;;
    esac
}

t_story() {
    case "$LANGUAGE" in
      es) echo "la historia:  " ;;
      en) echo "the story:    " ;;
      *)  echo "a história:   " ;;
    esac
}

t_lab_hint() {
    case "$LANGUAGE" in
      es) echo "./scripts/lab.sh refresh | status | logs <servicio>" ;;
      en) echo "./scripts/lab.sh refresh | status | logs <service>" ;;
      *)  echo "./scripts/lab.sh refresh | status | logs <serviço>" ;;
    esac
}

t_lab_reset_warning() {
    case "$LANGUAGE" in
      es) echo "   No ejecute 'lab.sh reset' (ni 'down') desde aquí: tira abajo todo el" ;;
      en) echo "   Don't run 'lab.sh reset' (or 'down') from in here: it tears down the" ;;
      *)  echo "   Não rode 'lab.sh reset' (nem 'down') por aqui: ele derruba todo o" ;;
    esac
    case "$LANGUAGE" in
      es) echo "   laboratorio, incluida esta misma terminal. Use su propia terminal." ;;
      en) echo "   whole lab, including this very terminal. Use your own terminal instead." ;;
      *)  echo "   laboratório, inclusive este terminal. Use o terminal do seu computador." ;;
    esac
}

case "$node" in
  lab)
      cd /lab || exec bash
      banner "$(t_console)  —  ./scripts/lab.sh" "$(t_lab_hint)"
      echo "   $(t_story)step1-clean | step2-hijack-simple | step3-rov-mark | step3-rov-drop"
      echo "                  step4-hijack-posrov | step5-aspa-mark | step5-aspa-drop"
      echo "                  step7-leak-on | step9-leak-off | step9-hijack-off"
      echo
      t_lab_reset_warning
      echo
      exec bash
      ;;
  origin|provider-a|provider-b|observer1|attacker|peer)
      if [ "$mode" = "birdc" ]; then
          exec docker exec -it "lab-$node" birdc
      fi
      banner "lab-$node  (BIRD)" "birdc  |  birdc show protocols  |  birdc show route all"
      exec docker exec -it "lab-$node" bash
      ;;
  observer2)
      if [ "$mode" = "bgpctl" ]; then
          exec docker exec -it lab-observer2 bgpctl show rib detail
      fi
      banner "lab-observer2  (OpenBGPD)" \
             "bgpctl show neighbor  |  bgpctl show rib detail  |  bgpctl show rtr"
      exec docker exec -it lab-observer2 bash
      ;;
  krill)
      banner "lab-krill  (Krill $(docker exec lab-krill krill --version 2>/dev/null | head -1))" \
             "krillc aspas list  |  krillc roas list  |  krillc show"
      exec docker exec -it lab-krill bash
      ;;
  rir)
      banner "lab-rir  (Krill for the simulated registry)" \
             "krillc list  |  krillc children connections --ca testbed  |  krillc pubserver publishers list"
      exec docker exec -it lab-rir bash
      ;;
  routinator)
      banner "lab-routinator" \
             "routinator --no-rir-tals --extra-tals-dir=/tals --enable-aspa vrps"
      exec docker exec -it lab-routinator sh
      ;;
  fort)
      banner "lab-fort  (FORT Validator)" \
             "fort --version  |  fort --tal=/tals --mode=print"
      exec docker exec -it lab-fort bash
      ;;
  *)
      banner "$(t_console)" \
             "docker ps  |  docker exec -it lab-observer1 birdc  |  ./scripts/..."
      t_lab_reset_warning
      echo
      exec bash
      ;;
esac
