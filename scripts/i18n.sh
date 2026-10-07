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

      pt:note_krill)        echo "(token: labpass)" ;;
      es:note_krill)        echo "(token: labpass)" ;;
      en:note_krill)        echo "(token: labpass)" ;;

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

      pt:step4_hijack_posrov_ok)  echo "passo 4: AS666 anuncia com um caminho forjado (AS_PATH: 666 <origem>)." ;;
      es:step4_hijack_posrov_ok)  echo "paso 4: AS666 anuncia con un camino falsificado (AS_PATH: 666 <origen>)." ;;
      en:step4_hijack_posrov_ok)  echo "step 4: AS666 is announcing with a forged path (AS_PATH: 666 <origin>)." ;;

      pt:step5_aspa_mark_ok)      echo "passo 5: os dois observadores agora também verificam ASPA, só MARCANDO o que ela acusa (o ROV continua só marcando). ASPA lista só o Provedor A." ;;
      es:step5_aspa_mark_ok)      echo "paso 5: los dos observers ahora también verifican ASPA, solo MARCANDO lo que esta señala (ROV sigue solo marcando). ASPA lista solo al Proveedor A." ;;
      en:step5_aspa_mark_ok)      echo "step 5: both observers now also verify ASPA, only MARKING what it flags (ROV keeps only marking too). ASPA lists Provider A only." ;;

      pt:step6_add_provider_b_ok) echo "passo 6: o objeto ASPA agora lista os Provedores A e B." ;;
      es:step6_add_provider_b_ok) echo "paso 6: el objeto ASPA ahora lista a los Proveedores A y B." ;;
      en:step6_add_provider_b_ok) echo "step 6: the ASPA object now lists Providers A and B." ;;

      pt:step7_leak_on_ok)        echo "passo 7: o peer agora vaza os prefixos da origem para o Provedor A." ;;
      es:step7_leak_on_ok)        echo "paso 7: el peer ahora filtra los prefijos del origen hacia el Proveedor A." ;;
      en:step7_leak_on_ok)        echo "step 7: peer is now leaking the origin's prefixes to Provider A." ;;

      pt:step8_drop_ok)           echo "passo 8: os dois observadores agora DESCARTAM rotas inválidas pelo ROV E pelo ASPA - o que um roteador de verdade faz." ;;
      es:step8_drop_ok)           echo "paso 8: los dos observers ahora DESCARTAN rutas inválidas según ROV Y según ASPA - lo que hace un router de verdad." ;;
      en:step8_drop_ok)           echo "step 8: both observers now DROP ROV-invalid AND ASPA-invalid routes - what a real router does." ;;

      pt:step9_leak_off_ok)       echo "passo 9: o peer parou de vazar." ;;
      es:step9_leak_off_ok)       echo "paso 9: el peer dejó de filtrar." ;;
      en:step9_leak_off_ok)       echo "step 9: peer has stopped leaking." ;;

      pt:step9_hijack_off_ok)     echo "passo 9: AS666 está calado." ;;
      es:step9_hijack_off_ok)     echo "paso 9: AS666 está callado." ;;
      en:step9_hijack_off_ok)     echo "step 9: AS666 is silent." ;;

      # -- scripts/lab.sh: ports, doctor, clean-objects ---------------------
      pt:port_busy_host)       echo "porta ocupada por outro programa deste computador:" ;;
      es:port_busy_host)       echo "puerto ocupado por otro programa de esta computadora:" ;;
      en:port_busy_host)       echo "port taken by another program on this computer:" ;;

      pt:port_busy_container)  echo "porta ocupada por outro contêiner (fora do laboratório)," ;;
      es:port_busy_container)  echo "puerto ocupado por otro contenedor (fuera del laboratorio)," ;;
      en:port_busy_container)  echo "port taken by another container (not part of the lab)," ;;

      pt:port_busy_hint)       echo "Libere a porta (pare o outro programa ou contêiner: 'docker ps' mostra os contêineres, 'lsof -i :<porta>' os programas) e rode 'up' de novo. Se for a porta do painel (${PANEL_PORT}), você também pode escolher outra em PANEL_PORT no lab.conf; se for uma das portas extras, deixe EXPOSE_PORTS=no." ;;
      es:port_busy_hint)       echo "Libere el puerto (detenga el otro programa o contenedor: 'docker ps' muestra los contenedores, 'lsof -i :<puerto>' los programas) y vuelva a ejecutar 'up'. Si es el puerto del panel (${PANEL_PORT}), también puede elegir otro en PANEL_PORT en lab.conf; si es uno de los puertos extra, deje EXPOSE_PORTS=no." ;;
      en:port_busy_hint)       echo "Free the port (stop the other program or container: 'docker ps' lists containers, 'lsof -i :<port>' lists programs) and run 'up' again. If it's the panel's port (${PANEL_PORT}), you can also pick another one with PANEL_PORT in lab.conf; if it's one of the extra ports, set EXPOSE_PORTS=no." ;;

      pt:beta_warning)         echo "o laboratório vai usar o beta.registro.br, e você vai precisar de acesso à Internet e de um login lá. Para o laboratório autocontido, use MODE=local no lab.conf." ;;
      es:beta_warning)         echo "el laboratorio va a usar beta.registro.br, y necesitará acceso a Internet y un usuario allí. Para el laboratorio autocontenido, use MODE=local en lab.conf." ;;
      en:beta_warning)         echo "the lab will use beta.registro.br, which needs Internet access and a login there. For the self-contained lab, set MODE=local in lab.conf." ;;

      pt:clean_objects_ok)     echo "ROAs e objeto ASPA removidos (a CA e a Preparação continuam intactas). Para a linha de base completa, rode também step1-clean." ;;
      es:clean_objects_ok)     echo "ROAs y objeto ASPA eliminados (la CA y la Preparación siguen intactas). Para la base completa, ejecute también step1-clean." ;;
      en:clean_objects_ok)     echo "ROAs and the ASPA object removed (the CA and Preparation are untouched). For the full baseline, also run step1-clean." ;;

      pt:doc_title)            echo "Conferindo o ambiente do laboratório..." ;;
      es:doc_title)            echo "Revisando el entorno del laboratorio..." ;;
      en:doc_title)            echo "Checking the lab's environment..." ;;

      pt:doc_no_docker)        echo "o comando 'docker' não foi encontrado. Instale o Docker (veja a seção 'Antes de começar' do README)." ;;
      es:doc_no_docker)        echo "no se encontró el comando 'docker'. Instale Docker (vea la sección 'Antes de empezar' del README)." ;;
      en:doc_no_docker)        echo "the 'docker' command wasn't found. Install Docker (see the README's 'Before you start' section)." ;;

      pt:doc_no_daemon)        echo "o Docker está instalado, mas não está rodando (ou você não tem permissão: no Linux, entre no grupo 'docker'). Abra o Docker Desktop/OrbStack, ou rode 'sudo systemctl start docker'." ;;
      es:doc_no_daemon)        echo "Docker está instalado pero no está corriendo (o no tiene permiso: en Linux, únase al grupo 'docker'). Abra Docker Desktop/OrbStack, o ejecute 'sudo systemctl start docker'." ;;
      en:doc_no_daemon)        echo "Docker is installed but not running (or you lack permission: on Linux, join the 'docker' group). Start Docker Desktop/OrbStack, or run 'sudo systemctl start docker'." ;;

      pt:doc_no_compose)       echo "falta o Docker Compose v2 ('docker compose'). No Linux, instale o pacote docker-compose-plugin." ;;
      es:doc_no_compose)       echo "falta Docker Compose v2 ('docker compose'). En Linux, instale el paquete docker-compose-plugin." ;;
      en:doc_no_compose)       echo "Docker Compose v2 ('docker compose') is missing. On Linux, install the docker-compose-plugin package." ;;

      pt:doc_mem)              echo "memória disponível para o Docker:" ;;
      es:doc_mem)              echo "memoria disponible para Docker:" ;;
      en:doc_mem)              echo "memory available to Docker:" ;;

      pt:doc_low_mem)          echo "o Docker tem menos de 2 GB de memória; o laboratório pode ficar lento ou instável (aumente em Settings > Resources)" ;;
      es:doc_low_mem)          echo "Docker tiene menos de 2 GB de memoria; el laboratorio puede volverse lento o inestable (auméntela en Settings > Resources)" ;;
      en:doc_low_mem)          echo "Docker has less than 2 GB of memory; the lab may be slow or unstable (raise it under Settings > Resources)" ;;

      pt:doc_low_disk)         echo "menos de 4 GB livres em disco; a primeira construção das imagens pode falhar" ;;
      es:doc_low_disk)         echo "menos de 4 GB libres en disco; la primera construcción de las imágenes puede fallar" ;;
      en:doc_low_disk)         echo "less than 4 GB of free disk; the first image build may fail" ;;

      pt:doc_bad_mode)         echo "valor inválido no lab.conf (use local ou beta)" ;;
      es:doc_bad_mode)         echo "valor inválido en lab.conf (use local o beta)" ;;
      en:doc_bad_mode)         echo "invalid value in lab.conf (use local or beta)" ;;

      pt:doc_port_lab)         echo "porta em uso pelo próprio laboratório:" ;;
      es:doc_port_lab)         echo "puerto en uso por el propio laboratorio:" ;;
      en:doc_port_lab)         echo "port in use by the lab itself:" ;;

      pt:doc_port_free)        echo "porta livre:" ;;
      es:doc_port_free)        echo "puerto libre:" ;;
      en:doc_port_free)        echo "port free:" ;;

      pt:doc_not_running)      echo "o laboratório não está rodando. Suba-o com './scripts/lab.sh up'." ;;
      es:doc_not_running)      echo "el laboratorio no está corriendo. Levántelo con './scripts/lab.sh up'." ;;
      en:doc_not_running)      echo "the lab isn't running. Bring it up with './scripts/lab.sh up'." ;;

      pt:doc_some_down)        echo "alguns contêineres não estão rodando (veja abaixo; './scripts/lab.sh logs <serviço>' mostra o motivo)" ;;
      es:doc_some_down)        echo "algunos contenedores no están corriendo (vea abajo; './scripts/lab.sh logs <servicio>' muestra el motivo)" ;;
      en:doc_some_down)        echo "some containers aren't running (see below; './scripts/lab.sh logs <service>' shows why)" ;;

      pt:doc_all_up)           echo "todos os contêineres rodando" ;;
      es:doc_all_up)           echo "todos los contenedores corriendo" ;;
      en:doc_all_up)           echo "all containers running" ;;

      pt:doc_panel_ok)         echo "painel respondendo em" ;;
      es:doc_panel_ok)         echo "panel respondiendo en" ;;
      en:doc_panel_ok)         echo "panel answering at" ;;

      pt:doc_panel_bad)        echo "o painel não responde em" ;;
      es:doc_panel_bad)        echo "el panel no responde en" ;;
      en:doc_panel_bad)        echo "the panel doesn't answer at" ;;

      pt:doc_vhost_bad)        echo "krill.localhost não respondeu deste terminal. Os navegadores resolvem *.localhost sozinhos; se o navegador também falhar, abra o painel em http://localhost:${PANEL_PORT} e use os botões dele." ;;
      es:doc_vhost_bad)        echo "krill.localhost no respondió desde esta terminal. Los navegadores resuelven *.localhost solos; si el navegador también falla, abra el panel en http://localhost:${PANEL_PORT} y use sus botones." ;;
      en:doc_vhost_bad)        echo "krill.localhost didn't answer from this terminal. Browsers resolve *.localhost on their own; if the browser fails too, open the panel at http://localhost:${PANEL_PORT} and use its buttons." ;;

      pt:doc_prep_ok)          echo "Preparação concluída: a CA tem pai, recursos e repositório" ;;
      es:doc_prep_ok)          echo "Preparación terminada: la CA tiene padre, recursos y repositorio" ;;
      en:doc_prep_ok)          echo "Preparation done: the CA has a parent, resources and a repository" ;;

      pt:doc_prep_missing)     echo "a Preparação ainda não terminou (CA, pai, recursos ou repositório). Siga a Preparação 2 do roteiro." ;;
      es:doc_prep_missing)     echo "la Preparación todavía no terminó (CA, padre, recursos o repositorio). Siga la Preparación 2 de la guía." ;;
      en:doc_prep_missing)     echo "Preparation isn't finished yet (CA, parent, resources or repository). Follow the guide's Preparation 2." ;;

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

      # -- scripts/lab.sh: krill_ca() sanity check (step3-rov-mark on) -------
      pt:krill_no_ca)      echo "nenhuma CA encontrada no Krill - termine a Preparação (criar a CA, obter o certificado do parent, local ou beta.registro.br) antes de rodar este comando." ;;
      es:krill_no_ca)      echo "no se encontró ninguna CA en Krill - termine la Preparación (crear la CA, obtener el certificado del parent, local o beta.registro.br) antes de ejecutar este comando." ;;
      en:krill_no_ca)      echo "no CA found in Krill yet - finish the Preparation (create the CA, get the certificate from the parent, local or beta.registro.br) before running this command." ;;

      pt:krill_multiple_ca) echo "mais de uma CA encontrada no Krill - o laboratório espera exatamente uma" ;;
      es:krill_multiple_ca) echo "se encontró más de una CA en Krill - el laboratorio espera exactamente una" ;;
      en:krill_multiple_ca) echo "more than one CA found in Krill - the lab expects exactly one" ;;

      pt:krill_not_ready)  echo "a CA ainda não está pronta: falta um parent ativo, os recursos (ASN e prefixos) do lab.conf, ou um repositório funcionando. Rode 'krillc show --ca <nome>' no terminal do Krill e confira se a Preparação terminou." ;;
      es:krill_not_ready)  echo "la CA todavía no está lista: falta un parent activo, los recursos (ASN y prefijos) del lab.conf, o un repositorio funcionando. Ejecute 'krillc show --ca <nombre>' en la terminal de Krill y confirme que la Preparación terminó." ;;
      en:krill_not_ready)  echo "the CA isn't ready yet: it's missing an active parent, the ASN/prefixes from lab.conf, or a working repository. Run 'krillc show --ca <name>' in the Krill terminal and check that Preparation finished." ;;

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
  doctor      revisa Docker, puertos, contenedores y la Preparación, y dice qué hacer

  refresh     fuerza al Routinator y a FORT a revalidar ahora
  clean-objects borra las ROAs y el ASPA de la CA (sin rehacer la Preparación)

  la historia de la guía - AS666 (secuestrador) y peer (con fuga) - pasos 1 a 9:
  step1-clean          AS666 y peer callados; observers sin validación alguna
  step2-hijack-simple  AS666 anuncia los prefijos del origen como propios
  step3-rov-mark       ROV en los dos observers, solo MARCANDO los inválidos
  step4-hijack-posrov  AS666 falsifica el camino para que termine en el origen real
  step5-aspa-mark      ROV y ASPA, los dos solo MARCANDO
  step6-add-provider-b agrega al Proveedor B al objeto ASPA
  step7-leak-on        peer empieza a filtrar las rutas del origen al Proveedor A
  step8-drop           ROV y ASPA pasan a DESCARTAR - lo que hace un router de verdad
  step9-leak-off       peer deja de filtrar
  step9-hijack-off     AS666 vuelve a callar

  ./scripts/validate.sh               resumen del estado, en texto
  ./scripts/generate-config.sh        regenera los vars.conf a partir de lab.conf

