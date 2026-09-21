#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
#
# Runs inside the virtual machine, as root, while Packer builds it (see
# packer/rpki-selflab.pkr.hcl). Expects /tmp/lab.tar.gz (the lab's files) and
# /tmp/images/*.tar (the Docker images, already for this architecture).
set -eu

: "${LAB_VERSION:?}" "${LAB_ARCH:?}"

# ---- disk: make sure the root filesystem uses the whole (resized) disk ------
root_dev="$(awk '$2=="/" {print $1}' /proc/mounts | tail -1)"
part_name="$(basename "$root_dev")"
apk add --no-cache parted e2fsprogs-extra >/dev/null
if [ -r "/sys/class/block/$part_name/partition" ]; then
    # the filesystem is on a partition (the arm64 image): grow it first
    disk_name="$(basename "$(readlink -f "/sys/class/block/$part_name/..")")"
    part_num="$(cat "/sys/class/block/$part_name/partition")"
    parted -s "/dev/$disk_name" resizepart "$part_num" 100% || true
fi
# (on the amd64 image the filesystem sits on the whole disk, no partition)
resize2fs "$root_dev" || true

# ---- packages ---------------------------------------------------------------
apk add --no-cache docker docker-cli-compose bash curl python3 openssh jq

# ---- the lab ----------------------------------------------------------------
mkdir -p /opt/lab
tar -xzf /tmp/lab.tar.gz -C /opt/lab
cat > /opt/lab/VERSION <<VERSION
version=${LAB_VERSION}
arch=${LAB_ARCH}
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)
VERSION
chmod +x /opt/lab/scripts/*.sh
rm -f /tmp/lab.tar.gz

# ---- Docker, with every image already loaded ---------------------------------
rc-update add cgroups boot >/dev/null
rc-update add docker default >/dev/null
rc-service cgroups start >/dev/null 2>&1 || true
rc-service docker start
i=0; until docker info >/dev/null 2>&1; do i=$((i+1)); [ "$i" -gt 60 ] && exit 1; sleep 1; done
for f in /tmp/images/*.tar; do
    docker load -i "$f"
    rm -f "$f"
done
docker images
rm -rf /tmp/images

# ---- starts the lab on every boot -------------------------------------------
cat > /etc/init.d/rpki-selflab <<'INIT'
#!/sbin/openrc-run
description="RPKI SelfLab"

depend() {
    need docker net
    after docker
}

start() {
    ebegin "Starting the RPKI SelfLab"
    # in the background: the first start takes a minute (creates the
    # containers), and there's no reason to hold up the login prompt
    ( cd /opt/lab && LAB_NO_BUILD=1 ./scripts/lab.sh up >/var/log/rpki-selflab.log 2>&1 ) &
    eend 0
}

stop() {
    ebegin "Stopping the RPKI SelfLab"
    ( cd /opt/lab && ./scripts/lab.sh down >/dev/null 2>&1 )
    eend 0
}
INIT
chmod +x /etc/init.d/rpki-selflab
rc-update add rpki-selflab default >/dev/null

# ---- access -----------------------------------------------------------------
echo 'root:labpass' | chpasswd
sed -i -e 's/^#*PermitRootLogin.*/PermitRootLogin yes/' \
       -e 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
rc-update add sshd default >/dev/null 2>&1 || true
echo rpki-selflab > /etc/hostname

cat > /etc/motd <<MOTD

  RPKI SelfLab ${LAB_VERSION} (${LAB_ARCH})

  Panel:   http://localhost:8080   (on the computer that runs this VM)
  Lab:     cd /opt/lab && ./scripts/lab.sh help
  Logs:    /var/log/rpki-selflab.log

MOTD

# ---- clean up: smaller image, and no state shared between copies -------------
rc-service docker stop >/dev/null 2>&1 || true
rm -f /etc/ssh/ssh_host_*
rm -rf /var/cache/apk/* /root/.ash_history /var/log/*.log
dd if=/dev/zero of=/zerofile bs=1M 2>/dev/null || true
rm -f /zerofile
sync
