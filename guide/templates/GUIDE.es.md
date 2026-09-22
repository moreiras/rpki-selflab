# RPKI SelfLab

*Laboratorio autónomo y guía de autoestudio para RPKI, ROA, ROV y ASPA*

*[English](GUIDE.en.md) · [Español](GUIDE.es.md) · [Português](GUIDE.pt.md)*

**Objetivo:** seguir a un atacante y a un peer con fuga de rutas a través de un laboratorio que corre en su
propia máquina. Ver qué detecta la validación de origen (ROV), qué deja pasar,
y qué agrega el ASPA - con cada veredicto verificado por dos pilas
independientes (BIRD + Routinator, y OpenBGPD + FORT).

Este es un laboratorio autocontenido: todo corre en contenedores en su propia
máquina, y asume que usted ya tiene una noción básica de RPKI, ROAs, ROV
y ASPA. Puede certificar sus recursos completamente de forma local, o, si
prefiere usar un registro del mundo real, contra el sistema de pruebas de
Registro.br.

El laboratorio es una sola historia en nueve pasos: **tres ataques, y el momento en que cada
uno deja de funcionar.** Primero viene una breve preparación (levantar el laboratorio
y certificar sus recursos), y al final algunos ejercicios extra.

## Qué le pide RPKI a su propio AS - y qué despliega este laboratorio

RPKI tiene dos mitades, y cada una tiene dos partes:

| | El origen publica... | ...y los routers validan |
|---|---|---|
| **Quién puede originar un prefijo** | **ROAs** (Route Origin Authorizations) | **ROV** (Route Origin Validation) |
| **Qué caminos son plausibles** | un objeto **ASPA** (Autonomous System Provider Authorization) | **verificación ASPA** |

En la vida real, **las dos van en el AS que usted opera**: usted *publica* objetos
sobre sus propios recursos, y *valida* lo que le envían sus vecinos.
Publicar sin validar protege a los demás pero no a usted; validar sin
publicar lo protege a usted pero deja sus propios prefijos desprotegidos para todos
los demás.

En este laboratorio, con fines didácticos, las dos se separan:

- **La publicación se despliega solo en el AS de origen** (AS{{ORIGIN_ASN}}, cuya CA vive en
  Krill). Es el único AS que crea ROAs y un objeto ASPA.
- **La validación se despliega solo en los AS observadores** (observer1 y
  observer2), los dos routers que va a observar. Todo lo demás en el laboratorio
  es un router BGP común que nunca mira RPKI.

La validación se despliega en los observadores **en dos etapas, para cada verificación**:
primero el router solo *marca* lo que la verificación señala (una community, una
preferencia menor - no se descarta nada, así que puede ver qué pasaría), y después
lo *descarta*. **Descartar las inválidas es lo que hacen los routers reales**; marcar
es el ensayo que se hace antes de confiar lo suficiente en una verificación como para dejar que rechace
rutas.

## Glosario

Un repaso rápido, no una introducción completa - esto es lo que estos
términos significan *en este laboratorio*. Salte adelante si ya se siente
cómodo con ellos.

| Término | Significado |
|---|---|
| **RIR/NIR** | Registro Regional/Nacional de Internet - asigna ASN y bloques de IP y, en RPKI, certifica que usted es el titular |
| **CA** | Certificate Authority (Autoridad Certificadora) - el motor RPKI que convierte "estos recursos son suyos" en certificados y objetos firmados |
| **TA** | Trust Anchor (ancla de confianza) - la CA en la raíz de la cadena de confianza de un validador; todo lo demás o es ella, o fue (transitivamente) certificado por ella |
| **ROA** | Route Origin Authorization - un objeto firmado que dice "este ASN puede originar este prefijo, hasta esta longitud" |
| **ASPA** | Autonomous System Provider Authorization - un objeto firmado que dice "estos son los únicos AS de los que este AS acepta rutas como proveedor upstream" |
| **ROV** | Route Origin Validation - verifica el *último* AS de la ruta (el que la originó) contra las ROAs |
| **Verificación ASPA** | verifica el *camino completo*, salto a salto, contra los objetos ASPA |
| **RRDP** | RPKI Repository Delta Protocol - cómo un validador obtiene los objetos firmados de un punto de publicación |
| **RTR** | RPKI-to-Router protocol - cómo un validador entrega sus veredictos a un router |
| **VRP** | Validated ROA Payload - la tripla (ASN, prefijo, longitud máxima) que un validador derivó de una ROA |
| **Secuestro (hijack)** | anunciar un prefijo que pertenece a otro, como si fuera suyo (o como si viniera a través de él) |
| **Fuga de ruta** | pasar una ruta que aprendió de un vecino a otro vecino al que no debería - nadie miente sobre el origen, pero el camino tiene una forma que no podría ocurrir legítimamente (RFC 7908) |

---

## La topología

```
              {{RIR_NAME}}   (RIR/NIR: ancla de confianza + repositorio)
             /                                              \
         RRDP                                                RRDP
          v                                                    v
     Routinator                                          FORT Validator
          |  RTR v2 :3323                                      |  RTR v2 :3323
          v                                                    v
  observer1 AS{{OBSERVER1_ASN}} (BIRD)                       observer2 AS{{OBSERVER2_ASN}} (OpenBGPD)

       los dos observadores reciben el MISMO prefijo por LOS DOS caminos:

            Proveedor A  AS{{PROVIDER_A_ASN}}
            Proveedor B  AS{{PROVIDER_B_ASN}}
                          \          /
                           \        /
                    origen AS{{ORIGIN_ASN}}   +   Krill (la CA del titular)
                    {{ORIGIN_V4}} , {{ORIGIN_V6}}
```

El AS{{ORIGIN_ASN}} es multihomed, y tiene una preferencia: **el Proveedor B es la entrada, el Proveedor A
es el respaldo.** Para lograrlo, el origen hace *prepend* de su propio ASN dos veces cuando anuncia
al Proveedor A (`{{ORIGIN_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}}` en lugar de solo `{{ORIGIN_ASN}}`), así que todo camino a través de
A parece dos saltos más largo que el que pasa por B - ingeniería de tráfico entrante común y corriente.
Los dos proveedores pasan el **mismo prefijo** a los dos observadores, con el mismo AS de origen. El laboratorio corre toda la historia **dos veces, en
paralelo**, sobre dos pilas independientes: observer1 y observer2 ven exactamente los
mismos anuncios y los mismos objetos RPKI, pero cada uno tiene su propio router
y su propio validador.

Dos routers más se suman a la historia. Los dos están en el panel, y los dos están en silencio
hasta que la historia los activa:

```
   AS{{ATTACKER_ASN}} (el atacante) ---- sesiones BGP directas ----> observer1, observer2
                             (un cliente de los observadores: cualquier cliente
                              puede enviarles un anuncio, y nadie
                              lo verifica a menos que los observadores validen)

   peer AS{{PEER_ASN}} ---- peering privado ---- origen AS{{ORIGIN_ASN}}
        |
        +---- tránsito ---- Proveedor A
```

| Componente | ASN | Rol |
|---|---|---|
| origen | {{ORIGIN_ASN}} | su AS; origina los prefijos |
| Proveedor A | {{PROVIDER_A_ASN}} | uno de los dos upstreams del origen - el respaldo (el origen hace prepend dos veces hacia él) |
| Proveedor B | {{PROVIDER_B_ASN}} | el otro upstream del origen - el preferido |
| observer1 | {{OBSERVER1_ASN}} | router que valida: **BIRD** + **Routinator** |
| observer2 | {{OBSERVER2_ASN}} | router que valida: **OpenBGPD** + **FORT Validator** |
| AS{{ATTACKER_ASN}} | {{ATTACKER_ASN}} | el atacante: un cliente de los observadores, y secuestra los prefijos del origen |
| peer | {{PEER_ASN}} | una red legítima que hace peering con el origen, y compra tránsito del Proveedor A |

Los ASN 64496–64511 son ASN reservados para documentación (RFC 5398). El AS{{PEER_ASN}} está en el
rango de uso privado (RFC 6996), y el AS{{ATTACKER_ASN}} no está en ninguno - simplemente es
fácil de recordar. Todos son inofensivos aquí: esta red nunca toca la Internet
real.

> El ASN y los prefijos del origen están en el archivo **`lab.conf`**, en la
> raíz del laboratorio. Si quiere otros, edítelos ahí y ejecute
> `./scripts/lab.sh up`: los routers, los scripts y este guion en pantalla
> pasan a usar los nuevos valores. (La guía está escrita con marcadores `{{ NAME }}`
> en `guide/templates/`; `up` la compila en `guide/GUIDE.*.md` con los
> valores de `lab.conf`. Edite las plantillas, nunca los archivos compilados.)

### Cómo está organizada la historia

Cada paso empieza con un cuadro de **Estado**: en qué etapa de despliegue están los observadores,
qué están haciendo el AS{{ATTACKER_ASN}} y el peer, y qué objetos RPKI deberían
existir. Si su laboratorio no coincide, el cuadro también dice cómo volver a dejarlo.

Esa recuperación es deliberadamente simple: **cada comando `./scripts/lab.sh
stepN-*` fija el estado *entero* de su paso**, no solo lo que cambió desde el
anterior. Ejecute `step9-leak-off` y después `step3-rov-mark`, y llega
exactamente adonde el Paso 3 espera - la fuga, la etapa de descarte, todo lo
que dejó `step9-leak-off` desaparece, reiniciado por el propio
`step3-rov-mark`. Eso vale para cualquier par de pasos, en cualquier
dirección: los comandos no suponen que usted va hacia adelante, ni dejan
nada atrás para que el siguiente tropiece con eso. Tres cosas se mueven
juntas cada vez que se ejecuta un comando `stepN-*`:

- **La etapa de despliegue de los observadores.** Empiezan sin ninguna validación,
  y la historia los lleva por cuatro etapas: las dos verificaciones se marcan
  antes de que ninguna descarte nada, y después las dos empiezan a descartar
  juntas, en el Paso 8. Cada comando fija una etapa completa
  en **los dos** observadores a la vez, sin importar en qué etapa estuvieran antes:

  | Etapa | Qué hacen los observadores | Comando |
  |---|---|---|
  | `none` | BGP común, sin validación (así empieza el laboratorio) | `step1-clean` |
  | `rov-mark` | ROV desplegado, rutas inválidas solo *marcadas* | `step3-rov-mark` |
  | `aspa-mark` | se suma la verificación ASPA, también solo *marcando* | `step5-aspa-mark` |
  | `aspa-drop` | el ROV y el ASPA los dos empiezan a *descartar* - producción | `step8-drop` |

  Cada etapa es un archivo de configuración completo por observador
  (`bird/observer1-<stage>.conf`, `openbgpd/observer2-<stage>.conf`), y la
  guía le pide que los abra: **lo que cambia de un archivo al siguiente es lo que
  significa desplegar esa verificación.** No tiene que recordar en qué etapa está -
  la insignia en el encabezado del panel lo dice (*validación: ninguna*, *ROV: marcando*,
  *ROV: descartando*, ...), y se pone ámbar si los dos observadores no están en la
  misma. observer2 se reinicia cada vez que cambia la etapa (OpenBGPD negocia
  sus roles RFC 9234 y su versión de RTR cuando se abre una sesión), así que dele diez
  o quince segundos para estabilizarse antes de sacar conclusiones de lo que muestra.
