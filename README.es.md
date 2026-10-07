# RPKI SelfLab

*Laboratorio autónomo y guía de autoestudio para RPKI, ROA, ROV y ASPA*

*[English](README.md) · [Español](README.es.md) · [Português](README.pt.md)*

Laboratorio de RPKI (ROA, ROV y ASPA) en contenedores, para correr en cualquier
computadora con Docker (Mac, Windows o Linux, probado con OrbStack y Docker
Desktop). Publica ROAs y un objeto ASPA, y después muestra qué hacen **dos
validadores distintos y dos routers distintos** con exactamente los mismos
objetos, mientras un secuestrador (AS666) y un peer que filtra rutas intentan
meterse en el medio. La guía del laboratorio cuenta una sola historia: tres ataques, y el
momento en que cada uno deja de funcionar.

Tiene dos modos, elegidos con la variable `MODE` en `lab.conf`:

| MODE | Quién certifica los recursos | Internet |
|---|---|---|
| `local` (por defecto) | **LabNIC**, un RIR/NIR simulado que corre dentro del laboratorio | no hace falta |
| `beta` | el sistema de pruebas de Registro.br | hace falta, y un login en beta.registro.br |

En modo local el laboratorio es **autocontenido**: tiene su propia ancla de confianza,
su propio repositorio, y un panel de registro donde ocurren la delegación de la CA
y la autorización de publicación, con los mismos intercambios de XML de las
RFC 6492 y 8183.

La guía está en **[guide/GUIDE.es.md](guide/GUIDE.es.md)** (también en
[inglés](guide/GUIDE.en.md) y [portugués](guide/GUIDE.pt.md)). En el panel web
aparece el mismo contenido, paso a paso, al lado de la topología en vivo, en el
idioma que elija ahí, y cada bloque de comandos dice dónde se ejecuta, con un
botón que abre la terminal correcta.

**Cómo usarlo.** El panel emula un laboratorio completo, y seguir la guía es
el camino recomendado: cada paso prepara el siguiente, y los puntos de
control se marcan solos cuando el laboratorio llega ahí. Un modo *Desafío*
esconde las soluciones detrás de pistas y un cronómetro, para una segunda
pasada. Una vez que termine, use el laboratorio como quiera: la última sección
de la
guía tiene ideas abiertas, la carpeta `work/` guarda sus propias
configuraciones, y cualquier comando de paso vuelve a encaminar el
laboratorio.

## Antes de empezar: Docker

Necesita Docker con Compose v2, una computadora de 64 bits (amd64 o arm64),
unos 2 GB de memoria para Docker y 4 GB libres en disco. Una vez en marcha,
el laboratorio usa alrededor de 300 MB de memoria.

