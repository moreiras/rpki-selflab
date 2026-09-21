#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# Text summary of the lab's state - good for projecting during class.
set -uo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=../lab.conf
. ./lab.conf
export LANGUAGE="${LANGUAGE:-pt}"
. ./scripts/i18n.sh

title() { printf '\n\033[1;36m== %s\033[0m\n' "$1"; }

title "$(msg t_objects)"
curl -s -m 8 http://localhost:8323/json \
  | python3 -c '
import json, os, sys

language = os.environ.get("LANGUAGE", "pt")
msgs = {
    "off":   {"pt": "  (Routinator indisponível)",
              "es": "  (Routinator no disponible)",
              "en": "  (Routinator unavailable)"},
    "empty": {"pt": "  (nada ainda - os objetos ja foram publicados? o Routinator ja atualizou?)",
              "es": "  (nada todavia - se publicaron los objetos? el Routinator ya actualizo?)",
              "en": "  (nothing yet - were the objects published? has Routinator refreshed?)"},
}

def m(k):
    return msgs[k].get(language, msgs[k]["pt"])

try:
    d = json.load(sys.stdin)
except Exception:
    print(m("off")); raise SystemExit

for r in d.get("roas", []):
    print("  ROA   {:<22} maxLength {}  AS {}".format(
        r["prefix"], r.get("maxLength"), r["asn"]))
for a in d.get("aspas", []):
    prov = ", ".join(str(p) for p in a.get("providers", []))
    print("  ASPA  {} => {}".format(a["customer"], prov))
if not d.get("roas") and not d.get("aspas"):
    print(m("empty"))
' 2>/dev/null || echo "$(msg routinator_off)"

title "$(msg t_tables)"
if docker exec lab-observer1 birdc -r show protocols routinator >/dev/null 2>&1; then
    docker exec lab-observer1 birdc -r show route table roa4_table 2>/dev/null | tail -n +3
    docker exec lab-observer1 birdc -r show route table aspa_table 2>/dev/null | tail -n +3
else
    echo "  $(msg no_rtr)"
fi

title "$(msg t_sessions)"
docker exec lab-observer1 birdc -r show protocols 2>/dev/null | tail -n +3

# The large communities are marked with OBSERVER1_ASN (see bird/observer1-*.conf);
# pass it into awk instead of hardcoding it, since lab.conf can change it.
OBS1_ASN="${OBSERVER1_ASN:-64510}"

verdicts_bird() {
    docker exec lab-observer1 birdc -r show route table "$1" all 2>/dev/null \
      | awk -v obs="$OBS1_ASN" '
        /unicast \[/ { proto=$0; sub(/.*unicast \[/,"",proto); sub(/ .*/,"",proto);
                       pre=$1; if (pre ~ /unicast/) pre=last; else last=pre; }
        /bgp_path:/ { path=$0; sub(/.*bgp_path: /,"",path) }
        /bgp_large_community:/ {
            rov="?"; aspa="?";
            if ($0 ~ "\\(" obs ", 1, 0\\)") rov="Invalid";
            if ($0 ~ "\\(" obs ", 1, 1\\)") rov="NotFound";
            if ($0 ~ "\\(" obs ", 1, 2\\)") rov="Valid";
            if ($0 ~ "\\(" obs ", 2, 0\\)") aspa="Invalid";
            if ($0 ~ "\\(" obs ", 2, 1\\)") aspa="Unknown";
            if ($0 ~ "\\(" obs ", 2, 2\\)") aspa="Valid";
            printf "  %-20s via %-14s AS_PATH %-18s ROV %-9s ASPA %s\n", pre, proto, path, rov, aspa;
        }'
}

title "$(msg t_verdicts4)"
verdicts_bird master4

title "$(msg t_verdicts6)"
verdicts_bird master6

# observer2 needs no community decoding: OpenBGPD carries the verdicts in the
# route itself, and bgpctl hands them over as JSON.
title "$(msg t_obs2_sessions)"
docker exec lab-observer2 bgpctl show rtr 2>/dev/null | head -5
docker exec lab-observer2 bgpctl show summary 2>/dev/null

title "$(msg t_obs2_verdicts)"
docker exec lab-observer2 bgpctl -j show rib 2>/dev/null \
  | python3 -c '
import json, sys

OVS = {"valid": "Valid", "invalid": "Invalid", "not-found": "NotFound"}
AVS = {"valid": "Valid", "invalid": "Invalid", "unknown": "Unknown"}

try:
    d = json.load(sys.stdin)
except Exception:
    print("  (observer2 unavailable)"); raise SystemExit

for r in d.get("rib", []):
    print("  {:<20} via {:<14} AS_PATH {:<18} ROV {:<9} ASPA {}".format(
        r.get("prefix", "?"),
        (r.get("neighbor") or {}).get("description", "?"),
        r.get("aspath", ""),
        OVS.get(str(r.get("ovs", "")).lower(), "?"),
        AVS.get(str(r.get("avs", "")).lower(), "?")))
' 2>/dev/null || echo "  (observer2 unavailable)"
echo
