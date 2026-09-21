# RPKI SelfLab as a virtual machine

A small Alpine Linux virtual machine with Docker, the lab, and **every Docker
image the lab needs already loaded**: no Internet access is needed to run it.
Two builds per release, `amd64` (Intel/AMD) and `arm64` (Apple Silicon and
other ARM computers), each as:

- `rpki-selflab-vX.Y.Z-<arch>.qcow2`, for QEMU (and UTM);
- `rpki-selflab-vX.Y.Z-<arch>.ova`, for VirtualBox and VMware.

Inside the VM, the lab starts by itself on every boot (about a minute after the
machine starts). The computer that runs the VM reaches it through two ports,
both on its own address only (`localhost`):

| Port | What |
|---|---|
| `8080` | the lab: panel, Krill, registry, Routinator and the terminals, all through nginx (`localhost`, `krill.localhost`, ...) |
| `2222` | ssh: `ssh -p 2222 root@localhost`, password `labpass` |

Use ssh for what must not run from the panel's console, such as
`./scripts/lab.sh reset`. The lab lives in `/opt/lab`. The VM has 2 vCPUs and
2 GB of RAM; the disk image grows up to 6 GB.

## Running it

Download the files of one release into one folder, check them against
`SHA256SUMS`, then:

**Linux and macOS** (QEMU: `brew install qemu`, or `apt install qemu-system`):

```sh
./start-selflab.sh              # starts in this terminal; Ctrl-A then X stops it
./start-selflab.sh --background # or in the background
./start-selflab.sh --reset      # throws away the VM's saved state first
```

The VM runs on a copy-on-write overlay (`selflab-disk.qcow2`) next to the
image, so the downloaded image stays untouched and `--reset` only deletes the
overlay. It uses hardware acceleration (KVM on Linux, HVF on macOS) when the
image matches the computer's CPU.

**Windows** (QEMU for Windows; turn on *Windows Hypervisor Platform* for speed):

```powershell
.\start-selflab.ps1             # -Reset throws away the VM's saved state
```

**VirtualBox** (Windows, Linux, Intel Macs; the `.ova` is experimental, see
below): import the `.ova`, then forward the two ports:

```sh
VBoxManage modifyvm "RPKI SelfLab <version> (amd64)" \
  --natpf1 "ssh,tcp,127.0.0.1,2222,,22" --natpf1 "lab,tcp,127.0.0.1,8080,,8080"
```

**Hyper-V**: convert the qcow2 with `qemu-img convert -O vhdx image.qcow2 image.vhdx`,
create a generation 1 VM (2 GB RAM, that disk) on a NAT switch, and forward
ports 8080 and 22 with `netsh interface portproxy`.

**WSL2** is lighter than any VM and needs no port forwarding: it is a plain
Linux with Docker, so install Docker there and run the lab as described in the
main README.

## Building a release

```sh
vm/release.sh --bump patch     # or minor / major, or --version 1.4.0
vm/release.sh                  # HEAD is already tagged vX.Y.Z
vm/release.sh --dev            # a test build of the working tree, tags nothing
```

Needs `git`, `docker` with `buildx`, `packer`, `qemu` (with its UEFI firmware
for arm64) and Internet access for the base images. Options: `--arch
amd64|arm64|all`, `--accel hvf|kvm|whpx|tcg`, `--skip-images`, `--no-ova`.

**Versioning.** The version *is* the git tag, `vMAJOR.MINOR.PATCH` (semantic
versioning). A build refuses to run unless the working tree is clean, and takes
the version from the tag on `HEAD`; with `--bump` or `--version` it works out
the next one and creates the annotated tag only after the images have been
built, so a failed build leaves no tag behind. It never pushes: publish with
`git push origin vX.Y.Z` and attach the files to the release. The version ends
up in `/opt/lab/VERSION` and in the login banner of the VM.

Everything is written to `vm/releases/vX.Y.Z/` (images, start scripts,
`SHA256SUMS`, `BUILDINFO`); that folder and `vm/build/` are ignored by git.

How the images are made: `scripts/build-images.sh` exports each Docker image
for the target architecture as a tar (without touching your local images);
Packer boots Alpine's official cloud image, uploads the lab and the tars, and
`scripts/provision.sh` installs Docker, loads the images and sets up the boot
service. A build for the architecture your computer doesn't have runs under
emulation and takes a good while.

## Status

Built and booted so far, on an Apple Silicon Mac: the arm64 image with
hardware acceleration, and the amd64 image under software emulation (slow, but
the lab came up in about a minute). In both, the panel, Krill, the registry,
Routinator and the terminals answered through port 8080, ssh worked with the
password above, and the 15 containers were running with the lab's 6 BGP
sessions established on observer1. Not tried yet: the `.ova` in VirtualBox or
VMware (its XML and checksums are valid, but it has never been imported), the
Windows script, Linux with KVM, and a release build from a git tag.
