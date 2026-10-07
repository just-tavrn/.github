#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Creates the dedicated runner VM on an Ubuntu host with KVM/libvirt (runner/README.md, "1. The VM").
# Ubuntu 24.04 cloud image + cloud-init (user-data.yaml): Docker Engine, compose plugin, Portainer agent,
# egress firewall with DNS allowlist. The VM gets no shared folders and no host mounts; its only network is
# VM_BRIDGE, which must be isolated from the LAN (a VLAN of its own, README "Host network").
#
# Usage (as root on the host):
#   ADMIN_CIDR=192.0.2.0/24 SSH_PUBKEY_FILE=/root/.ssh/id_ed25519.pub runner/vm/make-vm.sh
# Variables (defaults in brackets):
#   VM_NAME [tavrn-ci]  VM_RAM_GB [512]  VM_VCPUS [32]  VM_DISK_GB [64]  VM_BRIDGE [br-ci]
#   ADMIN_CIDR (required)   network(s), comma-separated, allowed to reach SSH and the Portainer agent
#   SSH_PUBKEY_FILE [~/.ssh/id_ed25519.pub]   key of the VM user "ciadmin"
#   DNS_UPSTREAM [9.9.9.9,149.112.112.112]    public resolvers of the VM's dnsmasq (never a LAN resolver)
#   AGENT_SECRET []          shared secret of the Portainer agent (same value as AGENT_SECRET of the server)
#   PORTAINER_AGENT_IMAGE    agent image, pinned; use the version of your Portainer server
#   VM_IP_CIDR, VM_GATEWAY   static address instead of DHCP (for example 10.30.0.10/24 and 10.30.0.1)
#   IMAGE_DIR [/var/lib/libvirt/images]   OUT_DIR [/var/lib/libvirt/cloud-init/$VM_NAME]
#   DRY_RUN [0]              1: only render the cloud-init files into OUT_DIR
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

VM_NAME="${VM_NAME:-tavrn-ci}"
VM_RAM_GB="${VM_RAM_GB:-512}"
VM_VCPUS="${VM_VCPUS:-32}"
VM_DISK_GB="${VM_DISK_GB:-64}"
VM_BRIDGE="${VM_BRIDGE:-br-ci}"
ADMIN_CIDR="${ADMIN_CIDR:?set ADMIN_CIDR to the network(s) allowed to administer the VM, e.g. 192.0.2.0/24}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
DNS_UPSTREAM="${DNS_UPSTREAM:-9.9.9.9,149.112.112.112}"
AGENT_SECRET="${AGENT_SECRET:-}"
PORTAINER_AGENT_IMAGE="${PORTAINER_AGENT_IMAGE:-portainer/agent:2.45.1@sha256:38bc1dc7b8470eecbd979d444aa5d0a187dacf1245f2b54466f0f25f4c6d9a7c}"
VM_IP_CIDR="${VM_IP_CIDR:-}"
VM_GATEWAY="${VM_GATEWAY:-}"
IMAGE_DIR="${IMAGE_DIR:-/var/lib/libvirt/images}"
OUT_DIR="${OUT_DIR:-/var/lib/libvirt/cloud-init/$VM_NAME}"
DRY_RUN="${DRY_RUN:-0}"
IMAGE_BASE_URL="https://cloud-images.ubuntu.com/noble/current"
IMAGE_FILE="noble-server-cloudimg-amd64.img"

die() { echo "make-vm: $*" >&2; exit 1; }

