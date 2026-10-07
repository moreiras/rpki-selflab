# RPKI SelfLab

*Standalone Lab and Self-Study Guide for RPKI, ROA, ROV, and ASPA*

*[English](README.md) · [Español](README.es.md) · [Português](README.pt.md)*

**Project site, with the lab's story illustrated step by step:
https://moreiras.github.io/rpki-selflab/**

A lab for RPKI (ROAs, ROV and ASPA) in containers, meant to run on any computer
with Docker (Mac, Windows, or Linux, tested with OrbStack and Docker Desktop).
It publishes ROAs and an ASPA object, then shows what **two different
validators and two different routers** make of exactly the same objects, while
a hijacker (AS666) and a leaky peer try to get in the way. The guide tells it
as one story: three attacks, and which check stops each one.

The guide is at **[guide/GUIDE.en.md](guide/GUIDE.en.md)** (also in
[Spanish](guide/GUIDE.es.md) and [Portuguese](guide/GUIDE.pt.md)). In the web
panel, the same content shows up step by step next to the live topology, in
whichever language is selected there, with every command block saying where
it runs and a button that opens that terminal.

**How to use it.** The panel controls a complete lab, and following the guide
is the recommended way in: each step sets up the next, and checkpoints tick
themselves as your lab gets there. Some steps are challenges, with the solution
hidden behind hints and a timer. Once you're through, use the lab freely: the
guide's last section has open-ended ideas, the `work/` folder holds your own
configurations, and any step command puts the lab back on track.

## Quick start

