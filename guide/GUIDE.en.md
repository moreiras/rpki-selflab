# RPKI SelfLab

*Standalone Lab and Self-Study Guide for RPKI, ROA, ROV, and ASPA*

*[English](GUIDE.en.md) · [Español](GUIDE.es.md) · [Português](GUIDE.pt.md)*

**Goal:** follow a hijacker and a leaky peer through a lab that runs on your
own machine. See what origin validation (ROV) catches, what it lets through,
and what ASPA adds - with every verdict checked by two independent stacks
(BIRD + Routinator, and OpenBGPD + FORT).

This is a self-contained lab: everything runs in containers on your own
machine, and it assumes you already have a basic grasp of RPKI, ROAs, ROV
and ASPA. You can certify your resources entirely locally, or, if you'd
rather use a real-world registry, against Registro.br's test system.

The lab is a single story in nine steps: **three attacks, and the moment each
one stops working.** A short preparation comes first (bring the lab up and
certify your resources), a few extra exercises come last.

## What RPKI asks of your own AS - and what this lab deploys

RPKI has two halves, and each one has two parts:

| | The origin publishes... | ...and routers validate |
|---|---|---|
| **Who may originate a prefix** | **ROAs** (Route Origin Authorizations) | **ROV** (Route Origin Validation) |
| **Which paths are plausible** | an **ASPA** object (Autonomous System Provider Authorization) | **ASPA verification** |

In real life, **both belong in the AS you operate**: you *publish* objects
about your own resources, and you *validate* what your neighbors send you.
Publishing without validating protects others but not you; validating without
publishing protects you but leaves your own prefixes unprotected for everybody
else.

In this lab, for teaching purposes, the two are split up:

- **Publication is deployed only in the Origin AS** (AS64500, whose CA lives in
  Krill). It's the only AS that creates ROAs and an ASPA object.
- **Validation is deployed only in the Observer ASes** (observer1 and
  observer2), the two routers you'll be watching. Everything else in the lab
  is an ordinary BGP router that never looks at RPKI.

Validation is deployed on the observers **in two stages, for each check**:
first the router only *marks* what the check flags (a community, a lower
preference - nothing is dropped, so you can see what would happen), and then
it *drops* it. **Dropping the invalid ones is what real routers do**; marking
is the rehearsal you do before you trust a check enough to let it reject
routes.

## Glossary

A quick review, not a full introduction - this is what these terms mean *in
this lab*. Skip ahead if you're already comfortable with them.

| Term | Meaning |
|---|---|
| **RIR/NIR** | Regional/National Internet Registry - allocates ASNs and IP blocks and, in RPKI, certifies that you hold them |
| **CA** | Certificate Authority - the RPKI engine that turns "these resources are yours" into signed certificates and objects |
| **TA** | Trust Anchor - the CA at the root of a validator's chain of trust; everything else is either it, or something it (transitively) certified |
| **ROA** | Route Origin Authorization - a signed object saying "this ASN may originate this prefix, up to this length" |
| **ASPA** | Autonomous System Provider Authorization - a signed object saying "these are the only ASes this AS accepts routes from as an upstream provider" |
| **ROV** | Route Origin Validation - checks a route's *last* AS (the one that originated it) against the ROAs |
| **ASPA verification** | checks the *whole path*, hop by hop, against the ASPA objects |
| **RRDP** | RPKI Repository Delta Protocol - how a validator fetches signed objects from a publication point |
| **RTR** | RPKI-to-Router protocol - how a validator hands its verdicts to a router |
| **VRP** | Validated ROA Payload - the (ASN, prefix, max length) triple a validator derived from a ROA |
| **Hijack** | announcing a prefix that belongs to someone else, as if it were yours (or as if it came through them) |
| **Route leak** | passing on a route you learned from one neighbor to another neighbor you shouldn't (RFC 7908) - nobody lies about the origin, but the path has a shape that couldn't legitimately happen |

---

## The topology

```
              LabNIC   (RIR/NIR: trust anchor + repository)
             /                                              \
         RRDP                                                RRDP
          v                                                    v
     Routinator                                          FORT Validator
          |  RTR v2 :3323                                      |  RTR v2 :3323
          v                                                    v
  observer1 AS64510 (BIRD)                       observer2 AS64511 (OpenBGPD)

       both observers receive the SAME prefix over BOTH paths:

            Provider A  AS64501
            Provider B  AS64502
                          \          /
                           \        /
                    origin AS64500   +   Krill (the holder's CA)
                    203.0.113.0/24 , 3fff:cafe::/32
```

AS64500 is multihomed, and it has a preference: **Provider B is the way in, Provider A
is the backup.** To get that, the origin *prepends* its own ASN twice when it announces
to Provider A (`64500 64500 64500` instead of just `64500`), so every path through
A looks two hops longer than the one through B - ordinary inbound traffic engineering.
The two providers pass the **same prefix** on to both observers, with the same origin AS. The lab runs the whole story **twice, in
parallel**, on two independent stacks: observer1 and observer2 see exactly the
same announcements and the same RPKI objects, but each one has its own router
and its own validator.

Two more routers join the story. Both are on the panel, and both are silent
until the story switches them on:

```
   AS666 (the attacker) ---- direct BGP sessions ----> observer1, observer2
                             (a customer of the observers: any customer
                              can send them an announcement, and nobody
                              checks it unless the observers validate)

   peer AS64999 ---- private peering ---- origin AS64500
        |
        +---- transit ---- Provider A
```

| Component | ASN | Role |
|---|---|---|
| origin | 64500 | your AS; originates the prefixes |
| Provider A | 64501 | one of the origin's two upstreams - the backup (the origin prepends twice to it) |
| Provider B | 64502 | the origin's other upstream - the preferred one |
| observer1 | 64510 | validating router: **BIRD** + **Routinator** |
| observer2 | 64511 | validating router: **OpenBGPD** + **FORT Validator** |
| AS666 | 666 | the attacker: a customer of the observers, and hijacks the origin's prefixes |
| peer | 64999 | a legitimate network that peers with the origin, and buys transit from Provider A |

ASNs 64496–64511 are reserved documentation ASNs (RFC 5398). AS64999 is in the
private-use range instead (RFC 6996), and AS666 is in neither - it's just
memorable. All of them are harmless here: this network never touches the real
Internet.

> The origin's ASN and prefixes live in the **`lab.conf`** file, at the lab's
> root. If you want different ones, edit it there and run
> `./scripts/lab.sh up`: the routers, the scripts, and this on-screen script
> all pick up the new values. (The guide is written with `{{ NAME }}` markers
> in `guide/templates/`; `up` compiles it into `guide/GUIDE.*.md` with the
> values from `lab.conf`. Edit the templates, never the compiled files.)

### How the story is organized

Every step begins with a **State** box: which deployment stage the observers
are in, what AS666 and the peer are doing, and which RPKI objects should
exist. If your lab doesn't match, the box also says how to put it back.

That recovery is deliberately simple: **each `./scripts/lab.sh stepN-*`
command sets its step's *entire* state**, not just what changed since the
previous one. Run `step9-leak-off`, then `step3-rov-mark`, and you land
exactly where Step 3 expects - the leak, the drop stage, everything Step 9
left behind is gone, reset by `step3-rov-mark` itself. That holds for any
pair of steps, in either direction: the commands don't assume you're going
forward, and don't leave anything behind for the next one to trip over. Three
things move together every time a `stepN-*` command runs:

- **The observers' deployment stage.** They start with no validation at all,
  and the story walks them through four stages: both checks are marked
  before either one drops anything, and then both start dropping together,
  in Step 8. Each command sets a whole stage on **both** observers at once,
  whatever stage they were in before:

  | Stage | What the observers do | Command |
  |---|---|---|
  | `none` | plain BGP, no validation (how the lab starts) | `step1-clean` |
  | `rov-mark` | ROV deployed, invalid routes only *marked* | `step3-rov-mark` |
  | `aspa-mark` | ASPA verification joins in, also only *marking* | `step5-aspa-mark` |
  | `aspa-drop` | both ROV and ASPA start *dropping* - production | `step8-drop` |

  Each stage is one complete config file per observer
  (`bird/observer1-<stage>.conf`, `openbgpd/observer2-<stage>.conf`), and the
  guide asks you to open them: **what changes from one file to the next is what
  deploying that check means.** You don't have to remember the stage you're in -
  the badge in the panel's header says it (*validation: none*, *ROV: marking*,
  *ROV: dropping*, ...), and turns amber if the two observers aren't in the
  same one. observer2 restarts every time the stage changes (OpenBGPD negotiates
  its RFC 9234 roles and its RTR version when a session opens), so give it ten
  or fifteen seconds to settle before you conclude anything from what it shows.
