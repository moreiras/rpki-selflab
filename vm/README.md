# RPKI SelfLab as a virtual machine

A small virtual machine with a desktop of its own, so there is **nothing to
configure**: no ports to forward, no network mode to pick, no address to look
up. You start it, and after about a minute a browser opens on the lab's panel
and a terminal is one key away. Docker, the lab and every image it needs are
inside (about 650 MB compressed), and it runs with no Internet access.

Files of a release (`rpki-selflab-vX.Y.Z-<arch>`):

| File | For |
|---|---|
| `...-arm64.qcow2` | Apple Silicon Macs (M1 and later), and other ARM computers |
| `...-amd64.qcow2` | Intel and AMD computers (Windows, Linux, Intel Macs) |
| `SHA256SUMS` | checksums: `shasum -a 256 -c SHA256SUMS` (Linux/macOS) |

Give the VM **at least 3 GB of RAM (4 GB is better), 2 CPUs**, and 8 GB of disk
(the image grows up to that).

## Using it

1. Start the VM (instructions per system below) and wait about a minute. The
   browser shows "Starting the lab..." and then opens the panel by itself.
2. Inside the VM:
   - **Alt+1** the browser, with the lab's panel and the guide (the *Script* tab);
   - **Alt+2** a terminal, already in the lab's folder (`/opt/lab`);
   - **Alt+Space** switches the keyboard layout (US, Brazilian, Spanish);
   - **Alt+Enter** opens another terminal, **Alt+F** makes a window full screen.
3. The desktop logs in by itself as `labuser`. The `root` password is
   `labpass` (`su -` in the terminal).
4. To start over, in the terminal: `./scripts/lab.sh reset`, then
   `./scripts/lab.sh up`. Both work offline.

The mouse and keyboard can be captured by the VM window: use your program's
release key (QEMU: `Ctrl+Alt+G`; UTM and VirtualBox show it in the window).

## macOS