1. **Install Docker** with Compose v2 (what to install on each system is in
   [Before you start: Docker](#before-you-start-docker)). On Windows, do
   everything inside the Ubuntu terminal of WSL 2.
2. **Get the lab.** Clone the repository:

   ```sh
   git clone https://github.com/moreiras/rpki-selflab.git
   cd rpki-selflab
   ```

   or download the source code (`.zip` or `.tar.gz`) of the latest version from
   [Releases](https://github.com/moreiras/rpki-selflab/releases) and unpack it.
3. **Bring it up**, inside the lab's folder:

   ```sh
   ./scripts/lab.sh up
   ```

   Then open **http://localhost:8080** in your browser and follow the guide
   in the panel's left column.

The first `up` downloads and builds the images, which takes a few minutes.
Would rather not install Docker? There's a ready-made virtual machine too:
see [As a virtual machine](#as-a-virtual-machine).

## Local and beta modes

The lab has two modes, chosen with the `MODE` variable in `lab.conf`:

| MODE | Who certifies the resources | Internet |
|---|---|---|
| `local` (default) | **LabNIC**, a simulated RIR/NIR running inside the lab | not needed |
| `beta` | Registro.br's test system | needed, plus a beta.registro.br login |

In local mode the lab is **self-contained**: its own trust anchor, its own
repository, and a registry panel where CA delegation and publication
authorization happen, using the same RFC 6492 and 8183 XML exchanges you'd see
with a real RIR.

The `beta` mode was created only for some of NIC.br's courses. The `local`
mode, where the lab is self-contained, is the default and almost certainly
the one you want.

## Before you start: Docker

You need Docker with Compose v2, a 64-bit computer (amd64 or arm64), about
2 GB of memory for Docker and 4 GB of free disk. The lab itself uses around
300 MB of memory once it's up.

| System | What to install |
|---|---|
| Linux | Docker Engine + the Compose plugin: https://docs.docker.com/engine/install/ (then https://docs.docker.com/engine/install/linux-postinstall/ to run it without `sudo`) |
| macOS | OrbStack (https://docs.orbstack.dev/quick-start, the one the lab is tested with) or Docker Desktop (https://docs.docker.com/desktop/setup/install/mac-install/) |
| Windows | WSL 2 (`wsl --install`, https://learn.microsoft.com/windows/wsl/install) plus Docker Desktop with WSL integration (https://docs.docker.com/desktop/features/wsl/). Clone and run the lab **inside** the Ubuntu terminal, in a Linux folder such as `~/rpki-selflab`, not under `/mnt/c` |

Check it with `docker version`, `docker compose version` and
`docker run --rm hello-world`. The guide's *Preparation 1* walks through all
of this in more detail.

## Services and ports

If anything goes wrong, `./scripts/lab.sh doctor` checks Docker, the ports,
the containers and the preparation, and says what to do about each problem.

| Service | URL | Note |
|---|---|---|
| Lab panel | http://localhost:8080 | clickable topology |
| Krill (CA) | http://krill.localhost:8080 | token `labpass` |
| Routinator | http://routinator.localhost:8080 | observer1's validator |
| Console (ttyd) | http://console.localhost:8080 | browser terminal |
| Registry panel | http://registry.localhost:8080 | only in `MODE=local` |
| LabNIC's Krill | http://rir-krill.localhost:8080 | only in `MODE=local`, token `labpass` |

Everything is reachable through one port, 8080: the panel at `localhost`,
and each of the other web apps under its own `<name>.localhost` (browsers
resolve `*.localhost` to your machine, and nginx routes by name). On the
panel, the bar at the top opens all of them, and the terminals, inside the
panel itself, in tabs. Open it at exactly `localhost`: by IP address those
names don't resolve.

Only 8080 is published on your computer, so the lab doesn't collide with
other software. If 8080 is already taken, set another port with `PANEL_PORT`
in `lab.conf` and run `./scripts/lab.sh up`; every address above then uses
that port. `EXPOSE_PORTS=yes` in `lab.conf` also publishes each
service's own port (Krill 3000, LabNIC's Krill 3001, Routinator 3323/8323,
FORT 3324, ttyd 7681, registry 8081; see `docker-compose.ports.yml`), for
connecting outside tools straight to a service.

## As a virtual machine

If you'd rather not install Docker, the lab also comes as a small virtual
machine with a desktop of its own (browser and terminal) that already has
everything installed, images included. Nothing to configure, and it runs
with no Internet access. See [vm/README.md](vm/README.md).

## Topology

![The lab's topology: the registry and the two validators at the top, the observers below them, the two providers, AS666 and, at the bottom, the origin, its CA and the peer](guide/img/topology.en.svg)

AS64500 is multihomed and announces `203.0.113.0/24` and `3fff:cafe::/32`. Each
observer receives the same prefix over both providers. The origin prefers
Provider B: it prepends its ASN twice when announcing to Provider A (the
backup), so A's path comes out two hops longer. Two more routers sit on the
topology, drawn with dashed borders, silent until the guide's story switches
them on:

- **AS666** hijacks the origin's prefixes: first announcing them as its own
  (`step2-hijack-simple`), then forging the AS_PATH so it ends in the real
  origin (`step4-hijack-posrov`).
- **peer** is a legitimate network that peers privately with the origin and
  buys transit from Provider A. It leaks the origin's routes to Provider A
  when the guide says so (`step7-leak-on`), a route leak, which ROV can
  never catch and ASPA can.

| Docker network | IPv4 | IPv6 | between |
|---|---|---|---|
| `lab-l-org-a` | 10.200.1.0/24 | fd00:1::/64 | origin ↔ Provider A |
| `lab-l-org-b` | 10.200.2.0/24 | fd00:2::/64 | origin ↔ Provider B |
| `lab-l-a-obs1` | 10.200.3.0/24 | fd00:3::/64 | Provider A ↔ observer1 |
| `lab-l-b-obs1` | 10.200.4.0/24 | fd00:4::/64 | Provider B ↔ observer1 |
| `lab-l-a-obs2` | 10.200.5.0/24 | fd00:5::/64 | Provider A ↔ observer2 |
| `lab-l-b-obs2` | 10.200.6.0/24 | fd00:6::/64 | Provider B ↔ observer2 |
| `lab-l-666-obs1` | 10.200.7.0/24 | fd00:7::/64 | AS666 ↔ observer1 |
| `lab-l-666-obs2` | 10.200.8.0/24 | fd00:8::/64 | AS666 ↔ observer2 |
| `lab-l-peer-org` | 10.200.9.0/24 | fd00:9::/64 | peer ↔ origin (private peering) |
| `lab-l-peer-a` | 10.200.10.0/24 | fd00:10::/64 | peer ↔ Provider A (transit) |
| `lab-mgmt` | 172.30.0.0/24 | fd00:30::/64 | Krill, validators, observers, panel |

## The two observers

Both observers receive the same announcements and RPKI objects, but each uses a
different router and validator:

| | observer1 | observer2 |
|---|---|---|
| Router | BIRD 3.1.4 | OpenBGPD 8.8 |
| Validator | Routinator | FORT Validator |
| ASN | 64510 | 64511 |
| How the verdict is read | large communities set by the lab's filters | native `ovs` / `avs` route attributes |
| Inspect with | `birdc show route table master4 all` | `bgpctl show rib detail` |

BIRD has no per-route validation attribute, so the `bird/observer1-*.conf`
files record each verdict in a large community: `(64510,1,x)` for ROV,
`(64510,2,x)` for ASPA. OpenBGPD computes both natively and `bgpctl -j` hands
them over as JSON. That's why the two configurations look so different while
testing the exact same thing.

### Why observer2 uses `role provider`

OpenBGPD only runs ASPA verification on a session that carries an RFC 9234
role, and **the role decides which ASPA algorithm runs**. The observers sit
above the providers (announcements flow up from the origin), so each
observer is the providers' upstream, and routes arrive from a customer. That
selects the *upstream* algorithm, the same one `bird/observer1-*.conf` asks
for with `aspa_check_upstream()`.

Set `role customer` instead and the *downstream* algorithm runs: the path
through Provider B comes back **Valid**. Same objects, same AS_PATH,
different verdict. It's probably the single most surprising thing in this
lab, and it isn't a bug in either implementation.

One consequence: switching stages on observer2 has to restart it. The role
is negotiated when a session opens, and an RTR session that's already up
keeps whatever version it negotiated; after a bare `bgpctl reload` every
`avs` falls back to `unknown`. The `step*` commands that switch stages
already handle the restart for you (the stage name is kept in
`/etc/lab-stage` inside the container, so a later restart comes back in the
same stage).

### Deployment stages

The observers don't come up validating anything. They start as plain BGP
routers, and the guide deploys validation on them in stages, the way you
would on a real router: first *marking* what a check flags (a community and
a lower preference, nothing dropped), then *dropping* it. Each stage is one
complete config file per observer:

| Stage | observer1 (BIRD) | observer2 (OpenBGPD) | What it does |
|---|---|---|---|
| `none` | `observer1-none.conf` | `observer2-none.conf` | plain BGP, no validation (how the lab starts) |
| `rov-mark` | `observer1-rov-mark.conf` | `observer2-rov-mark.conf` | RTR session + ROV, invalid routes only marked |
| `rov-drop` | `observer1-rov-drop.conf` | `observer2-rov-drop.conf` | ROV Invalid routes rejected |
| `aspa-mark` | `observer1-aspa-mark.conf` | `observer2-aspa-mark.conf` | ROV and ASPA verification, both only marked |
| `aspa-drop` | `observer1-aspa-drop.conf` | `observer2-aspa-drop.conf` | ROV and ASPA Invalid both rejected |

Reading one file after another is the point: what changes between two
stages is what deploying that check means. The stage indicator in the panel's
header shows the stage the observers are actually in.

## The story's commands

`./scripts/lab.sh` switches AS666 and the peer between behaviors; the names
carry the number of the guide's step they belong to. Each one sets its
step's *entire* state (attacker, peer, ROAs, ASPA object, and the
observers' deployment stage), not just what changed since the step before,
so they're safe to run in any order, from anywhere in the story. From
`step3-rov-mark` on, each command also checks that the Preparation (the
Krill CA, its parent, its resources) actually finished before touching
anything, and says what's missing if it didn't.

| Command | What it does |
|---|---|
| `step1-clean` | AS666 and peer silent, and both observers back to plain BGP (no validation) |
| `step2-hijack-simple` | AS666 announces the origin's prefixes as its own |
| `step3-rov-mark` | deploy ROV on both observers, only marking |
| `step4-hijack-posrov` | AS666 forges the path so it ends in the real origin |
| `step5-aspa-mark` | deploy ASPA verification too, also only marking |
| `step6-add-provider-b` | add Provider B to the ASPA object |
| `step7-leak-on` | peer starts leaking the origin's routes to Provider A |
| `step8-drop` | ROV and ASPA both start dropping invalid routes (what real routers do) |
| `step9-leak-off` | peer stops leaking |
| `step9-hijack-off` | AS666 goes silent |

Besides those: `refresh` (make the validators revalidate now), `doctor` (check
the environment), `clean-objects` (remove the CA's ROAs and ASPA, keeping the
CA, to restart the story without redoing the preparation), `status`, `logs`,
`down` and `reset`. The panel's **Commands** button lists them all, with a
button to run each one.

## Files

```
lab.conf                    MODE, LANGUAGE, EXPOSE_PORTS, holder, ASN and prefixes (what you edit)
docker-compose.yml          topology, networks and the pinned image versions
docker-compose.ports.yml    optional: the services' own host ports (EXPOSE_PORTS=yes)
bird/
  vars.conf                 GENERATED from lab.conf: BIRD's "define" statements
  origin.conf               AS64500, originates the prefixes
  provider-a.conf           AS64501, authorized transit
  provider-b.conf           AS64502, the origin's other upstream
  attacker-off.conf         AS666, silent (sessions up, nothing announced)
  attacker-simple.conf      AS666, naive hijack (AS_PATH: 666)
  attacker-posrov.conf      AS666, forged path (AS_PATH: 666 <origin>)
  peer-off.conf             AS64499, peering only (correct behavior)
  peer-leak.conf            AS64499, also leaks to Provider A
  observer1-<stage>.conf    AS64510, one file per deployment stage (none, rov-mark,
                            rov-drop, aspa-mark, aspa-drop)
openbgpd/
  vars.conf                 GENERATED from lab.conf: OpenBGPD macros
  observer2-<stage>.conf    AS64511, one file per deployment stage
rir/krill.conf              LabNIC's Krill in testbed mode (TA + repository)
rir-web/                    the registry panel (stock Python + HTML)
images/bird/                Alpine 3.22 + BIRD 3.1.4 (+ vim, nano)
images/openbgpd/            Alpine 3.22 + OpenBGPD 8.8 (+ vim, nano)
images/krill/               upstream Krill 0.16.0 + vim, nano
images/routinator/          upstream Routinator 0.15.2 + vim, nano
images/fort/                FORT Validator, built from source
images/console/             ttyd (browser terminals) + state collector
images/utils/               generates the internal PKI and installs the TAL
dashboard/
  index.html                the panel's page
  app.js, app.css           topology, side panel, dock (terminals/web apps in tabs), events
  guide.js                  the guide renderer: command blocks, challenges, predictions, checkpoints
  checks.js                 what the lab's state should look like at each checkpoint
  i18n.js, nodes.js         UI strings and per-component texts (en/es/pt)
  language.js               language switcher (en/es/pt), shared with rir-web
guide/
  templates/GUIDE.*.md           the class guide's sources, with {{NAME}} markers (edit these)
  GUIDE.en.md, .es.md, .pt.md    COMPILED from templates/ by generate-config.sh (don't edit)
  img/                           screenshots used by the guide
  TERMS.md                       translation terms and rules
work/                       your own configuration files (writable from the panel's Lab terminal)
web/nginx.conf              serves the panel and proxies Routinator
vm/                         the virtual machine: Packer template, scripts, releases (see vm/README.md)
docs/                       the project site (GitHub Pages): en/pt/es pages and screenshots;
                            docs/tools/screenshots.py regenerates the screenshots
scripts/
  lab.sh                    up / down / refresh / reset / doctor / clean-objects / step* (the story's commands)
  validate.sh               text summary of the lab's state
  generate-config.sh        lab.conf -> bird/vars.conf + openbgpd/vars.conf + guide/GUIDE.*.md
  check-guide-parity.sh     checks that the three guide translations keep the same structure
  i18n.sh                   message catalog (en/es/pt) used by the scripts above
```

## Versions

Every version is **pinned on purpose**. The lab parses the output of these
tools (`status.py` and `validate.sh` read `birdc`, `bgpctl` and Routinator
output), so an unattended upgrade in the middle of a course can break the
panel without a single line of this repo changing.

| Component | Version | Pinned in | If you change it |
|---|---|---|---|
| Krill | `v0.16.0` | `FROM` in `images/krill/Dockerfile` (used by the `krill` and `rir` services) | the guide's screenshots and steps assume 0.16's web UI (ROAs and ASPAs tabs) and `krillc` subcommand names |
| Routinator | `v0.15.2` | `FROM` in `images/routinator/Dockerfile` | needs `--enable-aspa` and RTR v2; older versions silently ignore ASPA objects |
| FORT Validator | `1.7.0.experimental` | `FORT_VERSION` in `images/fort/Dockerfile` | **ASPA and RTR v2 exist only from this tag onwards.** 1.6.x will come up fine and serve ROAs, and every `avs` on observer2 will be `unknown` |
| BIRD | 3.1.4 | indirectly, via `FROM alpine:3.22` in `images/bird/Dockerfile` | `aspa_check_upstream()` needs BIRD ≥ 2.16. Bumping Alpine changes the BIRD version as a side effect |
| OpenBGPD | 8.8 | indirectly, via `FROM alpine:3.22` in `images/openbgpd/Dockerfile` | needs 8.x for `aspa-set`, `role` and `rtr { min-version 2 }` |
| nginx | `1.29-alpine` | `docker-compose.yml` (`web`) | only serves the panel; low risk |

Two of those pins are **indirect** and worth knowing about. BIRD and OpenBGPD
are Alpine packages, so their versions are frozen by `alpine:3.22` rather
than chosen here. Alpine only backports security fixes within a release
branch, so `3.22` keeps giving you BIRD 3.1.4 and OpenBGPD 8.8, but
changing that line to `alpine:3.23` silently changes both routers at once.

FORT is built from source (`images/fort/Dockerfile`) rather than pulled from
`nicmx/fort-validator`, because the published image is amd64-only and the
lab needs to stay native on arm64 hosts. It builds on Debian rather than
Alpine because FORT includes `<sys/queue.h>`, a BSD/glibc header musl
doesn't ship.

To move a pinned version: edit the single place listed above, then
`./scripts/lab.sh up` (it rebuilds) and `./scripts/validate.sh` to confirm both
observers still produce verdicts rather than `?`.

### The internal PKI (MODE=local)

Every RPKI URI is HTTPS, and the validators and Krill validate TLS properly:
they don't have the browser's "proceed anyway" button. So the lab generates
its own certificate authority (the `pki-init` container), which signs
`rir.lab`'s certificate. That CA's certificate gets handed to whoever needs
to trust it:

| Who | How |
|---|---|
| Routinator | `--rrdp-root-cert=/pki/ca.pem` |
| FORT | installed into the system trust store by the image's entrypoint |
| Holder's Krill | `KRILL_HTTPS_ROOT_CERTS=/pki/ca.pem` |
| Registry panel | Python's SSL context |

FORT gets different treatment because its `--http.ca-path` expects an
OpenSSL hashed directory rather than a single file, and installing the CA
into the system store is less fragile than maintaining that directory.

Routinator also runs with `--allow-dubious-hosts`, since `rir.lab` isn't a
public name, and with `--disable-rsync`, since the only transport here is
RRDP.

All images in use (Alpine, Debian, nginx, Krill, Routinator) are
multi-architecture (amd64/arm64), and FORT and OpenBGPD are built or
packaged natively, so nothing runs under emulation, not on Apple Silicon,
not on Intel/AMD, not on Windows.

## Language

The lab's panel, the registry panel, and the messages printed by the scripts
(`lab.sh`, `validate.sh`, ...) exist in English, Spanish, and Portuguese. The
default is set by `LANGUAGE` in `lab.conf`, and each browser can freely
switch with the selector at the top of each panel, without affecting anyone
else.

Protocol vocabulary (BGP, ROA, ASPA, RFC numbers, the Valid/Invalid/Unknown
states, command names) stays in English across all three languages. That's
the vocabulary Krill, Routinator, BIRD and OpenBGPD already use in their own
command-line output, and mixing languages there would only get in the way of
cross-checking against the tools.

Source-code comments (scripts, `*.conf` files, Dockerfiles, Python) stay in
English throughout, regardless of the lab's own language.

English is the source of every translation. A change to the guide starts in
`guide/templates/GUIDE.en.md` and goes to the Spanish and Portuguese
templates in the same change; `scripts/check-guide-parity.sh` (run by every
`up`) checks that the three still have the same structure, and
[guide/TERMS.md](guide/TERMS.md) lists the interface terms and the words to
avoid in each language.

## Different values

Everything you might want to change lives in **`lab.conf`**. The values shown
throughout this README (AS64500, 203.0.113.0/24, ...) are the **defaults**.
The guide, on the other hand, is compiled from `lab.conf` and always shows
yours:

```sh
ORIGIN_ASN=64500
ORIGIN_V4=203.0.113.0/24
ORIGIN_V4_MAXLEN=24
ORIGIN_V6=3fff:cafe::/32
ORIGIN_V6_MAXLEN=32
```

Edit it and run `./scripts/lab.sh up`. That calls
`scripts/generate-config.sh`, which translates those values into
`bird/vars.conf` (BIRD `define` statements) and `openbgpd/vars.conf`
(OpenBGPD macros), included by every router. The panel re-reads `lab.conf`
on every cycle, and `up` also compiles the guide from `guide/templates/`
with your values.

The providers' and observers' ASNs (64501, 64502, 64510, 64511) are there
too, but don't need to change: they're documentation ASNs (RFC 5398) and
work with any origin ASN. `PEER_ASN` (64499) is cut from the same cloth, part
of the same reserved block. `ATTACKER_ASN` (666) is the odd one out: it
isn't reserved for documentation or for anything else; it's just easy to
remember. None of this ever touches the real Internet.

## License

- The lab's code and configuration: [Apache-2.0](LICENSE).
- The guide, the READMEs and their translations: [CC BY 4.0](LICENSE-docs).
- The software the lab runs keeps its own licenses: see
  [THIRD-PARTY.md](THIRD-PARTY.md).