| Sistema | Qué instalar |
|---|---|
| Linux | Docker Engine + el plugin de Compose: https://docs.docker.com/engine/install/ (después https://docs.docker.com/engine/install/linux-postinstall/ para usarlo sin `sudo`) |
| macOS | OrbStack (https://docs.orbstack.dev/quick-start, con el que se prueba el laboratorio) o Docker Desktop (https://docs.docker.com/desktop/setup/install/mac-install/) |
| Windows | WSL 2 (`wsl --install`, https://learn.microsoft.com/windows/wsl/install) más Docker Desktop con la integración WSL (https://docs.docker.com/desktop/features/wsl/). Clone y ejecute el laboratorio **dentro** de la terminal de Ubuntu, en una carpeta de Linux como `~/lab-aspa`, no en `/mnt/c` |

Verifíquelo con `docker version`, `docker compose version` y
`docker run --rm hello-world`. La *Preparación 1* de la guía explica todo
esto con más detalle.

## Primeros pasos

```sh
./scripts/lab.sh up
open http://localhost:8080
```

Si algo sale mal, `./scripts/lab.sh doctor` revisa Docker, los puertos, los
contenedores y la preparación, y dice qué hacer con cada problema.

| Servicio | URL | Nota |
|---|---|---|
| Panel del laboratorio | http://localhost:8080 | topología clicable |
| Krill (CA) | http://krill.localhost:8080 | token `labpass` |
| Routinator | http://routinator.localhost:8080 | validador del observer1 |
| Consola (ttyd) | http://console.localhost:8080 | terminal en el navegador |
| Panel del registro | http://registry.localhost:8080 | solo en `MODE=local` |
| Krill de LabNIC | http://rir-krill.localhost:8080 | solo en `MODE=local`, token `labpass` |

Todo se accede por un solo puerto, el 8080: el panel en `localhost`, y cada
una de las otras aplicaciones web bajo su propio `<nombre>.localhost` (los
navegadores resuelven `*.localhost` a su máquina, y nginx enruta según el nombre).
En el panel, la barra de arriba los abre a todos, y a las terminales,
dentro del propio panel, en pestañas. Ábralo exactamente en `localhost`: por
dirección IP, esos nombres no resuelven.

Solo el 8080 se publica en su computadora, así que el laboratorio no choca
con otros programas. Si el 8080 ya está ocupado, elija otro puerto en
`PANEL_PORT` en `lab.conf` y ejecute `./scripts/lab.sh up`; todas las
direcciones de arriba pasan a usar ese puerto. `EXPOSE_PORTS=yes` en `lab.conf` publica además el
puerto propio de cada servicio (Krill 3000, Krill de LabNIC 3001, Routinator
3323/8323, FORT 3324, ttyd 7681, registro 8081; vea
`docker-compose.ports.yml`), para conectar herramientas de afuera
directamente a un servicio.

## Como máquina virtual

Si prefiere no instalar Docker, el laboratorio también viene como una pequeña
máquina virtual con escritorio propio (navegador y terminal) que ya trae
todo adentro, imágenes incluidas. No hay nada que configurar, y funciona sin acceso a Internet.
Vea [vm/README.es.md](vm/README.es.md).

## Topología

```
                 LabNIC   (RIR/NIR: trust anchor + repository)
                /                                      \
            RRDP                                        RRDP
             v                                            v
        Routinator                                  FORT Validator
             |  RTR v2 :3323                             |  RTR v2 :3323
             v                                            v
   observer1  AS64510  (BIRD)                observer2  AS64511  (OpenBGPD)

        both observers receive the SAME prefix over BOTH paths:

        Provider A  AS64501                     Provider B  AS64502
                     \                          /
                      \                        /
                       origin  AS64500  --  Krill (the holder's CA)
                       203.0.113.0/24 , 3fff:cafe::/32
```

El AS64500 es multihomed y anuncia `203.0.113.0/24` y `3fff:cafe::/32`. Cada
observador recibe el mismo prefijo por los dos proveedores. El origen prefiere
al Proveedor B, y para lograrlo antepone su ASN dos veces al anunciar al Proveedor A (el
respaldo), de modo que el camino por A queda dos saltos más largo. Hay dos routers
más en la topología, callados hasta que la historia de la guía los pone en marcha:

```
   AS666 (attacker) ---- direct BGP sessions ----> observer1, observer2
                         (a customer of the observers)

   peer  AS64499 ---- private peering ---- origin AS64500
        |
        +---- transit ---- Provider A
```

- **AS666** secuestra los prefijos del origen: primero anunciándolos como
  propios (`step2-hijack-simple`), y después falsificando el AS_PATH para que
  termine en el origen real (`step4-hijack-posrov`).
- **peer** es una red legítima que hace peering privado con el origen y compra
  tránsito al Proveedor A. Cuando la guía lo indica (`step7-leak-on`) filtra las rutas del origen
  hacia el Proveedor A: una fuga de ruta, que el ROV
  nunca puede ver pero el ASPA sí.

| Red Docker | IPv4 | IPv6 | entre |
|---|---|---|---|
| `lab-l-org-a` | 10.200.1.0/24 | fd00:1::/64 | origen ↔ Proveedor A |
| `lab-l-org-b` | 10.200.2.0/24 | fd00:2::/64 | origen ↔ Proveedor B |
| `lab-l-a-obs1` | 10.200.3.0/24 | fd00:3::/64 | Proveedor A ↔ observer1 |
| `lab-l-b-obs1` | 10.200.4.0/24 | fd00:4::/64 | Proveedor B ↔ observer1 |
| `lab-l-a-obs2` | 10.200.5.0/24 | fd00:5::/64 | Proveedor A ↔ observer2 |
| `lab-l-b-obs2` | 10.200.6.0/24 | fd00:6::/64 | Proveedor B ↔ observer2 |
| `lab-l-666-obs1` | 10.200.7.0/24 | fd00:7::/64 | AS666 ↔ observer1 |
| `lab-l-666-obs2` | 10.200.8.0/24 | fd00:8::/64 | AS666 ↔ observer2 |
| `lab-l-peer-org` | 10.200.9.0/24 | fd00:9::/64 | peer ↔ origen (peering privado) |
| `lab-l-peer-a` | 10.200.10.0/24 | fd00:10::/64 | peer ↔ Proveedor A (tránsito) |
| `lab-mgmt` | 172.30.0.0/24 | fd00:30::/64 | Krill, validadores, observadores, panel |

## Los dos observadores

El laboratorio corre a propósito el mismo experimento dos veces, sobre dos pilas
independientes que no se comunican entre sí:

| | observer1 | observer2 |
|---|---|---|
| Router | BIRD 3.1.4 | OpenBGPD 8.8 |
| Validador | Routinator | FORT Validator |
| ASN | 64510 | 64511 |
| Cómo se lee el veredicto | large communities puestas por los filtros del laboratorio | atributos nativos `ovs` / `avs` de la ruta |
| Inspeccionar con | `birdc show route table master4 all` | `bgpctl show rib detail` |

BIRD no tiene un atributo de validación por ruta, así que los archivos
`bird/observer1-*.conf` graban cada veredicto en una large community:
`(64510,1,x)` para ROV y `(64510,2,x)` para ASPA. OpenBGPD calcula los dos
de forma nativa, y `bgpctl -j` los entrega en JSON. Por eso las dos
configuraciones se ven tan distintas probando exactamente lo mismo.

### Por qué observer2 usa `role provider`

OpenBGPD solo hace verificación ASPA en una sesión que tenga un rol de la RFC
9234, y **el rol decide qué algoritmo ASPA corre**. Los observadores están por
encima de los proveedores (los anuncios suben desde el origen), así que cada
observador es el upstream de los proveedores, y las rutas le llegan desde un
cliente. Eso selecciona el algoritmo *upstream*, el mismo que
`bird/observer1-*.conf` pide con `aspa_check_upstream()`.

Ponga `role customer` en cambio y corre el algoritmo *downstream*: el camino por el
Proveedor B vuelve como **Valid**. Mismos objetos, mismo AS_PATH, veredicto
distinto. Es probablemente lo más sorprendente de este laboratorio, y no es un bug de ninguna
de las dos implementaciones: las dos están leyendo el draft correctamente, solo que desde ángulos distintos.

Una consecuencia de esto: cambiar de etapa en observer2 tiene que reiniciarlo, porque
el rol se negocia al abrir la sesión, y una sesión RTR ya establecida
conserva la versión que negoció al principio. Tras un `bgpctl reload` a secas, todo `avs`
vuelve a `unknown`. Los comandos `step*` que cambian de etapa ya hacen ese
reinicio por usted (el nombre de la etapa queda guardado en `/etc/lab-stage` dentro
del contenedor, así que un reinicio posterior vuelve exactamente a la misma etapa).

### Etapas de despliegue

Los observadores no arrancan validando nada. Empiezan como routers BGP
comunes, y la guía despliega la validación en ellos por etapas, como se haría
en un router real: primero *marcando* lo que una verificación señala (una
community y una preferencia menor, sin descartar nada todavía), y después *descartándolo*.
Cada etapa es un archivo de configuración completo por observador:

| Etapa | observer1 (BIRD) | observer2 (OpenBGPD) | Qué hace |
|---|---|---|---|
| `none` | `observer1-none.conf` | `observer2-none.conf` | BGP común, sin validación (como arranca el laboratorio) |
| `rov-mark` | `observer1-rov-mark.conf` | `observer2-rov-mark.conf` | sesión RTR + ROV, rutas inválidas solo marcadas |
| `rov-drop` | `observer1-rov-drop.conf` | `observer2-rov-drop.conf` | rutas ROV Invalid rechazadas |
| `aspa-mark` | `observer1-aspa-mark.conf` | `observer2-aspa-mark.conf` | ROV y verificación ASPA, ambos solo marcando |
| `aspa-drop` | `observer1-aspa-drop.conf` | `observer2-aspa-drop.conf` | ROV y ASPA Invalid ambos rechazados |

Leer un archivo tras otro es justamente el punto: lo que cambia entre dos
etapas es lo que significa desplegar esa verificación. El indicador de
etapa en el encabezado del panel muestra en qué etapa están los observadores.

## Los comandos de la historia

`./scripts/lab.sh` cambia el comportamiento de AS666 y del peer; los nombres
llevan el número del paso de la guía al que pertenecen. Cada uno fija el
estado *completo* de su paso (atacante, peer, ROAs, objeto ASPA y la etapa
de los observadores), no solo lo que cambió desde el paso anterior, así que
son seguros de ejecutar en cualquier orden, desde cualquier punto de la
historia. Desde `step3-rov-mark` en adelante, cada comando además revisa
que la Preparación (la CA de Krill, su parent, sus recursos) realmente haya
terminado antes de tocar nada, y avisa qué falta si todavía no terminó.

| Comando | Qué hace |
|---|---|
| `step1-clean` | AS666 y peer en silencio, y los dos observadores de vuelta a BGP común (sin validación) |
| `step2-hijack-simple` | AS666 anuncia los prefijos del origen como propios |
| `step3-rov-mark` | despliega ROV en los dos observadores, solo marcando |
| `step4-hijack-posrov` | AS666 falsifica el camino para que termine en el origen real |
| `step5-aspa-mark` | despliega también la verificación ASPA, también solo marcando |
| `step6-add-provider-b` | agrega al Proveedor B al objeto ASPA |
| `step7-leak-on` | peer empieza a filtrar las rutas del origen hacia el Proveedor A |
| `step8-drop` | ROV y ASPA empiezan a descartar las rutas inválidas (lo que hacen los routers de verdad) |
| `step9-leak-off` | peer deja de filtrar |
| `step9-hijack-off` | AS666 vuelve al silencio |

Además de esos: `refresh` (hace que los validadores revaliden ya), `doctor`
(revisa el entorno), `clean-objects` (borra las ROAs y el ASPA de la CA,
conservando la CA, para recomenzar la historia sin rehacer la preparación),
`status`, `logs`, `down` y `reset`. La herramienta **Comandos del
laboratorio** del panel los lista a todos, con un botón para ejecutar cada
uno.

## Archivos

```
lab.conf                    MODE, LANGUAGE, EXPOSE_PORTS, titular, ASN y prefijos (lo que usted edita)
docker-compose.yml          topología, redes y las versiones fijadas de las imágenes
docker-compose.ports.yml    opcional: los puertos propios de los servicios en el host (EXPOSE_PORTS=yes)
bird/
  vars.conf                 GENERADO a partir de lab.conf: los "define" de BIRD
  origin.conf               AS64500, origina los prefijos
  provider-a.conf           AS64501, tránsito autorizado
  provider-b.conf           AS64502, el otro upstream del origen
  attacker-off.conf         AS666, callado (sesiones arriba, nada anunciado)
  attacker-simple.conf      AS666, secuestro ingenuo (AS_PATH: 666)
  attacker-posrov.conf      AS666, camino falsificado (AS_PATH: 666 <origen>)
  peer-off.conf             AS64499, solo peering (comportamiento correcto)
  peer-leak.conf            AS64499, también filtra hacia el Proveedor A
  observer1-<stage>.conf    AS64510, un archivo por etapa de despliegue (none, rov-mark,
                            rov-drop, aspa-mark, aspa-drop)
openbgpd/
  vars.conf                 GENERADO a partir de lab.conf: macros de OpenBGPD
  observer2-<stage>.conf    AS64511, un archivo por etapa de despliegue
rir/krill.conf              el Krill de LabNIC en modo testbed (TA + repositorio)
rir-web/                    el panel del registro (Python puro + HTML)
images/bird/                Alpine 3.22 + BIRD 3.1.4 (+ vim, nano)
images/openbgpd/            Alpine 3.22 + OpenBGPD 8.8 (+ vim, nano)
images/krill/               Krill 0.16.0 oficial + vim, nano
images/routinator/          Routinator 0.15.2 oficial + vim, nano
images/fort/                FORT Validator, compilado desde el código fuente
images/console/             ttyd (terminales en el navegador) + colector de estado
images/utils/               genera la PKI interna e instala el TAL
dashboard/
  index.html                la página del panel
  app.js, app.css           topología, panel lateral, dock (terminales/apps web en pestañas), eventos
  guide.js                  el renderizador de la guía: bloques de comandos, desafíos, predicciones, puntos de control
  checks.js                 cómo debe estar el laboratorio en cada punto de control
  i18n.js, nodes.js         textos de la interfaz y de cada componente (en/es/pt)
  language.js               selector de idioma (en/es/pt), compartido con rir-web
guide/
  templates/GUIDE.*.md           las fuentes de la guía, con marcadores {{NAME}} (edite estas)
  GUIDE.en.md, .es.md, .pt.md    COMPILADAS a partir de templates/ por generate-config.sh (no las edite)
  img/                           capturas de pantalla que usa la guía
  TERMS.md                       términos y reglas de traducción
work/                       sus propios archivos de configuración (se pueden escribir desde la Terminal del laboratorio)
web/nginx.conf              sirve el panel y hace de proxy de Routinator
vm/                         la máquina virtual: plantilla de Packer, scripts, releases (vea vm/README.es.md)
scripts/
  lab.sh                    up / down / refresh / reset / doctor / clean-objects / step* (los comandos de la historia)
  validate.sh               resumen del estado del laboratorio, en texto
  generate-config.sh        lab.conf -> bird/vars.conf + openbgpd/vars.conf + guide/GUIDE.*.md
  check-guide-parity.sh     verifica que las tres traducciones de la guía mantengan la misma estructura
  i18n.sh                   catálogo de mensajes (en/es/pt) que usan los scripts de arriba
```

## Versiones

Todas las versiones están **fijadas a propósito**. El laboratorio hace parsing
de la salida de esas herramientas (`status.py` y `validate.sh` leen la salida de
`birdc`, `bgpctl` y Routinator), así que una actualización automática en medio
de un curso puede romperle el panel sin que haya cambiado una sola línea de este
repositorio.

| Componente | Versión | Fijada en | Si usted la cambia |
|---|---|---|---|
| Krill | `v0.16.0` | `FROM` en `images/krill/Dockerfile` (usado por los servicios `krill` y `rir`) | las capturas y los pasos de la guía asumen la interfaz web de 0.16 (pestañas ROAs y ASPAs) y los nombres de subcomando de `krillc` |
| Routinator | `v0.15.2` | `FROM` en `images/routinator/Dockerfile` | necesita `--enable-aspa` y RTR v2; versiones viejas ignoran los objetos ASPA en silencio |
| FORT Validator | `1.7.0.experimental` | `FORT_VERSION` en `images/fort/Dockerfile` | **ASPA y RTR v2 existen solo a partir de esa tag.** La 1.6.x levanta normalmente y sirve ROAs, y todo `avs` de observer2 queda en `unknown` |
| BIRD | 3.1.4 | indirectamente, por el `FROM alpine:3.22` en `images/bird/Dockerfile` | `aspa_check_upstream()` necesita BIRD ≥ 2.16. Subir Alpine cambia la versión de BIRD como efecto colateral |
| OpenBGPD | 8.8 | indirectamente, por el `FROM alpine:3.22` en `images/openbgpd/Dockerfile` | necesita 8.x para `aspa-set`, `role` y `rtr { min-version 2 }` |
| nginx | `1.29-alpine` | `docker-compose.yml` (`web`) | solo sirve el panel; riesgo bajo |

Dos de esas fijaciones son **indirectas**, y conviene conocerlas: BIRD y
OpenBGPD son paquetes de Alpine, así que sus versiones quedan congeladas por
`alpine:3.22`, no elegidas aquí. Alpine solo hace backport de correcciones de
seguridad dentro de una rama de release, así que `3.22` sigue entregando BIRD
3.1.4 y OpenBGPD 8.8. Pero cambiar esa línea a `alpine:3.23` cambia los dos
routers a la vez, sin avisar.

FORT se compila desde el fuente (`images/fort/Dockerfile`) en lugar de bajarse
de `nicmx/fort-validator`, porque la imagen publicada es solo amd64 y el
laboratorio tiene que seguir siendo nativo también en hosts arm64. Se compila en
Debian y no en Alpine porque FORT incluye `<sys/queue.h>`, un header BSD/glibc
que musl no trae.

Para mover una versión fijada: edite el único lugar listado arriba, corra
`./scripts/lab.sh up` (reconstruye) y después `./scripts/validate.sh` para
confirmar que los dos observadores siguen produciendo veredictos, y no puros `?`.

### La PKI interna (MODE=local)

Toda URI de RPKI es HTTPS, y los validadores y Krill validan TLS de verdad: no tienen el
botón "continuar de todos modos" del navegador. Así que el laboratorio genera
su propia autoridad certificadora (el contenedor `pki-init`), que firma el
certificado de `rir.lab`. El certificado de esa CA se entrega a quien necesite
confiar en ella:

| Quién | Cómo |
|---|---|
| Routinator | `--rrdp-root-cert=/pki/ca.pem` |
| FORT | instalado en el trust store del sistema por el entrypoint de la imagen |
| Krill del titular | `KRILL_HTTPS_ROOT_CERTS=/pki/ca.pem` |
| Panel del registro | contexto SSL de Python |

FORT recibe un trato distinto porque su `--http.ca-path` espera un directorio
con hashes de OpenSSL, no un archivo único, e instalar la CA en el trust store
del sistema resulta menos frágil que mantener ese directorio a mano.

Routinator también corre con `--allow-dubious-hosts`, porque `rir.lab` no es un
nombre público, y con `--disable-rsync`, ya que el único transporte que se usa aquí es
RRDP.

Todas las imágenes (Alpine, Debian, nginx, Krill, Routinator) son
multi-arquitectura (amd64/arm64), y FORT y OpenBGPD se compilan o empaquetan
de forma nativa, así que nada corre bajo emulación, ni en Apple Silicon, ni en Intel/AMD,
ni en Windows.

## Idioma

El panel del laboratorio, el panel del registro y los mensajes que imprimen los
scripts (`lab.sh`, `validate.sh`, ...) existen en inglés, español y portugués.
El valor por defecto lo define `LANGUAGE` en `lab.conf`, pero cada navegador puede
cambiar de idioma libremente con el selector en la parte superior de cada
panel, sin afectar a nadie más que lo esté usando.

El vocabulario de protocolo (BGP, ROA, ASPA, números de RFC, los estados
Valid/Invalid/Unknown, nombres de comando) se queda en inglés en los tres idiomas.
Es el mismo vocabulario que ya usa la salida de línea de comandos de Krill,
Routinator, BIRD y OpenBGPD, y mezclar idiomas ahí solo estorbaría al
comparar con lo que muestran las herramientas.

Los comentarios del código fuente (scripts, archivos `*.conf`, Dockerfiles,
Python) están todos en inglés, sin importar el idioma del laboratorio.

El inglés es la fuente de todas las traducciones. Un cambio en la guía empieza
en `guide/templates/GUIDE.en.md` y pasa a las plantillas en español y
portugués en el mismo cambio; `scripts/check-guide-parity.sh` (que corre en
cada `up`) verifica que las tres sigan teniendo la misma estructura, y
[guide/TERMS.md](guide/TERMS.md) lista los términos de la interfaz y las
palabras a evitar en cada idioma.

## Valores distintos

Todo lo que usted podría querer cambiar vive en **`lab.conf`**. Los valores
mostrados a lo largo de este README (AS64500, 203.0.113.0/24, ...) son los
**valores por defecto**; la guía, en cambio, se compila desde `lab.conf` y
siempre muestra los suyos propios:

```sh
ORIGIN_ASN=64500
ORIGIN_V4=203.0.113.0/24
ORIGIN_V4_MAXLEN=24
ORIGIN_V6=3fff:cafe::/32
ORIGIN_V6_MAXLEN=32
```

Edítelo y corra `./scripts/lab.sh up`. Eso llama a
`scripts/generate-config.sh`, que traduce esos valores a `bird/vars.conf` (los
`define` de BIRD) y `openbgpd/vars.conf` (las macros de OpenBGPD), que incluyen
todos los routers. El panel relee `lab.conf` en cada ciclo, y `up` también
compila la guía desde `guide/templates/` con sus valores.

Los ASN de los proveedores y de los observadores, 64501/64502/64510/64511,
también están ahí, pero no hace falta tocarlos: son ASN de documentación (RFC
5398) y funcionan con cualquier ASN de origen. Lo mismo vale para `PEER_ASN`
(64499), que también cae dentro de ese mismo bloque de documentación. El único que
queda afuera es `ATTACKER_ASN` (666): pertenece a la historia de la guía igual
que los demás, pero no está en ningún rango reservado. De todos modos, ninguno de estos ASN
toca jamás la Internet real.

## Licencia

- El código y la configuración del laboratorio: [Apache-2.0](LICENSE).
- La guía, los README y sus traducciones: [CC BY 4.0](LICENSE-docs).
- El software que ejecuta el laboratorio conserva sus propias licencias: vea [THIRD-PARTY.md](THIRD-PARTY.md).
