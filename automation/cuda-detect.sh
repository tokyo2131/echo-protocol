#!/usr/bin/env bash
# Detects whether an NVIDIA GPU is present and whether drivers/CUDA are
# installed. This host ships CPU-only; this script exists so that if
# the droplet is ever resized/migrated onto a GPU-enabled plan, you have
# a one-command way to check readiness and next steps.
set -euo pipefail

echo "== PCI GPU devices =="
if lspci 2>/dev/null | grep -qi nvidia; then
  lspci | grep -i nvidia
else
  echo "No NVIDIA GPU detected via lspci."
  echo "(DigitalOcean GPU droplets are a separate product line from standard droplets —"
  echo " you'd need to provision/attach one before this would find anything.)"
  exit 0
fi

echo
echo "== Driver / CUDA status =="
if command -v nvidia-smi &>/dev/null; then
  nvidia-smi
else
  cat <<'EOF'
NVIDIA GPU present but the driver is not installed. To install on Debian 12:

  sudo apt-get install -y linux-headers-$(uname -r)
  # Add the non-free-firmware component (Bookworm splits proprietary
  # firmware out of "main"), then:
  sudo apt-get install -y nvidia-driver firmware-misc-nonfree
  sudo reboot

For CUDA toolkit (needed to build/run CUDA applications, distinct from
just the display/compute driver above), see NVIDIA's Debian 12 install
guide for the current package set — it changes with each CUDA release,
so pulling instructions from this script would go stale.
EOF
fi
