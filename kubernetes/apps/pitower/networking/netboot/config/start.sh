#!/bin/sh
# proxyDHCP + TFTP + HTTP for the untagged LAN (192.168.0.0/24), where
# bare-metal nodes PXE-boot and Talos maintenance mode comes up. Proxy mode
# leaves IP assignment to the Ubiquiti DHCP server and only injects boot
# options.
#
# Talos kernel/initramfs are mirrored from the image factory at startup and
# served over plain local HTTP: iPXE's https (cross-signed cert validation)
# proved unreliable and the factory's /pxe endpoint hangs for minutes at a
# time, so the factory is only needed here, at pod start, over real TLS.
#
# The host interface is found by its 192.168.0.x address (static, from
# talos/pitower/node/worker-0[56]/03-netboot-lan.yaml.tpl), so this works
# unchanged on any node that carries one.
set -eu

IFACE=$(ip -4 -o addr show | awk '$4 ~ /^192\.168\.0\./ {print $2; exit}')
ADDR=$(ip -4 -o addr show | awk '$4 ~ /^192\.168\.0\./ {split($4, a, "/"); print a[1]; exit}')
if [ -z "${IFACE}" ]; then
  echo "no interface with a 192.168.0.0/24 address on this node" >&2
  exit 1
fi
echo "serving proxyDHCP + TFTP + HTTP on ${IFACE} (${ADDR})"

# The menu can't rely on ${next-server} (in proxyDHCP it points at the main
# DHCP server, i.e. the router), so bake our own address in. Talos version
# and schematic ids come from values.yaml env - single source for both the
# menu and the mirror below.
sed -e "s/@@NETBOOT_IP@@/${ADDR}/g" \
    -e "s/@@TALOS_VERSION@@/${TALOS_VERSION}/g" \
    -e "s/@@SCHEMATIC_AMD@@/${SCHEMATIC_AMD}/g" \
    -e "s/@@SCHEMATIC_INTEL@@/${SCHEMATIC_INTEL}/g" \
    -e "s/@@SCHEMATIC_PROXMOX@@/${SCHEMATIC_PROXMOX}/g" \
    /config/menu.ipxe > /var/lib/tftpboot/menu.ipxe

for sch in "${SCHEMATIC_AMD}" "${SCHEMATIC_INTEL}" "${SCHEMATIC_PROXMOX}"; do
  mkdir -p "/var/lib/tftpboot/talos/${sch}"
  for f in kernel-amd64 initramfs-amd64.xz; do
    if [ ! -s "/var/lib/tftpboot/talos/${sch}/${f}" ]; then
      curl -fsSL --retry 3 -o "/var/lib/tftpboot/talos/${sch}/${f}" \
        "https://factory.talos.dev/image/${sch}/${TALOS_VERSION}/${f}" &
    fi
  done
done
wait
for sch in "${SCHEMATIC_AMD}" "${SCHEMATIC_INTEL}" "${SCHEMATIC_PROXMOX}"; do
  for f in kernel-amd64 initramfs-amd64.xz; do
    [ -s "/var/lib/tftpboot/talos/${sch}/${f}" ] || \
      echo "WARNING: mirror of ${sch}/${f} failed - that Talos menu entry will 404" >&2
  done
done

# EFI clients get snponly.efi (drives the NIC via the firmware's SNP
# protocol) - the bundled ipxe.efi uses iPXE-native drivers, which fail to
# claim the NIC on OVMF/virtio VMs and some real firmware (and the bundled
# copy is actually a stale 404 page, not a binary). Best-effort download
# with fallback to the bundled binary; chain.efi is the stable name both
# dnsmasq and menu.ipxe reference.
if ! curl -fsSL -o /var/lib/tftpboot/chain.efi https://boot.ipxe.org/x86_64-efi/snponly.efi; then
  echo "snponly.efi download failed, falling back to bundled ipxe.efi" >&2
  cp /var/lib/tftpboot/ipxe.efi /var/lib/tftpboot/chain.efi
fi

busybox httpd -p 8080 -h /var/lib/tftpboot

# PXE firmware first chainloads iPXE (undionly.kpxe / chain.efi); iPXE then
# re-DHCPs with user-class iPXE and gets menu.ipxe.
exec dnsmasq -d -q \
  --port=0 \
  --interface="${IFACE}" \
  --bind-interfaces \
  --dhcp-range=192.168.0.0,proxy,255.255.255.0 \
  --enable-tftp \
  --tftp-root=/var/lib/tftpboot \
  --dhcp-userclass=set:ipxe,iPXE \
  --pxe-prompt="netboot",1 \
  --pxe-service=tag:!ipxe,x86PC,"Chainload iPXE",undionly.kpxe \
  --pxe-service=tag:!ipxe,BC_EFI,"Chainload iPXE",chain.efi \
  --pxe-service=tag:!ipxe,X86-64_EFI,"Chainload iPXE",chain.efi \
  --pxe-service=tag:ipxe,x86PC,"boot menu",menu.ipxe \
  --pxe-service=tag:ipxe,BC_EFI,"boot menu",menu.ipxe \
  --pxe-service=tag:ipxe,X86-64_EFI,"boot menu",menu.ipxe \
  --log-dhcp