- **AS666 and the peer.** Every `stepN-*` command also sets their state -
  silent, naive hijack, forged path, leaking - to whatever the guide's text
  for that step describes, even the ones whose name doesn't mention them
  (`step6-add-provider-b` and `step8-drop`, for instance, still put
  AS666 back in its forged-path form, since that's what those steps expect).
- **The origin's RPKI objects**, in Krill: the ROAs (created once, from
  `step3-rov-mark` on) and the ASPA object, kept at exactly the list each
  step expects - `krillc aspas add` replaces the whole object, so a command
  can grow it (Step 6) or shrink it back (jumping to Step 5 after Step 6 ran)
  just as easily.

  This is also the one place a `stepN-*` command can fail through no fault of
  its own: from `step3-rov-mark` on, each one starts by checking that
  Preparation actually finished - the CA exists, has an active parent, holds
  the AS number and prefixes from `lab.conf`, and has a working repository.
  If it hasn't, the command stops and tells you so, instead of silently
  creating ROAs Krill can't actually publish. Preparation is the one part of
  the story a `stepN-*` command can't do for you.

The names of all these commands carry the number of the step they belong to.

---

## Preparation 1 — Bring the lab up

The lab has two modes, chosen with the `MODE` variable in `lab.conf`:

| MODE | Who certifies | Needs Internet? |
|---|---|---|
| `local` | **LabNIC**, a simulated registry that runs inside the lab | no |
| `beta` | **beta.registro.br**, Registro.br's test system | yes, and a beta.registro.br login |

Both modes use exactly the same protocols - RFC 6492 for delegation and
RFC 8181 for publication. What changes is the panel where you paste the XML,
and how long the objects take to show up at the validator: seconds in local
mode, a few minutes on beta. The next preparation step has one version per
mode; only do the one that matches yours.

1. Requirements: Docker installed (Mac, Windows, or Linux - **OrbStack**,
   Docker Desktop, or Docker Engine) and Internet access.

2. In the terminal, inside the lab's folder:

   ```
   #./scripts/lab.sh up
   ```

   The first time, Docker pulls the images and builds a few local ones.
   Takes a few minutes.

3. Open the lab's panel:

   **http://localhost:8080**

   Clicking each box in the topology opens that component's terminal, its
   web interface, and its addressing information.

   **Where to type the commands in this guide.** Everything can be done
   without leaving the browser, and every command block shows both ways:

   - **On the panel (the way the blocks are written first).** Click a box
     and use its **Shell** button (**Terminal (krillc)** on Krill): you land
     inside that container, so a command is written without any prefix -
     for example `birdc show protocols` in observer1's Shell. The
     **Lab commands** button opens a terminal already in the lab's folder,
     for `./scripts/lab.sh ...`, `cat bird/...` and `diff ...`.
   - **From your own computer's terminal, in the lab's folder.** The same
     command, run from outside: `docker exec lab-<box> <command>`, as in
     `docker exec lab-observer1 birdc show protocols`. Use this if you prefer
     your own terminal - or for `reset`, which must never run from the
     panel.

4. Check that the routers came up and that the BGP sessions are established.
   On the panel, each router's pill shows how many of its BGP sessions are
   up. To see the detail:

   ```
   # Panel: click the observer1 box, then Shell:
   #birdc show protocols
   # Panel: click the observer2 box, then Shell:
   #bgpctl show summary
   # Or, from your computer's terminal:
   #docker exec lab-observer1 birdc show protocols
   #docker exec lab-observer2 bgpctl show summary
   ```

   You should see `provider_a_v4`, `provider_a_v6`, `provider_b_v4` and
   `provider_b_v6` in `Established` on observer1 - plus `attacker_v4` and
   `attacker_v6`, the sessions with AS666, which is up but silent for now.
   observer2 lists the same six sessions. There's no `routinator` protocol
   yet: the observers don't validate anything until Step 3.

---

## Preparation 2 — Certify your resources (MODE=local)

> Do this if `lab.conf` has `MODE=local`. If it has `MODE=beta`, skip to
> Preparation 2-B.

Here you'll play **both sides** of the conversation: the holder, in Krill,
and the registry, in the LabNIC panel. It's the same XML exchange that
happens between a provider and their RIR.

### Your side: the CA in Krill

1. Open Krill: **http://krill.localhost:8080**

   (It's served through the lab's web server, so there's no certificate
   warning. The direct address, `https://localhost:3000`, still works, with a
   self-signed certificate.)

2. Log in with the token **`passlab`**.

3. Create your CA named **`minha_ca`**.
   If you like, switch the language to English in the top-right corner.

### The registry's side: the LabNIC panel

4. In another tab, open the registry panel: **http://registry.localhost:8080**

   Notice the *Allocated resources* section: it's exactly the ASN and blocks
   from your `lab.conf`. The certificate the registry is about to issue
   covers that set - no more, no less.

### Part 1 — CA delegation (RFC 6492)

5. In Krill, go to *Parent CAs* → *Add a new parent CA* and copy the XML from
   the *Child Request* field (the `child_request`).

6. In the LabNIC panel, paste that XML in **Step 1** and click
   *Issue certificate*.

7. The registry hands back the `parent_response`. Copy it.

8. Back in Krill, under *Parent CAs* → *Parent Response*, paste the XML. In
   the *Parent CA name* field use **`labnic`** and confirm.

### Part 2 — Publication service (RFC 8181)

9. In Krill, go to *Repository* → *Add a repository* and copy the XML from
   the *Publisher Request* (the `publisher_request`).

10. In the LabNIC panel, paste it in **Step 2** and click *Authorize publication*.

11. Copy the `repository_response` that appears and paste it into Krill,
    under *Repository* → *Repository Response*. Confirm.

### Checking

12. In Krill, the CA should show the resources received from the parent: the
    ASN 64500 and the prefixes 203.0.113.0/24 and 3fff:cafe::/32.

13. In the LabNIC panel, the *Delegated RPKI* section now shows **active**,
    with the date of the latest Up-Down exchange and the count of objects in
    the repository.

> **Why two separate parts?** Because they're two independent things. The
> first says *which resources are yours*; the second says *where you're going
> to publish the signed objects*. A RIR can certify your resources while you
> publish somewhere else - including your own publication server.

**Notice what you have *not* done:** created a ROA, or an ASPA object. Your
resources are certified, but nothing says who may announce them. That's where
the story begins.

---

## Preparation 2-B — Certify your resources (MODE=beta)

> Only do this if `lab.conf` has `MODE=beta`. It needs Internet access and a
> beta.registro.br login.

1. Open Krill at **http://krill.localhost:8080**, log in with the token
   **`passlab`**, and create the CA **`minha_ca`**.

2. In another tab, log in to **https://beta.registro.br/login/**. In the
   Panel, go to *Holdership*, select the AS, and scroll down to the **RPKI**
   section → *Configure RPKI*.

3. In Krill, under *Parent CAs* → *Add a new parent CA*, copy the XML from
   the *Child Request* field and paste it into the field indicated on
   Registro.br.

4. On success, "RPKI enabled successfully!" appears, along with a
   **Parent response** field. Copy the XML and paste it into Krill, under
   *Parent CAs* → *Parent Response*, with the parent CA name
   **`nicbr_ca`**.

5. Still on Registro.br, under *Configure RPKI* → *Configure remote publication*.
   In Krill, under *Repository* → *Add a repository*, copy the *Publisher
   Request* and paste it there.

6. The field turns into **Repository response**. Copy it and paste it into
   Krill, under *Repository* → *Repository Response*.

7. In the end, Krill should show the resources received from the parent.

**Notice what you have *not* done:** created a ROA, or an ASPA object. Your
resources are certified, but nothing says who may announce them. That's where
the story begins. (On beta, expect objects to take a few minutes to reach the
validators whenever a step asks you to create one.)

---

## Step 1 — A clean baseline

> **State:** stage `none` (no validation) · AS666 silent · peer silent · no ROAs,
> no ASPA.
>
> **If yours differs:** `./scripts/lab.sh step1-clean` silences AS666 and the
> peer *and* puts both observers back to plain BGP. If ROAs or an ASPA object
> are left over from an earlier run (check with `krillc roas list` and `krillc
> aspas list` in the Krill terminal), the simplest way out is
> `./scripts/lab.sh reset`, then `up`, then Preparation 2 again - run from your
> own computer's terminal, not the panel's.

1. Make sure the lab is at its baseline:

   ```
   #./scripts/lab.sh step1-clean
   ```

