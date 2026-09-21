#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
#
# Exports every Docker image the lab uses, for one architecture, as
# docker-archive tars in <out_dir>/. Uses buildx with "-o type=docker,dest=",
# which writes a file and never touches the local image store: your running lab
# and its images stay as they are, even when you build for the other
# architecture.
#
#   build-images.sh <amd64|arm64> <out_dir>
set -euo pipefail

arch="${1:?usage: build-images.sh <amd64|arm64> <out_dir>}"
out="${2:?usage: build-images.sh <amd64|arm64> <out_dir>}"
platform="linux/${arch}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$out"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# "image  build-context" pairs, one per image (the same image can serve several
# services). An empty context means the image is pulled, not built.
cd "$root"
COMPOSE_PROFILES=local docker compose config --format json | python3 -c '
import json, sys
cfg = json.load(sys.stdin)
seen = {}
for svc in cfg["services"].values():
    image = svc.get("image")
    if not image:
        continue
    build = svc.get("build")
    ctx = ""
    dockerfile = ""
    if build:
        ctx = build["context"] if isinstance(build, dict) else build
        dockerfile = build.get("dockerfile", "") if isinstance(build, dict) else ""
    seen.setdefault(image, (ctx, dockerfile))
for image, (ctx, dockerfile) in sorted(seen.items()):
    print(image, ctx or "-", dockerfile or "-")
' > "$tmp/images.txt"

while read -r image ctx dockerfile; do
    file="$out/$(echo "$image" | tr '/:' '__').tar"
    echo "==> $image ($platform)"
    if [ "$ctx" != "-" ]; then
        args=(--platform "$platform" -t "$image" -o "type=docker,dest=$file")
        [ "$dockerfile" != "-" ] && args+=(-f "$ctx/$dockerfile")
        docker buildx build "${args[@]}" "$ctx"
    else
        # a prebuilt image: re-tag it through a one-line Dockerfile, so the
        # architecture can be chosen without pulling it into the local store
        printf 'FROM --platform=%s %s\n' "$platform" "$image" > "$tmp/Dockerfile"
        docker buildx build --platform "$platform" -t "$image" \
            -o "type=docker,dest=$file" "$tmp"
    fi
done < "$tmp/images.txt"

ls -lh "$out"
