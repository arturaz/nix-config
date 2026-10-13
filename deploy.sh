#!/usr/bin/env bash
# Evaluates nixosConfigurations.<name> (hosts/<name>/) on this machine, then builds
# and activates it on the target over ssh.
# Usage: ./deploy.sh <name> [switch|boot|test|dry-activate|build]   (default: switch)
# The machine is reached at arturas@<name>.lan; override with TARGET=user@host.
# Set UPDATE=1 to update the flake inputs (nixpkgs) first; commit flake.lock afterwards.
# Set BUILD_LOCAL=1 to build on this machine instead (worth it only when something
# has to be compiled; otherwise everything comes from cache.nixos.org anyway, and
# the target already has most of it).
#
# It does what `nixos-rebuild --build-host/--target-host --sudo` does, step by step,
# so it can check the sudo password before building (nixos-rebuild only finds out
# it's wrong after the build) and say which step failed and what that left behind.
set -euo pipefail

cd "$(dirname "$0")"

ACTIONS="switch|boot|test|dry-activate|build"
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <name> [$ACTIONS]" >&2
  echo "Available: $(ls hosts | tr '\n' ' ')" >&2
  exit 1
fi

NAME="$1"
ACTION="${2:-switch}"
TARGET="${TARGET:-arturas@$NAME.lan}"
UPDATE="${UPDATE:-0}"
BUILD_LOCAL="${BUILD_LOCAL:-0}"

error() {
  echo "error: $*" >&2
  exit 1
}

if [[ ! -d "hosts/$NAME" ]]; then
  error "no such host: hosts/$NAME (available: $(ls hosts | tr '\n' ' '))"
fi
if [[ ! "$ACTION" =~ ^($ACTIONS)$ ]]; then
  error "unknown action '$ACTION' (expected one of: ${ACTIONS//|/, })"
fi

# One ssh connection for the whole run (including nix's own ssh), so ssh only
# connects, and asks for anything, once.
tmp="$(mktemp -d)"
ssh_opts=(-o ControlMaster=auto -o "ControlPath=$tmp/ssh-%C" -o ControlPersist=60)
export NIX_SSHOPTS="${ssh_opts[*]}"
on_target() {
  ssh "${ssh_opts[@]}" "$TARGET" "$@"
}

# Files generated on the machine itself (e.g. by nixos-generate-config). The
# machine's /etc/nixos is their source of truth; they're copied from there into
# hosts/<name>/ before every build, and committed like everything else.
MACHINE_FILES=(hardware-configuration.nix)