valid_cidr_list() { [[ "$1" =~ ^[0-9./,\ ]+$ ]]; }
valid_cidr_list "$ADMIN_CIDR" || die "ADMIN_CIDR must be IPv4 addresses/networks, comma-separated"
valid_cidr_list "$DNS_UPSTREAM" || die "DNS_UPSTREAM must be IPv4 addresses, comma-separated"
[[ "$VM_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "VM_NAME: lowercase letters, digits and dashes only"
[[ "$AGENT_SECRET" =~ ^[A-Za-z0-9._~+-]*$ ]] || die "AGENT_SECRET: letters, digits and ._~+- only"
[[ "$PORTAINER_AGENT_IMAGE" =~ ^[A-Za-z0-9./:@_-]+$ ]] || die "PORTAINER_AGENT_IMAGE looks wrong"
[ -r "$SSH_PUBKEY_FILE" ] || die "SSH public key $SSH_PUBKEY_FILE not readable (SSH_PUBKEY_FILE)"
ssh_pubkey="$(head -n 1 "$SSH_PUBKEY_FILE")"
[[ "$ssh_pubkey" =~ ^(ssh-|ecdsa-|sk-)[A-Za-z0-9@.-]+\ [A-Za-z0-9+/=]+(\ [A-Za-z0-9@._-]+)*$ ]] || die "$SSH_PUBKEY_FILE is not an OpenSSH public key"
if [ -n "$VM_IP_CIDR" ] || [ -n "$VM_GATEWAY" ]; then
  [[ "$VM_IP_CIDR" =~ ^[0-9.]+/[0-9]+$ && "$VM_GATEWAY" =~ ^[0-9.]+$ ]] || die "set both VM_IP_CIDR (a.b.c.d/nn) and VM_GATEWAY"
fi

# ---- Render the cloud-init files ----------------------------------------------------------------------
umask 077
mkdir -p "$OUT_DIR"

admin_set="$(echo "$ADMIN_CIDR" | tr -d ' ' | sed 's/,/, /g')"
dns_set="$(echo "$DNS_UPSTREAM" | tr -d ' ' | sed 's/,/, /g')"
dns_servers="$(echo "$DNS_UPSTREAM" | tr -d ' ' | tr ',' '\n' | sed 's/^/server=/')"

sed -e "s|@@ADMIN_CIDR@@|$admin_set|" -e "s|@@DNS_UPSTREAM@@|$dns_set|" \
  "$here/nftables.conf" > "$OUT_DIR/nftables.conf"
awk -v servers="$dns_servers" '{ if ($0 == "@@DNS_SERVERS@@") print servers; else print }' \
  "$here/dnsmasq-egress.conf" > "$OUT_DIR/dnsmasq-egress.conf"
if grep -qE '@@[A-Z0-9_]+@@' "$OUT_DIR/nftables.conf" "$OUT_DIR/dnsmasq-egress.conf"; then
  die "unfilled placeholder in nftables.conf or dnsmasq-egress.conf"
fi

agent_secret_arg=""
[ -n "$AGENT_SECRET" ] && agent_secret_arg="-e AGENT_SECRET=$AGENT_SECRET"
sed -e "s|@@VM_NAME@@|$VM_NAME|" \
    -e "s|@@SSH_PUBKEY@@|$ssh_pubkey|" \
    -e "s|@@NFTABLES_B64@@|$(base64 -w0 "$OUT_DIR/nftables.conf")|" \
    -e "s|@@DNSMASQ_B64@@|$(base64 -w0 "$OUT_DIR/dnsmasq-egress.conf")|" \
    -e "s|@@AGENT_SECRET_ARG@@|$agent_secret_arg|" \
    -e "s|@@PORTAINER_AGENT_IMAGE@@|$PORTAINER_AGENT_IMAGE|" \
    "$here/user-data.yaml" > "$OUT_DIR/user-data"
grep -qE '@@[A-Z0-9_]+@@' "$OUT_DIR/user-data" && die "unfilled placeholder in user-data"

if [ -n "$VM_IP_CIDR" ]; then
  cat > "$OUT_DIR/network-config" <<NET
network:
  version: 2
  ethernets:
    uplink0:
      match:
        driver: virtio_net
      set-name: uplink0
      dhcp4: false
      dhcp6: false
      accept-ra: false
      addresses: [$VM_IP_CIDR]
      routes:
        - to: default
          via: $VM_GATEWAY
NET
else
  grep -v '^#' "$here/network-config.yaml" > "$OUT_DIR/network-config"
fi
echo "cloud-init files in $OUT_DIR"
[ "$DRY_RUN" = 1 ] && exit 0

# ---- Base image, disk, VM -----------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "run as root (libvirt system connection, $IMAGE_DIR)"
for cmd in virt-install qemu-img curl sha256sum virsh; do
  command -v "$cmd" >/dev/null || die "$cmd missing: apt install virtinst qemu-utils libvirt-daemon-system curl"
done
virsh dominfo "$VM_NAME" >/dev/null 2>&1 && die "a VM named $VM_NAME exists already"
ip link show "$VM_BRIDGE" >/dev/null 2>&1 || die "bridge $VM_BRIDGE missing (README, \"Host network\")"
[ -e /dev/kvm ] || die "/dev/kvm missing: enable virtualization (VT-x/AMD-V) in the firmware"

mkdir -p "$IMAGE_DIR"
base="$IMAGE_DIR/$IMAGE_FILE"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/SHA256SUMS" "$IMAGE_BASE_URL/SHA256SUMS"
if [ ! -f "$base" ] || ! (cd "$IMAGE_DIR" && grep " \*\?$IMAGE_FILE\$" "$tmp/SHA256SUMS" | sha256sum -c --status -); then
  echo "downloading $IMAGE_FILE"
  curl -fSL -o "$base.part" "$IMAGE_BASE_URL/$IMAGE_FILE"
  mv "$base.part" "$base"
  (cd "$IMAGE_DIR" && grep " \*\?$IMAGE_FILE\$" "$tmp/SHA256SUMS" | sha256sum -c -) || die "checksum mismatch for $IMAGE_FILE"
fi

disk="$IMAGE_DIR/$VM_NAME.qcow2"
[ -e "$disk" ] && die "$disk exists already"
qemu-img create -q -f qcow2 -F qcow2 -b "$base" "$disk" "${VM_DISK_GB}G"

virt-install \
  --name "$VM_NAME" \
  --memory "$((VM_RAM_GB * 1024))" \
  --vcpus "$VM_VCPUS" \
  --cpu host-passthrough \
  --machine q35 \
  --osinfo ubuntu24.04 \
  --import \
  --disk "path=$disk,format=qcow2,bus=virtio,discard=unmap" \
  --network "bridge=$VM_BRIDGE,model=virtio" \
  --cloud-init "user-data=$OUT_DIR/user-data,network-config=$OUT_DIR/network-config" \
  --rng /dev/urandom \
  --graphics none \
  --console pty,target_type=serial \
  --autostart \
  --noautoconsole

echo "VM $VM_NAME created. Follow the first boot with: virsh console $VM_NAME (leave with Ctrl+])"
echo "When cloud-init is done: ssh ciadmin@<VM address>  ->  cloud-init status --wait"