Los parámetros del laboratorio (ASN, prefijos, MODE, EXPOSE_PORTS) están en lab.conf.
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
  doctor      checks Docker, ports, containers and Preparation, and says what to do

  refresh     forces Routinator and FORT to revalidate now
  clean-objects removes the CA's ROAs and ASPA (without redoing Preparation)

  the guide's story - AS666 (hijacker) and peer (leaky) - steps 1 to 9:
  step1-clean          AS666 and peer silent; observers with no validation at all
  step2-hijack-simple  AS666 announces the origin's prefixes as its own
  step3-rov-mark       ROV on both observers, only MARKING invalid routes
  step4-hijack-posrov  AS666 forges the path so it ends in the real origin
  step5-aspa-mark      ROV and ASPA, both only MARKING
  step6-add-provider-b adds Provider B to the ASPA object
  step7-leak-on        peer starts leaking the origin's routes to Provider A
  step8-drop           ROV and ASPA start DROPPING - what a real router does
  step9-leak-off       peer stops leaking
  step9-hijack-off     AS666 goes silent again

  ./scripts/validate.sh               text summary of the lab's state
  ./scripts/generate-config.sh        regenerates the vars.conf files from lab.conf

The lab's parameters (ASN, prefixes, MODE, EXPOSE_PORTS) live in lab.conf.
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
  doctor      confere Docker, portas, contêineres e a Preparação, e diz o que fazer

  refresh     força o Routinator e o FORT a revalidarem agora
  clean-objects apaga as ROAs e o ASPA da CA (sem refazer a Preparação)

  a história do roteiro - AS666 (sequestrador) e peer (vazando) - passos 1 a 9:
  step1-clean          AS666 e peer calados; observadores sem validação nenhuma
  step2-hijack-simple  AS666 anuncia os prefixos da origem como se fossem seus
  step3-rov-mark       ROV nos dois observadores, só MARCANDO os inválidos
  step4-hijack-posrov  AS666 forja o caminho para terminar na origem verdadeira
  step5-aspa-mark      ROV e ASPA, os dois só MARCANDO
  step6-add-provider-b acrescenta o Provedor B ao objeto ASPA
  step7-leak-on        peer começa a vazar as rotas da origem para o Provedor A
  step8-drop           ROV e ASPA passam a DESCARTAR - o que um roteador de verdade faz
  step9-leak-off       peer para de vazar
  step9-hijack-off     AS666 volta a ficar calado

  ./scripts/validate.sh               resumo do estado, em texto
  ./scripts/generate-config.sh        regera os vars.conf a partir do lab.conf

Os parâmetros do laboratório (ASN, prefixos, MODE, EXPOSE_PORTS) ficam em lab.conf.
O idioma desta saída e dos painéis é definido por LANGUAGE no lab.conf.
HELP
        ;;
    esac
}