uncommitted=()
# Reported on exit, so it isn't lost under the build output (or a failed build).
on_exit() {
  ssh "${ssh_opts[@]}" -O exit "$TARGET" 2>/dev/null || true
  rm -rf "$tmp"
  if (( ${#uncommitted[@]} )); then
    echo
    echo "Updated from $TARGET, needs committing:"
    printf '  %s\n' "${uncommitted[@]}"
  fi
}
trap on_exit EXIT

# ssh exits with 255 on connection/auth errors.
if ! on_target true; then
  error "could not connect to $TARGET. Is it on and on the network? Try: ssh $TARGET"
fi

for f in "${MACHINE_FILES[@]}"; do
  dest="hosts/$NAME/$f"
  if on_target "cat /etc/nixos/$f" > "$dest.tmp"; then
    mv "$dest.tmp" "$dest"
  else
    rm -f "$dest.tmp"
    error "/etc/nixos/$f is missing on $TARGET." \
      "Generate it there first, e.g.: sudo nixos-generate-config"
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

# Activating needs root on the target: ask for the sudo password now and check it,
# before spending time on the build.
as_root=()
password=""
if [[ "$ACTION" != build && "$(on_target id -u)" != 0 ]]; then
  as_root=(sudo --stdin --prompt=)
  for attempt in 1 2 3; do
    read -rsp "[sudo] password for $TARGET: " password
    echo
    # -k: check the password even if sudo remembers an earlier one.
    if out="$(on_target sudo --stdin --prompt= -k true 2>&1 <<<"$password")"; then
      break
    elif [[ "$out" == *"incorrect password"* ]]; then
      echo "Wrong password." >&2
      ((attempt < 3)) || error "3 wrong sudo passwords for $TARGET. Nothing was changed."
    elif [[ "$out" == *"not in the sudoers"* || "$out" == *"not allowed"* ]]; then
      error "${TARGET%@*} may not use sudo on $NAME (needs to be in the wheel group)."
    else
      error "checking the sudo password on $TARGET failed: $out"
    fi
  done
fi

# `path:` makes Nix see new files that aren't in git's index yet (a git flake only sees
# those, and jj doesn't add them there).
FLAKE="path:$PWD"
NIX=(nix --extra-experimental-features "nix-command flakes")

if [[ "$UPDATE" == 1 ]]; then
  "${NIX[@]}" flake update --flake "$FLAKE" ||
    error "updating flake.lock failed (see above). Nothing was changed on $NAME."
  echo "Updated flake.lock; commit it."
fi

echo "Evaluating the configuration..." >&2
drv="$("${NIX[@]}" eval --raw "$FLAKE#nixosConfigurations.$NAME.config.system.build.toplevel.drvPath")" ||
  error "the configuration doesn't evaluate (see above). Nothing was changed on $NAME."

# By default the target builds (mostly: downloads from cache.nixos.org) the system
# itself. Pushing a locally built one requires the target to trust our ssh user
# (nix.settings.trusted-users), which a freshly installed machine doesn't yet.
if [[ "$BUILD_LOCAL" == 1 ]] &&
  ! "${NIX[@]}" store info --json --store "ssh-ng://$TARGET" | grep -q '"trusted":true'; then
  echo "note: $TARGET doesn't trust this user yet, building there instead." >&2
  BUILD_LOCAL=0
fi

if [[ "$BUILD_LOCAL" == 1 ]]; then
  echo "Building locally..." >&2
  system="$("${NIX[@]}" build --no-link --print-out-paths "$drv^*")" ||
    error "the build failed (see above). Nothing was changed on $NAME."
  echo "Copying to $TARGET..." >&2
  # --substitute-on-destination: the target fetches what it can from cache.nixos.org
  # instead of receiving it from us.
  "${NIX[@]}" copy --substitute-on-destination --to "ssh-ng://$TARGET" "$system" ||
    error "copying the system to $TARGET failed (see above). Nothing was changed on $NAME."
else
  echo "Building on $TARGET..." >&2
  "${NIX[@]}" copy --derivation --to "ssh://$TARGET" "$drv" ||
    error "copying the build instructions to $TARGET failed (see above). Nothing was changed on $NAME."
  system="$(on_target "$(printf '%q ' "${NIX[@]}" build --no-link --print-out-paths "$drv^*")")" ||
    error "the build on $TARGET failed (see above). Nothing was changed on $NAME."
fi

if [[ "$ACTION" == build ]]; then
  echo "Done: $system is built and on $TARGET."
  exit 0
fi

# As root on the target, what nixos-rebuild does: record the new generation (for
# switch/boot), then run switch-to-configuration through systemd-run, so it finishes
# even if the ssh connection drops halfway.
# Exit codes: 10 = recording the generation failed, otherwise switch-to-configuration's
# (4 = it switched, but some units failed).
# shellcheck disable=SC2016 # expanded on the target
activate='
  action=$1 system=$2
  if [ "$action" = switch ] || [ "$action" = boot ]; then
    /run/current-system/sw/bin/nix-env -p /nix/var/nix/profiles/system --set "$system" || exit 10
  fi
  export NIXOS_INSTALL_BOOTLOADER=0
  exec /run/current-system/sw/bin/systemd-run -E LOCALE_ARCHIVE \
    -E NIXOS_INSTALL_BOOTLOADER -E NIXOS_NO_CHECK --collect --no-ask-password --pipe \
    --quiet --service-type=exec --unit=nixos-rebuild-switch-to-configuration \
    "$system/bin/switch-to-configuration" "$action" </dev/null
'
echo "Activating ($ACTION) on $TARGET..." >&2
status=0
on_target "$(printf '%q ' "${as_root[@]}" sh -c "$activate" sh "$ACTION" "$system")" \
  <<<"$password" || status=$?

case "$ACTION:$status" in
  *:0)
    echo "Done: $NAME is on $system ($ACTION)." ;;
  *:10)
    error "recording the new generation on $NAME failed (see above). Nothing was changed." ;;
  *:4)
    error "$NAME switched to the new configuration, but some services failed (see above)." \
      "Check them with: ssh $TARGET systemctl --failed" ;;
  *:255)
    error "lost the connection to $TARGET while activating. The switch may still have" \
      "finished there; check with: ssh $TARGET readlink /run/current-system" \
      "(the new system is $system)" ;;
  switch:* | boot:*)
    error "activating the new configuration on $NAME failed (see above). It's recorded as" \
      "the newest generation, so $NAME boots into it and may be partly running it." \
      "To go back: ssh -t $TARGET sudo nixos-rebuild switch --rollback" ;;
  *)
    error "$ACTION on $NAME failed (see above). A reboot returns it to its current" \
      "generation." ;;
esac
