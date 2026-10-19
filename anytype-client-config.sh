#!/usr/bin/env bash
# Fetches the client-config.yml of a host's Anytype sync server (see
# modules/services/anytype.nix), the file Anytype apps load to join its network.
# Usage: ./anytype-client-config.sh [name] [output]   (default: tv-box, anytype-<name>.yml)
# The output is relative to the current directory; `-` prints it instead.
# The machine is reached at arturas@<name>.lan; override with TARGET=user@host.
#
# The file is in /var/lib/any-sync, readable by root only, so this asks for the sudo
# password (`ssh host sudo cat ...` can't: without a terminal, sudo can't ask). Nothing
# in the file is secret: the network's id, the server's public key and addresses.
set -euo pipefail

NAME="${1:-tv-box}"
OUTPUT="${2:-anytype-$NAME.yml}"
TARGET="${TARGET:-arturas@$NAME.lan}"
FILE=/var/lib/any-sync/client-config.yml

error() {
  echo "error: $*" >&2
  exit 1
}

if [[ $# -gt 2 ]]; then
  echo "Usage: $0 [name] [output]" >&2
  exit 1
fi

# One ssh connection for the whole run, so ssh only connects, and asks for anything,
# once.
tmp="$(mktemp -d)"
ssh_opts=(-o ControlMaster=auto -o "ControlPath=$tmp/ssh-%C" -o ControlPersist=60)
on_target() {
  ssh "${ssh_opts[@]}" "$TARGET" "$@"
}
trap 'ssh "${ssh_opts[@]}" -O exit "$TARGET" 2>/dev/null || true; rm -rf "$tmp"' EXIT

# ssh exits with 255 on connection/auth errors.
if ! on_target true; then
  error "could not connect to $TARGET. Is it on and on the network? Try: ssh $TARGET"
fi

# As root on the target: directly if we're root there or sudo needs no password,
# otherwise with the password, asked for here and checked first.
as_root=()
password=""
if [[ "$(on_target id -u)" != 0 ]]; then
  as_root=(sudo --non-interactive)
  if ! on_target sudo --non-interactive true 2>/dev/null; then
    as_root=(sudo --stdin --prompt=)
    for attempt in 1 2 3; do
      read -rsp "[sudo] password for $TARGET: " password
      echo >&2
      # -k: check the password even if sudo remembers an earlier one.
      if out="$(on_target sudo --stdin --prompt= -k true 2>&1 <<<"$password")"; then
        break
      elif [[ "$out" == *"incorrect password"* ]]; then
        echo "Wrong password." >&2
        ((attempt < 3)) || error "3 wrong sudo passwords for $TARGET."
      elif [[ "$out" == *"not in the sudoers"* || "$out" == *"not allowed"* ]]; then
        error "${TARGET%@*} may not use sudo on $NAME (needs to be in the wheel group)."
      else
        error "checking the sudo password on $TARGET failed: $out"
      fi
    done
  fi
fi
as_root_target() {
  on_target "$(printf '%q ' "${as_root[@]}" "$@")" <<<"$password"
}

# The bundle writes it on every start, so it's missing only if the server never
# started.
if ! as_root_target test -s "$FILE"; then
  error "$FILE doesn't exist on $TARGET. Does $NAME run the Anytype sync server" \
    "(modules/services/anytype.nix)? Check: ssh $TARGET systemctl status any-sync"
fi

if [[ "$OUTPUT" == - ]]; then
  as_root_target cat "$FILE"
  exit 0
fi
# Into a temporary file first, so a failed copy doesn't leave half a file.
as_root_target cat "$FILE" > "$tmp/client-config.yml" ||
  error "could not read $FILE on $TARGET (see above)."
mv "$tmp/client-config.yml" "$OUTPUT"
echo "Saved to $OUTPUT. In the Anytype app, before logging in: the gear icon on the" \
  "start screen, the \"Self-hosted\" network, then load this file." >&2
