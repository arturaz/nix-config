#!/usr/bin/env bash
# Evaluates nixosConfigurations.<name> (hosts/<name>/) on this machine, then builds
# and activates it on the target over ssh.
# Usage: ./deploy.sh <name> [switch|boot|test|dry-activate|build]   (default: switch)
# The machine is reached at arturas@<name>.lan; override with TARGET=user@host.
# Set UPDATE=1 to update the flake inputs (nixpkgs) first; commit flake.lock afterwards.
# Set BUILD_LOCAL=1 to build on this machine instead (worth it only when something
# has to be compiled; otherwise everything comes from cache.nixos.org anyway, and
# the target already has most of it).
set -euo pipefail

cd "$(dirname "$0")"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <name> [switch|boot|test|dry-activate|build]" >&2
  echo "Available: $(ls hosts | tr '\n' ' ')" >&2
  exit 1
fi

NAME="$1"
ACTION="${2:-switch}"
TARGET="${TARGET:-arturas@$NAME.lan}"
UPDATE="${UPDATE:-0}"
BUILD_LOCAL="${BUILD_LOCAL:-0}"

if [[ ! -d "hosts/$NAME" ]]; then
  echo "error: no such host: hosts/$NAME" >&2
  exit 1
fi

# Files generated on the machine itself (e.g. by nixos-generate-config). The
# machine's /etc/nixos is their source of truth; they're copied from there into
# hosts/<name>/ before every build, and committed like everything else.
MACHINE_FILES=(hardware-configuration.nix)

uncommitted=()
# Reported on exit, so it isn't lost under the build output (or a failed build).
report_uncommitted() {
  if (( ${#uncommitted[@]} )); then
    echo
    echo "Updated from $TARGET, needs committing:"
    printf '  %s\n' "${uncommitted[@]}"
  fi
}
trap report_uncommitted EXIT

for f in "${MACHINE_FILES[@]}"; do
  dest="hosts/$NAME/$f"
  # ssh exits with 255 on connection/auth errors, otherwise with the remote
  # command's status.
  if ssh "$TARGET" "cat /etc/nixos/$f" > "$dest.tmp"; then
    mv "$dest.tmp" "$dest"
  else
    status=$?
    rm -f "$dest.tmp"
    if [[ $status == 255 ]]; then
      echo "error: could not connect to $TARGET." >&2
    else
      echo "error: /etc/nixos/$f is missing on $TARGET." >&2
      echo "Generate it there first, e.g.: sudo nixos-generate-config" >&2
    fi
    exit 1
  fi
  # New or different from the last commit (for jj: changed in the working-copy commit).
  if [[ -d .jj ]]; then
    changed="$(jj diff --name-only -- "$dest")"
  else
    changed="$(git status --porcelain -- "$dest")"
  fi
  if [[ -n "$changed" ]]; then
    uncommitted+=("$dest")
  fi
done

# `path:` makes Nix see new files that aren't in git's index yet (a git flake only sees
# those, and jj doesn't add them there).
FLAKE="path:$PWD"

if [[ "$UPDATE" == 1 ]]; then
  nix flake update --flake "$FLAKE"
  echo "Updated flake.lock; commit it."
fi

# By default the target builds (mostly: downloads from cache.nixos.org) the system
# itself. Pushing a locally built one requires the target to trust our ssh user
# (nix.settings.trusted-users), which a freshly installed machine doesn't yet.
build_args=(--build-host "$TARGET")
if [[ "$BUILD_LOCAL" == 1 ]]; then
  if nix store info --json --store "ssh-ng://$TARGET" | grep -q '"trusted":true'; then
    # --use-substitutes: the target fetches what it can from cache.nixos.org instead
    # of receiving it from us.
    build_args=(--use-substitutes)
  else
    echo "note: $TARGET doesn't trust this user yet, building there instead." >&2
  fi
fi

# nixos-rebuild from the same nixpkgs the machines use. --ask-sudo-password prompts
# once, locally, for the sudo password on the target.
nix shell --inputs-from "$FLAKE" nixpkgs#nixos-rebuild --command \
  nixos-rebuild "$ACTION" --flake "$FLAKE#$NAME" \
    --target-host "$TARGET" "${build_args[@]}" --sudo --ask-sudo-password
