#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
"""Collects the lab's state and writes /srv/status/status.json.

The panel (dashboard/index.html) reads this file to color the topology and
show command output that's already prepared, without the instructor having
to open a terminal for each thing.

There are two observers, and they expose their verdicts very differently:

  observer1  BIRD + Routinator. BIRD has no per-route validation attribute,
             so the lab's filters record the verdicts in large communities
             (see bird/observer1.conf) and we decode them back here.
  observer2  OpenBGPD + FORT. OpenBGPD computes the verdicts natively into
             the "ovs" and "avs" fields, which bgpctl -j hands over as JSON.

Both are normalised into the same route shape so the panel can show them
side by side.
"""
import json
import os
import re
import subprocess
import time
import urllib.request

INTERVAL = int(os.environ.get("INTERVAL", "6"))
OUTPUT = "/srv/status/status.json"
LAB_CONF = "/lab/lab.conf"

BIRD_ROUTERS = ["origin", "provider-a", "provider-b", "observer1", "attacker", "peer"]
ALL_ROUTERS = BIRD_ROUTERS + ["observer2"]


def read_lab_conf():
    """Reads lab.conf (KEY=value pairs) so the panel can show the real values."""
    conf = {}
    try:
        with open(LAB_CONF) as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if "=" in line:
                    key, value = line.split("=", 1)
                    conf[key.strip()] = value.strip().strip('"\'')
    except OSError:
        pass
    return conf


# re-read on every cycle: editing lab.conf shows up in the panel with no restart
CONFIG = read_lab_conf()
OBS1_ASN = int(CONFIG.get("OBSERVER1_ASN", "64510"))


def sh(args, timeout=15):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return (p.stdout + p.stderr).strip()
    except Exception as e:                                    # noqa: BLE001
        return f"(unavailable: {e})"


def birdc(node, command):
    return sh(["docker", "exec", f"lab-{node}", "birdc", "-r", *command.split()])


def bgpctl_json(command):
    """Runs bgpctl -j on observer2 and returns the parsed object, or None."""
    raw = sh(["docker", "exec", "lab-observer2", "bgpctl", "-j", *command.split()])
    try:
        return json.loads(raw)
    except Exception:                                         # noqa: BLE001
        return None


def http(url, timeout=5):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.read().decode("utf-8", "replace")
    except Exception as e:                                    # noqa: BLE001
        return f"(unavailable: {e})"


def running(name):
    return name in sh(["docker", "ps", "--format", "{{.Names}}"])


# --------------------------------------------------------------------------
# observer1 and the other BIRD routers
# --------------------------------------------------------------------------
RE_PROTO = re.compile(
    r"^(?P<name>\S+)\s+(?P<type>BGP|RPKI|Device|Static|Kernel)\s+(?P<table>\S+)\s+"
    r"(?P<state>up|down|start)\s+(?P<since>\S+)\s*(?P<info>.*)$"
)


def bird_protocols(node):
    out = birdc(node, "show protocols")
    res = []
    for line in out.splitlines():
        m = RE_PROTO.match(line.strip())
        if m:
            d = m.groupdict()
            d["info"] = d["info"].strip()
            res.append(d)
    return res


RE_HEAD = re.compile(
    r"^(?P<net>\S+)?\s*unicast \[(?P<proto>\S+) [^\]]*\]\s*(?P<best>\*)?\s*"
    r"\((?P<pref>\d+)\)"
)

VERDICT = {
    (1, 0): ("rov", "Invalid"),
    (1, 1): ("rov", "NotFound"),
    (1, 2): ("rov", "Valid"),
    (2, 0): ("aspa", "Invalid"),
    (2, 1): ("aspa", "Unknown"),
    (2, 2): ("aspa", "Valid"),
}


def bird_routes(node, table):
    """Extracts the routes and the verdict recorded in the large communities."""
    raw = sh(["docker", "exec", f"lab-{node}", "birdc", "-r",
              "show", "route", "table", table, "all"])
    res = []
    current = None
    last_net = None
    for line in raw.splitlines():
        m = RE_HEAD.match(line.rstrip())
        if m:
            if current:
                res.append(current)
            last_net = m.group("net") or last_net
            current = {
                "net": last_net,
                "proto": m.group("proto"),
                "best": bool(m.group("best")),
                "pref": int(m.group("pref")),
                "path": "",
                "local_pref": None,
                "rov": "-",
                "aspa": "-",
            }
            continue
        if current is None:
            continue
        line = line.strip()
        # BIRD 3 prints "bgp_path:" / "bgp_large_community:";
        # BIRD 2 printed "BGP.as_path:" / "BGP.large_community:".
        if line.startswith(("bgp_path:", "BGP.as_path:")):
            current["path"] = line.split(":", 1)[1].strip()
        elif line.startswith(("bgp_local_pref:", "BGP.local_pref:")):
            try:
                current["local_pref"] = int(line.split(":", 1)[1].strip())
            except ValueError:
                pass
        elif line.startswith(("bgp_large_community:", "BGP.large_community:")):
            for a, b, c in re.findall(r"\((\d+),\s*(\d+),\s*(\d+)\)", line):
                key = (int(b), int(c))
                if int(a) == OBS1_ASN and key in VERDICT:
                    field, value = VERDICT[key]
                    current[field] = value
    if current:
        res.append(current)
    return res