- **El AS{{ATTACKER_ASN}} y el peer.** Todo comando `stepN-*` también fija su
  estado - silencioso, secuestro ingenuo, ruta falsificada, en fuga - al que
  describe el texto de la guía para ese paso, incluso los comandos cuyo
  nombre no los menciona (`step6-add-provider-b` y `step8-drop`, por ejemplo,
  igual vuelven a dejar al AS{{ATTACKER_ASN}} en su forma de ruta falsificada,
  porque eso es lo que esos pasos esperan).
- **Los objetos RPKI del origen**, en Krill: las ROAs (creadas una sola vez,
  desde `step3-rov-mark` en adelante) y el objeto ASPA, mantenido con
  exactamente la lista que cada paso espera - `krillc aspas add` reemplaza el
  objeto entero, así que un comando puede hacerlo crecer (Paso 6) o volver a
  achicarlo (al saltar al Paso 5 después de haber corrido el Paso 6) con la
  misma facilidad.

  Este es también el único punto donde un comando `stepN-*` puede fallar sin
  culpa propia: desde `step3-rov-mark` en adelante, cada uno empieza
  comprobando que la Preparación realmente haya terminado - que la CA
  exista, tenga un padre activo, tenga el número de AS y los prefijos de
  `lab.conf`, y tenga un repositorio funcionando. Si no es así, el comando
  se detiene y se lo dice, en vez de crear en silencio ROAs que Krill en
  realidad no puede publicar. La Preparación es la única parte de la
  historia que un comando `stepN-*` no puede hacer por usted.

---

## Preparación 1 — Levantar el laboratorio

El laboratorio tiene dos modos, elegidos con la variable `MODE` en `lab.conf`:

| MODE | Quién certifica | ¿Necesita Internet? |
|---|---|---|
| `local` | **{{RIR_NAME}}**, un registro simulado que corre dentro del laboratorio | no |
| `beta` | **beta.registro.br**, el sistema de pruebas de Registro.br | sí, y un login en beta.registro.br |

Los dos modos usan exactamente los mismos protocolos - RFC 6492 para la delegación y
RFC 8181 para la publicación. Lo que cambia es el panel donde pega los XML,
y cuánto tardan los objetos en aparecer en el validador: segundos en modo
local, algunos minutos en beta. El próximo paso de preparación tiene una versión por
modo; haga solo la que corresponde al suyo.

1. Requisitos: Docker instalado (Mac, Windows o Linux - **OrbStack**,
   Docker Desktop o Docker Engine) y acceso a Internet.

2. En la terminal, dentro de la carpeta del laboratorio:

   ```
   #./scripts/lab.sh up
   ```

   La primera vez, Docker descarga las imágenes y construye algunas locales.
   Tarda unos minutos.

3. Abra el panel del laboratorio:

   **http://localhost:8080**

   Al hacer clic en cada recuadro de la topología se abre la terminal de ese
   componente, su interfaz web y su información de direccionamiento.

   **Dónde escribir los comandos de esta guía.** Todo se puede hacer
   sin salir del navegador, y cada bloque de comandos muestra las dos formas:

   - **En el panel (la forma en que están escritos los bloques primero).** Haga clic en un recuadro
     y use su botón **Shell** (**Terminal (krillc)** en Krill): usted queda
     dentro de ese contenedor, así que un comando se escribe sin ningún prefijo -
     por ejemplo `birdc show protocols` en el Shell de observer1. El botón
     **Comandos del laboratorio** abre una terminal ya en la carpeta del laboratorio,
     para `./scripts/lab.sh ...`, `cat bird/...` y `diff ...`.
   - **Desde la terminal de su propia computadora, en la carpeta del laboratorio.** El mismo
     comando, ejecutado desde afuera: `docker exec lab-<box> <command>`, como en
     `docker exec lab-observer1 birdc show protocols`. Use esta si prefiere su
     propia terminal - o para `reset`, que nunca debe ejecutarse desde el
     panel.

4. Verifique que los routers levantaron y que las sesiones BGP están establecidas.
   En el panel, la insignia de cada router muestra cuántas de sus sesiones BGP están
   arriba. Para ver el detalle:

   ```
   # Panel: haga clic en el recuadro observador 1, luego en Shell:
   #birdc show protocols
   # Panel: haga clic en el recuadro observador 2, luego en Shell:
   #bgpctl show summary
   # O, desde la terminal de su computadora:
   #docker exec lab-observer1 birdc show protocols
   #docker exec lab-observer2 bgpctl show summary
   ```

   Debería ver `provider_a_v4`, `provider_a_v6`, `provider_b_v4` y
   `provider_b_v6` en `Established` en observer1 - más `attacker_v4` y
   `attacker_v6`, las sesiones con el AS{{ATTACKER_ASN}}, que está arriba pero en silencio por ahora.
   observer2 lista las mismas seis sesiones. Todavía no hay un protocolo `routinator`:
   los observadores no validan nada hasta el Paso 3.

---

## Preparación 2 — Certificar sus recursos (MODE=local)

> Haga esto si `lab.conf` tiene `MODE=local`. Si tiene `MODE=beta`, pase a la
> Preparación 2-B.

Aquí va a actuar en **los dos lados** de la conversación: el titular, en Krill,
y el registro, en el panel de {{RIR_NAME}}. Es el mismo intercambio de XML que ocurre
entre un proveedor y su RIR.

### Su lado: la CA en Krill

1. Abra Krill: **http://krill.localhost:8080**

   (Se sirve a través del servidor web del laboratorio, así que no hay
   advertencia de certificado. La dirección directa, `https://localhost:3000`,
   sigue funcionando, con un certificado autofirmado.)

2. Inicie sesión con el token **`passlab`**.

3. Cree su CA con el nombre **`acme_ca`**.
   Si quiere, cambie el idioma a Español en la esquina superior derecha.

### El lado del registro: el panel de {{RIR_NAME}}

4. En otra pestaña, abra el panel del registro: **http://registry.localhost:8080**

   Fíjese en la sección *Recursos asignados*: son exactamente el ASN y los bloques
   de su `lab.conf`. El certificado que el registro está por emitir
   cubre ese conjunto, ni más ni menos.

### Parte 1 — Delegación de la CA (RFC 6492)

5. En Krill, vaya a *CAs-padre* → *Incluir una nueva CA-padre* y copie el XML del campo
   *Solicitud de la CA-Hija* (el `child_request`).

6. En el panel de {{RIR_NAME}}, pegue ese XML en la **Etapa 1** y haga clic en
   *Emitir certificado*.

7. El registro devuelve el `parent_response`. Cópielo.

8. De vuelta en Krill, en *CAs-padre* → *Respuesta de la CA-padre*, pegue el XML. En
   el campo *Nombre de la CA-padre* use **`labnic`** y confirme.

### Parte 2 — Servicio de publicación (RFC 8181)

9. En Krill, vaya a *Repositorio* → *Incluir un repositorio* y copie el XML de
   la *Solicitud del Publicador* (el `publisher_request`).

10. En el panel de {{RIR_NAME}}, péguelo en la **Etapa 2** y haga clic en *Autorizar publicación*.

11. Copie el `repository_response` que aparece y péguelo en Krill,
    en *Repositorio* → *Respuesta del Repositorio*. Confirme.

### Verificando

12. En Krill, la CA debe mostrar los recursos recibidos del padre: el
    ASN {{ORIGIN_ASN}} y los prefijos {{ORIGIN_V4}} y {{ORIGIN_V6}}.

13. En el panel de {{RIR_NAME}}, la sección *RPKI delegado* pasa a mostrar **activo**,
    con la fecha del último intercambio Up-Down y el conteo de objetos en
    el repositorio.

> **¿Por qué dos partes separadas?** Porque son dos cosas independientes. La
> primera dice *qué recursos son suyos*; la segunda dice *dónde va a publicar
> los objetos firmados*. Un RIR puede certificar sus recursos mientras usted
> publica en otro lugar - incluso en su propio servidor de publicación.

**Fíjese en lo que *no* hizo:** crear una ROA, o un objeto ASPA. Sus
recursos están certificados, pero nada dice quién puede anunciarlos. Ahí es donde
empieza la historia.

---

## Preparación 2-B — Certificar sus recursos (MODE=beta)

> Haga esto solo si `lab.conf` tiene `MODE=beta`. Necesita acceso a Internet y un
> login en beta.registro.br.

1. Abra Krill en **http://krill.localhost:8080**, entre con el token
   **`passlab`** y cree la CA **`acme_ca`**.

2. En otra pestaña, entre en **https://beta.registro.br/login/**. En el
   Panel, vaya a *Titularidad*, seleccione el AS y baje hasta la sección
   **RPKI** → *Configurar RPKI*.

3. En Krill, en *CAs-padre* → *Incluir una nueva CA-padre*, copie el XML del campo
   *Solicitud de la CA-Hija* y péguelo en el campo indicado de
   Registro.br.

4. Si tiene éxito aparece "¡RPKI habilitado con éxito!" y surge el campo
   **Parent response**. Copie el XML y péguelo en Krill, en
   *CAs-padre* → *Respuesta de la CA-padre*, con el nombre de CA-padre
   **`nicbr_ca`**.

5. Todavía en Registro.br, en *Configurar RPKI* → *Configurar publicación remota*.
   En Krill, en *Repositorio* → *Incluir un repositorio*, copie la *Solicitud del
   Publicador* y péguela ahí.

6. El campo se convierte en **Repository response**. Cópielo y péguelo en
   Krill, en *Repositorio* → *Respuesta del Repositorio*.

7. Al final, Krill debe mostrar los recursos recibidos del padre.

**Fíjese en lo que *no* hizo:** crear una ROA, o un objeto ASPA. Sus
recursos están certificados, pero nada dice quién puede anunciarlos. Ahí es donde
empieza la historia. (En beta, cuente con que los objetos tarden unos minutos en llegar a los
validadores cada vez que un paso le pida crear uno.)

---

## Paso 1 — Una base limpia

> **Estado:** etapa `none` (sin validación) · AS{{ATTACKER_ASN}} en silencio · peer en silencio · sin ROAs,
> sin ASPA.
>
> **Si el suyo difiere:** `./scripts/lab.sh step1-clean` silencia al AS{{ATTACKER_ASN}} y al
> peer *y* devuelve los dos observadores a BGP común. Si quedaron ROAs o un objeto ASPA
> de una ejecución anterior (verifique con `krillc roas list` y `krillc
> aspas list` en la terminal de Krill), la salida más simple es
> `./scripts/lab.sh reset`, luego `up`, y de nuevo la Preparación 2 - ejecutado desde la
> terminal de su propia computadora, no la del panel.

1. Asegúrese de que el laboratorio esté en su base:

   ```
   #./scripts/lab.sh step1-clean
   ```

