# RPKI SelfLab

*Laboratorio autónomo y guía de autoestudio para RPKI, ROA, ROV y ASPA*

*[English](README.md) · [Español](README.es.md) · [Português](README.pt.md)*

Laboratorio de RPKI (ROA, ROV y ASPA) en contenedores, para correr en cualquier
computadora con Docker (Mac, Windows o Linux - probado con OrbStack y Docker
Desktop). Publica ROAs y un objeto ASPA, y luego muestra qué hacen **dos
validadores distintos y dos routers distintos** con exactamente los mismos
objetos - mientras un secuestrador (AS666) y un peer que filtra rutas intentan
interponerse. La guía del laboratorio es una sola historia: tres ataques, y el
momento en que cada uno deja de funcionar.

Tiene dos modos, elegidos con la variable `MODE` en `lab.conf`:

| MODE | Quién certifica los recursos | Internet |
|---|---|---|
| `local` (por defecto) | **LabNIC**, un RIR/NIR simulado que corre dentro del laboratorio | no hace falta |
| `beta` | el sistema de pruebas de Registro.br | hace falta, y un login en beta.registro.br |

En modo local el laboratorio es **autocontenido**: ancla de confianza propia,
repositorio propio y un panel de registro donde ocurren la delegación de la CA
y la autorización de publicación, usando los mismos intercambios de XML de las
RFC 6492 y 8183.

La guía está en **[guide/GUIDE.es.md](guide/GUIDE.es.md)** (también en
[inglés](guide/GUIDE.en.md) y [portugués](guide/GUIDE.pt.md)). En el panel web,
el mismo contenido aparece renderizado paso a paso, en el idioma seleccionado
ahí.

## Primeros pasos

```sh
./scripts/lab.sh up
open http://localhost:8080
```

| Servicio | URL | Nota |
|---|---|---|
| Panel del laboratorio | http://localhost:8080 | topología clicable |
| Krill (CA) | http://krill.localhost:8080 | token `passlab` |
| Routinator | http://routinator.localhost:8080 | validador del observer1 |
| FORT (RTR) | localhost:3324 | validador del observer2, sin interfaz web |
| Consola (ttyd) | http://console.localhost:8080 | terminal en el navegador |
| Panel del registro | http://registry.localhost:8080 | solo en `MODE=local` |
| Krill de LabNIC | http://rir-krill.localhost:8080 | solo en `MODE=local`, token `passlab` |

Todo es accesible por un solo puerto, el 8080: el panel en `localhost`, y cada
una de las otras aplicaciones web bajo su propio `<nombre>.localhost` (los
navegadores resuelven `*.localhost` a su máquina, y nginx enruta por el nombre).
Los puertos propios de los servicios (3000, 3001, 7681, 8081, 8323) siguen
publicados también. Eso ayuda en la máquina virtual, donde solo el 8080 necesita
reenvío.

## Como máquina virtual

Si prefiere no instalar Docker, el laboratorio también viene como una pequeña
máquina virtual con escritorio propio (navegador y terminal) que ya contiene
todo, imágenes incluidas: nada que configurar, y funciona sin acceso a Internet.
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
                       10.0.0.0/24 , 3fff:cafe::/32
```

El AS64500 es multihomed y anuncia `10.0.0.0/24` y `3fff:cafe::/32`. Cada
observador recibe el mismo prefijo por los dos proveedores. El origen prefiere
al Proveedor B: antepone su ASN dos veces al anunciar al Proveedor A (el
respaldo), de modo que el camino de A es dos saltos más largo. Hay dos routers
más en la topología, en silencio hasta que la historia de la guía los activa:

```
   AS666 (attacker) ---- direct BGP sessions ----> observer1, observer2
                         (a customer of the observers)

   peer  AS64999 ---- private peering ---- origin AS64500
        |
        +---- transit ---- Provider A
