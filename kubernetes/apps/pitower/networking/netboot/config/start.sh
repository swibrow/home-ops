#!/bin/sh
# proxyDHCP + TFTP for the untagged LAN (192.168.0.0/24), where bare-metal
# nodes PXE-boot and Talos maintenance mode comes up. Proxy mode leaves IP
# assignment to the Ubiquiti DHCP server and only injects boot options.
#
# The host interface is found by its 192.168.0.x address (static, from
# talos/pitower/node/worker-0[56]/03-netboot-lan.yaml.tpl), so this works
# unchanged on any node that carries one.
set -eu

IFACE=$(ip -4 -o addr show | awk '$4 ~ /^192\.168\.0\./ {print $2; exit}')
if [ -z "${IFACE}" ]; then
  echo "no interface with a 192.168.0.0/24 address on this node" >&2
  exit 1
fi
echo "serving proxyDHCP + TFTP on ${IFACE}"

cp /config/menu.ipxe /var/lib/tftpboot/menu.ipxe

# PXE firmware first chainloads iPXE (undionly.kpxe / ipxe.efi, bundled in
# the image); iPXE then re-DHCPs with user-class iPXE and gets menu.ipxe.
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
  --pxe-service=tag:!ipxe,BC_EFI,"Chainload iPXE",ipxe.efi \
  --pxe-service=tag:!ipxe,X86-64_EFI,"Chainload iPXE",ipxe.efi \
  --pxe-service=tag:ipxe,x86PC,"boot menu",menu.ipxe \
  --pxe-service=tag:ipxe,BC_EFI,"boot menu",menu.ipxe \
  --pxe-service=tag:ipxe,X86-64_EFI,"boot menu",menu.ipxe \
  --log-dhcp
