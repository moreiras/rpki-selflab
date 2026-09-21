#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
#
# Packs a qcow2 into an OVA (OVF + streamOptimized VMDK), which VirtualBox and
# VMware import directly.
#
#   make-ova.sh <image.qcow2> <version> <amd64|arm64> <out.ova>
set -euo pipefail
qcow2="${1:?}"; version="${2:?}"; arch="${3:?}"; out="${4:?}"
name="RPKI SelfLab ${version} (${arch})"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
base="rpki-selflab"

qemu-img convert -f qcow2 -O vmdk -o subformat=streamOptimized "$qcow2" "$tmp/$base.vmdk"
capacity="$(qemu-img info --output=json "$qcow2" | python3 -c 'import json,sys;print(json.load(sys.stdin)["virtual-size"])')"
size="$(wc -c < "$tmp/$base.vmdk" | tr -d ' ')"

cat > "$tmp/$base.ovf" <<OVF
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://schemas.dmtf.org/ovf/envelope/1"
          xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
          xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
          xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData">
  <References>
    <File ovf:id="file1" ovf:href="$base.vmdk" ovf:size="$size"/>
  </References>
  <DiskSection>
    <Info>Virtual disk</Info>
    <Disk ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:capacity="$capacity" ovf:capacityAllocationUnits="byte"
          ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/>
  </DiskSection>
  <NetworkSection>
    <Info>Networks</Info>
    <Network ovf:name="NAT"><Description>NAT</Description></Network>
  </NetworkSection>
  <VirtualSystem ovf:id="$base">
    <Info>RPKI SelfLab</Info>
    <Name>$name</Name>
    <OperatingSystemSection ovf:id="109">
      <Info>Linux</Info>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemType>vmx-07</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:Caption>2 virtual CPUs</rasd:Caption>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>2</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
        <rasd:Caption>2048 MB of memory</rasd:Caption>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>2048</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Caption>SATA controller</rasd:Caption>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>AHCI</rasd:ResourceSubType>
        <rasd:ResourceType>20</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:Caption>Disk</rasd:Caption>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Caption>Ethernet adapter on NAT</rasd:Caption>
        <rasd:Connection>NAT</rasd:Connection>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceSubType>E1000</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
OVF

( cd "$tmp" && for f in "$base.ovf" "$base.vmdk"; do
    echo "SHA256($f)= $(shasum -a 256 "$f" | cut -d' ' -f1)"; done > "$base.mf" )
# an OVA is a plain tar with the OVF first
out_abs="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
# Plain ustar, no extras: macOS's tar would otherwise add "._name" resource-fork
# entries and pax headers, and importers (VirtualBox) take the first entry for
# the OVF and fail with "empty file".
( cd "$tmp" && COPYFILE_DISABLE=1 tar --format ustar -cf "$out_abs.tmp" "$base.ovf" "$base.vmdk" "$base.mf" )
mv "$out_abs.tmp" "$out_abs"