2. Check that the origin's prefix reaches both observers, over both
   providers - and which one they prefer:

   ```
   # Panel: click the observer1 box, then Shell:
   #birdc show route table master4 all 203.0.113.0/24
   # Panel: click the observer2 box, then Shell:
   #bgpctl show rib 203.0.113.0/24
   # Or, from your computer's terminal:
   #docker exec lab-observer1 birdc show route table master4 all 203.0.113.0/24
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   203.0.113.0/24  unicast [provider_b_v4 ...] * (100) [AS64500i]
        bgp_path: 64502 64500
        bgp_local_pref: 100

                unicast [provider_a_v4 ...] (100) [AS64500i]
        bgp_path: 64501 64500 64500 64500
        bgp_local_pref: 100
   ```

   ```
   flags  vs destination          gateway          lpref   med aspath origin
   *>    N-? 203.0.113.0/24          10.200.6.10       100     0 64502 64500 i
   *     N-? 203.0.113.0/24          10.200.5.10       100     0 64501 64500 64500 64500 i
   ```

   Two paths on each observer: `64502 64500` (selected: the origin's preferred way in, 2
   hops) and `64501 64500 64500 64500` (the backup, kept in the table but 4 hops
   long because of the prepends). There are no
   verdicts on them (BIRD has no communities; OpenBGPD's `N-?` is just "nothing
   to compare against", and the panel shows `-` for both) - because **the
   observers aren't validating anything yet.** The panel's header badge says
   *validation: none*.

3. **Take a look at how these routers are configured.** Open the observers'
   baseline files (in the Lab commands terminal, your own terminal in the
   lab's folder, or your editor):

   ```
   #cat bird/observer1-none.conf
   #cat openbgpd/observer2-none.conf
   ```

   You'll find ordinary BGP: sessions with the two providers (and with AS666,
   which is silent for now), and a policy that accepts everything:

   ```
   template bgp CUSTOMER4 {
       local as OBSERVER1_ASN;
       ipv4 {
           import all;                 # <- BIRD: accept whatever the neighbor sends
           export none;
           import table on;
       };
   }
   ```

   ```
   deny from any
   allow from any                      # <- OpenBGPD: same idea
   ```

   There's no RTR session to Routinator or FORT (both are running, but nothing
   listens to them), and nothing that could tell a ROA from a hole in the
   wall. Everything the story does to these two files, from here on, is what
   *deploying RPKI validation* on a router looks like.

**Along the way:** the validators, the CA and the repository all exist by now,
and the resources are certified - and still, from where a router sits, none of
it matters until the router is told to listen.

---

## Step 2 — The naive hijack

> **State:** stage `none` · AS666 silent (about to change) · peer silent · no
> ROAs, no ASPA.
>
> **If yours differs:** `./scripts/lab.sh step1-clean`.

AS666 announces the origin's prefix as if it were its own.

1. Switch it on:

   ```
   #./scripts/lab.sh step2-hijack-simple
   ```

2. **Before you look:** AS666's path is just `666` - shorter than the
   legitimate `64502 64500` (and than the backup through A). Which one do you expect the observers to prefer?
   Is there *anything* the observers could use to tell the two apart?

3. Now look:

   ```
   # Panel: click the observer1 box, then Shell:
   #birdc show route table master4 all 203.0.113.0/24
   # Panel: click the observer2 box, then Shell:
   #bgpctl show rib 203.0.113.0/24
   # Or, from your computer's terminal:
   #docker exec lab-observer1 birdc show route table master4 all 203.0.113.0/24
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   203.0.113.0/24  unicast [attacker_v4 ...] * (100) [AS666i]
        bgp_path: 666
        bgp_local_pref: 100
   ```

   ```
   *>    N-? 203.0.113.0/24          10.200.8.10       100     0 666 i
   *     N-? 203.0.113.0/24          10.200.6.10       100     0 64502 64500 i
   *     N-? 203.0.113.0/24          10.200.5.10       100     0 64501 64500 64500 64500 i
   ```

   The hijack **won**: it's the selected route (`*`, `*>`) on both observers -
   its AS path is shorter (1 hop against 2 and 4), and nothing else distinguishes it. On the panel,
   the attacker's pill reads *hijacking* and its links to the observers turn
   **amber**: an observer is accepting what it announces. The *Verdicts* table
   has new rows labeled *AS666*, with no verdicts, because there is no
   validation.

**Along the way:** a hijack with the wrong origin ASN - the oldest trick there
is, and the one ROAs were invented for.

---

## Step 3 — ROV enters, marking what looks wrong

