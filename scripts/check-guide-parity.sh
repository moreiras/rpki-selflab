#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# Checks that the three guide templates (guide/templates/GUIDE.{en,es,pt}.md)
# still have the same structure, so a translation can't silently drift from
# the English source (which is what happened before this check existed: a
# Portuguese step said the observers were "dropping" where English said
# "only marking").
#
# What has to match, in order, across the three languages:
#   - the number of "##" and "###" headings
#   - every code fence's info string (```cmd @observer1, ```output, ...)
#   - every line inside the ```cmd blocks (commands are never translated)
#   - the guide's directives: checkpoint ids, challenge/predict ids, checks,
#     answers, and how many hints each challenge has
#   - the set of {{NAME}} markers used
#
# Usage: ./scripts/check-guide-parity.sh     (exit status 1 on a mismatch)
# generate-config.sh runs it and prints its findings as a warning.
set -uo pipefail
cd "$(dirname "$0")/.."

SOURCE=en
LANGS="en es pt"

# One "fingerprint" line per structural element, in document order.
fingerprint() {
    awk '
        /^## /                { print "H2"; next }
        /^### /               { print "H3"; next }
        /^[ \t]*```/ {
            line = $0; sub(/^[ \t]*```[ \t]*/, "", line)
            if (in_code) { in_code = 0; in_cmd = 0; print "END"; next }
            in_code = 1; in_cmd = (line ~ /^cmd/)
            print "FENCE " line; next
        }
        in_cmd                { line = $0; sub(/^[ \t]+/, "", line); print "CMD " line; next }
        in_code               { next }
        /^[ \t]*<!--/ {
            d = $0
            sub(/^[ \t]*<!--[ \t]*/, "", d); sub(/[ \t]*-->[ \t]*$/, "", d)
            if (d ~ /^checkpoint:/)          { print "DIR " d; next }
            if (d ~ /^\/(challenge|predict)$/) { print "DIR " d; next }
            if (d ~ /^hint:/)                { print "DIR hint"; next }
            if (d ~ /^(challenge|predict)/) {
                head = d; sub(/:.*/, "", head)                    # keep "challenge id=x check=y"
                if (d ~ /^predict/) {                             # and how many options
                    n = split(d, parts, "|"); head = head " options=" n
                }
                print "DIR " head; next
            }
        }
    ' "$1"
}

markers() {
    grep -o '{{[A-Z0-9_]*}}' "$1" | sort -u
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

status=0
for l in $LANGS; do
    fingerprint "guide/templates/GUIDE.$l.md" > "$tmp/$l.fp"
    markers "guide/templates/GUIDE.$l.md" > "$tmp/$l.mk"
done

for l in $LANGS; do
    [ "$l" = "$SOURCE" ] && continue
    if ! diff -u "$tmp/$SOURCE.fp" "$tmp/$l.fp" > "$tmp/$l.diff"; then
        echo "GUIDE.$l.md: structure differs from GUIDE.$SOURCE.md (- $SOURCE, + $l):" >&2
        sed -n '3,40p' "$tmp/$l.diff" >&2
        status=1
    fi
    if ! diff -u "$tmp/$SOURCE.mk" "$tmp/$l.mk" > "$tmp/$l.mkdiff"; then
        echo "GUIDE.$l.md: uses a different set of {{NAME}} markers than GUIDE.$SOURCE.md:" >&2
        sed -n '3,20p' "$tmp/$l.mkdiff" >&2
        status=1
    fi
done

[ "$status" = 0 ] && echo "guide parity: en, es and pt match"
exit "$status"