```

- **AS666** secuestra los prefijos del origen: primero anunciándolos como
  propios (`step2-hijack-simple`), y luego falsificando el AS_PATH para que
  termine en el origen real (`step4-hijack-posrov`).
- **peer** es una red legítima que hace peering privado con el origen y compra
  tránsito al Proveedor A. Filtra las rutas del origen hacia el Proveedor A
  cuando la guía lo indica (`step7-leak-on`) - una fuga de ruta, que el ROV
  nunca puede ver y el ASPA sí.

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

El laboratorio corre a propósito el mismo experimento dos veces, en dos pilas
independientes:

| | observer1 | observer2 |
|---|---|---|
| Router | BIRD 3.1.4 | OpenBGPD 8.8 |
| Validador | Routinator | FORT Validator |
| ASN | 64510 | 64511 |
| Cómo se lee el veredicto | large communities puestas por los filtros del laboratorio | atributos nativos `ovs` / `avs` de la ruta |
| Inspeccionar con | `birdc show route table master4 all` | `bgpctl show rib detail` |

BIRD no tiene un atributo de validación por ruta, así que los archivos
`bird/observer1-*.conf` graban cada veredicto en una large community —
`(64510,1,x)` para ROV y `(64510,2,x)` para ASPA. OpenBGPD calcula los dos
nativamente y `bgpctl -j` los entrega en JSON, y por eso las dos
configuraciones se ven tan distintas probando lo mismo.

### Por qué observer2 usa `role provider`

OpenBGPD solo hace verificación ASPA en una sesión que tenga un rol de la RFC
9234, y **el rol decide qué algoritmo ASPA corre**. Los observadores están por
encima de los proveedores — los anuncios suben desde el origen —, así que cada
observador es el upstream de los proveedores y las rutas llegan desde un
cliente. Eso selecciona el algoritmo *upstream*, el mismo que
`bird/observer1-*.conf` piden con `aspa_check_upstream()`.

Ponga `role customer` y corre el algoritmo *downstream*: el camino por el
Proveedor B vuelve como **Valid**. Mismos objetos, mismo AS_PATH, veredicto
distinto. Es lo más sorprendente de este laboratorio, y no es un bug de ninguna
de las dos implementaciones.

Una consecuencia: cambiar de etapa en observer2 tiene que reiniciarlo, porque
el rol se negocia al abrir la sesión y una sesión RTR que ya está establecida
conserva la versión que negoció. Tras un `bgpctl reload` a secas, todo `avs`
vuelve a `unknown`. Los comandos `step*` que cambian de etapa ya hacen ese
reinicio por usted (el nombre de la etapa se guarda en `/etc/lab-stage` dentro
del contenedor, así que un reinicio posterior vuelve en la misma etapa).

### Etapas de despliegue

Los observadores no arrancan validando nada: empiezan como routers BGP
comunes, y la guía despliega la validación en ellos por etapas, como se haría
en un router real - primero *marcando* lo que una verificación señala (una
community y una preferencia menor, sin descartar nada), y luego *descartándolo*.
Cada etapa es un archivo de configuración completo por observador:

| Etapa | observer1 (BIRD) | observer2 (OpenBGPD) | Qué hace |
|---|---|---|---|
| `none` | `observer1-none.conf` | `observer2-none.conf` | BGP común, sin validación (como arranca el laboratorio) |
| `rov-mark` | `observer1-rov-mark.conf` | `observer2-rov-mark.conf` | sesión RTR + ROV, rutas inválidas solo marcadas |
| `rov-drop` | `observer1-rov-drop.conf` | `observer2-rov-drop.conf` | rutas ROV Invalid rechazadas |
| `aspa-mark` | `observer1-aspa-mark.conf` | `observer2-aspa-mark.conf` | ROV descartando + verificación ASPA, solo marcada |
| `aspa-drop` | `observer1-aspa-drop.conf` | `observer2-aspa-drop.conf` | ROV y ASPA Invalid ambos rechazados |

Leer un archivo tras otro es justamente el punto: lo que cambia entre dos
etapas es lo que significa desplegar esa verificación. La insignia en el
encabezado del panel muestra la etapa en que están los observadores.

## Los comandos de la historia

`./scripts/lab.sh` cambia el comportamiento de AS666 y del peer; los nombres
llevan el número del paso de la guía al que pertenecen. Todos se pueden repetir
sin riesgo.

| Comando | Qué hace |
|---|---|
| `step1-clean` | AS666 y peer en silencio, y los dos observadores de vuelta a BGP común (sin validación) |
| `step2-hijack-simple` | AS666 anuncia los prefijos del origen como propios |
| `step3-rov-mark` | despliega ROV en los dos observadores, solo marcando |
| `step3-rov-drop` | el ROV empieza a descartar las rutas inválidas |
| `step4-hijack-posrov` | AS666 falsifica el camino para que termine en el origen real |
| `step5-aspa-mark` | despliega la verificación ASPA (el ROV sigue descartando), solo marcando |
| `step5-aspa-drop` | la verificación ASPA empieza a descartar los caminos inválidos |
| `step7-leak-on` | peer empieza a filtrar las rutas del origen hacia el Proveedor A |
| `step9-leak-off` | peer deja de filtrar |
| `step9-hijack-off` | AS666 vuelve al silencio |

## Archivos

```
lab.conf                    MODE, LANGUAGE, holder, ASN and prefixes (what you edit)
docker-compose.yml          topology, networks and the pinned image versions
bird/
  vars.conf                 GENERATED from lab.conf: BIRD's "define" statements
  origin.conf               AS64500, originates the prefixes
  provider-a.conf           AS64501, authorized transit
  provider-b.conf           AS64502, the origin's other upstream
  attacker-off.conf         AS666, silent (sessions up, nothing announced)
  attacker-simple.conf      AS666, naive hijack (AS_PATH: 666)
  attacker-posrov.conf      AS666, forged path (AS_PATH: 666 <origin>)
  peer-off.conf             AS64999, peering only (correct behavior)
  peer-leak.conf            AS64999, also leaks to Provider A
  observer1-<stage>.conf    AS64510, one file per deployment stage (none, rov-mark,
                            rov-drop, aspa-mark, aspa-drop)
