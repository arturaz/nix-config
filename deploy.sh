#!/usr/bin/env bash
# Copies this configuration to tv-box and rebuilds it there.
# Usage: ./deploy.sh [switch|boot|test|dry-activate]   (default: switch)
set -euo pipefail

HOST="${HOST:-arturas@tv-box.lan}"
ACTION="${1:-switch}"
cd "$(dirname "$0")"

# -t allocates a TTY so sudo can prompt for a password.
rsync -av --delete --rsync-path="sudo rsync" \
  --exclude='.jj' --exclude='.git' --exclude='deploy.sh' --exclude='README.md' \
  ./ "$HOST:/etc/nixos/"
ssh -t "$HOST" "sudo nixos-rebuild $ACTION"
