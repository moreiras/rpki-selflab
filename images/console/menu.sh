#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
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

t_work_hint() {
    case "$LANGUAGE" in
      es) echo "   sus propios archivos: work/  (nano, vim; los routers los leen en /etc/lab-work)" ;;
      en) echo "   your own files: work/  (nano, vim; the routers read them at /etc/lab-work)" ;;
      *)  echo "   seus próprios arquivos: work/  (nano, vim; os roteadores os leem em /etc/lab-work)" ;;
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
      # The panel's ▶ buttons open this terminal with one of the lab's own
      # commands as the second argument: run it, then stay in the shell.
      # Anything else (reset, down, arbitrary text) is refused on purpose.
      case "$mode" in
        refresh|status|doctor|clean-objects|step[1-9]-[a-z-]*)
            echo "\$ ./scripts/lab.sh $mode"
            ./scripts/lab.sh "$mode"
            echo
            exec bash ;;
      esac
      banner "$(t_console)  —  ./scripts/lab.sh" "$(t_lab_hint)"
      echo "   $(t_story)step1-clean | step2-hijack-simple | step3-rov-mark"
      echo "                  step4-hijack-posrov | step5-aspa-mark | step6-add-provider-b"
      echo "                  step7-leak-on | step8-drop | step9-leak-off | step9-hijack-off"
      echo
      t_work_hint
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