def exported_routes(node, protocol):
    """How many routes a BGP session is currently exporting (0 if unknown)."""
    out = birdc(node, f"show protocols all {protocol}")
    m = re.search(r"(\d+) exported", out)
    return int(m.group(1)) if m else 0


DEPLOYMENT_STAGES = ["none", "rov-mark", "rov-drop", "aspa-mark", "aspa-drop"]


def observer_stages():
    """Which deployment stage each observer is in, None if unknown.

    observer1 (BIRD): each stage's config defines a marker filter named
    stage_<name>_marker. observer2 (OpenBGPD): lab.sh writes the stage name
    to /etc/lab-stage (a fresh container falls back to its STAGE variable).
    """
    stages = {"observer1": None, "observer2": None}
    out = sh(["docker", "exec", "lab-observer1", "birdc", "-r", "show", "symbols", "filter"])
    for st in DEPLOYMENT_STAGES:
        if "stage_%s_marker" % st.replace("-", "_") in out:
            stages["observer1"] = st
    name = sh(["docker", "exec", "lab-observer2", "sh", "-c",
               "cat /etc/lab-stage 2>/dev/null || echo ${STAGE:-none}"]).strip()
    if name in DEPLOYMENT_STAGES:
        stages["observer2"] = name
    return stages


def count_table(node, table):
    out = birdc(node, f"show route table {table} count")
    m = re.search(r"(\d+) of (\d+) routes", out)
    return int(m.group(1)) if m else None


# --------------------------------------------------------------------------
# observer2 (OpenBGPD)
# --------------------------------------------------------------------------
OVS = {"valid": "Valid", "invalid": "Invalid", "not-found": "NotFound"}
AVS = {"valid": "Valid", "invalid": "Invalid", "unknown": "Unknown"}


def openbgpd_protocols():
    """BGP sessions plus the RTR session, in the same shape as BIRD's."""
    res = []
    data = bgpctl_json("show neighbor")
    for n in (data or {}).get("neighbors", []):
        state = str(n.get("state", "")).lower()
        res.append({
            "name": n.get("description") or n.get("remote_addr", "?"),
            "type": "BGP",
            "table": "-",
            "state": "up" if state == "established" else "down",
            "since": n.get("last_updown", ""),
            "info": f"AS{n.get('remote_as', '?')} {n.get('state', '')}",
        })
    rtr = bgpctl_json("show rtr")
    for s in (rtr or {}).get("rtrs", []) or []:
        state = str(s.get("state", "")).lower()
        res.append({
            "name": "fort",
            "type": "RTR",
            "table": "-",
            "state": "up" if state == "established" else "down",
            "since": "",
            "info": f"RTR v{s.get('version', '?')} serial {s.get('serial', '?')}",
        })
    return res


def openbgpd_routes(family, stage=None):
    """observer2's routes, normalised to the same shape as observer1's.

    OpenBGPD always computes ovs/avs natively, even on a router with no
    validation deployed (they read "not-found" / "unknown" against empty
    tables). A check that hasn't been deployed yet has no verdict to show, so
    those fields are blanked according to the deployment stage - which is also
    what observer1 shows, since BIRD only records a verdict once its filter
    has computed it.
    """
    data = bgpctl_json("show rib")
    res = []
    for r in (data or {}).get("rib", []):
        prefix = r.get("prefix", "")
        is_v6 = ":" in prefix
        if (family == 6) != is_v6:
            continue
        res.append({
            "net": prefix,
            "proto": (r.get("neighbor") or {}).get("description", "?"),
            "best": bool(r.get("best")),
            "pref": r.get("dmetric"),
            "path": r.get("aspath", ""),
            "local_pref": r.get("localpref"),
            "rov": OVS.get(str(r.get("ovs", "")).lower(), "-") if stage not in (None, "none") else "-",
            "aspa": AVS.get(str(r.get("avs", "")).lower(), "-") if stage in ("aspa-mark", "aspa-drop") else "-",
        })
    return res


