#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# ---------------------------------------------------------------------------
# Shared message catalog for the scripts in this directory
# (lab.sh, validate.sh, generate-config.sh).
#
# Written to work under bash 3.2 (macOS's default system bash), so no
# associative arrays - just a case statement keyed on "LANGUAGE:key".
#
# Usage:
#   . ./scripts/i18n.sh     # after lab.conf has been sourced, so LANGUAGE is set
#   msg some_key
# ---------------------------------------------------------------------------

msg() {
    local key="$1"
    case "${LANGUAGE:-pt}:${key}" in

      # -- scripts/lab.sh --------------------------------------------------
      pt:lbl_registry)      echo "Registro:" ;;
      es:lbl_registry)      echo "Registro:" ;;
      en:lbl_registry)      echo "Registry:" ;;

      pt:note_registry)     echo "(RIR do laboratório)" ;;
      es:note_registry)     echo "(RIR del laboratorio)" ;;
      en:note_registry)     echo "(the lab's RIR)" ;;

      pt:lbl_panel)         echo "Painel:" ;;
      es:lbl_panel)         echo "Panel:" ;;
      en:lbl_panel)         echo "Panel:" ;;

      pt:lbl_krill)         echo "Krill:" ;;
      es:lbl_krill)         echo "Krill:" ;;
      en:lbl_krill)         echo "Krill:" ;;

      pt:note_krill)        echo "(token: passlab)" ;;
      es:note_krill)        echo "(token: passlab)" ;;
      en:note_krill)        echo "(token: passlab)" ;;

      pt:lbl_routinator)    echo "Routinator:" ;;
      es:lbl_routinator)    echo "Routinator:" ;;
      en:lbl_routinator)    echo "Routinator:" ;;

      pt:lbl_console)       echo "Console:" ;;
      es:lbl_console)       echo "Consola:" ;;
      en:lbl_console)       echo "Console:" ;;

      pt:refreshing)        echo "forçando nova validação no Routinator e no FORT..." ;;
      es:refreshing)        echo "forzando una nueva validación en el Routinator y en FORT..." ;;
      en:refreshing)        echo "forcing Routinator and FORT to revalidate..." ;;

      pt:refreshed_ok)      echo "pronto - olhe o painel (pode levar alguns segundos)." ;;
      es:refreshed_ok)      echo "listo - mire el panel (puede tardar unos segundos)." ;;
      en:refreshed_ok)      echo "done - check the panel (it may take a few seconds)." ;;

      # The guide's story
      pt:step1_clean_ok)          echo "passo 1: AS666 e peer calados, e os dois observadores voltaram a ser roteadores BGP comuns (sem validação)." ;;
      es:step1_clean_ok)          echo "paso 1: AS666 y peer callados, y los dos observers vuelven a ser routers BGP comunes (sin validación)." ;;
      en:step1_clean_ok)          echo "step 1: AS666 and peer are silent, and both observers are plain BGP routers again (no validation)." ;;

      pt:step2_hijack_simple_ok)  echo "passo 2: AS666 anuncia os prefixos da origem como se fossem seus (AS_PATH: 666)." ;;
      es:step2_hijack_simple_ok)  echo "paso 2: AS666 anuncia los prefijos del origen como propios (AS_PATH: 666)." ;;
      en:step2_hijack_simple_ok)  echo "step 2: AS666 is announcing the origin's prefixes as its own (AS_PATH: 666)." ;;

      pt:step3_rov_mark_ok)       echo "passo 3: os dois observadores agora rodam ROV e só MARCAM as rotas inválidas (community + local-pref)." ;;
      es:step3_rov_mark_ok)       echo "paso 3: los dos observers ahora ejecutan ROV y solo MARCAN las rutas inválidas (community + local-pref)." ;;
      en:step3_rov_mark_ok)       echo "step 3: both observers now run ROV and only MARK invalid routes (community + local-pref)." ;;

      pt:step3_rov_drop_ok)       echo "passo 3: os dois observadores agora DESCARTAM as rotas inválidas pelo ROV." ;;
      es:step3_rov_drop_ok)       echo "paso 3: los dos observers ahora DESCARTAN las rutas inválidas según ROV." ;;
      en:step3_rov_drop_ok)       echo "step 3: both observers now DROP ROV-invalid routes." ;;

      pt:step4_hijack_posrov_ok)  echo "passo 4: AS666 anuncia com um caminho forjado (AS_PATH: 666 <origem>)." ;;
      es:step4_hijack_posrov_ok)  echo "paso 4: AS666 anuncia con un camino falsificado (AS_PATH: 666 <origen>)." ;;
      en:step4_hijack_posrov_ok)  echo "step 4: AS666 is announcing with a forged path (AS_PATH: 666 <origin>)." ;;

      pt:step5_aspa_mark_ok)      echo "passo 5: os dois observadores descartam o que o ROV marca como inválido e agora também verificam ASPA, só MARCANDO o que ela acusa." ;;
      es:step5_aspa_mark_ok)      echo "paso 5: los dos observers descartan lo inválido según ROV y ahora también verifican ASPA, solo MARCANDO lo que esta señala." ;;
      en:step5_aspa_mark_ok)      echo "step 5: both observers drop ROV-invalid routes and now also verify ASPA, only MARKING what it flags." ;;

      pt:step5_aspa_drop_ok)      echo "passo 5: os dois observadores agora descartam rotas inválidas pelo ROV E pelo ASPA." ;;
      es:step5_aspa_drop_ok)      echo "paso 5: los dos observers ahora descartan rutas inválidas según ROV Y según ASPA." ;;
      en:step5_aspa_drop_ok)      echo "step 5: both observers now drop ROV-invalid AND ASPA-invalid routes." ;;

      pt:step7_leak_on_ok)        echo "passo 7: o peer agora vaza os prefixos da origem para o Provedor A." ;;
      es:step7_leak_on_ok)        echo "paso 7: el peer ahora filtra los prefijos del origen hacia el Proveedor A." ;;
      en:step7_leak_on_ok)        echo "step 7: peer is now leaking the origin's prefixes to Provider A." ;;

      pt:step9_leak_off_ok)       echo "passo 9: o peer parou de vazar." ;;
      es:step9_leak_off_ok)       echo "paso 9: el peer dejó de filtrar." ;;
      en:step9_leak_off_ok)       echo "step 9: peer has stopped leaking." ;;

      pt:step9_hijack_off_ok)     echo "passo 9: AS666 está calado." ;;
      es:step9_hijack_off_ok)     echo "paso 9: AS666 está callado." ;;
      en:step9_hijack_off_ok)     echo "step 9: AS666 is silent." ;;

      # -- scripts/validate.sh ----------------------------------------------
      pt:t_objects)         echo "Objetos validados pelo Routinator" ;;
      es:t_objects)         echo "Objetos validados por el Routinator" ;;
      en:t_objects)         echo "Objects validated by Routinator" ;;

      pt:t_tables)          echo "Tabelas que chegaram ao observer1 pelo RTR" ;;
      es:t_tables)          echo "Tablas que llegaron al observer1 por RTR" ;;
      en:t_tables)          echo "Tables observer1 received over RTR" ;;

      pt:no_rtr)            echo "(nenhuma sessão RTR: os observadores ainda não validam nada)" ;;
      es:no_rtr)            echo "(ninguna sesión RTR: los observers todavía no validan nada)" ;;
      en:no_rtr)            echo "(no RTR session: the observers don't validate anything yet)" ;;

      pt:t_sessions)        echo "Sessões do observer1 (BIRD)" ;;
      es:t_sessions)        echo "Sesiones del observer1 (BIRD)" ;;
      en:t_sessions)        echo "observer1's sessions (BIRD)" ;;

      pt:t_verdicts4)       echo "observer1 — vereditos (IPv4)" ;;
      es:t_verdicts4)       echo "observer1 — veredictos (IPv4)" ;;
      en:t_verdicts4)       echo "observer1 — verdicts (IPv4)" ;;

      pt:t_verdicts6)       echo "observer1 — vereditos (IPv6)" ;;
      es:t_verdicts6)       echo "observer1 — veredictos (IPv6)" ;;
      en:t_verdicts6)       echo "observer1 — verdicts (IPv6)" ;;

      pt:t_obs2_sessions)   echo "Sessões do observer2 (OpenBGPD)" ;;
      es:t_obs2_sessions)   echo "Sesiones del observer2 (OpenBGPD)" ;;
      en:t_obs2_sessions)   echo "observer2's sessions (OpenBGPD)" ;;

      pt:t_obs2_verdicts)   echo "observer2 — vereditos (ovs / avs, nativos do OpenBGPD)" ;;
      es:t_obs2_verdicts)   echo "observer2 — veredictos (ovs / avs, nativos de OpenBGPD)" ;;
      en:t_obs2_verdicts)   echo "observer2 — verdicts (ovs / avs, native to OpenBGPD)" ;;

      pt:routinator_off)    echo "  (Routinator indisponível)" ;;
      es:routinator_off)    echo "  (Routinator no disponible)" ;;
      en:routinator_off)    echo "  (Routinator unavailable)" ;;

      # -- scripts/generate-config.sh ----------------------------------------
      pt:vars_generated)   echo "bird/vars.conf e openbgpd/vars.conf gerados:" ;;
      es:vars_generated)   echo "bird/vars.conf y openbgpd/vars.conf generados:" ;;
      en:vars_generated)   echo "bird/vars.conf and openbgpd/vars.conf generated:" ;;

      *)
        # not translated yet: use the English text, and only if there's none
        # either, print the key itself
        if [ "${LANGUAGE:-pt}" != "en" ]; then
            LANGUAGE=en msg "$key"
        else
            echo "$key"
        fi ;;
    esac
}

