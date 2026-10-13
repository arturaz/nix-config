# tv-box NixOS configuration

Configuration for `tv-box.lan`. Mirrors `/etc/nixos` on the machine.

Deploy with `./deploy.sh` (rsyncs to `/etc/nixos` and runs `nixos-rebuild switch`).
Pass `test`, `boot` or `dry-activate` to use a different `nixos-rebuild` action.