openbgpd/
  vars.conf                 GENERATED from lab.conf: OpenBGPD macros
  observer2-<stage>.conf    AS64511, one file per deployment stage
rir/krill.conf              LabNIC's Krill in testbed mode (TA + repository)
rir-web/                    the registry panel (stock Python + HTML)
images/bird/                Alpine 3.22 + BIRD 3.1.4
images/openbgpd/            Alpine 3.22 + OpenBGPD 8.8
images/fort/                FORT Validator, built from source
images/console/             ttyd (browser terminal) + state collector
images/utils/               generates the internal PKI and installs the TAL
dashboard/
  index.html                the panel
  language.js               language switcher (en/es/pt), shared with rir-web
guide/
  templates/GUIDE.*.md           the class guide's sources, with {{NAME}} markers (edit these)
  GUIDE.en.md, .es.md, .pt.md    COMPILED from templates/ by generate-config.sh (don't edit)
web/nginx.conf              serves the panel and proxies Routinator
vm/                         la máquina virtual: plantilla de Packer, scripts, releases (vea vm/README.md)
scripts/
  lab.sh                    up / down / refresh / reset / step* (the story's commands)
  validate.sh               text summary of the lab's state
  generate-config.sh        lab.conf -> bird/vars.conf + openbgpd/vars.conf + guide/GUIDE.*.md
  i18n.sh                   message catalog (en/es/pt) used by the scripts above
```

## Versiones

Todas las versiones están **fijadas a propósito**. El laboratorio hace parsing
de la salida de esas herramientas (`status.py` y `validate.sh` leen la salida de
`birdc`, `bgpctl` y Routinator), así que una actualización automática en medio
de un curso puede romper el panel sin que cambie una sola línea de este
repositorio.

| Componente | Versión | Fijada en | Si usted la cambia |
|---|---|---|---|
| Krill | `v0.16.0` | `docker-compose.yml` (servicios `krill` y `rir`) | en 0.16 el ASPA existe solo por la CLI; los pasos `krillc aspas` de la guía asumen esos nombres de subcomando |
| Routinator | `v0.15.2` | `docker-compose.yml` (`routinator`) | necesita `--enable-aspa` y RTR v2; versiones viejas ignoran los objetos ASPA en silencio |
| FORT Validator | `1.7.0.experimental` | `FORT_VERSION` en `images/fort/Dockerfile` | **ASPA y RTR v2 existen solo a partir de esa tag.** La 1.6.x levanta normalmente y sirve ROAs, y todo `avs` de observer2 queda en `unknown` |
| BIRD | 3.1.4 | indirectamente, por el `FROM alpine:3.22` en `images/bird/Dockerfile` | `aspa_check_upstream()` necesita BIRD ≥ 2.16. Subir Alpine cambia la versión de BIRD como efecto colateral |
| OpenBGPD | 8.8 | indirectamente, por el `FROM alpine:3.22` en `images/openbgpd/Dockerfile` | necesita 8.x para `aspa-set`, `role` y `rtr { min-version 2 }` |
| nginx | `1.29-alpine` | `docker-compose.yml` (`web`) | solo sirve el panel; riesgo bajo |

Dos de esas fijaciones son **indirectas** y conviene conocerlas: BIRD y
OpenBGPD son paquetes de Alpine, así que sus versiones quedan congeladas por
`alpine:3.22`, no elegidas aquí. Alpine solo hace backport de correcciones de
seguridad dentro de una rama de release, así que `3.22` sigue entregando BIRD
3.1.4 y OpenBGPD 8.8 — pero cambiar esa línea a `alpine:3.23` cambia los dos
routers a la vez, en silencio.

FORT se compila desde el fuente (`images/fort/Dockerfile`) en lugar de bajarse
de `nicmx/fort-validator`, porque la imagen publicada es solo amd64 y el
laboratorio debe seguir siendo nativo también en hosts arm64. Se compila en
Debian y no en Alpine porque FORT incluye `<sys/queue.h>`, un header BSD/glibc
que musl no provee.

Para mover una versión fijada: edite el único lugar listado arriba, corra
`./scripts/lab.sh up` (reconstruye) y después `./scripts/validate.sh` para
confirmar que los dos observadores siguen produciendo veredictos, y no `?`.

### La PKI interna (MODE=local)

Toda URI de RPKI es HTTPS, y los validadores y Krill validan TLS - no tienen el
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
del sistema es menos frágil que mantener ese directorio.

Routinator también corre con `--allow-dubious-hosts`, porque `rir.lab` no es un
nombre público, y con `--disable-rsync`, ya que el único transporte aquí es
RRDP.

Todas las imágenes usadas (Alpine, Debian, nginx, Krill, Routinator) son
multi-arquitectura (amd64/arm64), y FORT y OpenBGPD se compilan o empaquetan
nativamente, así que nada corre bajo emulación en Apple Silicon, Intel/AMD o
Windows.

## Idioma

El panel del laboratorio, el panel del registro y los mensajes que imprimen los
scripts (`lab.sh`, `validate.sh`, ...) existen en inglés, español y portugués.
El valor por defecto lo define `LANGUAGE` en `lab.conf`; cada navegador puede
cambiar de idioma libremente con el selector en la parte superior de cada
panel, sin afectar a nadie más.

El vocabulario de protocolo (BGP, ROA, ASPA, números de RFC, los estados
Valid/Invalid/Unknown, nombres de comando) queda en inglés en los tres idiomas
- es el vocabulario que ya usa la salida de línea de comandos de Krill,
Routinator, BIRD y OpenBGPD, y mezclar idiomas ahí solo estorbaría al
contrastar con las herramientas.

Los comentarios del código fuente (scripts, archivos `*.conf`, Dockerfiles,
Python) están todos en inglés, sin importar el idioma del laboratorio.

## Valores distintos

Todo lo que usted podría querer cambiar está en **`lab.conf`**. Los valores
mostrados a lo largo de este README (AS64500, 10.0.0.0/24, ...) son los
**valores por defecto**; la guía, en cambio, se compila desde `lab.conf` y
siempre muestra los suyos:

```sh
ORIGIN_ASN=64500
ORIGIN_V4=10.0.0.0/24
ORIGIN_V4_MAXLEN=24
ORIGIN_V6=3fff:cafe::/32
ORIGIN_V6_MAXLEN=32
```

Edítelo y corra `./scripts/lab.sh up`. Eso llama a
`scripts/generate-config.sh`, que traduce esos valores a `bird/vars.conf` (los
`define` de BIRD) y `openbgpd/vars.conf` (las macros de OpenBGPD), incluidos
por todos los routers. El panel relee `lab.conf` en cada ciclo, y `up` también
compila la guía desde `guide/templates/` con sus valores.

Los ASN de los proveedores y de los observadores, 64501/64502/64510/64511,
también están ahí, pero no necesitan cambiar: son ASN de documentación (RFC
5398) y funcionan con cualquier ASN de origen. Lo mismo vale para
`ATTACKER_ASN` (666) y `PEER_ASN` (64999), que pertenecen a la historia de la
guía; el del peer, en cambio, está en el rango de uso privado (RFC 6996), y
ninguno de los dos toca jamás la Internet real.

## Licencia

- El código y la configuración del laboratorio: [Apache-2.0](LICENSE).
- La guía, los README y sus traducciones: [CC BY 4.0](LICENSE-docs).
- El software que ejecuta el laboratorio conserva sus propias licencias: vea [THIRD-PARTY.md](THIRD-PARTY.md).
