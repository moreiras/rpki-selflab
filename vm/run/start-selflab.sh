#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
#
# Starts the RPKI SelfLab virtual machine with QEMU (Linux and macOS).
#
#   ./start-selflab.sh              starts it in this terminal (Ctrl-A then X quits)
#   ./start-selflab.sh --background starts it and gives the terminal back
#   ./start-selflab.sh --reset      throws away the VM's saved state first
#
# Then open http://localhost:8080 or log in with: ssh -p 2222 root@localhost
# (password: labpass). Only your own computer can reach those two ports.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

background=0; reset=0
for a in "$@"; do
    case "$a" in
        --background) background=1 ;; --reset) reset=1 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

arch="$(uname -m)"
case "$arch" in x86_64|amd64) arch=amd64 ;; arm64|aarch64) arch=arm64 ;; *) echo "unsupported CPU: $arch" >&2; exit 1 ;; esac
image="$(ls "$here"/rpki-selflab-*-"$arch".qcow2 2>/dev/null | head -1)"
[ -n "$image" ] || { echo "no rpki-selflab-*-$arch.qcow2 next to this script" >&2; exit 1; }
command -v qemu-system-x86_64 >/dev/null || command -v qemu-system-aarch64 >/dev/null \
    || { echo "QEMU isn't installed (macOS: brew install qemu; Debian/Ubuntu: apt install qemu-system)" >&2; exit 1; }

# the VM runs on an overlay, so the downloaded image itself stays pristine and
# "--reset" is just deleting the overlay
disk="$here/selflab-disk.qcow2"
[ "$reset" = 1 ] && rm -f "$disk"
[ -f "$disk" ] || qemu-img create -q -f qcow2 -b "$image" -F qcow2 "$disk"

case "$(uname -s)" in
    Darwin) accel=hvf ;;
    *) [ -w /dev/kvm ] && accel=kvm || accel=tcg ;;
esac

# host ports -> guest: ssh and the lab's one web port (nginx)
nic="user,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:8080-:8080"

if [ "$arch" = amd64 ]; then
    cmd=(qemu-system-x86_64 -machine "q35,accel=$accel" -cpu "$([ "$accel" = tcg ] && echo max || echo host)")
else
    prefix="$(brew --prefix qemu 2>/dev/null || echo /usr)"
    fw=""
    for f in "$prefix/share/qemu/edk2-aarch64-code.fd" /usr/share/qemu/edk2-aarch64-code.fd /usr/share/AAVMF/AAVMF_CODE.fd; do
        [ -f "$f" ] && { fw="$f"; break; }
    done
    [ -n "$fw" ] || { echo "UEFI firmware for arm64 not found (it comes with QEMU's packages)" >&2; exit 1; }
    cmd=(qemu-system-aarch64 -machine "virt,accel=$accel" -cpu "$([ "$accel" = tcg ] && echo cortex-a72 || echo host)" -bios "$fw")
fi
cmd+=(-smp 2 -m 2048 -drive "file=$disk,if=virtio,format=qcow2" -nic "$nic")

echo "Starting the RPKI SelfLab ($arch, $accel). The lab takes about a minute to come up."
echo "  Panel: http://localhost:8080      ssh: ssh -p 2222 root@localhost   (password: labpass)"
if [ "$background" = 1 ]; then
    "${cmd[@]}" -display none -daemonize -pidfile "$here/selflab.pid"
    echo "Running in the background (pid $(cat "$here/selflab.pid")). To stop: ssh in and run 'poweroff', or kill that pid."
else
    exec "${cmd[@]}" -nographic
fi