> **State:** stage `none` (about to change) · AS666 doing the naive hijack ·
> peer silent · no ROAs yet (you'll create them here), no ASPA.
>
> **If yours differs:** `./scripts/lab.sh step1-clean`, then
> `./scripts/lab.sh step2-hijack-simple`.

This step has two halves, in this order: the **Origin publishes** ROAs, and
the **Observers validate** them - only marking, for now.

### The Origin publishes: create the ROAs

> **Wait for the CA to receive its certificate before creating ROAs.** Right
> after the preparation the CA might not yet have the parent's resource
> class, and Krill accepts the command without creating anything. Check under
> *ROAs* that Krill already shows your prefixes; if the list is empty, wait a
> few seconds or run `docker exec lab-krill krillc bulk refresh`.

1. In Krill, go to the **ROAs** section and click *Add ROA*.

2. Create the IPv4 ROA:

   | field | value |
   |---|---|
   | ASN | 64500 |
   | Prefix | 203.0.113.0/24 |
   | Max length | 24 |

3. Create the IPv6 ROA:

   | field | value |
   |---|---|
   | ASN | 64500 |
   | Prefix | 3fff:cafe::/32 |
   | Max length | 32 |

   (Prefer the command line? In the Krill box's terminal:
   `krillc roas update --add "203.0.113.0/24-24 => 64500"`, and the same with
   `"3fff:cafe::/32-32 => 64500"`. If Krill says an ROA is a *duplicate*,
   it's already there.)

4. Make the validators pick them up, and check that they did:

   ```
   #./scripts/lab.sh refresh
   #./scripts/validate.sh
   ```

   `validate.sh` prints what Routinator validated (two ROAs). On the panel,
   the Routinator and FORT boxes show `2 VRP`. If nothing shows up yet, **it's
   a matter of time**: Krill has to publish and the validators have to reread
   (seconds in local mode, minutes on beta); run `refresh` again.

Right now nothing has changed for the routers: the ROAs are published and
validated, and **no router is listening to the validators.** Look at the
observers again if you like - the hijack is still winning.

### The Observers validate

1. Deploy ROV on both observers, in its safe first form:

   ```
   #./scripts/lab.sh step3-rov-mark
   ```

2. **See what this deployment is made of.** Compare the new files with the
   baseline you read in Step 1 (`diff` shows exactly what was added):

   ```
   #diff bird/observer1-none.conf bird/observer1-rov-mark.conf
   #diff openbgpd/observer2-none.conf openbgpd/observer2-rov-mark.conf
   ```

   Three ideas, on both routers:

   **(a) A session to a validator**, over which the router learns the ROAs:

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

   **(b) A test on every route**, comparing its origin AS (the *last* AS in the
   path) and prefix with the ROAs. BIRD computes it in the import filter and
   records the result in a large community, so you can read it later;
   OpenBGPD computes it natively into the route's `ovs` attribute:

   ```
   filter import_customer_v4 {                     # observer1 (BIRD)
       if roa_check(roa4_table, net, bgp_path.last) = ROA_INVALID then {
           bgp_large_community.add((OBSERVER1_ASN,1,0));
           bgp_local_pref = 10;                    # <- (c) an action: lose to any valid route
       } else if roa_check(roa4_table, net, bgp_path.last) = ROA_VALID then
           bgp_large_community.add((OBSERVER1_ASN,1,2));
       else
           bgp_large_community.add((OBSERVER1_ASN,1,1));
       accept;
   }
   ```

   **(c) An action on the result.** In this stage the action is only to
   *lower the preference* of an invalid route - nothing is rejected:

   ```
   match from any ovs invalid    set { localpref 10 }      # observer2 (OpenBGPD)
   ```

   > **This is not a BIRD or OpenBGPD thing.** Any router that supports ROV
   > has the same three pieces, with different syntax: a session to a
   > validator (RTR), a policy that matches the validation state, and an
   > action. On Cisco IOS XR it's a `route-policy` testing `validation-state`;
   > on Junos, a `policy-statement` matching `validation-database`; on
   > Huawei, `if-match rpki` in a route-policy - check your platform's
   > documentation for the exact syntax. BIRD and OpenBGPD are used here
   > because they're free and easy to run in containers, not because they're
   > what you'll meet at work: what carries over is the anatomy.
   >
   > If you'd rather type the configuration yourself than read it: start
   > from `bird/observer1-none.conf`, add the pieces above, save the result as
   > a new file in `bird/`, and load it with `docker exec lab-observer1 birdc
   > 'configure "/etc/bird-lab/your-file.conf"'`. The script only saves you
   > the typing.

3. Now look at the routes again:

   ```
   # Panel: click the observer1 box, then Shell:
   #birdc show route table master4 all 203.0.113.0/24
   # Panel: click the observer2 box, then Shell:
   #bgpctl show rib 203.0.113.0/24
   # Or, from your computer's terminal:
   #docker exec lab-observer1 birdc show route table master4 all 203.0.113.0/24
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   203.0.113.0/24  unicast [attacker_v4 ...] (100) [AS666i]
        bgp_path: 666
        bgp_local_pref: 10
        bgp_large_community: (64510, 1, 0)                   <- ROV Invalid
   ```

   ```
   *>    V-? 203.0.113.0/24          10.200.6.10       100     0 64502 64500 i
   *     V-? 203.0.113.0/24          10.200.5.10       100     0 64501 64500 64500 64500 i
   *     !-? 203.0.113.0/24          10.200.8.10        10     0 666 i
   ```

   The hijack is still in the table - visible, not gone - but now it carries
   **ROV Invalid** and a `local_pref` of 10, so it loses to the legitimate
   paths, and Provider B's is the selected route again. The badge in the header says
   *ROV: marking*, and the attacker's links turn **red**: it's announcing,
   and both observers are flagging it. Everything you needed to check is
   right: the hijack is flagged, the legitimate paths are `Valid`, and nothing
   legitimate got hurt. **That's the point of the marking stage** - you get to
   see what the check *would* do before you let it reject anything.

   **This is where ROV stays for the rest of the story - marking, not
   dropping.** A router that only marks still uses an invalid route whenever
   it's the best one it has, so marking alone isn't the end of the job; it's
   the rehearsal. You'll see what real, production dropping looks like - for
   ROV and ASPA together, at once - in Step 8, once both checks have had
   their turn to prove themselves this way.

### How to read the verdicts

The two observers show them differently:

- **observer1 (BIRD)** has no per-route validation attribute, so its
  filters record each verdict in a large community:

  | community | meaning | | community | meaning |
  |---|---|---|---|---|
  | (64510,1,0) | ROV Invalid | | (64510,2,0) | ASPA Invalid |
  | (64510,1,1) | ROV NotFound | | (64510,2,1) | ASPA Unknown |
  | (64510,1,2) | ROV Valid | | (64510,2,2) | ASPA Valid |

- **observer2 (OpenBGPD)** computes both natively. The `vs` column is the
  pair **ovs-avs**: origin validation state, then ASPA validation state,
  each one `V` (valid), `!` (invalid), or `N`/`?` (not-found / unknown).
  So `V-!` is ROV Valid and ASPA Invalid. (No ASPA verification is
  deployed yet, so the second half is `?` for now.)

**Along the way:** what "deploying ROV" is made of - an RTR session, a test on
every route, and an action on the result - and how new objects reach the
routers: Krill publishes, the validators reread, the routers get the change
over RTR. You just watched every hop.

---

## Step 4 — The forged path

> **State:** stage `rov-mark` · AS666 doing the naive hijack (marked invalid,
> losing) · peer silent · ROAs for both prefixes · no ASPA.
>
> **If yours differs:** `./scripts/lab.sh step4-hijack-posrov` - it also makes
> sure the ROAs exist and puts the observers back in `rov-mark`.

AS666 reads the same documentation you did. ROV only looks at the **last** AS
in the path - so what if the last AS were the right one?

1. Switch AS666 to the forged-path attack:

   ```
   #./scripts/lab.sh step4-hijack-posrov
   ```

   AS666 now announces the path `666 64500`: as if it had received the
   prefix directly from the real origin.

   **That relationship is a lie.** AS666 has no BGP session - no peering, no
   transit, nothing - with AS64500: the two aren't even connected. The
   `666 64500` adjacency exists only because AS666's configuration *writes it into
   the path*. Have a look at how it does that:

   ```
   # Panel: click the attacker box, then Shell:
   #cat /etc/bird.conf
   # Or, from your computer's terminal:
   #cat bird/attacker-posrov.conf
   ```

   Find the `forge_export` filters: `bgp_path.prepend(ORIGIN_ASN)` puts the
   origin's number into the path *before* the router adds its own on export -
   that's the whole forgery. Compare it with `bird/attacker-simple.conf` (no
   filter, so the path is just `666`), and check that neither file has a
   session with the origin: only the two observers.

2. **Before you look:** ROV is only marking right now, not dropping anything
   - but the naive hijack still got flagged Invalid and lost the race. Will
   this forged path get flagged the same way?

3. Look:

   ```
   # Panel: click the observer2 box, then Shell:
   #bgpctl show rib 203.0.113.0/24
   # Or, from your computer's terminal:
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   flags  vs destination          gateway          lpref   med aspath origin
   *>    V-? 203.0.113.0/24          10.200.8.10       100     0 666 64500 i
   *m    V-? 203.0.113.0/24          10.200.6.10       100     0 64502 64500 i
   *     V-? 203.0.113.0/24          10.200.5.10       100     0 64501 64500 64500 64500 i
   ```

   It isn't flagged. ROV says `Valid` - the path ends in 64500, which is
   exactly what the ROA authorizes - so it gets full `local_pref` (100) like
   any legitimate route, and it's the selected one. The attacker's links on
   the panel turn **amber**: no longer red, because ROV has nothing to flag.
   Three paths, all "valid", one of them a lie, and *nothing you have
   deployed so far can tell which*.

   > The forged path (`666 64500`, 2 hops) ties with Provider B's (`64502 64500`, also 2),
   > and the attacker wins the tie by a tie-breaker (its router ID happens to
   > be the lowest); Provider A's backup is 4 hops long and never in the race.
   > That's beside the point: the point is that ROV has handed you three
   > equally valid-looking routes and no way to choose between them.

**Along the way:** can origin validation tell two paths for the same prefix
apart, when the origin is the same and a ROA matches? Now you know: it can't.
It only ever looks at the last AS.

---

## Step 5 — ASPA enters, also marking first

> **State:** stage `rov-mark` · AS666 forging the path · peer silent · ROAs for
> both prefixes · no ASPA yet (you'll create it here).
>
> **If yours differs:** `./scripts/lab.sh step3-rov-mark` and
> `./scripts/lab.sh step4-hijack-posrov`; if an ASPA object already exists,
> `krillc aspas remove --customer AS64500` in the Krill terminal.

Same shape as Step 3: the **Origin publishes** an ASPA object, then the
**Observers validate** it - in the same safe, marking-only form ROV used.

### The Origin publishes: create the ASPA object

Krill 0.16 still does **not** have ASPA in the web UI - it's managed from the
command line (the UI is on its way in the next release).

1. On the panel, click the **Krill** box, then the **Terminal (krillc)**
   button. (Or, from your own terminal: `docker exec -it lab-krill bash`.)

2. See that there's no ASPA yet:

   ```
   #krillc aspas list
   ```

3. Create the ASPA object declaring which providers may propagate routes from
   AS64500. For the story's sake, list **only Provider A** for now - you'll
   see why in the next step:

   ```
   #krillc aspas add --aspa "AS64500 => AS64501"
   ```

4. Check it, and make the validators pick it up:

   ```
   #krillc aspas list
   #./scripts/lab.sh refresh
   ```

> **About the notation.** Krill's syntax accepts a per-address-family
> restriction (`AS64501(v4)`), but the ASPA profile's final version at the
> IETF **removed** that option: a single ASPA object applies to both IPv4 and
> IPv6 at once. Don't use the `(v4)`/`(v6)` qualifiers.
>
> **One object per customer AS.** The RFC requires exactly one ASPA object
> per customer ASN, listing *all* the providers. `krillc aspas add` replaces
> the whole object (so it's safe to repeat); to change the list, use
> `krillc aspas update`.
>
> **Watch out for a flag.** Without `--enable-aspa`, Routinator simply
> ignores ASPA objects. It's the number-one mistake when setting up a lab
> like this one; here it's already on.

As with ROAs, nothing changes for the routers yet: the object is published,
and no router is verifying paths.

### The Observers validate

1. Deploy ASPA verification on both observers - ROV keeps only marking:

   ```
   #./scripts/lab.sh step5-aspa-mark
   ```

2. **Compare with the stage you just left** (`rov-mark`):

   ```
   #diff bird/observer1-rov-mark.conf bird/observer1-aspa-mark.conf
   #diff openbgpd/observer2-rov-mark.conf openbgpd/observer2-aspa-mark.conf
   ```

   The same three ideas, this time for paths:

   **(a) The validator now also delivers ASPA objects.** ASPA only travels in
   RTR version 2, so each router asks for it:

   ```
   aspa table aspa_table;                          # observer1 (BIRD)
   protocol rpki routinator {
       ...
       aspa { table aspa_table; };                 # ASPA only exists on RTR version 2
   }
   ```

   ```
   rtr 172.30.0.50 {                               # observer2 (OpenBGPD)
       port 3323
       min-version 2                               # without it, no ASPA ever arrives
   }
   ```

   **(b) A test on every path**, and **(c) an action on the result** - in this
   stage, only marking:

   ```
   case aspa_check_upstream(aspa_table) {          # observer1 (BIRD)
       ASPA_INVALID: {
           bgp_large_community.add((OBSERVER1_ASN,2,0));
           bgp_local_pref = 20;                    # lose to a valid path
       }
       ASPA_VALID: {
           bgp_large_community.add((OBSERVER1_ASN,2,2));
           bgp_local_pref = 200;                   # prefer a proven path
       }
       ASPA_UNKNOWN: bgp_large_community.add((OBSERVER1_ASN,2,1));
   }
   ```

   ```
   neighbor 10.200.5.10 {                          # observer2 (OpenBGPD)
       remote-as $provider_a_asn
       role provider                               # <- what turns ASPA verification on
   }
   ...
   match from any avs invalid    set { localpref 20 }      # lose to a valid path
   match from any avs valid      set { localpref 200 }     # prefer a proven path
   ```

   > **Why "upstream"?** The observer treats each neighbor as its
   > *customer*: for routes coming from a customer, the strictest algorithm
   > applies - every hop of the path has to be an authorized
   > customer→provider pair. BIRD asks for it by name
   > (`aspa_check_upstream`); OpenBGPD selects it through the session's RFC
   > 9234 role. It's also the check that catches route leaks - you'll meet one
   > in Step 7. Extra exercise A takes it apart, and shows what changes if you
   > ask the *downstream* algorithm instead.
   >
   > ASPA verification is newer than ROV, and support in commercial
   > platforms is still arriving. Where it exists, it has the same anatomy as
   > the ROV deployment you saw in Step 3.

3. Look at the routes:

   ```
   # Panel: click the observer2 box, then Shell:
   #bgpctl show rib 203.0.113.0/24
   # Or, from your computer's terminal:
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   *>    V-V 203.0.113.0/24          10.200.5.10       200     0 64501 64500 64500 64500 i
   *     V-! 203.0.113.0/24          10.200.8.10        20     0 666 64500 i
   *     V-! 203.0.113.0/24          10.200.6.10        20     0 64502 64500 i
   ```

   The forged path is now **ASPA Invalid** - the hop `64500 → 666` isn't
   authorized, since only 64501 is listed. It's still visible, but with a
   `local_pref` of 20 it loses to Provider A's path (`V-V`, 200). The
   attacker's links turn **red** again, and the badge reads *ROV: marking ·
   ASPA: marking*.

   Two routes carry `V-!`, though - not one. Look closely at the second one:
   it's **Provider B**, the origin's own preferred way in from Step 1's
   traffic engineering. The ASPA object you just created only lists Provider
   A, so ASPA calls Provider B's path invalid too - and what got selected
   instead is Provider A's path, the *backup*, the one the origin deliberately
   made longer with its prepends. Because nothing is dropped yet, you get to
   see this mistake before it costs anything: hold that thought into the next
   step.

**Along the way:** the ASPA verdict that ROV could never give - the path
itself is what's wrong, even though the origin is right - and a reminder of
why marking runs before dropping: it let you catch a mistake in your own
ASPA object before it took anything down.

---

## Step 6 — You forgot a provider

> **State:** stage `aspa-mark` · AS666 forging the path · peer silent · ROAs for
> both prefixes · ASPA listing Provider A only.
>
> **If yours differs:** `./scripts/lab.sh step5-aspa-mark`, and in the Krill
> terminal `krillc aspas add --aspa "AS64500 => AS64501"` (this replaces the
> object with exactly that list), then `./scripts/lab.sh refresh`.

The route you noticed at the end of the last step - Provider B's, marked
ASPA Invalid alongside the forged one - is a *legitimate* path, **the very
one the origin prefers**, demoted for no better reason than an incomplete
object. The observers are left using the backup path, the one the origin
deliberately made longer with its prepends: the origin's traffic engineering,
undone by an incomplete ASPA. Once this stage drops instead of marks (Step
8), this is the day the traffic that used to arrive through that interface
stops arriving, and someone starts asking why. (This lab has no data plane, so
you can't watch traffic stop; you can watch the route's preference collapse,
which is the same thing said differently.)

1. Fix the object:

   ```
   #krillc aspas update --customer AS64500 --add "AS64502"
   #krillc aspas list
   #./scripts/lab.sh refresh
   ```

2. Check the observers:

   ```
   # Panel: click the observer2 box, then Shell:
   #bgpctl show rib 203.0.113.0/24
   # Or, from your computer's terminal:
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   *>    V-V 203.0.113.0/24          10.200.6.10       200     0 64502 64500 i
   *     V-V 203.0.113.0/24          10.200.5.10       200     0 64501 64500 64500 64500 i
   *     V-! 203.0.113.0/24          10.200.8.10        20     0 666 64500 i
   ```

   Both legitimate paths are back at `V-V` and `local_pref` 200, and Provider
   B - the origin's preferred way in - is reselected: once they're tied on
   preference, its shorter path wins. The forged one stays demoted (`V-!`,
   20), and AS666 - still announcing - stays defeated. Notice how the fix
   didn't involve AS666 at all: the ASPA object describes *your*
   relationships, and anything that contradicts them loses.

   (`./scripts/lab.sh step6-add-provider-b` does exactly this fix - it's the
   command to jump straight to this step's state later, from anywhere in the
   story, without typing the `krillc` command by hand again.)

3. BIRD picked up the change on its own, with nobody touching the router,
   because its sessions are set up with `import table on` and `rpki reload
   on`. To force revalidation by hand:

   ```
   # Panel: click the observer1 box, then Shell:
   #birdc reload in provider_b_v4
   # Or, from your computer's terminal:
   #docker exec lab-observer1 birdc reload in provider_b_v4
   ```

**Along the way:** what happens when an ASPA object forgets a real provider -
half the Internet starts seeing that provider's routes as invalid - and how
a fix propagates: republish, revalidate, no router touched.

Leave AS666 running. It's harmless now, and it'll be a useful reminder on the
panel of what's being kept out.

---

## Step 7 — The peer leaks (and ASPA catches what ROV can't)

> **State:** stage `aspa-mark` · AS666 forging the path (marked, losing) · peer
> silent · ROAs for both prefixes · ASPA listing Providers A and B.
>
> **If yours differs:** `./scripts/lab.sh step6-add-provider-b` - it sets up
> everything this step needs (ASPA listing both providers, peer silent)
> without the leak.

This one is nobody's attack. The peer - a legitimate network - has a private
peering link with the origin, so it *learns* the origin's prefixes. A peering
link is bilateral: what the peer learns there is not for its own provider.
Then somebody edits a configuration...

1. Switch the leak on:

   ```
   #./scripts/lab.sh step7-leak-on
   ```

   The peer now re-announces to Provider A what it learned from the origin.
   Nothing is forged - the peer is telling the truth about where the route
   came from. On the panel, the peer's pill reads *leaking*.

2. **Before you look:** Provider A now has two routes for the origin's
   prefix - the origin's own, and the peer's. Which one does Provider A pass
   on to the observers? And once it arrives, still only *marking* what looks
   invalid, will you be able to see it?

3. Look at Provider A first:

   ```
   # Panel: click the provider-a box, then Shell:
   #birdc show route 203.0.113.0/24 all
   # Or, from your computer's terminal:
   #docker exec lab-provider-a birdc show route 203.0.113.0/24 all
   ```

   ```
   203.0.113.0/24  unicast [customer_peer_v4 ...] * (100) [AS64500i]
        bgp_path: 64999 64500
        bgp_local_pref: 100
                unicast [customer_v4 ...] (100) [AS64500i]
        bgp_path: 64500 64500 64500
        bgp_local_pref: 100
   ```

   Provider A only ever passes on its *best* route, and nothing special was
   configured to make the peer's win: it's simply **shorter** - 2 hops
   against the origin's own 3. The prepends that made Provider A the
   *backup* also made a leak through it irresistible. (That's typical: a
   leaked route wins because someone's traffic engineering made the honest
   path look worse. See `bird/provider-a.conf` - there's no policy there at
   all.)

4. Now the observers:

   ```
   # Panel: click the observer2 box, then Shell:
   #bgpctl show rib 203.0.113.0/24
   # Or, from your computer's terminal:
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   *>    V-V 203.0.113.0/24          10.200.6.10       200     0 64502 64500 i
   *     V-! 203.0.113.0/24          10.200.8.10        20     0 666 64500 i
   *     V-! 203.0.113.0/24          10.200.5.10        20     0 64501 64999 64500 i
   ```

   **Provider A's own path is already gone** - it stopped advertising it the
   moment it picked the peer's shorter one as best, and that has nothing to
   do with what the observers do with what they receive. What arrives from
   Provider A instead is the leaked path, `64501 64999 64500` - and
   because marking never removes anything from the table, you get to look
   straight at it. Two things to notice:

   - **ROV Valid.** Of course - the origin really is 64500. Nothing is
     forged. *A leak can never be caught by ROV*: it doesn't lie about who
     originated the prefix, it lies about the *shape of the path*.
   - **ASPA Invalid.** The hop `64500 → 64999` was never authorized: the
     origin's ASPA object lists Providers A and B, and the peer is neither.

   The peer's link on the panel turns **red**. Provider B's path is still
   what's selected (`V-V`, 200) - it doesn't need any help from ASPA to win,
   since it's also the shorter one - but the damage is real: the origin has
   lost its *backup*, and Provider A's other customers are now sending their
   traffic to the origin through the peer.

**Along the way:** a route leak is nobody forging anything - it's a route
crossing a boundary it was never supposed to cross - and it's a verdict ROV
structurally cannot give, because the origin at the end of the path is
telling the truth. ASPA catches it for the same reason it caught Step 4's
forgery: an unauthorized hop, wherever in the path it happens to sit.

---

## Step 8 — Deploying for real: drop

> **State:** stage `aspa-mark` · AS666 forging the path (marked, losing) · the peer
> leaking (marked, losing) · ROAs for both prefixes · ASPA listing Providers A and B.
>
> **If yours differs:** `./scripts/lab.sh step7-leak-on` - it sets up
> everything this step needs, leak included.

Every invalid route you've seen so far has stayed on the table, demoted but
visible - deliberately, so you could look at exactly what each check decided
before trusting it with anything. **A real router doesn't stop there.**
Marking a route invalid and still using it whenever nothing better shows up
is not what ROV or ASPA are for; both only protect anything once an invalid
route is actually rejected. This is the step where that happens - for both
checks, together, the way you'd configure a production router from the
start.

1. Switch both observers to dropping:

   ```
   #./scripts/lab.sh step8-drop
   ```

2. Compare the stage you just left with this one - the change is one line of
   policy per check, on each router:

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

3. Look at the routes again:

   ```
   # Panel: click the observer2 box, then Shell:
   #bgpctl show rib 203.0.113.0/24
   # Or, from your computer's terminal:
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   *>    V-V 203.0.113.0/24          10.200.6.10       200     0 64502 64500 i
   ```

   **Two routes disappeared, not one.** AS666's forged path is gone, as
   expected. So is the entry that used to sit under Provider A - the leaked
   path you just inspected. It isn't lost; BIRD keeps what it rejected:

   ```
   # Panel: click the observer1 box, then Shell:
   #birdc show route table master4 filtered 203.0.113.0/24
   # Or, from your computer's terminal:
   #docker exec lab-observer1 birdc show route table master4 filtered 203.0.113.0/24
   ```

   The badge now reads *ROV + ASPA: dropping*. Notice what dropping did
   **not** fix: Provider A's own, legitimate path is still nowhere to be
   seen, because Provider A itself is still advertising the leaked route
   *instead of* its own - and no policy on the observers can make Provider A
   propagate something it isn't sending. ASPA protects the observers from
   *using* the leak; only the peer fixing its export policy stops the leak at
   the source. That's next.

**Along the way:**

- **Marking versus dropping.** Same verdicts as Steps 3, 5 and 7 - the policy
  is what changed. Marking is how you roll a check out without breaking
  anything; dropping is what the check is *for*, and it's what turns a
  diagnostic into a defense.
- **Dropping doesn't repair upstream damage.** It only controls what the
  observers themselves accept. Provider A propagating the leak is a separate
  problem, fixed at the source, not at the observers.
- **From here on, both checks keep dropping.** A router that has learned to
  reject invalid routes doesn't go back.

---

## Step 9 — Put it away

> **State:** stage `aspa-drop` · AS666 forging the path (defeated) · the peer
> leaking · ROAs for both prefixes · ASPA listing Providers A and B.

1. Stop the leak:

   ```
   #./scripts/lab.sh step9-leak-off
   ```

   Provider A's own path returns on both observers.

2. If you're going on to the extra exercises, silence AS666 too - they'll be
   easier to read without it:

   ```
   #./scripts/lab.sh step9-hijack-off
   ```

The observers stay fully deployed - ROV and ASPA both dropping - which is
where a real router ends up. (`./scripts/lab.sh step1-clean` is the way back
to the very beginning: it silences AS666 and the peer, *and* takes validation
off the observers.)

---

## Recap - what caught what, and what the story answered

| Attack | ROV | ASPA |
|---|---|---|
| Naive hijack (AS_PATH `666`) | **catches it** (wrong origin) | nothing to check (one-AS path) |
| Forged path (AS_PATH `666 64500`) | **fooled** (origin looks right) | **catches it** (the hop `64500 → 666` isn't authorized) |
| Route leak (AS_PATH `64501 64999 64500`) | **can't see it** (origin is genuine) | **catches it** (the hop `64500 → 64999` isn't authorized) |

Neither is redundant. ROV stops attackers who lie about the origin; ASPA stops
paths that couldn't have happened. And the origin has to do its part: an ASPA
that forgets a real provider (Step 6) is its own outage.

Along the way, the story quietly answered questions this lab used to ask one
exercise at a time:

- **What does "deploying validation" on a router actually consist of?** A
  session to a validator, a test on every route or path, and an action on the
  result - the same three pieces for ROV (Step 3) and ASPA (Step 5), on any
  vendor's router.
- **Why mark first and drop later - and why drop at all?** Marking lets you
  see what a check would do before you trust it, and it's what caught your
  own incomplete ASPA object in Step 6 before it broke anything; dropping is
  what real routers do, and what makes the check protect anything - Step 8
  turns both checks on at once, the way a production router is configured
  from the start.
- **Can ROV tell two paths for the same prefix apart?** No (Step 4).
- **What does a hijack with the wrong origin ASN look like?** Step 2, and how
  ROV flags it in Step 3.
- **What happens when an ASPA forgets a real provider?** Step 6.
- **Does a fix propagate on its own?** BIRD revalidates by itself; the objects
  take a republish and a revalidation to arrive (Steps 3, 5 and 6).
- **Do the two independent stacks agree?** Every step shows both, and they
  agree everywhere the story looks - Extra exercise A shows where they don't.
- **What's a route leak, and why can't ROV see it?** Step 7 shows it; Step 8
  shows what dropping does, and doesn't, fix about it.

Four topics didn't fit in the story, and live in the extras below: how the
upstream and downstream algorithms differ (and the `role` that selects one),
a hijack that gets the ASN right but the length wrong, a look inside the
validators and RTR, and the **NotFound** and **Unknown** verdicts - the "no
opinion" ones you haven't met yet, because the story never left a prefix
uncovered.

---

## Extra exercises

The extras assume you finished the story (the observers in `aspa-drop`, the
peer silent, `step9-hijack-off` run) with objects for both prefixes and an
ASPA listing Providers A and B. Each one says which stage it wants; the `step`
commands move both observers there in one go.

### A. Upstream, downstream, and the role that decides

*Stage:* `step5-aspa-mark`.

In `bird/observer1-aspa-mark.conf` the ASPA check is:

```
case aspa_check_upstream(aspa_table) { ... }
```

The observer treats each neighbor as its **customer**. For routes coming from
a customer, the *Algorithm for Upstream Paths* applies - the strictest one:
every hop in the path has to be an authorized customer→provider relationship.
This is the check that catches route leaks. If the session were with a provider
or a peer, the right call would be `aspa_check_downstream()`, which is more
permissive. BIRD offers both.

OpenBGPD does it with a session **role** (RFC 9234). Look at
`openbgpd/observer2-aspa-mark.conf`:

```
neighbor 10.200.5.10 {
    remote-as $provider_a_asn
    role provider
}
```

OpenBGPD only performs ASPA verification on a session that carries a role, and
**the role decides which ASPA algorithm runs**. `role provider` says the local
system is the providers' upstream - routes arrive from a customer - and that
selects the *upstream* algorithm, the same one observer1 asks BIRD for with
`aspa_check_upstream()`.

To see the difference, you need a path that the strict algorithm rejects and
the permissive one doesn't. Take Provider B back out of the ASPA object (in the
Krill terminal):

```
#krillc aspas add --aspa "AS64500 => AS64501"
#./scripts/lab.sh refresh
```

The path through Provider B now reads Invalid on both observers.

1. **Before you change anything:** the objects on disk won't change at all -
   only one word in a config file will. Do you expect the path through
   Provider B to still read Invalid, or to flip?

2. `openbgpd/observer2-extra-a-role-customer.conf` is
   `openbgpd/observer2-aspa-mark.conf` with exactly that one word changed:
   `role provider` to `role customer` on the Provider B neighbors
   (10.200.6.10 and fd00:6::10). Open it and compare (`diff
   openbgpd/observer2-aspa-mark.conf openbgpd/observer2-extra-a-role-customer.conf`),
   then apply it by hand - not through `lab.sh`, since this state only exists
   for this exercise:

   ```
   # Panel: click the observer2 box, then Shell:
   #cp /etc/openbgpd-lab/observer2-extra-a-role-customer.conf /etc/bgpd.conf && bgpctl reload
   #bgpctl show rib 203.0.113.0/24
   # Or, from your computer's terminal:
   #docker exec lab-observer2 sh -c "cp /etc/openbgpd-lab/observer2-extra-a-role-customer.conf /etc/bgpd.conf && bgpctl reload"
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   The path through Provider B comes back **Valid**. Same objects, same
   AS_PATH, a different verdict - and neither implementation is wrong. It is
   the clearest demonstration in this lab that "is this path ASPA-valid?"
   cannot be answered without also saying *from whom* you received it.

3. Now do the equivalent on BIRD: `bird/observer1-extra-a-downstream.conf` is
   `bird/observer1-aspa-mark.conf` with `aspa_check_upstream` swapped for
   `aspa_check_downstream` in both filters - open it and compare the same
   way, then apply it by hand:

   ```
   # Panel: click the observer1 box, then Shell:
   #birdc configure "/etc/bird-lab/observer1-extra-a-downstream.conf"
   # Or, from your computer's terminal:
   #docker exec lab-observer1 birdc configure "/etc/bird-lab/observer1-extra-a-downstream.conf"
   ```

   **Before you look:** do you expect observer1's new verdict to match
   observer2's `role customer` result (`Valid`), or its `role provider`
   result (`Invalid`)?

   ```
   # Panel: click the observer1 box, then Shell:
   #birdc show route table master4 all 203.0.113.0/24
   # Or, from your computer's terminal:
   #docker exec lab-observer1 birdc show route table master4 all 203.0.113.0/24
   ```

   Neither, quite: BIRD reports the Provider B path as **ASPA Unknown**
   (`(64510, 2, 1)`). Both readings are far more permissive than the upstream
   algorithm, which said `Invalid` - but where OpenBGPD calls the path valid,
   BIRD says it can't tell. Two independent implementations, reading an edge
   of the same draft differently.

4. Compare the observers side by side, then discuss: if "upstream" and
   "downstream" is fundamentally about *who you received the route from*,
   what should happen in a topology where the same neighbor is a provider for
   one prefix and a customer for another? (This is why BIRD's choice of
   algorithm is a per-session `aspa_check_*()` call rather than a lab-wide
   setting, and why OpenBGPD's `role` is set inside each `neighbor` block.)

5. Undo: restore `role provider` and `aspa_check_upstream`, re-add Provider B
   to the ASPA (`krillc aspas add --aspa "AS64500 => AS64501, AS64502"`),
   run `./scripts/lab.sh step5-aspa-mark` and `./scripts/lab.sh refresh`.

6. One more edge case, while you're here: switch AS666 back to its naive
   hijack (`./scripts/lab.sh step2-hijack-simple`). With **one AS** in the
   path there's no customer→provider hop to check, so ASPA has nothing to say
   about *who may originate a prefix* - that was never its job. BIRD calls
   such a path `Valid` (`(64510, 2, 2)`), OpenBGPD `Unknown` (`?`). Again two
   readings of an edge. Go back with `./scripts/lab.sh step9-hijack-off`.

### B. Right ASN, prefix too specific

*Stage:* `step3-rov-mark` (so the invalid route stays visible).

Step 2 was a hijack with the wrong origin ASN. This is the opposite mistake:
the origin is completely legitimate, but the prefix exceeds what the ROA
authorized. An IPv4 example would mean deaggregating 203.0.113.0/24 down to a
`/25` - something that gets filtered network-wide on the real Internet and
would feel contrived here. Announcing an IPv6 block more specific than a
`/32` (a `/36` or `/40`, say) is completely ordinary operational practice, so
that's what this exercise uses instead - and to make the point that it isn't
about either provider, it uses **two** sub-blocks of 3fff:cafe::/32, one
announced only to Provider A and the other only to Provider B.

`bird/origin-extra-b.conf` is `bird/origin.conf` plus exactly that: two
static routes for `3fff:cafe:1000::/40` and `3fff:cafe:2000::/40` (both
inside 3fff:cafe::/32, both more specific than 32 authorizes),
and each provider's export filter extended to also carry its own sub-block.
Open it and compare with `bird/origin.conf` (`diff bird/origin.conf
bird/origin-extra-b.conf`) before applying it by hand:

```
# Panel: click the origin box, then Shell:
#birdc configure "/etc/bird-lab/origin-extra-b.conf"
# Or, from your computer's terminal:
#docker exec lab-origin birdc configure "/etc/bird-lab/origin-extra-b.conf"
```

Look at what each provider actually received:

```
# Panel: click the provider-a box, then Shell:
#birdc show route
# Panel: click the provider-b box, then Shell:
#birdc show route
```

Provider A has `3fff:cafe:1000::/40`; Provider B has `3fff:cafe:2000::/40` -
each only the one meant for it. Now the observers:

```
# Panel: click the observer2 box, then Shell:
#bgpctl show rib 3fff:cafe:1000::/40
#bgpctl show rib 3fff:cafe:2000::/40
# Or, from your computer's terminal:
#docker exec lab-observer2 bgpctl show rib 3fff:cafe:1000::/40
#docker exec lab-observer2 bgpctl show rib 3fff:cafe:2000::/40
```

```
*>    !-? 3fff:cafe:1000::/40  fd00:5::10         10     0 64501 64500 64500 64500 i
```

```
*>    !-? 3fff:cafe:2000::/40  fd00:6::10         10     0 64502 64500 i
```

Both paths are **ROV Invalid** - each a perfectly legitimate announcement
through an authorized provider, rejected for the same reason on both sides:
the ROA for 3fff:cafe::/32 only authorizes announcements up to
`/32`, and both sub-blocks are more specific than that. It
isn't about Provider A or Provider B - it's the prefix. In `rov-mark` both
stay visible, demoted, exactly like the hijack in Step 3. Run `step8-drop`
and they disappear the same way the hijack later did.

Undo when you're done:

```
# Panel: click the origin box, then Shell:
#birdc configure
# Or, from your computer's terminal:
#docker exec lab-origin birdc configure
```

> **The pattern:** ROV checks *what is being announced and by whom*. ASPA
> checks *whether the path that carried it here is one the origin
> authorized*. This exercise, and the naive hijack of Step 2, break ROV
> without touching ASPA; the forged path and the leak break ASPA without
> touching ROV. A real deployment wants both running.

### C. Inside the validators, and RTR

*Stage:* `step5-aspa-mark` (so both the ROA and the ASPA tables exist).

The story only looked at the routers' verdicts. This looks at how they got
there.

1. Open Routinator: **http://routinator.localhost:8080**

   It's configured to validate **only** the lab's own trust anchor, not the
   whole Internet:

   ```
   --no-rir-tals  --extra-tals-dir=/tals  --enable-aspa
   ```

   The TAL is installed automatically when the lab comes up. In `MODE=local`
   it comes from LabNIC's own trust anchor (and is available for download
   from the registry panel); in `MODE=beta`, from
   `https://rpki-test-ta.beta.registro.br/ta/ta.tal`.

2. Look at the validated set, with ROAs and ASPAs:

   ```
   #curl -s http://routinator.localhost:8080/json
   ```

3. See what observer1 received over RTR:

   ```
   # Panel: click the observer1 box, then Shell:
   #birdc show protocols all routinator
   #birdc show route table roa4_table
   #birdc show route table aspa_table
   # Or, from your computer's terminal:
   #docker exec lab-observer1 birdc show protocols all routinator
   #docker exec lab-observer1 birdc show route table roa4_table
   #docker exec lab-observer1 birdc show route table aspa_table
   ```

   The RTR protocol needs to be `Established`. The ASPA table only gets
   filled with **RTR version 2** - the version Routinator negotiates when
   ASPA is turned on.

4. And observer2, which gets its objects from FORT instead:

   ```
   # Panel: click the observer2 box, then Shell:
   #bgpctl show rtr
   #bgpctl show sets
   # Or, from your computer's terminal:
   #docker exec lab-observer2 bgpctl show rtr
   #docker exec lab-observer2 bgpctl show sets
   ```

   `show rtr` has to say `Version: 2`. ASPA only travels in RTR version 2
   PDUs: on version 1 the session still comes up and the ROAs still arrive,
   but every ASPA verdict would stay `unknown`. `show sets` lists one ROA
   entry for IPv4, one for IPv6, and one ASPA (`#ASnum 1`).

### D. NotFound and Unknown

*Stage:* `step5-aspa-mark`.

The story only ever showed **Valid** and **Invalid**. The other two verdicts -
**NotFound** (no ROA covers the prefix at all) and **Unknown** (no ASPA object
exists for that customer ASN) - are actually the *default*, most common state
on the real Internet, where most prefixes still have no RPKI coverage at all.
They never appeared because every route in the story was covered. Make them
appear on purpose, by taking objects away:

1. Remove the IPv4 ROA and the ASPA object:

   ```
   # Panel: click the krill box, then Shell:
   #krillc roas update --ca minha_ca --remove "203.0.113.0/24-24 => 64500"
   #krillc aspas remove --ca minha_ca --customer AS64500
   #krillc bulk publish
   # Or, from your computer's terminal:
   #docker exec lab-krill krillc roas update --ca minha_ca --remove "203.0.113.0/24-24 => 64500"
   #docker exec lab-krill krillc aspas remove --ca minha_ca --customer AS64500
   #docker exec lab-krill krillc bulk publish
   ```

2. Confirm they're really gone before moving on (`krillc roas list --ca
   minha_ca` and `krillc aspas list --ca minha_ca` should both come back
   without them), then refresh:

   ```
   #./scripts/lab.sh refresh
   ```

3. Check the verdicts for `203.0.113.0/24` on both observers: both paths should
   now read **ROV NotFound, ASPA Unknown** - "we have no opinion", not a
   rejection: they stay in the table even though both checks are on. Notice
   that `3fff:cafe::/32` is unaffected: its own ROA is still there, so it
   keeps its normal verdicts. Coverage is per prefix - having none for one
   says nothing about another. (This is also why deploying ROV protects
   nothing until the *other* ASes publish ROAs: a prefix with no ROA can't be
   caught by anything.)

4. Restore both objects and refresh again:

   ```
   # Panel: click the krill box, then Shell:
   #krillc roas update --ca minha_ca --add "203.0.113.0/24-24 => 64500"
   #krillc aspas add --ca minha_ca --aspa "AS64500 => AS64501, AS64502"
   #krillc bulk publish
   # Or, from your computer's terminal:
   #docker exec lab-krill krillc roas update --ca minha_ca --add "203.0.113.0/24-24 => 64500"
   #docker exec lab-krill krillc aspas add --ca minha_ca --aspa "AS64500 => AS64501, AS64502"
   #docker exec lab-krill krillc bulk publish
   #./scripts/lab.sh refresh
   ```

> If the verdicts in step 4 don't come back after one refresh, it usually
> just means that refresh ran before Krill had actually finished publishing
> (check with `krillc roas list`/`krillc aspas list` first, as in step 2).
> Running `./scripts/lab.sh refresh` again a few seconds later resolves it.

---

## If something doesn't work

| Symptom | What to check |
|---|---|
| What I see doesn't match a step | Read the step's **State** box and run the single command it lists - every `stepN-*` command sets its whole state (attacker, peer, ROAs, ASPA, observers' stage), not just what changed since the step before it, so it's safe to run from anywhere in the story. |
| A `stepN-*` command stops with a Krill/CA error | From `step3-rov-mark` on, every `stepN-*` command checks that Preparation actually finished before touching anything - see "How the story is organized". The message says what's missing (no CA, more than one, or one that isn't fully set up yet); fix that in Krill and the panel, then re-run the same command. |
| AS666's route doesn't show up | Once an observer is *dropping* what a check flags (stage `aspa-drop`, from `step8-drop` on), that route is gone from the table on purpose: look under `birdc show route table master4 filtered` on observer1. Before that, `none` has no verdicts and `rov-mark`/`aspa-mark` only demote, so the route should still be there. Otherwise check that you ran the step's command and that the session is up: `docker exec lab-attacker birdc show protocols`. |
| The two observers disagree, or the stage badge is amber | The badge in the panel's header shows the stage each observer is really running; amber means they differ. Run the step command of the stage you want (e.g. `./scripts/lab.sh step8-drop`) to put both in the same one. Right after a switch, observer2 also needs ten or fifteen seconds to settle (it restarts), so look again before concluding anything. |
| I created the ROA/ASPA but nothing changed | `./scripts/lab.sh refresh` forces both validators to revalidate. If it still doesn't change, `refresh` may have run before Krill finished publishing: check `krillc roas list` / `krillc aspas list`, wait a few seconds, refresh again. |
| I created the ROA but it isn't showing up in Krill | The CA didn't have the parent's certificate yet. `docker exec lab-krill krillc bulk refresh`, redo the ROA, then `krillc bulk publish` |
| Routinator shows no ASPA at all | `--enable-aspa` was missing, or the object hasn't been published/revalidated yet. `./scripts/lab.sh refresh`. |
| BIRD's `aspa_table` table is empty | RTR negotiated version 1. Check `birdc show protocols all routinator` and whether Routinator came up with `--enable-aspa`. |
| A BGP session won't come up | `docker compose logs origin provider-a provider-b observer1 observer2 attacker peer` |
| observer2 shows `avs` as `unknown` everywhere | The RTR session negotiated version 1, or FORT is older than 1.7.0.experimental. Check `bgpctl show rtr` says `Version: 2`. |
| observer2 shows `avs` as `valid` on BOTH paths | The session lost its RFC 9234 role - usually after a bare `bgpctl reload`. Re-run the stage's step command (`./scripts/lab.sh step5-aspa-mark` or `step8-drop`), which restarts observer2 with the stage's config. |
| FORT won't start or fetches nothing | `docker logs lab-fort`. It should end with "First validation cycle successfully ended". If TLS fails, the lab CA didn't reach its trust store: check that the `pki` volume is mounted. |
| Krill can't talk to Registro.br | The container needs outbound Internet access: `docker exec lab-krill ping -c1 beta.registro.br` |
| I want to start over | `./scripts/lab.sh reset` (deletes Krill's CA, LabNIC's own registry state, and both validators' caches), then `up`. Don't run a bare `docker compose down -v`: LabNIC and the registry panel only come up under the `local` compose profile, and a bare `docker compose down` silently leaves them running - `lab.sh` sets that up for you. Also run it from your own computer's terminal, not from the panel's in-browser console: `reset` tears down the whole lab, including that console itself, which kills the command halfway through. |
| The validators show ROAs/ASPA but Krill's CA looks completely empty | You're looking at two different CAs: your own (freshly created) one in Krill, and stale objects still published under an old CA of the same name at the registry, left over from before a reset that didn't fully clean up. `./scripts/lab.sh reset` (not a bare `docker compose down -v`) clears both sides together. |
| I changed `lab.conf` and nothing changed | `./scripts/lab.sh up` regenerates `bird/vars.conf` and recreates the routers |
| The registry panel won't open | It only exists in `MODE=local`. Check `lab.conf` and run `./scripts/lab.sh up` |
| Krill can't talk to LabNIC | Krill needs to trust the lab's internal CA: `docker logs lab-krill` shows a TLS error if `/pki/ca.pem` isn't mounted |
| I switched MODE and the CA disappeared | That's on purpose: each mode has its own volume, so one doesn't clobber the other's work |
| The objects are in Routinator but BIRD hasn't changed | BIRD revalidates on its own, but it takes a few seconds. To force it: `docker exec lab-observer1 birdc reload in provider_a_v4` |

## References

- RFC 6811 - origin validation for BGP
- RFC 9582 - ROA profile
- RFC 7908 - problem definition and classification of BGP route leaks
- RFC 9234 - route leak prevention and detection using roles
- `draft-ietf-sidrops-aspa-profile` - the ASPA object's profile
- `draft-ietf-sidrops-aspa-verification` - the upstream and downstream algorithms
- `draft-ietf-sidrops-8210bis` - RTR version 2, which carries the ASPAs
- Krill documentation: https://krill.docs.nlnetlabs.nl
- Routinator documentation: https://routinator.docs.nlnetlabs.nl
- BIRD documentation: https://bird.network.cz/

*This guide is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The lab's code is under Apache-2.0. See the `LICENSE` files in the repository.*
