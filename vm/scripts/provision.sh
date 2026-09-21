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
# the graphical session: Wayland compositor, terminal, browser, GPU drivers
apk add --no-cache sway foot firefox seatd mesa-dri-gallium mesa-egl mesa-gbm \
    font-dejavu xkeyboard-config adwaita-icon-theme hicolor-icon-theme dbus \
    spice-vdagent open-vm-tools swaybg
# sway (libinput) finds keyboards and mice through udev; Alpine's default is mdev
apk add --no-cache eudev udev-init-scripts udev-init-scripts-openrc
setup-devd udev >/dev/null 2>&1 || {
    for s in udev udev-trigger udev-settle; do rc-update add "$s" sysinit; done
    rc-update del mdev sysinit 2>/dev/null || true; rc-update del hwdrivers sysinit 2>/dev/null || true
}

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

# ---- the desktop user and session -------------------------------------------
adduser -D -s /bin/sh labuser
echo 'labuser:labpass' | chpasswd
for g in seat video input audio docker; do addgroup labuser "$g" 2>/dev/null || true; done
chown -R labuser:labuser /opt/lab
D=/tmp/desktop
install -d -o labuser -g labuser /home/labuser/.config/sway /home/labuser/.config/foot
install -m 644 -o labuser -g labuser "$D/sway.config" /home/labuser/.config/sway/config
install -m 644 -o labuser -g labuser "$D/foot.ini" /home/labuser/.config/foot/foot.ini
install -m 644 -o labuser -g labuser "$D/profile" /home/labuser/.profile
install -d /usr/lib/firefox/distribution /usr/share/selflab /usr/local/sbin
install -m 644 "$D/policies.json" /usr/lib/firefox/distribution/policies.json
install -m 644 "$D/start.html" /usr/share/selflab/start.html
install -m 755 "$D/autologin" /usr/local/sbin/autologin-labuser
install -m 755 "$D/status.sh" /usr/local/bin/selflab-status
rm -rf "$D"
echo 'export LAB_NO_BUILD=1' > /etc/profile.d/selflab.sh
# log labuser in by itself on the first console (the serial console stays as is)
sed -i 's#^tty1::.*#tty1::respawn:/sbin/getty -n -l /usr/local/sbin/autologin-labuser 38400 tty1#' /etc/inittab
grep -q autologin-labuser /etc/inittab || echo 'tty1::respawn:/sbin/getty -n -l /usr/local/sbin/autologin-labuser 38400 tty1' >> /etc/inittab
rc-update add seatd boot >/dev/null
rc-update add dbus default >/dev/null
rc-update add spice-vdagentd default >/dev/null 2>&1 || true
rc-update add open-vm-tools default >/dev/null 2>&1 || true

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

  The desktop (browser + terminal) starts by itself on the first console.
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