The Apple Silicon (`arm64`) image runs at full speed with **UTM** (free,
https://mac.getutm.app) or with QEMU.

**UTM:** *Create a New Virtual Machine* → *Virtualize* → *Linux*. Leave the boot
ISO empty. Set 4096 MB of memory and 2 CPUs. Finish, then edit the VM: remove
the default drive and *New Drive → Import…* the `.qcow2` (interface *VirtIO*),
and make sure the display is *virtio-gpu-pci* (not a `-gl` variant). Start it.

**QEMU** (`brew install qemu`), in the folder with the image:

```sh
# a throw-away layer on top of the image, so the image itself stays untouched
qemu-img create -f qcow2 -b rpki-selflab-vX.Y.Z-arm64.qcow2 -F qcow2 selflab-disk.qcow2

qemu-system-aarch64 -machine virt,accel=hvf -cpu host -smp 2 -m 4096 \
  -bios "$(brew --prefix qemu)/share/qemu/edk2-aarch64-code.fd" \
  -drive file=selflab-disk.qcow2,if=virtio,format=qcow2 \
  -nic user -device virtio-gpu-pci -device qemu-xhci -device usb-kbd -device usb-tablet \
  -display cocoa
```

To start over from scratch, delete `selflab-disk.qcow2` and create it again.

## Linux

**QEMU/KVM** on an Intel/AMD computer:

```sh
qemu-img create -f qcow2 -b rpki-selflab-vX.Y.Z-amd64.qcow2 -F qcow2 selflab-disk.qcow2

qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 2 -m 4096 \
  -drive file=selflab-disk.qcow2,if=virtio,format=qcow2 \
  -nic user -device virtio-vga -device qemu-xhci -device usb-kbd -device usb-tablet \
  -display gtk
```

**virt-manager:** *New virtual machine* → *Import existing disk image* → pick the
`.qcow2`, OS *Generic Linux*, 4096 MB and 2 CPUs; before starting, set *Video* to
*Virtio* (the `arm64` image also needs UEFI firmware on an ARM computer).

**VirtualBox:** see the Windows section (it is the same).

## Windows

**VirtualBox** (Intel/AMD; https://www.virtualbox.org). Convert the image once
(`qemu-img` comes with QEMU for Windows, or use any Linux/macOS computer):

```
qemu-img convert -O vdi rpki-selflab-vX.Y.Z-amd64.qcow2 rpki-selflab.vdi
```

Then *New*: type *Linux*, version *Other Linux (64-bit)*, 4096 MB, 2 CPUs, *Use an
existing virtual hard disk file* → the `.vdi`, and leave EFI **off**. Before
starting: *Display → Graphics Controller: VMSVGA* with 128 MB of video memory,
and *System → Pointing Device: USB Tablet*. The network can stay at its default
(NAT); the lab doesn't use it.

**QEMU for Windows** (https://www.qemu.org/download/#windows), in PowerShell,
with *Windows Hypervisor Platform* turned on for speed:

```powershell
qemu-img create -f qcow2 -b rpki-selflab-vX.Y.Z-amd64.qcow2 -F qcow2 selflab-disk.qcow2

qemu-system-x86_64 -machine "q35,accel=whpx:tcg" -cpu max -smp 2 -m 4096 `
  -drive file=selflab-disk.qcow2,if=virtio,format=qcow2 `
  -nic user -device virtio-vga -device qemu-xhci -device usb-kbd -device usb-tablet `
  -display sdl
```

**Hyper-V** (Windows Pro): `qemu-img convert -O vhdx rpki-selflab-vX.Y.Z-amd64.qcow2 rpki-selflab.vhdx`,
create a **Generation 1** VM with 4096 MB and that disk, and start it.

## If something looks wrong

- **Blank or black screen for a while:** wait; the first start takes about a
  minute (the browser waits for the lab and then opens it by itself).
- **The window is small or doesn't follow the size of the window:** set the
  resolution in the VM program's display settings, or use full screen (Alt+F
  inside the VM, and your program's full-screen mode).
- **The keyboard types the wrong characters:** Alt+Space cycles through US,
  Brazilian (ABNT2) and Spanish layouts.
- **The panel says nothing is running:** open the terminal (Alt+2) and run
  `./scripts/lab.sh status`; the start-up log is `/var/log/rpki-selflab.log`.

## Status

The `arm64` image was built and started on an Apple Silicon Mac with QEMU
(hardware acceleration): the desktop, the browser opening the panel, and the
terminal all worked. The other programs and systems in this file were not
tried.

## For the maintainer: building a release

```sh
vm/release.sh --bump patch     # or minor / major, or --version 1.4.0
vm/release.sh                  # HEAD is already tagged vX.Y.Z
vm/release.sh --dev            # a test build of the working tree, tags nothing
```

Needs `git`, `docker` with `buildx`, `packer`, `qemu` (with its UEFI firmware
for arm64) and Internet access for the base images. Options: `--arch
amd64|arm64|all`, `--accel hvf|kvm|whpx|tcg`, `--skip-images`, `--no-ova`,
`--dry-run`.

**Versioning.** The version *is* the git tag, `vMAJOR.MINOR.PATCH` (semantic
versioning). A build refuses to run unless the working tree is clean, and takes
the version from the tag on `HEAD`; with `--bump` or `--version` it works out
the next one and creates the annotated tag only after the images have been
built, so a failed build leaves no tag behind. It never pushes: publish with
`git push origin vX.Y.Z` and attach the files to the release. The version ends
up in `/opt/lab/VERSION` and in the console banner.

Everything is written to `vm/releases/vX.Y.Z/` (images, these READMEs,
`SHA256SUMS`, `BUILDINFO`); that folder and `vm/build/` are ignored by git.
An `.ova` (for VirtualBox and VMware) is also produced for `amd64`; it has
never been imported anywhere, so treat it as experimental.

How the images are made: `scripts/build-images.sh` exports each Docker image
for the target architecture as a tar (without touching your local images);
Packer boots Alpine's official cloud image, uploads the lab, the tars and the
desktop settings (`desktop/`), and `scripts/provision.sh` installs Docker and
the desktop (sway, foot, Firefox), loads the images and sets up the boot
services. A build for the architecture your computer doesn't have runs under
emulation and takes a good while.