# lab_help() prints the whole ./scripts/lab.sh help block. It's long enough
# that a case-per-line would be unreadable, so each language gets its own
# heredoc.
lab_help() {
    case "${LANGUAGE:-pt}" in
      es)
        cat <<'HELP'
uso: ./scripts/lab.sh <comando>

  up          levanta el laboratorio (construye las imágenes si hace falta)
  down        lo baja, conservando los datos del Krill
  reset       lo baja y BORRA los volúmenes (CA del Krill, cachés de los validadores)
  status      estado de los contenedores
  logs [svc]  sigue los logs
  panel       abre el panel del laboratorio en el navegador
  registry    abre el panel del registro (RIR local, o beta.registro.br)

  refresh     fuerza al Routinator y a FORT a revalidar ahora

  la historia de la guía - AS666 (secuestrador) y peer (con fuga) - pasos 1 a 9:
  step1-clean          AS666 y peer callados; observers sin validación alguna
  step2-hijack-simple  AS666 anuncia los prefijos del origen como propios
  step3-rov-mark       ROV en los dos observers, solo MARCANDO los inválidos
  step3-rov-drop       ROV DESCARTANDO los inválidos
  step4-hijack-posrov  AS666 falsifica el camino para que termine en el origen real
  step5-aspa-mark      ROV descartando + ASPA solo MARCANDO
  step5-aspa-drop      ROV y ASPA descartando
  step7-leak-on        peer empieza a filtrar las rutas del origen al Proveedor A
  step9-leak-off       peer deja de filtrar
  step9-hijack-off     AS666 vuelve a callar

  ./scripts/validate.sh               resumen del estado, en texto
  ./scripts/generate-config.sh        regenera los vars.conf a partir de lab.conf

