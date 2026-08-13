#!/bin/bash
#
# pin-lts-kernel.sh
#
# Pin an Ubuntu 24.04 AWS host to the GA-LTS kernel (6.8 series) and remove the
# rolling `linux-aws` meta so it can never advance to kernel >= 6.19 (e.g. 7.0),
# which the MongoDB 8.x tcmalloc/rseq startup guard refuses to run on
# (MongoDB SERVER-121912 / SERVER-125742).
#
# The `linux-aws-lts-24.04` meta keeps receiving 6.8 security ABI bumps for the
# life of 24.04, so this is NOT an `apt-mark hold` freeze -- kernel CVE patching
# continues. It just never crosses into the 7.0 series.
#
# Idempotent. Safe to run at AMI build time and repeatedly via SSM on live hosts.
# Exit codes: 0 = already compliant / no reboot needed; 10 = changed, reboot
# required to activate the 6.8 kernel; non-zero (other) = error.

set -euo pipefail

LTS_META="linux-aws-lts-24.04"
ROLLING_METAS=(linux-aws linux-aws-edge)
KERNEL_SERIES="6.8"

log() { echo "[pin-lts-kernel] $*"; }

export DEBIAN_FRONTEND=noninteractive

# Only relevant on Ubuntu AWS hosts; no-op elsewhere so it is safe to call broadly.
if [ ! -f /etc/os-release ] || ! grep -q '^ID=ubuntu' /etc/os-release; then
  log "Not an Ubuntu host; nothing to do."
  exit 0
fi
if ! apt-cache show "$LTS_META" >/dev/null 2>&1; then
  log "$LTS_META not available (not an AWS image?); nothing to do."
  exit 0
fi

changed=0

# 1. Ensure the 6.8 GA-LTS meta is installed (tracks 6.8 security updates).
if ! dpkg -s "$LTS_META" >/dev/null 2>&1; then
  log "Installing $LTS_META"
  apt-get update -q
  apt-get install -y "$LTS_META"
  changed=1
else
  log "$LTS_META already installed"
fi

# 2. Remove rolling metas so nothing pulls a kernel >= 6.19 back in.
#    (Purging the meta leaves the concrete kernel image in place as a fallback;
#    the currently running kernel is never removed by apt.)
for meta in "${ROLLING_METAS[@]}"; do
  if dpkg -s "$meta" >/dev/null 2>&1; then
    log "Purging rolling meta $meta"
    apt-get purge -y "$meta"
    changed=1
  fi
done

# 3. Point GRUB at the newest installed 6.8 kernel. Required because leftover
#    newer-series images (e.g. 7.0) would otherwise win GRUB's default ordering.
newest="$(find /boot -maxdepth 1 -name "vmlinuz-${KERNEL_SERIES}.*-aws" -printf '%f\n' 2>/dev/null \
  | sed 's/^vmlinuz-//' | sort -V | tail -1 || true)"
if [ -z "$newest" ]; then
  log "ERROR: no ${KERNEL_SERIES} kernel found in /boot; refusing to change GRUB."
  exit 1
fi
menu="Advanced options for Ubuntu>Ubuntu, with Linux ${newest}"
if ! grep -q "^GRUB_DEFAULT=\"${menu}\"$" /etc/default/grub; then
  log "Setting GRUB default to ${newest}"
  if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
    sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"${menu}\"|" /etc/default/grub
  else
    echo "GRUB_DEFAULT=\"${menu}\"" >> /etc/default/grub
  fi
  update-grub
  changed=1
else
  log "GRUB already defaulting to ${newest}"
fi

# Verify the chosen entry actually exists in the generated config.
if ! grep -qE "menuentry '.*${newest}[^']*'" /boot/grub/grub.cfg; then
  log "ERROR: GRUB menuentry for ${newest} not found in grub.cfg; not safe to reboot."
  exit 1
fi

# 4. Report whether a reboot is needed to activate the 6.8 kernel.
running="$(uname -r)"
case "$running" in
  ${KERNEL_SERIES}.*-aws)
    log "Running kernel ${running} is already on the ${KERNEL_SERIES} series."
    [ "$changed" -eq 1 ] && log "Config updated; no reboot required."
    exit 0
    ;;
  *)
    log "Running kernel ${running} is NOT on ${KERNEL_SERIES}; reboot required to activate ${newest}."
    exit 10
    ;;
esac
