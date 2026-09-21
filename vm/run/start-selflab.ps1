# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
#
# Starts the RPKI SelfLab virtual machine with QEMU on Windows (x86-64, with the
# Windows Hypervisor Platform turned on; without it QEMU falls back to software
# emulation, which works but is slow).
#
#   .\start-selflab.ps1            starts it in this window (Ctrl-A then X quits)
#   .\start-selflab.ps1 -Reset     throws away the VM's saved state first
#
# Then open http://localhost:8080 or log in with: ssh -p 2222 root@localhost
# (password: labpass). Only your own computer can reach those two ports.
param([switch]$Reset)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$qemu = (Get-Command qemu-system-x86_64.exe -ErrorAction SilentlyContinue).Source
if (-not $qemu) { $qemu = "C:\Program Files\qemu\qemu-system-x86_64.exe" }
if (-not (Test-Path $qemu)) { throw "QEMU isn't installed (https://www.qemu.org/download/#windows, or: winget install SoftwareFreedomConservancy.QEMU)" }
$qimg = Join-Path (Split-Path $qemu) "qemu-img.exe"

$image = Get-ChildItem $here -Filter "rpki-selflab-*-amd64.qcow2" | Select-Object -First 1
if (-not $image) { throw "no rpki-selflab-*-amd64.qcow2 next to this script" }

# the VM runs on an overlay: the image itself stays pristine, and -Reset is
# just deleting the overlay
$disk = Join-Path $here "selflab-disk.qcow2"
if ($Reset) { Remove-Item $disk -ErrorAction SilentlyContinue }
if (-not (Test-Path $disk)) { & $qimg create -q -f qcow2 -b $image.FullName -F qcow2 $disk }

Write-Host "Starting the RPKI SelfLab. The lab takes about a minute to come up."
Write-Host "  Panel: http://localhost:8080      ssh: ssh -p 2222 root@localhost   (password: labpass)"
& $qemu -machine "q35,accel=whpx:tcg" -cpu max -smp 2 -m 2048 `
    -drive "file=$disk,if=virtio,format=qcow2" `
    -nic "user,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:8080-:8080" `
    -nographic
