#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
#
# Builds the lab's virtual machine images (qcow2 and OVA, amd64 and arm64) into
# vm/releases/v<version>/. The version IS the git tag: v<MAJOR>.<MINOR>.<PATCH>
# (semantic versioning).
#
#   vm/release.sh                     HEAD must already carry a vX.Y.Z tag
#   vm/release.sh --bump patch|minor|major
#                                     next version after the latest tag; the tag
#                                     is created (locally) once the build succeeds
#   vm/release.sh --version 1.4.0     an explicit version, same as above
#   vm/release.sh --dev               test build from the working tree, named
#                                     dev-<commit>; creates no tag
#
# Options: --arch amd64|arm64|all (default all), --accel hvf|kvm|whpx|tcg,
#          --skip-images (reuse vm/build/images-<arch>), --no-ova,
#          --dry-run (only shows the version it would build).
#
# Needs: git, docker (with buildx), packer, qemu (qemu-img and the system
# emulators), and Internet access to fetch base images. Building for the
# architecture the computer doesn't have runs under emulation (slow).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
cd "$root"

bump="" ; explicit="" ; dev=0 ; dry=0 ; archs="all" ; accel="" ; skip_images=0 ; ova=1
while [ $# -gt 0 ]; do
    case "$1" in
        --bump)        bump="${2:?}"; shift 2 ;;
        --version)     explicit="${2:?}"; shift 2 ;;
        --dev)         dev=1; shift ;;
        --arch)        archs="${2:?}"; shift 2 ;;
        --accel)       accel="${2:?}"; shift 2 ;;
        --skip-images) skip_images=1; shift ;;
        --no-ova)      ova=0; shift ;;
        --dry-run)     dry=1; shift ;;
        -h|--help)     sed -n '4,23p' "$here/release.sh" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
done
[ "$archs" = "all" ] && archs="amd64 arm64"

die() { echo "release.sh: $*" >&2; exit 1; }

# ---------------------------------------------------------------- version ---
tag_to_create=""
if [ "$dev" = 1 ]; then
    version="dev-$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
else
    git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
    [ -z "$(git status --porcelain)" ] || die "the working tree isn't clean: commit or stash first (or use --dev for a test build)"
    if [ -n "$explicit" ]; then
        version="${explicit#v}"
        tag_to_create="v$version"
    elif [ -n "$bump" ]; then
        last="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0)"
        IFS=. read -r major minor patch <<< "${last#v}"
        case "$bump" in
            major) major=$((major+1)); minor=0; patch=0 ;;
            minor) minor=$((minor+1)); patch=0 ;;
            patch) patch=$((patch+1)) ;;
            *) die "--bump takes major, minor or patch" ;;
        esac
        version="$major.$minor.$patch"
        tag_to_create="v$version"
    else
        tag="$(git describe --exact-match --tags --match 'v[0-9]*' HEAD 2>/dev/null || true)"
        [ -n "$tag" ] || die "HEAD has no vX.Y.Z tag. Tag it, or use --bump / --version / --dev."
        version="${tag#v}"
    fi
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "'$version' isn't a MAJOR.MINOR.PATCH version"
    if [ -n "$tag_to_create" ] && git rev-parse -q --verify "refs/tags/$tag_to_create" >/dev/null; then
        die "tag $tag_to_create already exists"
    fi
fi
echo "== RPKI SelfLab VM, version $version (${archs})"
[ "$dry" = 1 ] && { echo "(dry run: ${tag_to_create:+would create tag $tag_to_create; }nothing built)"; exit 0; }

release_dir="$here/releases/v$version"
[ "$dev" = 1 ] && release_dir="$here/releases/$version"
build_dir="$here/build"
mkdir -p "$release_dir" "$build_dir"

# ------------------------------------------------------- the lab's files ----
lab_tar="$build_dir/lab-$version.tar.gz"
if [ "$dev" = 1 ]; then
    tar -czf "$lab_tar" --exclude=./vm --exclude=./.git -C "$root" .
else
    git archive --format=tar.gz -o "$lab_tar" HEAD -- . ':(exclude)vm'
fi

# -------------------------------------------------------------- per arch ----
host_arch="$(uname -m)"; case "$host_arch" in x86_64|amd64) host_arch=amd64 ;; arm64|aarch64) host_arch=arm64 ;; esac
case "$(uname -s)" in Darwin) native_accel=hvf ;; Linux) native_accel=kvm ;; *) native_accel=whpx ;; esac

find_first() { for f in "$@"; do [ -f "$f" ] && { echo "$f"; return; }; done; }

for arch in $archs; do
    echo "== $arch"
    a="${accel:-tcg}"; [ -z "$accel" ] && [ "$arch" = "$host_arch" ] && a="$native_accel"

    images="$build_dir/images-$arch"
    if [ "$skip_images" = 0 ]; then
        rm -rf "$images"
        "$here/scripts/build-images.sh" "$arch" "$images"
    fi

    efi_code=""; efi_vars=""
    if [ "$arch" = arm64 ]; then
        prefix="$(brew --prefix qemu 2>/dev/null || echo /usr)"
        efi_code="$(find_first "$prefix/share/qemu/edk2-aarch64-code.fd" /usr/share/qemu/edk2-aarch64-code.fd /usr/share/AAVMF/AAVMF_CODE.fd)"
        efi_vars="$(find_first "$prefix/share/qemu/edk2-arm-vars.fd" /usr/share/qemu/edk2-arm-vars.fd /usr/share/AAVMF/AAVMF_VARS.fd)"
        [ -n "$efi_code" ] && [ -n "$efi_vars" ] || die "UEFI firmware for arm64 not found (install qemu with its edk2 firmware)"
    fi

    out="$build_dir/packer-$arch"
    rm -rf "$out"
    "${PACKER:-packer}" init "$here/packer"
    "${PACKER:-packer}" build -force \
        -var "arch=$arch" -var "version=$version" -var "accel=$a" \
        -var "lab_tar=$lab_tar" -var "images_dir=$images" -var "output_dir=$out" \
        -var "efi_code=$efi_code" -var "efi_vars=$efi_vars" \
        "$here/packer"

    name="rpki-selflab-v$version-$arch"
    [ "$dev" = 1 ] && name="rpki-selflab-$version-$arch"
    mv "$out/rpki-selflab-$arch.qcow2" "$release_dir/$name.qcow2"
    if [ "$ova" = 1 ]; then
        "$here/scripts/make-ova.sh" "$release_dir/$name.qcow2" "$version" "$arch" "$release_dir/$name.ova"
    fi
done

# --------------------------------------------------------------- wrap up ----
cp "$here/run/"* "$release_dir/"
( cd "$release_dir" && shasum -a 256 * > SHA256SUMS )
{
    echo "version=$version"
    echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "archs=$archs"
} > "$release_dir/BUILDINFO"

if [ -n "$tag_to_create" ]; then
    git tag -a "$tag_to_create" -m "RPKI lab $version"
    echo "== created tag $tag_to_create (not pushed: git push origin $tag_to_create)"
fi
echo "== done: $release_dir"
ls -lh "$release_dir"
