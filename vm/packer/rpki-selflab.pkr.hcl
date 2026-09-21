# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
#
# Builds the lab's virtual machine: Alpine Linux with Docker, the lab in
# /opt/lab and every Docker image the lab needs already loaded, so it runs
# with no Internet access. Started from vm/release.sh (which prepares the
# variables below); one build per architecture (amd64 / arm64).

packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "arch" {
  type        = string
  description = "amd64 or arm64"
}

variable "version" {
  type        = string
  description = "Release version, e.g. 1.2.0 (the git tag without the leading v)"
}

variable "alpine" {
  type    = string
  default = "3.22.4"
}

variable "accel" {
  type        = string
  default     = "tcg"
  description = "hvf (macOS), kvm (Linux), whpx (Windows) or tcg (software emulation, slow). Only native-architecture builds can use hvf/kvm/whpx."
}

variable "lab_tar" {
  type        = string
  description = "tar.gz with the lab's files (what ends up in /opt/lab)"
}

variable "images_dir" {
  type        = string
  description = "Directory with the docker-archive tars (one per image) for this architecture"
}

variable "output_dir" {
  type = string
}

variable "efi_code" {
  type        = string
  default     = ""
  description = "arm64 only: path to the UEFI firmware (edk2-aarch64-code.fd)"
}

variable "efi_vars" {
  type        = string
  default     = ""
  description = "arm64 only: path to the UEFI variable store template (edk2-arm-vars.fd)"
}

variable "headless" {
  type    = bool
  default = true
}

locals {
  is_arm     = var.arch == "arm64"
  alp_arch   = local.is_arm ? "aarch64" : "x86_64"
  alp_boot   = local.is_arm ? "uefi" : "bios"
  alp_series = join(".", slice(split(".", var.alpine), 0, 2))
  base_name  = "nocloud_alpine-${var.alpine}-${local.alp_arch}-${local.alp_boot}-tiny-r0.qcow2"
  base_url   = "https://dl-cdn.alpinelinux.org/alpine/v${local.alp_series}/releases/cloud/${local.base_name}"
}

source "qemu" "lab" {
  # Alpine's official cloud image (NoCloud flavor): it boots, gets an address
  # by DHCP and runs the script in seed/user-data, which is all it takes for
  # Packer to log in over SSH - no keystrokes typed into an installer.
  iso_url          = local.base_url
  iso_checksum     = "file:${local.base_url}.sha512"
  disk_image       = true
  use_backing_file = false

  disk_size        = "8G"
  format           = "qcow2"
  disk_compression = true
  vm_name          = "rpki-selflab-${var.arch}.qcow2"
  output_directory = var.output_dir

  cd_files = ["${path.root}/seed/user-data", "${path.root}/seed/meta-data"]
  cd_label = "cidata"

  qemu_binary  = local.is_arm ? "qemu-system-aarch64" : "qemu-system-x86_64"
  machine_type = local.is_arm ? "virt" : "q35"
  accelerator  = var.accel
  cpus         = 2
  memory       = 2048
  net_device   = "virtio-net"
  disk_interface = "virtio"
  efi_boot          = local.is_arm
  efi_firmware_code = local.is_arm ? var.efi_code : null
  efi_firmware_vars = local.is_arm ? var.efi_vars : null
  qemuargs = local.is_arm ? [
    ["-cpu", var.accel == "tcg" ? "cortex-a72" : "host"],
  ] : []

  headless     = var.headless
  communicator = "ssh"
  ssh_username = "root"
  ssh_password = "labpass"
  ssh_timeout  = "20m"

  shutdown_command = "poweroff"
}

build {
  sources = ["source.qemu.lab"]

  provisioner "shell" {
    inline = ["mkdir -p /tmp/images /tmp/desktop"]
  }

  provisioner "file" {
    source      = var.lab_tar
    destination = "/tmp/lab.tar.gz"
  }

  provisioner "file" {
    source      = "${var.images_dir}/"
    destination = "/tmp/images/"
  }

  provisioner "file" {
    source      = "${path.root}/../desktop/"
    destination = "/tmp/desktop/"
  }

  provisioner "shell" {
    script           = "${path.root}/../scripts/provision.sh"
    environment_vars = ["LAB_VERSION=${var.version}", "LAB_ARCH=${var.arch}"]
  }
}
