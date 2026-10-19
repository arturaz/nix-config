#!/usr/bin/env bash
# Updates everything this repo pins, tests the result, then deploys it:
#   1. flake.lock (nixpkgs, sops-nix);
#   2. the packages nixpkgs lacks (packages/), to the newest release each one's
#      package.nix accepts (`passthru.updateScript`), with their hashes;
#   3. the VM tests (tests/, the flake's checks), stopping if one fails, before the
#      machine is touched;
#   4. deploy.sh.
# Commit the updated files afterwards (it lists them).
# Usage: ./upgrade.sh <name> [switch|boot|test|dry-activate|build]   (default: switch)
# Same arguments and env vars as deploy.sh, which does the deploying.
set -euo pipefail

cd "$(dirname "$0")"

# Wrong arguments: let deploy.sh say so, before anything is updated.
if [[ $# -lt 1 || $# -gt 2 || ! -d "hosts/$1" ||
  ! "${2:-switch}" =~ ^(switch|boot|test|dry-activate|build)$ ]]; then
  exec ./deploy.sh "$@"
fi

FLAKE="path:$PWD"
NIX=(nix --extra-experimental-features "nix-command flakes")
UPDATED=(flake.lock packages)

error() {
  echo "error: $*" >&2
  exit 1
}
not_deployed() {
  error "$1 (see above). Nothing was deployed; the updated files are left as they are" \
    "(undo with: jj restore ${UPDATED[*]})."
}

echo "Updating flake.lock..." >&2
"${NIX[@]}" flake update --flake "$FLAKE" ||
  error "updating flake.lock failed (see above). Nothing was changed."

# Each package in packages/ declares how it's updated (`passthru.updateScript`: which
# releases it accepts); the flake's update-packages runs them all.
echo "Updating packages/..." >&2
"${NIX[@]}" run "$FLAKE#update-packages" || not_deployed "updating packages/ failed"

# Builds the packages and everything the tests use, then boots the test VMs (a few
# minutes; needs KVM). Also checks that every host's configuration evaluates.
echo "Running the VM tests..." >&2
"${NIX[@]}" flake check -L "$FLAKE" || not_deployed "a test failed"

if [[ -d .jj ]]; then
  changed="$(jj diff --name-only -- "${UPDATED[@]}")"
else
  changed="$(git status --porcelain -- "${UPDATED[@]}")"
fi
echo "Updated (commit them): ${changed:-nothing}" | tr '\n' ' ' >&2
echo >&2

exec ./deploy.sh "$@"