Los parámetros del laboratorio (ASN y prefijos) están en lab.conf.
El idioma de esta salida y de los paneles se define con LANGUAGE en lab.conf.
HELP
        ;;
      en)
        cat <<'HELP'
usage: ./scripts/lab.sh <command>

  up          brings the lab up (builds the images if needed)
  down        brings it down, keeping Krill's data
  reset       brings it down and DELETES the volumes (Krill's CA, validator caches)
  status      container status
  logs [svc]  follows the logs
  panel       opens the lab's panel in the browser
  registry    opens the registry panel (local RIR, or beta.registro.br)

  refresh     forces Routinator and FORT to revalidate now

  the guide's story - AS666 (hijacker) and peer (leaky) - steps 1 to 9:
  step1-clean          AS666 and peer silent; observers with no validation at all
  step2-hijack-simple  AS666 announces the origin's prefixes as its own
  step3-rov-mark       ROV on both observers, only MARKING invalid routes
  step3-rov-drop       ROV DROPPING invalid routes
  step4-hijack-posrov  AS666 forges the path so it ends in the real origin
  step5-aspa-mark      ROV dropping + ASPA verification only MARKING
  step5-aspa-drop      ROV and ASPA both dropping
  step7-leak-on        peer starts leaking the origin's routes to Provider A
  step9-leak-off       peer stops leaking
  step9-hijack-off     AS666 goes silent again

  ./scripts/validate.sh               text summary of the lab's state
  ./scripts/generate-config.sh        regenerates the vars.conf files from lab.conf

The lab's parameters (ASN and prefixes) live in lab.conf.
The language of this output and of the panels is set with LANGUAGE in lab.conf.
HELP
        ;;
      *)
        cat <<'HELP'
uso: ./scripts/lab.sh <comando>

  up          sobe o laboratório (constrói as imagens se preciso)
  down        derruba, preservando os dados do Krill
  reset       derruba e APAGA os volumes (CA do Krill, caches dos validadores)
  status      estado dos contêineres
  logs [svc]  acompanha os logs
  panel       abre o painel do laboratório no navegador
  registry    abre o painel do registro (RIR local, ou o beta.registro.br)

  refresh     força o Routinator e o FORT a revalidarem agora

  a história do roteiro - AS666 (sequestrador) e peer (vazando) - passos 1 a 9:
  step1-clean          AS666 e peer calados; observadores sem validação nenhuma
  step2-hijack-simple  AS666 anuncia os prefixos da origem como se fossem seus
  step3-rov-mark       ROV nos dois observadores, só MARCANDO os inválidos
  step3-rov-drop       ROV DESCARTANDO os inválidos
  step4-hijack-posrov  AS666 forja o caminho para terminar na origem verdadeira
  step5-aspa-mark      ROV descartando + ASPA só MARCANDO
  step5-aspa-drop      ROV e ASPA descartando
  step7-leak-on        peer começa a vazar as rotas da origem para o Provedor A
  step9-leak-off       peer para de vazar
  step9-hijack-off     AS666 volta a ficar calado

  ./scripts/validate.sh               resumo do estado, em texto
  ./scripts/generate-config.sh        regera os vars.conf a partir do lab.conf

Os parâmetros do laboratório (ASN e prefixos) ficam em lab.conf.
O idioma desta saída e dos painéis é definido por LANGUAGE no lab.conf.
HELP
        ;;
    esac
}