2. Verifique que el prefijo del origen llega a los dos observadores, por los dos
   proveedores - y cuál prefieren:

   ```
   # Panel: haga clic en el recuadro observador 1, luego en Shell:
   #birdc show route table master4 all {{ORIGIN_V4}}
   # Panel: haga clic en el recuadro observador 2, luego en Shell:
   #bgpctl show rib {{ORIGIN_V4}}
   # O, desde la terminal de su computadora:
   #docker exec lab-observer1 birdc show route table master4 all {{ORIGIN_V4}}
   #docker exec lab-observer2 bgpctl show rib {{ORIGIN_V4}}
   ```

   ```
   {{ORIGIN_V4}}  unicast [provider_b_v4 ...] * (100) [AS{{ORIGIN_ASN}}i]
        bgp_path: {{PROVIDER_B_ASN}} {{ORIGIN_ASN}}
        bgp_local_pref: 100

                unicast [provider_a_v4 ...] (100) [AS{{ORIGIN_ASN}}i]
        bgp_path: {{PROVIDER_A_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}}
        bgp_local_pref: 100
   ```

   ```
   flags  vs destination          gateway          lpref   med aspath origin
   *>    N-? {{ORIGIN_V4}}          10.200.6.10       100     0 {{PROVIDER_B_ASN}} {{ORIGIN_ASN}} i
   *     N-? {{ORIGIN_V4}}          10.200.5.10       100     0 {{PROVIDER_A_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} i
   ```

   Dos caminos en cada observador: `{{PROVIDER_B_ASN}} {{ORIGIN_ASN}}` (seleccionado: la entrada preferida del origen, 2
   saltos) y `{{PROVIDER_A_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}}` (el respaldo, mantenido en la tabla pero de 4 saltos
   por los prepends). No tienen
   veredictos (BIRD no tiene communities; el `N-?` de OpenBGPD es solo "nada
   con qué comparar", y el panel muestra `-` en los dos) - porque **los
   observadores todavía no validan nada.** La insignia del encabezado del panel dice
   *validación: ninguna*.

3. **Eche un vistazo a cómo están configurados estos routers.** Abra los
   archivos base de los observadores (en la terminal de Comandos del laboratorio, en su propia terminal en la
   carpeta del laboratorio, o en su editor):

   ```
   #cat bird/observer1-none.conf
   #cat openbgpd/observer2-none.conf
   ```

   Va a encontrar BGP común: sesiones con los dos proveedores (y con el AS{{ATTACKER_ASN}},
   que está en silencio por ahora), y una política que acepta todo:

   ```
   template bgp CUSTOMER4 {
       local as OBSERVER1_ASN;
       ipv4 {
           import all;                 # <- BIRD: acepta lo que envíe el vecino
           export none;
           import table on;
       };
   }
   ```

   ```
   deny from any
   allow from any                      # <- OpenBGPD: la misma idea
   ```

   No hay sesión RTR con Routinator ni con FORT (los dos están corriendo, pero nadie
   los escucha), y nada que pueda distinguir una ROA de un agujero en la
   pared. Todo lo que la historia le hace a estos dos archivos, de aquí en adelante, es cómo se ve
   *desplegar la validación RPKI* en un router.

**En el camino:** los validadores, la CA y el repositorio ya existen,
y los recursos están certificados - y aun así, desde donde está un router, nada de
eso importa hasta que se le dice que escuche.

---

## Paso 2 — El secuestro ingenuo

> **Estado:** etapa `none` · AS{{ATTACKER_ASN}} en silencio (a punto de cambiar) · peer en silencio · sin
> ROAs, sin ASPA.
>
> **Si el suyo difiere:** `./scripts/lab.sh step1-clean`.

El AS{{ATTACKER_ASN}} anuncia el prefijo del origen como si fuera suyo.

1. Actívelo:

   ```
   #./scripts/lab.sh step2-hijack-simple
   ```

2. **Antes de mirar:** el camino del AS{{ATTACKER_ASN}} es solo `{{ATTACKER_ASN}}` - más corto que el
   legítimo `{{PROVIDER_B_ASN}} {{ORIGIN_ASN}}` (y que el respaldo por A). ¿Cuál espera que prefieran los observadores?
   ¿Hay *algo* que los observadores puedan usar para distinguir uno de otro?

3. Ahora mire:

   ```
   # Panel: haga clic en el recuadro observador 1, luego en Shell:
   #birdc show route table master4 all {{ORIGIN_V4}}
   # Panel: haga clic en el recuadro observador 2, luego en Shell:
   #bgpctl show rib {{ORIGIN_V4}}
   # O, desde la terminal de su computadora:
   #docker exec lab-observer1 birdc show route table master4 all {{ORIGIN_V4}}
   #docker exec lab-observer2 bgpctl show rib {{ORIGIN_V4}}
   ```

   ```
   {{ORIGIN_V4}}  unicast [attacker_v4 ...] * (100) [AS{{ATTACKER_ASN}}i]
        bgp_path: {{ATTACKER_ASN}}
        bgp_local_pref: 100
   ```

   ```
   *>    N-? {{ORIGIN_V4}}          10.200.8.10       100     0 {{ATTACKER_ASN}} i
   *     N-? {{ORIGIN_V4}}          10.200.6.10       100     0 {{PROVIDER_B_ASN}} {{ORIGIN_ASN}} i
   *     N-? {{ORIGIN_V4}}          10.200.5.10       100     0 {{PROVIDER_A_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} i
   ```

   El secuestro **ganó**: es la ruta seleccionada (`*`, `*>`) en los dos observadores -
   su camino es más corto (1 salto contra 2 y 4), y nada más lo distingue. En el panel,
   la insignia del atacante dice *secuestrando* y sus enlaces a los observadores se ponen
   **ámbar**: un observador está aceptando lo que anuncia. La tabla de *Veredictos*
   tiene filas nuevas rotuladas *AS{{ATTACKER_ASN}}*, sin veredictos, porque no hay
   validación.

**En el camino:** un secuestro con el ASN de origen equivocado - el truco más
viejo que existe, y para el que se inventaron las ROAs.

---

## Paso 3 — Entra el ROV, marcando lo que parece mal

> **Estado:** etapa `none` (a punto de cambiar) · AS{{ATTACKER_ASN}} haciendo el secuestro ingenuo ·
> peer en silencio · todavía sin ROAs (las va a crear aquí), sin ASPA.
>
> **Si el suyo difiere:** `./scripts/lab.sh step1-clean`, y luego
> `./scripts/lab.sh step2-hijack-simple`.

Este paso tiene dos mitades, en este orden: el **Origen publica** las ROAs, y
los **Observadores** la **validan** - por ahora, solo marcando.

### El Origen publica: crear las ROAs

> **Espere a que la CA reciba su certificado antes de crear ROAs.** Justo
> después de la preparación, la CA puede todavía no tener la clase de recursos del
> padre, y Krill acepta el comando sin crear nada. Verifique en
> *ROAs* que Krill ya muestra sus prefijos; si la lista está vacía, espere unos
> segundos o ejecute `docker exec lab-krill krillc bulk refresh`.

1. En Krill, vaya a la sección **ROAs** y haga clic en *Agregar ROA*.

2. Cree la ROA de IPv4:

   | campo | valor |
   |---|---|
   | ASN | {{ORIGIN_ASN}} |
   | Prefijo | {{ORIGIN_V4}} |
   | Longitud máxima | {{ORIGIN_V4_MAXLEN}} |

3. Cree la ROA de IPv6:

   | campo | valor |
   |---|---|
   | ASN | {{ORIGIN_ASN}} |
   | Prefijo | {{ORIGIN_V6}} |
   | Longitud máxima | {{ORIGIN_V6_MAXLEN}} |

   (¿Prefiere la línea de comandos? En la terminal del recuadro de Krill:
   `krillc roas update --add "{{ORIGIN_V4}}-{{ORIGIN_V4_MAXLEN}} => {{ORIGIN_ASN}}"`, y lo mismo con
   `"{{ORIGIN_V6}}-{{ORIGIN_V6_MAXLEN}} => {{ORIGIN_ASN}}"`. Si Krill dice que una ROA es un *duplicado*,
   ya está ahí.)

4. Haga que los validadores las recojan, y verifique que lo hicieron:

   ```
   #./scripts/lab.sh refresh
   #./scripts/validate.sh
   ```

   `validate.sh` imprime lo que Routinator validó (dos ROAs). En el panel,
   los recuadros de Routinator y FORT muestran `2 VRP`. Si todavía no aparece nada, **es
   cuestión de tiempo**: Krill tiene que publicar y los validadores tienen que releer
   (segundos en modo local, minutos en beta); ejecute `refresh` de nuevo.

Por ahora nada cambió para los routers: las ROAs están publicadas y
validadas, y **ningún router está escuchando a los validadores.** Mire los
observadores de nuevo si quiere - el secuestro sigue ganando.

### Los Observadores validan

1. Despliegue el ROV en los dos observadores, en su primera forma segura:

   ```
   #./scripts/lab.sh step3-rov-mark
   ```

2. **Vea de qué está hecho este despliegue.** Compare los archivos nuevos con la
   base que leyó en el Paso 1 (`diff` muestra exactamente lo que se agregó):

   ```
   #diff bird/observer1-none.conf bird/observer1-rov-mark.conf
   #diff openbgpd/observer2-none.conf openbgpd/observer2-rov-mark.conf
   ```

   Tres ideas, en los dos routers:

   **(a) Una sesión con un validador**, por la cual el router aprende las ROAs:

   ```
   protocol rpki routinator {                      # observer1 (BIRD)
       remote 172.30.0.20 port 3323;
       roa4 { table roa4_table; };
       roa6 { table roa6_table; };
       ...
   }
   ```

   ```
   rtr 172.30.0.50 {                               # observer2 (OpenBGPD)
       port 3323
   }
   ```

   **(b) Una prueba en cada ruta**, comparando su AS de origen (el *último* AS del
   camino) y su prefijo con las ROAs. BIRD la calcula en el filtro de importación y
   guarda el resultado en una large community, para que pueda leerlo después;
   OpenBGPD la calcula de forma nativa en el atributo `ovs` de la ruta:

   ```
   filter import_customer_v4 {                     # observer1 (BIRD)
       if roa_check(roa4_table, net, bgp_path.last) = ROA_INVALID then {
           bgp_large_community.add((OBSERVER1_ASN,1,0));
           bgp_local_pref = 10;                    # <- (c) una acción: pierde contra cualquier ruta válida
       } else if roa_check(roa4_table, net, bgp_path.last) = ROA_VALID then
           bgp_large_community.add((OBSERVER1_ASN,1,2));
       else
           bgp_large_community.add((OBSERVER1_ASN,1,1));
       accept;
   }
   ```

   **(c) Una acción sobre el resultado.** En esta etapa la acción es solo
   *bajar la preferencia* de una ruta inválida - no se rechaza nada:

   ```
   match from any ovs invalid    set { localpref 10 }      # observer2 (OpenBGPD)
   ```

   > **Esto no es cosa de BIRD ni de OpenBGPD.** Cualquier router que soporte ROV
   > tiene las mismas tres piezas, con distinta sintaxis: una sesión con un
   > validador (RTR), una política que compara el estado de validación, y una
   > acción. En Cisco IOS XR es una `route-policy` que prueba `validation-state`;
   > en Junos, una `policy-statement` que compara `validation-database`; en
   > Huawei, `if-match rpki` en una route-policy - consulte la
   > documentación de su plataforma para la sintaxis exacta. Aquí se usan BIRD y OpenBGPD
   > porque son libres y fáciles de correr en contenedores, no porque sean
   > lo que va a encontrar en el trabajo: lo que se traslada es la anatomía.
   >
   > Si prefiere escribir la configuración usted mismo en vez de leerla: parta
   > de `bird/observer1-none.conf`, agregue las piezas de arriba, guarde el resultado como
   > un archivo nuevo en `bird/`, y cárguelo con `docker exec lab-observer1 birdc
   > 'configure "/etc/bird-lab/your-file.conf"'`. El script solo le ahorra
   > el tipeo.

3. Ahora mire las rutas de nuevo:

   ```
   # Panel: haga clic en el recuadro observador 1, luego en Shell:
   #birdc show route table master4 all {{ORIGIN_V4}}
   # Panel: haga clic en el recuadro observador 2, luego en Shell:
   #bgpctl show rib {{ORIGIN_V4}}
   # O, desde la terminal de su computadora:
   #docker exec lab-observer1 birdc show route table master4 all {{ORIGIN_V4}}
   #docker exec lab-observer2 bgpctl show rib {{ORIGIN_V4}}
   ```

   ```
   {{ORIGIN_V4}}  unicast [attacker_v4 ...] (100) [AS{{ATTACKER_ASN}}i]
        bgp_path: {{ATTACKER_ASN}}
        bgp_local_pref: 10
        bgp_large_community: ({{OBSERVER1_ASN}}, 1, 0)                   <- ROV Invalid
   ```

   ```
   *>    V-? {{ORIGIN_V4}}          10.200.6.10       100     0 {{PROVIDER_B_ASN}} {{ORIGIN_ASN}} i
   *     V-? {{ORIGIN_V4}}          10.200.5.10       100     0 {{PROVIDER_A_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} i
   *     !-? {{ORIGIN_V4}}          10.200.8.10        10     0 {{ATTACKER_ASN}} i
   ```

   El secuestro sigue en la tabla - visible, no desaparecido - pero ahora lleva
   **ROV Invalid** y un `local_pref` de 10, así que pierde contra los caminos
   legítimos, y el del Proveedor B vuelve a ser la ruta seleccionada. La insignia del encabezado dice
   *ROV: marcando*, y los enlaces del atacante se ponen **rojos**: está anunciando,
   y los dos observadores lo están marcando. Todo lo que tenía que verificar está
   bien: el secuestro está marcado, los caminos legítimos son `Valid`, y nada
   legítimo salió perjudicado. **Ese es el sentido de la etapa de marcado** - puede
   ver qué *haría* la verificación antes de dejar que rechace algo.

   **Aquí es donde el ROV se queda por el resto de la historia - marcando, no
   descartando.** Un router que solo marca igual usa una ruta inválida cuando
   es lo mejor que tiene, así que marcar solo no es el final del trabajo: es el
   ensayo. Va a ver cómo es descartar de verdad, en producción - para el ROV y
   el ASPA juntos, a la vez - en el Paso 8, una vez que las dos verificaciones
   hayan tenido su turno para demostrar lo que hacen de esta forma.

### Cómo leer los veredictos

Los dos observadores los muestran de forma distinta:

- **observer1 (BIRD)** no tiene un atributo de validación por ruta, así que sus
  filtros registran cada veredicto en una large community:

  | community | significado | | community | significado |
  |---|---|---|---|---|
  | ({{OBSERVER1_ASN}},1,0) | ROV Invalid | | ({{OBSERVER1_ASN}},2,0) | ASPA Invalid |
  | ({{OBSERVER1_ASN}},1,1) | ROV NotFound | | ({{OBSERVER1_ASN}},2,1) | ASPA Unknown |
  | ({{OBSERVER1_ASN}},1,2) | ROV Valid | | ({{OBSERVER1_ASN}},2,2) | ASPA Valid |

- **observer2 (OpenBGPD)** calcula los dos de forma nativa. La columna `vs` es el
  par **ovs-avs**: estado de validación de origen, luego estado de validación ASPA,
  cada uno `V` (válido), `!` (inválido), o `N`/`?` (not-found / unknown).
  Así, `V-!` es ROV Valid y ASPA Invalid. (Todavía no hay verificación ASPA
  desplegada, así que la segunda mitad es `?` por ahora.)

**En el camino:** de qué está hecho "desplegar ROV" - una sesión RTR, una
prueba en cada ruta, y una acción sobre el resultado - y cómo llegan los
objetos nuevos a los routers: Krill publica, los validadores releen, los
routers reciben el cambio por RTR. Acaba de ver cada salto.

---

## Paso 4 — El camino falsificado

> **Estado:** etapa `rov-mark` · AS{{ATTACKER_ASN}} haciendo el secuestro ingenuo (marcado,
> perdiendo) · peer en silencio · ROAs para los dos prefijos · sin ASPA.
>
> **Si el suyo difiere:** `./scripts/lab.sh step4-hijack-posrov` - también se
> asegura de que existan las ROAs y vuelve a poner a los observadores en
> `rov-mark`.

El AS{{ATTACKER_ASN}} lee la misma documentación que usted. El ROV solo mira el **último** AS
del camino - entonces, ¿y si el último AS fuera el correcto?

1. Cambie el AS{{ATTACKER_ASN}} al ataque del camino falsificado:

   ```
   #./scripts/lab.sh step4-hijack-posrov
   ```

   El AS{{ATTACKER_ASN}} ahora anuncia el camino `{{ATTACKER_ASN}} {{ORIGIN_ASN}}`: como si hubiera recibido el
   prefijo directamente del origen real.

   **Esa relación es mentira.** El AS{{ATTACKER_ASN}} no tiene ninguna sesión BGP - ni peering, ni
   tránsito, nada - con el AS{{ORIGIN_ASN}}: ni siquiera están conectados. La
   adyacencia `{{ATTACKER_ASN}} {{ORIGIN_ASN}}` existe solo porque la configuración del AS{{ATTACKER_ASN}} *la escribe en
   el camino*. Vea cómo lo hace:

   ```
   # Panel: haga clic en el recuadro attacker, luego en Shell:
   #cat /etc/bird.conf
   # O, desde la terminal de su computadora:
   #cat bird/attacker-posrov.conf
   ```

   Encuentre los filtros `forge_export`: `bgp_path.prepend(ORIGIN_ASN)` pone el
   número del origen en el camino *antes* de que el router agregue el suyo al exportar -
   esa es toda la falsificación. Compárelo con `bird/attacker-simple.conf` (sin
   filtro, así que el camino es solo `{{ATTACKER_ASN}}`), y verifique que ninguno de los dos archivos tiene una
   sesión con el origen: solo los dos observadores.

2. **Antes de mirar:** el ROV por ahora solo marca, no descarta nada - pero el
   secuestro ingenuo igual quedó marcado Invalid y perdió la carrera. ¿Este
   camino falsificado va a quedar marcado de la misma forma?

3. Mire:

   ```
   # Panel: haga clic en el recuadro observador 2, luego en Shell:
   #bgpctl show rib {{ORIGIN_V4}}
   # O, desde la terminal de su computadora:
   #docker exec lab-observer2 bgpctl show rib {{ORIGIN_V4}}
   ```

   ```
   flags  vs destination          gateway          lpref   med aspath origin
   *>    V-? {{ORIGIN_V4}}          10.200.8.10       100     0 {{ATTACKER_ASN}} {{ORIGIN_ASN}} i
   *m    V-? {{ORIGIN_V4}}          10.200.6.10       100     0 {{PROVIDER_B_ASN}} {{ORIGIN_ASN}} i
   *     V-? {{ORIGIN_V4}}          10.200.5.10       100     0 {{PROVIDER_A_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} i
   ```

   No quedó marcado. El ROV dice `Valid` - el camino termina en {{ORIGIN_ASN}},
   que es exactamente lo que autoriza la ROA - así que recibe el `local_pref`
   completo (100) igual que cualquier ruta legítima, y es la seleccionada. Los
   enlaces del atacante en el panel se ponen **ámbar**: ya no rojos, porque el
   ROV no tiene nada que marcar. Tres caminos, todos "válidos", uno de ellos
   una mentira, y *nada de lo que desplegó hasta ahora puede decir cuál*.

   > El camino falsificado (`{{ATTACKER_ASN}} {{ORIGIN_ASN}}`, 2 saltos) empata con el del Proveedor B (`{{PROVIDER_B_ASN}} {{ORIGIN_ASN}}`, también 2),
   > y el atacante gana el empate por un criterio de desempate (su router ID resulta
   > ser el más bajo); el respaldo del Proveedor A tiene 4 saltos y nunca entra en la carrera.
   > Eso es secundario: lo importante es que el ROV le entregó tres rutas
   > igualmente válidas en apariencia y ninguna forma de elegir entre ellas.

**En el camino:** ¿puede la validación de origen distinguir dos caminos para el mismo
prefijo, cuando el origen es el mismo y una ROA coincide? Ahora lo sabe: no puede.
Solo mira el último AS.

---

## Paso 5 — Entra el ASPA, también marcando primero

> **Estado:** etapa `rov-mark` · AS{{ATTACKER_ASN}} falsificando el camino · peer en silencio · ROAs para
> los dos prefijos · todavía sin ASPA (lo va a crear aquí).
>
> **Si el suyo difiere:** `./scripts/lab.sh step3-rov-mark` y
> `./scripts/lab.sh step4-hijack-posrov`; si ya existe un objeto ASPA,
> `krillc aspas remove --customer AS{{ORIGIN_ASN}}` en la terminal de Krill.

La misma forma que el Paso 3: el **Origen publica** un objeto ASPA, y luego los
**Observadores lo validan** - con la misma forma segura y de solo marcado que
usó el ROV.

### El Origen publica: crear el objeto ASPA

Krill 0.16 todavía **no** tiene el ASPA en la interfaz web - se gestiona por la
línea de comandos (la interfaz está en camino en la próxima versión).

1. En el panel, haga clic en el recuadro **Krill** y luego en el botón **Terminal (krillc)**.
   (O, en su propia terminal: `docker exec -it lab-krill bash`.)

2. Vea que todavía no hay ningún ASPA:

   ```
   #krillc aspas list
   ```

3. Cree el objeto ASPA declarando qué proveedores pueden propagar rutas del
   AS{{ORIGIN_ASN}}. Por el bien de la historia, liste **solo al Proveedor A** por ahora - va a
   ver por qué en el próximo paso:

   ```
   #krillc aspas add --aspa "AS{{ORIGIN_ASN}} => AS{{PROVIDER_A_ASN}}"
   ```

4. Verifíquelo, y haga que los validadores lo recojan:

   ```
   #krillc aspas list
   #./scripts/lab.sh refresh
   ```

> **Sobre la notación.** La sintaxis de Krill acepta una restricción por
> familia de direcciones (`AS{{PROVIDER_A_ASN}}(v4)`), pero la versión final del perfil ASPA en el
> IETF **eliminó** esa opción: un único objeto ASPA se aplica a IPv4 e
> IPv6 a la vez. No use los calificadores `(v4)`/`(v6)`.
>
> **Un objeto por AS cliente.** El RFC exige exactamente un objeto ASPA
> por ASN cliente, listando *a todos* los proveedores. `krillc aspas add` reemplaza
> el objeto entero (así que es seguro repetirlo); para cambiar la lista, use
> `krillc aspas update`.
>
> **Ojo con un flag.** Sin `--enable-aspa`, Routinator simplemente
> ignora los objetos ASPA. Es el error número uno al armar un laboratorio
> como este; aquí ya está activado.

Igual que con las ROAs, todavía no cambia nada para los routers: el objeto está publicado,
y ningún router está verificando caminos.

### Los Observadores validan

1. Despliegue la verificación ASPA en los dos observadores - el ROV sigue solo marcando:

   ```
   #./scripts/lab.sh step5-aspa-mark
   ```

2. **Compare con la etapa que acaba de dejar** (`rov-mark`):

   ```
   #diff bird/observer1-rov-mark.conf bird/observer1-aspa-mark.conf
   #diff openbgpd/observer2-rov-mark.conf openbgpd/observer2-aspa-mark.conf
   ```

   Las mismas tres ideas, esta vez para caminos:

   **(a) El validador ahora también entrega objetos ASPA.** El ASPA solo viaja en
   RTR versión 2, así que cada router lo pide:

   ```
   aspa table aspa_table;                          # observer1 (BIRD)
   protocol rpki routinator {
       ...
       aspa { table aspa_table; };                 # el ASPA solo existe en RTR versión 2
   }
   ```

   ```
   rtr 172.30.0.50 {                               # observer2 (OpenBGPD)
       port 3323
       min-version 2                               # sin esto, nunca llega ningún ASPA
   }
   ```

   **(b) Una prueba en cada camino**, y **(c) una acción sobre el resultado** - en esta
   etapa, solo marcar:

   ```
   case aspa_check_upstream(aspa_table) {          # observer1 (BIRD)
       ASPA_INVALID: {
           bgp_large_community.add((OBSERVER1_ASN,2,0));
           bgp_local_pref = 20;                    # pierde contra un camino válido
       }
       ASPA_VALID: {
           bgp_large_community.add((OBSERVER1_ASN,2,2));
           bgp_local_pref = 200;                   # prefiere un camino comprobado
       }
       ASPA_UNKNOWN: bgp_large_community.add((OBSERVER1_ASN,2,1));
   }
   ```

   ```
   neighbor 10.200.5.10 {                          # observer2 (OpenBGPD)
       remote-as $provider_a_asn
       role provider                               # <- lo que activa la verificación ASPA
   }
   ...
   match from any avs invalid    set { localpref 20 }      # pierde contra un camino válido
   match from any avs valid      set { localpref 200 }     # prefiere un camino comprobado
   ```

   > **¿Por qué "upstream"?** El observador trata a cada vecino como su
   > *cliente*: para las rutas que vienen de un cliente, se aplica el algoritmo
   > más estricto - cada salto del camino tiene que ser un par
   > cliente→proveedor autorizado. BIRD lo pide por nombre
   > (`aspa_check_upstream`); OpenBGPD lo selecciona mediante el rol RFC
   > 9234 de la sesión. También es la verificación que detecta las fugas de ruta - va a conocer una
   > en el Paso 7. El ejercicio extra A lo desarma, y muestra qué cambia si
   > se pide en cambio el algoritmo *downstream*.
   >
   > La verificación ASPA es más nueva que el ROV, y el soporte en plataformas
   > comerciales todavía está llegando. Donde existe, tiene la misma anatomía que el
   > despliegue de ROV que vio en el Paso 3.

3. Mire las rutas:

   ```
   # Panel: haga clic en el recuadro observador 2, luego en Shell:
   #bgpctl show rib {{ORIGIN_V4}}
   # O, desde la terminal de su computadora:
   #docker exec lab-observer2 bgpctl show rib {{ORIGIN_V4}}
   ```

   ```
   *>    V-V {{ORIGIN_V4}}          10.200.5.10       200     0 {{PROVIDER_A_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} i
   *     V-! {{ORIGIN_V4}}          10.200.8.10        20     0 {{ATTACKER_ASN}} {{ORIGIN_ASN}} i
   *     V-! {{ORIGIN_V4}}          10.200.6.10        20     0 {{PROVIDER_B_ASN}} {{ORIGIN_ASN}} i
   ```

   El camino falsificado ahora es **ASPA Invalid** - el salto `{{ORIGIN_ASN}} → {{ATTACKER_ASN}}` no está
   autorizado, ya que solo {{PROVIDER_A_ASN}} figura en la lista. Sigue visible, pero con un
   `local_pref` de 20 pierde contra el camino del Proveedor A (`V-V`, 200). Los
   enlaces del atacante se ponen **rojos** otra vez, y la insignia dice *ROV: marcando ·
   ASPA: marcando*.

   Pero dos rutas llevan `V-!` - no una. Mire de cerca la segunda: es la del
   **Proveedor B**, la entrada preferida del propio origen, la de la
   ingeniería de tráfico del Paso 1. El objeto ASPA que acaba de crear solo
   lista al Proveedor A, así que el ASPA también llama inválido al camino del
   Proveedor B - y lo que quedó seleccionado en su lugar es el camino del
   Proveedor A, el *respaldo*, el que el origen alargó a propósito con sus
   prepends. Como todavía no se descarta nada, puede ver este error antes de
   que le cueste algo: guarde ese pensamiento para el próximo paso.

**En el camino:** el veredicto ASPA que el ROV nunca podría dar - el camino
mismo es lo que está mal, aunque el origen sea correcto - y un recordatorio
de por qué marcar corre antes que descartar: le permitió detectar un error en
su propio objeto ASPA antes de que tirara nada abajo.

---

## Paso 6 — Se olvidó de un proveedor

> **Estado:** etapa `aspa-mark` · AS{{ATTACKER_ASN}} falsificando el camino · peer en silencio · ROAs para
> los dos prefijos · ASPA listando solo al Proveedor A.
>
> **Si el suyo difiere:** `./scripts/lab.sh step5-aspa-mark`, y en la terminal
> de Krill `krillc aspas add --aspa "AS{{ORIGIN_ASN}} => AS{{PROVIDER_A_ASN}}"` (esto reemplaza el
> objeto por exactamente esa lista), luego `./scripts/lab.sh refresh`.

La ruta que notó al final del paso anterior - la del Proveedor B, marcada
ASPA Invalid junto con la falsificada - es un camino *legítimo*, **justamente
el que el origen prefiere**, degradado sin mejor razón que un objeto
incompleto. Los observadores se quedan usando el camino de respaldo, el que
el origen alargó a propósito con sus prepends: la ingeniería de tráfico del
origen, deshecha por un ASPA incompleto. Una vez que esta etapa descarte en
lugar de marcar (Paso 8), este va a ser el día en que el tráfico que solía
llegar por esa interfaz deja de llegar, y alguien empieza a preguntar por qué.
(Este laboratorio no tiene plano de datos, así que no puede ver cómo se
detiene el tráfico; puede ver cómo se desploma la preferencia de la ruta,
que es lo mismo dicho de otra forma.)

1. Arregle el objeto:

   ```
   #krillc aspas update --customer AS{{ORIGIN_ASN}} --add "AS{{PROVIDER_B_ASN}}"
   #krillc aspas list
   #./scripts/lab.sh refresh
   ```

2. Verifique los observadores:

   ```
   # Panel: haga clic en el recuadro observador 2, luego en Shell:
   #bgpctl show rib {{ORIGIN_V4}}
   # O, desde la terminal de su computadora:
   #docker exec lab-observer2 bgpctl show rib {{ORIGIN_V4}}
   ```

   ```
   *>    V-V {{ORIGIN_V4}}          10.200.6.10       200     0 {{PROVIDER_B_ASN}} {{ORIGIN_ASN}} i
   *     V-V {{ORIGIN_V4}}          10.200.5.10       200     0 {{PROVIDER_A_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} i
   *     V-! {{ORIGIN_V4}}          10.200.8.10        20     0 {{ATTACKER_ASN}} {{ORIGIN_ASN}} i
   ```

   Los dos caminos legítimos volvieron a `V-V` y `local_pref` 200, y el
   Proveedor B - la entrada preferida del origen - vuelve a ser el
   seleccionado: una vez empatados en preferencia, gana su camino más corto.
   El falsificado sigue degradado (`V-!`, 20), y el AS{{ATTACKER_ASN}} - que sigue
   anunciando - sigue derrotado. Note que el arreglo no involucró al
   AS{{ATTACKER_ASN}} en absoluto: el objeto ASPA describe *sus* relaciones, y todo
   lo que las contradiga queda afuera.

3. BIRD recogió el cambio por sí solo, sin que nadie tocara el router,
   porque sus sesiones están configuradas con `import table on` y `rpki reload
   on`. Para forzar la revalidación a mano:

   ```
   # Panel: haga clic en el recuadro observador 1, luego en Shell:
   #birdc reload in provider_b_v4
   # O, desde la terminal de su computadora:
   #docker exec lab-observer1 birdc reload in provider_b_v4
   ```

   (`./scripts/lab.sh step6-add-provider-b` hace exactamente este arreglo -
   es el comando para saltar directamente al estado de este paso más
   adelante, desde cualquier punto de la historia, sin volver a escribir el
   comando `krillc` a mano.)

**En el camino:** qué pasa cuando un objeto ASPA se olvida de un proveedor real -
la mitad de Internet empieza a ver las rutas de ese proveedor como inválidas - y cómo
se propaga un arreglo: republicar, revalidar, sin tocar ningún router.

Deje el AS{{ATTACKER_ASN}} corriendo. Ahora es inofensivo, y va a ser un recordatorio útil en el
panel de lo que se está manteniendo afuera.

---

## Paso 7 — El peer filtra (y el ASPA detecta lo que el ROV no puede)

> **Estado:** etapa `aspa-mark` · AS{{ATTACKER_ASN}} falsificando el camino (marcado,
> perdiendo) · peer en silencio · ROAs para los dos prefijos · ASPA listando
> a los Proveedores A y B.
>
> **Si el suyo difiere:** `./scripts/lab.sh step6-add-provider-b` - deja listo
> todo lo que este paso necesita (ASPA listando a los dos proveedores, peer
> en silencio) sin la fuga.

Este no es el ataque de nadie. El peer - una red legítima - tiene un enlace de
peering privado con el origen, así que *aprende* los prefijos del origen. Un enlace de
peering es bilateral: lo que el peer aprende ahí no es para su propio proveedor.
Entonces alguien edita una configuración...

1. Active la fuga:

   ```
   #./scripts/lab.sh step7-leak-on
   ```

   El peer ahora re-anuncia al Proveedor A lo que aprendió del origen.
   No se falsifica nada - el peer dice la verdad sobre de dónde
   vino la ruta. En el panel, la insignia del peer dice *filtrando*.

2. **Antes de mirar:** el Proveedor A ahora tiene dos rutas para el prefijo
   del origen - la del propio origen, y la del peer. ¿Cuál le pasa el Proveedor A
   a los observadores? Y una vez que llegue, si todavía solo se está *marcando*
   lo que parece inválido, ¿va a poder verla?

3. Mire primero el Proveedor A:

   ```
   # Panel: haga clic en el recuadro Proveedor A, luego en Shell:
   #birdc show route {{ORIGIN_V4}} all
   # O, desde la terminal de su computadora:
   #docker exec lab-provider-a birdc show route {{ORIGIN_V4}} all
   ```

   ```
   {{ORIGIN_V4}}  unicast [customer_peer_v4 ...] * (100) [AS{{ORIGIN_ASN}}i]
        bgp_path: {{PEER_ASN}} {{ORIGIN_ASN}}
        bgp_local_pref: 100
                unicast [customer_v4 ...] (100) [AS{{ORIGIN_ASN}}i]
        bgp_path: {{ORIGIN_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}}
        bgp_local_pref: 100
   ```

   El Proveedor A solo pasa su *mejor* ruta, y no se configuró nada especial para
   que la del peer ganara: simplemente es **más corta** - 2 saltos
   contra los 3 del propio origen. Los prepends que hicieron del Proveedor A el
   *respaldo* también hicieron irresistible una fuga a través de él. (Eso es típico: una
   ruta filtrada gana porque la ingeniería de tráfico de alguien hizo que el camino
   honesto pareciera peor. Vea `bird/provider-a.conf` - ahí no hay ninguna política
   en absoluto.)

4. Ahora los observadores:

   ```
   # Panel: haga clic en el recuadro observador 2, luego en Shell:
   #bgpctl show rib {{ORIGIN_V4}}
   # O, desde la terminal de su computadora:
   #docker exec lab-observer2 bgpctl show rib {{ORIGIN_V4}}
   ```

   ```
   *>    V-V {{ORIGIN_V4}}          10.200.6.10       200     0 {{PROVIDER_B_ASN}} {{ORIGIN_ASN}} i
   *     V-! {{ORIGIN_V4}}          10.200.8.10        20     0 {{ATTACKER_ASN}} {{ORIGIN_ASN}} i
   *     V-! {{ORIGIN_V4}}          10.200.5.10        20     0 {{PROVIDER_A_ASN}} {{PEER_ASN}} {{ORIGIN_ASN}} i
   ```

   **El camino propio del Proveedor A ya desapareció** - dejó de anunciarlo en el
   momento en que eligió como mejor el camino más corto del peer, y eso no tiene
   nada que ver con lo que los observadores hacen con lo que reciben. Lo que llega
   desde el Proveedor A en su lugar es el camino filtrado, `{{PROVIDER_A_ASN}} {{PEER_ASN}} {{ORIGIN_ASN}}`
   - y como marcar nunca saca nada de la tabla, puede mirarlo de frente. Dos cosas
   para notar:

   - **ROV Valid.** Claro - el origen realmente es {{ORIGIN_ASN}}. No hay nada
     falsificado. *Una fuga nunca puede ser detectada por el ROV*: no miente sobre quién
     originó el prefijo, miente sobre la *forma del camino*.
   - **ASPA Invalid.** El salto `{{ORIGIN_ASN}} → {{PEER_ASN}}` nunca fue autorizado: el
     objeto ASPA del origen lista a los Proveedores A y B, y el peer no es ninguno de los dos.

   El enlace del peer en el panel se pone **rojo**. El camino del Proveedor B sigue
   siendo el seleccionado (`V-V`, 200) - no necesita ninguna ayuda del ASPA para
   ganar, porque además es el más corto - pero el daño es real: el origen perdió
   su *respaldo*, y los demás clientes del Proveedor A ahora están enviando su
   tráfico al origen a través del peer.

**En el camino:** una fuga de ruta no es que nadie falsifique nada - es una ruta
que cruza un límite que nunca debía cruzar - y es un veredicto que el ROV no
puede dar por estructura, porque el origen al final del camino está diciendo la
verdad. El ASPA la detecta por la misma razón que detectó la falsificación del
Paso 4: un salto no autorizado, esté donde esté en el camino.

---

## Paso 8 — Desplegando de verdad: descartar

> **Estado:** etapa `aspa-mark` · AS{{ATTACKER_ASN}} falsificando el camino (marcado,
> perdiendo) · el peer filtrando (marcado, perdiendo) · ROAs para los dos
> prefijos · ASPA listando a los Proveedores A y B.
>
> **Si el suyo difiere:** `./scripts/lab.sh step7-leak-on` - deja listo todo
> lo que este paso necesita, fuga incluida.

Cada ruta inválida que vio hasta ahora se quedó en la tabla, degradada pero
visible - a propósito, para que pudiera mirar exactamente qué decidió cada
verificación antes de confiarle algo. **Un router real no se queda ahí.**
Marcar una ruta como inválida y seguir usándola cuando no aparece nada mejor
no es para lo que sirven el ROV ni el ASPA; los dos protegen algo recién
cuando una ruta inválida se *rechaza* de verdad. Este es el paso donde eso
pasa - para las dos verificaciones, juntas, de la misma forma en que
configuraría un router de producción desde el principio.

1. Cambie los dos observadores a descartar:

   ```
   #./scripts/lab.sh step8-drop
   ```

2. Compare la etapa que acaba de dejar con esta - el cambio es una línea de
   política por verificación, en cada router:

   ```
   #diff bird/observer1-aspa-mark.conf bird/observer1-aspa-drop.conf
   #diff openbgpd/observer2-aspa-mark.conf openbgpd/observer2-aspa-drop.conf
   ```

   ```
       if roa_check(roa4_table, net, bgp_path.last) = ROA_INVALID then
           reject "ROV Invalid: ", net, " origin AS", bgp_path.last;   # observer1 (BIRD)
       ...
       ASPA_INVALID: reject "ASPA Invalid: ", net, " AS_PATH ", bgp_path;
   ```

   ```
   deny from any ovs invalid                               # observer2 (OpenBGPD)
   deny from any avs invalid
   ```

3. Mire las rutas de nuevo:

   ```
   # Panel: haga clic en el recuadro observador 2, luego en Shell:
   #bgpctl show rib {{ORIGIN_V4}}
   # O, desde la terminal de su computadora:
   #docker exec lab-observer2 bgpctl show rib {{ORIGIN_V4}}
   ```

   ```
   *>    V-V {{ORIGIN_V4}}          10.200.6.10       200     0 {{PROVIDER_B_ASN}} {{ORIGIN_ASN}} i
   ```

   **Desaparecieron dos rutas, no una.** El camino falsificado del AS{{ATTACKER_ASN}} se
   fue, como era de esperar. También se fue la entrada que antes estaba bajo el
   Proveedor A - el camino filtrado que acaba de inspeccionar. No se perdió; BIRD
   guarda lo que rechazó:

   ```
   # Panel: haga clic en el recuadro observador 1, luego en Shell:
   #birdc show route table master4 filtered {{ORIGIN_V4}}
   # O, desde la terminal de su computadora:
   #docker exec lab-observer1 birdc show route table master4 filtered {{ORIGIN_V4}}
   ```

   La insignia ahora dice *ROV + ASPA: descartando*. Note lo que descartar **no**
   arregló: el camino propio y legítimo del Proveedor A sigue sin aparecer por
   ningún lado, porque el Proveedor A mismo sigue anunciando la ruta filtrada *en
   lugar de* la suya - y ninguna política en los observadores puede hacer que el
   Proveedor A propague algo que no está enviando. El ASPA protege a los
   observadores de *usar* la fuga; solo que el peer arregle su política de
   exportación detiene la fuga en la fuente. Eso viene a continuación.

**En el camino:**

- **Marcar versus descartar.** Los mismos veredictos de los Pasos 3, 5 y 7 - lo
  que cambió fue la política. Marcar es cómo se despliega una verificación sin
  romper nada; descartar es *para qué* sirve la verificación, y lo que convierte
  un diagnóstico en una defensa.
- **Descartar no repara el daño río arriba.** Solo controla lo que los propios
  observadores aceptan. Que el Proveedor A propague la fuga es un problema
  aparte, que se arregla en la fuente, no en los observadores.
- **De aquí en adelante, las dos verificaciones siguen descartando.** Un router
  que aprendió a rechazar rutas inválidas no vuelve atrás.

---

## Paso 9 — Guardar todo

> **Estado:** etapa `aspa-drop` · AS{{ATTACKER_ASN}} falsificando el camino (derrotado) · el peer
> filtrando · ROAs para los dos prefijos · ASPA listando a los Proveedores A y B.

1. Detenga la fuga:

   ```
   #./scripts/lab.sh step9-leak-off
   ```

   El propio camino del Proveedor A vuelve en los dos observadores.

2. Si va a seguir con los ejercicios extra, silencie también al AS{{ATTACKER_ASN}} - van a ser
   más fáciles de leer sin él:

   ```
   #./scripts/lab.sh step9-hijack-off
   ```

Los observadores quedan completamente desplegados - ROV y ASPA los dos descartando - que es
donde termina un router real. (`./scripts/lab.sh step1-clean` es el camino de vuelta
al comienzo de todo: silencia al AS{{ATTACKER_ASN}} y al peer, *y* saca la validación
de los observadores.)

---

## Repaso - qué detectó qué, y qué respondió la historia

| Ataque | ROV | ASPA |
|---|---|---|
| Secuestro ingenuo (AS_PATH `{{ATTACKER_ASN}}`) | **lo detecta** (origen equivocado) | nada que verificar (camino de un solo AS) |
| Camino falsificado (AS_PATH `{{ATTACKER_ASN}} {{ORIGIN_ASN}}`) | **engañado** (el origen parece correcto) | **lo detecta** (el salto `{{ORIGIN_ASN}} → {{ATTACKER_ASN}}` no está autorizado) |
| Fuga de ruta (AS_PATH `{{PROVIDER_A_ASN}} {{PEER_ASN}} {{ORIGIN_ASN}}`) | **no la ve** (el origen es genuino) | **la detecta** (el salto `{{ORIGIN_ASN}} → {{PEER_ASN}}` no está autorizado) |

Ninguno es redundante. El ROV detiene a los atacantes que mienten sobre el origen; el ASPA detiene
los caminos que no podrían haber ocurrido. Y el origen tiene que hacer su parte: un ASPA
que se olvida de un proveedor real (Paso 6) es una caída propia.

En el camino, la historia respondió en silencio preguntas que este laboratorio antes hacía un
ejercicio a la vez:

- **¿En qué consiste realmente "desplegar validación" en un router?** Una
  sesión con un validador, una prueba en cada ruta o camino, y una acción sobre el
  resultado - las mismas tres piezas para el ROV (Paso 3) y el ASPA (Paso 5), en el router
  de cualquier fabricante.
- **¿Por qué marcar primero y descartar después - y por qué descartar, en definitiva?** Marcar le permite
  ver qué haría una verificación antes de confiar en ella, y fue lo que le permitió detectar
  su propio objeto ASPA incompleto en el Paso 6 antes de que tirara algo abajo; descartar es lo que
  hacen los routers reales, y lo que hace que la verificación proteja algo - el Paso 8 activa las
  dos verificaciones a la vez, de la forma en que se configura un router de producción desde el principio.
- **¿Puede el ROV distinguir dos caminos para el mismo prefijo?** No (Paso 4).
- **¿Cómo se ve un secuestro con el ASN de origen equivocado?** Paso 2, y cómo
  lo detiene el ROV en el Paso 3.
- **¿Qué pasa cuando un ASPA se olvida de un proveedor real?** Paso 6.
- **¿Se propaga un arreglo por sí solo?** BIRD revalida por sí mismo; los objetos
  necesitan una republicación y una revalidación para llegar (Pasos 3, 5 y 6).
- **¿Coinciden las dos pilas independientes?** Cada paso muestra las dos, y
  coinciden en todo lo que la historia mira - el Ejercicio extra A muestra dónde no coinciden.
- **¿Qué es una fuga de ruta, y por qué el ROV no la puede ver?** El Paso 7 la
  muestra; el Paso 8 muestra qué arregla descartar, y qué no.

Cuatro temas no cupieron en la historia, y viven en los extras de abajo: en qué se diferencian los algoritmos
upstream y downstream (y el `role` que selecciona uno),
un secuestro que acierta el ASN pero se equivoca en la longitud, una mirada dentro de los
validadores y de RTR, y los veredictos **NotFound** y **Unknown** - los de "sin
opinión" que todavía no conoció, porque la historia nunca dejó un prefijo
sin cubrir.

---

## Ejercicios extra

Los extras asumen que terminó la historia (los observadores en `aspa-drop`, el
peer en silencio, `step9-hijack-off` ejecutado) con objetos para los dos prefijos y un
ASPA que lista a los Proveedores A y B. Cada uno dice qué etapa necesita; los comandos
`step` llevan a los dos observadores ahí de una sola vez.

### A. Upstream, downstream, y el rol que decide

*Etapa:* `step5-aspa-mark`.

En `bird/observer1-aspa-mark.conf` la verificación ASPA es:

```
case aspa_check_upstream(aspa_table) { ... }
```

El observador trata a cada vecino como su **cliente**. Para las rutas que vienen de
un cliente, se aplica el *Algoritmo para Caminos Upstream* - el más estricto:
cada salto del camino tiene que ser una relación cliente→proveedor autorizada.
Esta es la verificación que detecta las fugas de ruta. Si la sesión fuera con un proveedor
o un peer, la llamada correcta sería `aspa_check_downstream()`, que es más
permisiva. BIRD ofrece las dos.

OpenBGPD lo hace con un **rol** de sesión (RFC 9234). Mire
`openbgpd/observer2-aspa-mark.conf`:

```
neighbor 10.200.5.10 {
    remote-as $provider_a_asn
    role provider
}
```

OpenBGPD solo realiza la verificación ASPA en una sesión que tiene un rol, y
**el rol decide qué algoritmo ASPA corre**. `role provider` dice que el sistema local
es el upstream de los proveedores - las rutas llegan de un cliente - y eso
selecciona el algoritmo *upstream*, el mismo que observer1 le pide a BIRD con
`aspa_check_upstream()`.

Para ver la diferencia, necesita un camino que el algoritmo estricto rechace y
el permisivo no. Saque al Proveedor B de nuevo del objeto ASPA (en la
terminal de Krill):

```
#krillc aspas add --aspa "AS{{ORIGIN_ASN}} => AS{{PROVIDER_A_ASN}}"
#./scripts/lab.sh refresh
```

El camino por el Proveedor B ahora figura como Invalid en los dos observadores.

1. **Antes de cambiar nada:** los objetos no van a cambiar en absoluto -
   solo una palabra en un archivo de configuración. ¿Espera que el camino por
   el Proveedor B siga figurando como Invalid, o que cambie?

2. `openbgpd/observer2-extra-a-role-customer.conf` es
   `openbgpd/observer2-aspa-mark.conf` con exactamente esa palabra cambiada:
   `role provider` por `role customer` en los vecinos del Proveedor B
   (10.200.6.10 y fd00:6::10). Ábralo y compare (`diff
   openbgpd/observer2-aspa-mark.conf openbgpd/observer2-extra-a-role-customer.conf`),
   y luego aplíquelo a mano - no mediante `lab.sh`, ya que este estado solo
   existe para este ejercicio:

   ```
   # Panel: haga clic en el recuadro observador 2, luego en Shell:
   #cp /etc/openbgpd-lab/observer2-extra-a-role-customer.conf /etc/bgpd.conf && bgpctl reload
   #bgpctl show rib {{ORIGIN_V4}}
   # O, desde la terminal de su computadora:
   #docker exec lab-observer2 sh -c "cp /etc/openbgpd-lab/observer2-extra-a-role-customer.conf /etc/bgpd.conf && bgpctl reload"
   #docker exec lab-observer2 bgpctl show rib {{ORIGIN_V4}}
   ```

   El camino por el Proveedor B vuelve como **Valid**. Los mismos objetos, el mismo
   AS_PATH, un veredicto distinto - y ninguna de las implementaciones está equivocada. Es
   la demostración más clara de este laboratorio de que "¿es este camino ASPA-válido?"
   no se puede responder sin decir también *de quién* lo recibió.

3. Ahora haga el equivalente en BIRD: `bird/observer1-extra-a-downstream.conf`
   es `bird/observer1-aspa-mark.conf` con `aspa_check_upstream` cambiado por
   `aspa_check_downstream` en los dos filtros - ábralo y compare de la misma
   manera, y luego aplíquelo a mano:

   ```
   # Panel: haga clic en el recuadro observador 1, luego en Shell:
   #birdc configure "/etc/bird-lab/observer1-extra-a-downstream.conf"
   # O, desde la terminal de su computadora:
   #docker exec lab-observer1 birdc configure "/etc/bird-lab/observer1-extra-a-downstream.conf"
   ```

   **Antes de mirar:** ¿espera que el nuevo veredicto de observer1 coincida con el resultado de
   `role customer` de observer2 (`Valid`), o con su resultado de `role provider`
   (`Invalid`)?

   ```
   # Panel: haga clic en el recuadro observador 1, luego en Shell:
   #birdc show route table master4 all {{ORIGIN_V4}}
   # O, desde la terminal de su computadora:
   #docker exec lab-observer1 birdc show route table master4 all {{ORIGIN_V4}}
   ```

   Ninguno de los dos, exactamente: BIRD informa el camino del Proveedor B como **ASPA Unknown**
   (`({{OBSERVER1_ASN}}, 2, 1)`). Las dos lecturas son mucho más permisivas que el algoritmo
   upstream, que dijo `Invalid` - pero donde OpenBGPD llama válido al camino,
   BIRD dice que no puede saberlo. Dos implementaciones independientes, leyendo un borde
   del mismo draft de manera distinta.

4. Compare los observadores lado a lado, y luego discutan: si "upstream" y
   "downstream" tiene que ver fundamentalmente con *de quién recibió la ruta*,
   ¿qué debería pasar en una topología donde el mismo vecino es proveedor de
   un prefijo y cliente de otro? (Por eso la elección de algoritmo en BIRD es una llamada
   `aspa_check_*()` por sesión y no un ajuste global del laboratorio, y por qué el `role` de
   OpenBGPD se fija dentro de cada bloque `neighbor`.)

5. Deshaga: restaure `role provider` y `aspa_check_upstream`, vuelva a agregar al Proveedor B
   al ASPA (`krillc aspas add --aspa "AS{{ORIGIN_ASN}} => AS{{PROVIDER_A_ASN}}, AS{{PROVIDER_B_ASN}}"`),
   ejecute `./scripts/lab.sh step5-aspa-mark` y `./scripts/lab.sh refresh`.

6. Un caso de borde más, ya que está aquí: vuelva a poner al AS{{ATTACKER_ASN}} en su secuestro
   ingenuo (`./scripts/lab.sh step2-hijack-simple`). Con **un solo AS** en el
   camino no hay ningún salto cliente→proveedor que verificar, así que el ASPA no tiene nada que decir
   sobre *quién puede originar un prefijo* - ese nunca fue su trabajo. BIRD llama
   `Valid` a un camino así (`({{OBSERVER1_ASN}}, 2, 2)`), OpenBGPD `Unknown` (`?`). De nuevo dos
   lecturas de un borde. Vuelva con `./scripts/lab.sh step9-hijack-off`.

### B. ASN correcto, prefijo demasiado específico

*Etapa:* `step3-rov-mark` (para que la ruta inválida siga visible).

El Paso 2 fue un secuestro con el ASN de origen equivocado. Este es el error opuesto:
el origen es completamente legítimo, pero el prefijo excede lo que la ROA
autorizó. Un ejemplo en IPv4 significaría desagregar {{ORIGIN_V4}} hasta un
`/25` - algo que en la Internet real se filtra en toda la red y que aquí
resultaría artificial. Anunciar un bloque IPv6 más específico que un
`/32` (un `/36` o un `/40`, por ejemplo) es una práctica operativa
completamente normal, así que este ejercicio usa eso en su lugar - y para
dejar en claro que no se trata de uno u otro proveedor, usa **dos**
sub-bloques de {{ORIGIN_V6}}, uno anunciado solo al Proveedor A y el otro
solo al Proveedor B.

`bird/origin-extra-b.conf` es `bird/origin.conf` más exactamente eso: dos
rutas estáticas para `3fff:cafe:1000::/40` y `3fff:cafe:2000::/40` (ambas
dentro de {{ORIGIN_V6}}, ambas más específicas de lo que autoriza
{{ORIGIN_V6_MAXLEN}}), y el filtro de exportación de cada proveedor
ampliado para llevar también su propio sub-bloque. Ábralo y compárelo con
`bird/origin.conf` (`diff bird/origin.conf bird/origin-extra-b.conf`) antes
de aplicarlo a mano:

```
# Panel: haga clic en el recuadro origen, luego en Shell:
#birdc configure "/etc/bird-lab/origin-extra-b.conf"
# O, desde la terminal de su computadora:
#docker exec lab-origin birdc configure "/etc/bird-lab/origin-extra-b.conf"
```

Vea qué recibió realmente cada proveedor:

```
# Panel: haga clic en el recuadro Proveedor A, luego en Shell:
#birdc show route
# Panel: haga clic en el recuadro Proveedor B, luego en Shell:
#birdc show route
```

El Proveedor A tiene `3fff:cafe:1000::/40`; el Proveedor B tiene
`3fff:cafe:2000::/40` - cada uno solo el que le correspondía. Ahora los
observadores:

```
# Panel: haga clic en el recuadro observador 2, luego en Shell:
#bgpctl show rib 3fff:cafe:1000::/40
#bgpctl show rib 3fff:cafe:2000::/40
# O, desde la terminal de su computadora:
#docker exec lab-observer2 bgpctl show rib 3fff:cafe:1000::/40
#docker exec lab-observer2 bgpctl show rib 3fff:cafe:2000::/40
```

```
*>    !-? 3fff:cafe:1000::/40  fd00:5::10         10     0 {{PROVIDER_A_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} {{ORIGIN_ASN}} i
```

```
*>    !-? 3fff:cafe:2000::/40  fd00:6::10         10     0 {{PROVIDER_B_ASN}} {{ORIGIN_ASN}} i
```

Los dos caminos son **ROV Invalid** - cada uno un anuncio perfectamente
legítimo a través de un proveedor autorizado, rechazado por la misma razón
en ambos lados: la ROA de {{ORIGIN_V6}} solo autoriza anuncios hasta
`/{{ORIGIN_V6_MAXLEN}}`, y los dos sub-bloques son más específicos que eso.
No se trata del Proveedor A ni del Proveedor B - es el prefijo. En
`rov-mark` los dos se quedan visibles, degradados, exactamente como el
secuestro del Paso 3. Ejecute `step8-drop` y desaparecen de la misma forma
en que después desapareció el secuestro.

Deshaga cuando termine:

```
# Panel: haga clic en el recuadro origen, luego en Shell:
#birdc configure
# O, desde la terminal de su computadora:
#docker exec lab-origin birdc configure
```

> **El patrón:** el ROV verifica *qué se está anunciando y quién lo anuncia*. El ASPA
> verifica *si el camino que lo trajo hasta aquí es uno que el origen
> autorizó*. Este ejercicio, y el secuestro ingenuo del Paso 2, rompen el ROV
> sin tocar el ASPA; el camino falsificado y la fuga rompen el ASPA sin
> tocar el ROV. Un despliegue real quiere los dos funcionando.

### C. Dentro de los validadores, y RTR

*Etapa:* `step5-aspa-mark` (para que existan tanto la tabla de ROAs como la de ASPAs).

La historia solo miró los veredictos de los routers. Esto mira cómo llegaron
hasta ahí.

1. Abra Routinator: **http://routinator.localhost:8080**

   Está configurado para validar **solo** el ancla de confianza del propio laboratorio, no
   toda la Internet:

   ```
   --no-rir-tals  --extra-tals-dir=/tals  --enable-aspa
   ```

   El TAL se instala automáticamente cuando el laboratorio levanta. En `MODE=local`
   viene del ancla de confianza de {{RIR_NAME}} (y se puede descargar
   del panel del registro); en `MODE=beta`, de
   `https://rpki-test-ta.beta.registro.br/ta/ta.tal`.

2. Mire el conjunto validado, con ROAs y ASPAs:

   ```
   #curl -s http://routinator.localhost:8080/json
   ```

3. Vea qué recibió observer1 por RTR:

   ```
   # Panel: haga clic en el recuadro observador 1, luego en Shell:
   #birdc show protocols all routinator
   #birdc show route table roa4_table
   #birdc show route table aspa_table
   # O, desde la terminal de su computadora:
   #docker exec lab-observer1 birdc show protocols all routinator
   #docker exec lab-observer1 birdc show route table roa4_table
   #docker exec lab-observer1 birdc show route table aspa_table
   ```

   El protocolo RTR tiene que estar `Established`. La tabla ASPA solo se
   llena con **RTR versión 2** - la versión que Routinator negocia cuando
   el ASPA está activado.

4. Y observer2, que recibe sus objetos de FORT:

   ```
   # Panel: haga clic en el recuadro observador 2, luego en Shell:
   #bgpctl show rtr
   #bgpctl show sets
   # O, desde la terminal de su computadora:
   #docker exec lab-observer2 bgpctl show rtr
   #docker exec lab-observer2 bgpctl show sets
   ```

   `show rtr` tiene que decir `Version: 2`. El ASPA solo viaja en PDUs de RTR
   versión 2: en la versión 1 la sesión igual se establece y las ROAs igual llegan,
   pero todo veredicto ASPA quedaría `unknown`. `show sets` lista una entrada de ROA
   para IPv4, una para IPv6, y un ASPA (`#ASnum 1`).

### D. NotFound y Unknown

*Etapa:* `step5-aspa-mark`.

La historia solo mostró **Valid** e **Invalid**. Los otros dos veredictos -
**NotFound** (ninguna ROA cubre el prefijo) y **Unknown** (no existe ningún objeto ASPA
para ese ASN cliente) - son en realidad el estado *por defecto*, el más común
en la Internet real, donde la mayoría de los prefijos todavía no tienen ninguna cobertura RPKI.
Nunca aparecieron porque cada ruta de la historia estaba cubierta. Haga que
aparezcan a propósito, sacando objetos:

1. Quite la ROA de IPv4 y el objeto ASPA:

   ```
   # Panel: haga clic en el recuadro Krill, luego en Shell:
   #krillc roas update --ca acme_ca --remove "{{ORIGIN_V4}}-{{ORIGIN_V4_MAXLEN}} => {{ORIGIN_ASN}}"
   #krillc aspas remove --ca acme_ca --customer AS{{ORIGIN_ASN}}
   #krillc bulk publish
   # O, desde la terminal de su computadora:
   #docker exec lab-krill krillc roas update --ca acme_ca --remove "{{ORIGIN_V4}}-{{ORIGIN_V4_MAXLEN}} => {{ORIGIN_ASN}}"
   #docker exec lab-krill krillc aspas remove --ca acme_ca --customer AS{{ORIGIN_ASN}}
   #docker exec lab-krill krillc bulk publish
   ```

2. Confirme que realmente se fueron antes de seguir (`krillc roas list --ca
   acme_ca` y `krillc aspas list --ca acme_ca` deberían responder los dos
   sin ellos), y luego refresque:

   ```
   #./scripts/lab.sh refresh
   ```

3. Verifique los veredictos de `{{ORIGIN_V4}}` en los dos observadores: los dos caminos deberían
   figurar ahora como **ROV NotFound, ASPA Unknown** - "no tenemos opinión", no un
   rechazo: se quedan en la tabla aunque las dos verificaciones estén activas. Note
   que `{{ORIGIN_V6}}` no se ve afectado: su propia ROA sigue ahí, así que
   mantiene sus veredictos normales. La cobertura es por prefijo - no tenerla
   en uno no dice nada sobre otro. (Esta es también la razón por la que desplegar ROV no protege
   nada hasta que los *otros* AS publiquen ROAs: un prefijo sin ROA no puede ser
   detectado por nada.)

4. Restaure los dos objetos y refresque de nuevo:

   ```
   # Panel: haga clic en el recuadro Krill, luego en Shell:
   #krillc roas update --ca acme_ca --add "{{ORIGIN_V4}}-{{ORIGIN_V4_MAXLEN}} => {{ORIGIN_ASN}}"
   #krillc aspas add --ca acme_ca --aspa "AS{{ORIGIN_ASN}} => AS{{PROVIDER_A_ASN}}, AS{{PROVIDER_B_ASN}}"
   #krillc bulk publish
   # O, desde la terminal de su computadora:
   #docker exec lab-krill krillc roas update --ca acme_ca --add "{{ORIGIN_V4}}-{{ORIGIN_V4_MAXLEN}} => {{ORIGIN_ASN}}"
   #docker exec lab-krill krillc aspas add --ca acme_ca --aspa "AS{{ORIGIN_ASN}} => AS{{PROVIDER_A_ASN}}, AS{{PROVIDER_B_ASN}}"
   #docker exec lab-krill krillc bulk publish
   #./scripts/lab.sh refresh
   ```

> Si los veredictos del punto 4 no vuelven después de un refresh, normalmente
> significa que el refresh corrió antes de que Krill terminara de publicar
> (verifique con `krillc roas list`/`krillc aspas list` primero, como en el punto 2).
> Ejecutar `./scripts/lab.sh refresh` de nuevo unos segundos después lo resuelve.

---

## Si algo no funciona

| Síntoma | Qué verificar |
|---|---|
| Lo que veo no coincide con un paso | Lea el cuadro de **Estado** del paso y ejecute el único comando que lista - cada comando `stepN-*` fija todo su estado (atacante, peer, ROAs, ASPA, etapa de los observadores), no solo lo que cambió desde el paso anterior, así que es seguro ejecutarlo desde cualquier punto de la historia. |
| Un comando `stepN-*` se detiene con un error de Krill/CA | Desde `step3-rov-mark` en adelante, todo comando `stepN-*` verifica que la Preparación realmente haya terminado antes de tocar nada - vea "Cómo está organizada la historia". El mensaje dice qué falta (ninguna CA, más de una, o una que todavía no está completamente configurada); arregle eso en Krill y en el panel, y vuelva a ejecutar el mismo comando. |
| La ruta del AS{{ATTACKER_ASN}} no aparece | Cuando un observador está *descartando* lo que una verificación marca (etapa `aspa-drop`, desde `step8-drop` en adelante), esa ruta desaparece de la tabla a propósito: mire en `birdc show route table master4 filtered` en observer1. Antes de eso, en `none` no hay veredictos, y en `rov-mark`/`aspa-mark` solo se degrada, así que la ruta debería seguir ahí. Si no, verifique que ejecutó el comando del paso y que la sesión está arriba: `docker exec lab-attacker birdc show protocols`. |
| Los dos observadores no coinciden, o la insignia de etapa está ámbar | La insignia en el encabezado del panel muestra la etapa que cada observador realmente está corriendo; ámbar significa que difieren. Ejecute el comando de paso de la etapa que quiere (p. ej. `./scripts/lab.sh step8-drop`) para dejar los dos en la misma. Justo después de un cambio, observer2 también necesita diez o quince segundos para estabilizarse (se reinicia), así que mire de nuevo antes de sacar conclusiones. |
| Creé la ROA/ASPA pero nada cambió | `./scripts/lab.sh refresh` obliga a los dos validadores a revalidar. Si sigue sin cambiar, puede que `refresh` haya corrido antes de que Krill terminara de publicar: verifique `krillc roas list` / `krillc aspas list`, espere unos segundos, refresque de nuevo. |
| Creé la ROA pero no aparece en Krill | La CA todavía no tenía el certificado del padre. `docker exec lab-krill krillc bulk refresh`, rehaga la ROA, y luego `krillc bulk publish` |
| Routinator no muestra ningún ASPA | Faltó `--enable-aspa`, o el objeto todavía no fue publicado/revalidado. `./scripts/lab.sh refresh`. |
| La tabla `aspa_table` de BIRD está vacía | RTR negoció la versión 1. Verifique `birdc show protocols all routinator` y si Routinator levantó con `--enable-aspa`. |
| Una sesión BGP no levanta | `docker compose logs origin provider-a provider-b observer1 observer2 attacker peer` |
| observer2 muestra `avs` como `unknown` en todas partes | La sesión RTR negoció la versión 1, o FORT es anterior a 1.7.0.experimental. Verifique que `bgpctl show rtr` diga `Version: 2`. |
| observer2 muestra `avs` como `valid` en LOS DOS caminos | La sesión perdió su rol RFC 9234 - normalmente después de un `bgpctl reload` a secas. Vuelva a ejecutar el comando de paso de la etapa (`./scripts/lab.sh step5-aspa-mark` o `step8-drop`), que reinicia observer2 con la configuración de la etapa. |
| FORT no arranca o no obtiene nada | `docker logs lab-fort`. Debería terminar con "First validation cycle successfully ended". Si TLS falla, la CA del laboratorio no llegó a su almacén de confianza: verifique que el volumen `pki` esté montado. |
| Krill no puede comunicarse con Registro.br | El contenedor necesita acceso saliente a Internet: `docker exec lab-krill ping -c1 beta.registro.br` |
| Quiero empezar de nuevo | `./scripts/lab.sh reset` (borra la CA de Krill, el estado propio del registro {{RIR_NAME}}, y las cachés de los dos validadores), y luego `up`. No ejecute un `docker compose down -v` a secas: {{RIR_NAME}} y el panel del registro solo levantan bajo el perfil compose `local`, y un `docker compose down` a secas los deja corriendo sin avisar - `lab.sh` lo configura por usted. Ejecútelo además desde la terminal de su propia computadora, no desde la consola en el navegador del panel: `reset` tira abajo todo el laboratorio, incluida esa misma consola, lo que mata el comando a la mitad. |
| Los validadores muestran ROAs/ASPA pero la CA de Krill se ve completamente vacía | Está mirando dos CAs distintas: la suya (recién creada) en Krill, y objetos viejos todavía publicados bajo una CA anterior del mismo nombre en el registro, sobrantes de un reset que no limpió del todo. `./scripts/lab.sh reset` (no un `docker compose down -v` a secas) limpia los dos lados juntos. |
| Cambié `lab.conf` y no cambió nada | `./scripts/lab.sh up` regenera `bird/vars.conf`, recrea los routers, y ahora también devuelve la historia a su estado limpio (etapa `none`, AS{{ATTACKER_ASN}} y el peer callados). Si cambió el ASN o los prefijos y ya tiene una CA, su certificado todavía tiene los recursos *antiguos* - rehaga el paso de delegación de la Preparación 2 (en modo local, "Add parent" en Krill contra el mismo parent actualiza los derechos; `docker exec lab-krill krillc bulk refresh` obliga a la CA a recogerlos) antes de que `step3-rov-mark` en adelante vuelva a funcionar. |
| El panel del registro no abre | Solo existe en `MODE=local`. Verifique `lab.conf` y ejecute `./scripts/lab.sh up` |
| Krill no puede comunicarse con {{RIR_NAME}} | Krill necesita confiar en la CA interna del laboratorio: `docker logs lab-krill` muestra un error TLS si `/pki/ca.pem` no está montado |
| Cambié el MODE y la CA desapareció | Es a propósito: cada modo tiene su propio volumen, para que uno no pise el trabajo del otro |
| Los objetos están en Routinator pero BIRD no cambió | BIRD revalida por sí solo, pero tarda unos segundos. Para forzarlo: `docker exec lab-observer1 birdc reload in provider_a_v4` |

## Referencias

- RFC 6811 - validación de origen para BGP
- RFC 9582 - perfil de la ROA
- RFC 7908 - definición del problema y clasificación de las fugas de ruta BGP
- RFC 9234 - prevención y detección de fugas de ruta usando roles
- `draft-ietf-sidrops-aspa-profile` - el perfil del objeto ASPA
- `draft-ietf-sidrops-aspa-verification` - los algoritmos upstream y downstream
- `draft-ietf-sidrops-8210bis` - RTR versión 2, que transporta los ASPAs
- Documentación de Krill: https://krill.docs.nlnetlabs.nl
- Documentación de Routinator: https://routinator.docs.nlnetlabs.nl
- Documentación de BIRD: https://bird.network.cz/

*Esta guía está licenciada bajo [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). El código del laboratorio está bajo Apache-2.0. Vea los archivos `LICENSE` en el repositorio.*