def fort_summary():
    """What observer2 actually received from FORT over RTR."""
    out = {"up": running("lab-fort"), "roas": None, "aspas": None}
    data = bgpctl_json("show sets")
    for s in (data or {}).get("sets", []) or []:
        kind = str(s.get("type", "")).upper()
        if kind == "ROA":
            out["roas"] = (s.get("num_IPv4", 0) or 0) + (s.get("num_IPv6", 0) or 0)
        elif kind == "ASPA":
            out["aspas"] = s.get("num_ASnum", 0)
    return out


def routinator_summary():
    text = http("http://routinator:8323/status")
    data = {"text": text, "vrps": None, "aspas": None, "serial": None}
    # the /status endpoint uses "vrps:" (and "final-vrps:" after local filters)
    m = re.search(r"^final-vrps:\s*(\d+)", text, re.M) or \
        re.search(r"^vrps:\s*(\d+)", text, re.M)
    if m:
        data["vrps"] = int(m.group(1))
    m = re.search(r"^serial:\s*(\d+)", text, re.M)
    if m:
        data["serial"] = int(m.group(1))
    raw = http("http://routinator:8323/json")
    try:
        j = json.loads(raw)
        data["aspas"] = len(j.get("aspas", []))
        data["vrp_list"] = j.get("roas", [])[:50]
        data["aspa_list"] = j.get("aspas", [])[:50]
    except Exception:                                         # noqa: BLE001
        data["vrp_list"] = []
        data["aspa_list"] = []
    return data


def collect():
    global CONFIG, OBS1_ASN
    CONFIG = read_lab_conf()
    OBS1_ASN = int(CONFIG.get("OBSERVER1_ASN", "64510"))

    state = {
        "ts": time.strftime("%Y-%m-%d %H:%M:%S"),
        "nodes": {},
        "routinator": routinator_summary(),
        "fort": fort_summary(),
        "krill": {"up": running("lab-krill")},
        "rir": {"up": running("lab-rir")},
        "config": CONFIG,
        "panels": {},
        "stage": {"observer1": None, "observer2": None},
    }

    for node in ALL_ROUTERS:
        state["nodes"][node] = {"up": running(f"lab-{node}"), "protocols": []}

    for node in BIRD_ROUTERS:
        if state["nodes"][node]["up"]:
            state["nodes"][node]["protocols"] = bird_protocols(node)

    # AS666 and peer only have behavior worth showing: is the attacker
    # announcing something, is the peer passing routes on to its provider.
    # Asking the routers themselves keeps this right even when the observers
    # drop the routes and so can't be used to tell.
    if state["nodes"]["attacker"]["up"]:
        state["nodes"]["attacker"]["announcing"] = exported_routes("attacker", "observer1_v4") > 0
    if state["nodes"]["peer"]["up"]:
        state["nodes"]["peer"]["leaking"] = exported_routes("peer", "provider_a_v4") > 0

    if state["nodes"]["observer1"]["up"] and state["nodes"]["observer2"]["up"]:
        state["stage"] = observer_stages()

    obs1 = state["nodes"]["observer1"]
    if obs1["up"]:
        obs1["routes4"] = bird_routes("observer1", "master4")
        obs1["routes6"] = bird_routes("observer1", "master6")
        obs1["tables"] = {
            "roa4": count_table("observer1", "roa4_table"),
            "roa6": count_table("observer1", "roa6_table"),
            "aspa": count_table("observer1", "aspa_table"),
        }

    obs2 = state["nodes"]["observer2"]
    if obs2["up"]:
        obs2["protocols"] = openbgpd_protocols()
        obs2["routes4"] = openbgpd_routes(4, state["stage"]["observer2"])
        obs2["routes6"] = openbgpd_routes(6, state["stage"]["observer2"])

    state["panels"] = {
        "observer1/routes v4": sh(["docker", "exec", "lab-observer1", "birdc", "-r",
                                   "show", "route", "table", "master4", "all"]),
        "observer1/routes v6": sh(["docker", "exec", "lab-observer1", "birdc", "-r",
                                   "show", "route", "table", "master6", "all"]),
        "observer1/RTR session": birdc("observer1", "show protocols all routinator"),
        "observer1/ASPA table": sh(["docker", "exec", "lab-observer1", "birdc", "-r",
                                    "show", "route", "table", "aspa_table"]),
        "observer2/rib": sh(["docker", "exec", "lab-observer2", "bgpctl",
                             "show", "rib", "detail"]),
        "observer2/RTR session": sh(["docker", "exec", "lab-observer2", "bgpctl",
                                     "show", "rtr"]),
        "routinator/status": state["routinator"]["text"],
    }
    return state


def main():
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    while True:
        try:
            state = collect()
        except Exception as e:                                # noqa: BLE001
            state = {"ts": time.strftime("%Y-%m-%d %H:%M:%S"), "error": str(e)}
        tmp = OUTPUT + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f, ensure_ascii=False)
        os.replace(tmp, OUTPUT)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
