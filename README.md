# NixOS configurations

A flake with one `nixosConfigurations.<name>` per machine. `flake.nix` picks up every
directory in `hosts/` automatically.

- `modules/`: settings shared between machines, one topic per file (`locale.nix`,
  `desktop/audio.nix`, ...). Add new things here, as a new file when it's a new topic.
- `hosts/<name>/configuration.nix`: imports the modules a machine uses, plus what's
  specific to it (hostname, boot loader, `system.stateVersion`).

Current hosts:

- `tv-box` (`tv-box.lan`)

## Deploying

`./deploy.sh <name>` evaluates the configuration on this machine, then builds and
activates it on `arturas@<name>.lan` (`nixos-rebuild switch --build-host/--target-host`),
asking for the target's sudo password once. Pass `test`, `boot`, `dry-activate` or
`build` as a second argument to use a different `nixos-rebuild` action, and set
`TARGET=user@host` if the machine isn't reachable at the default address.

Needs Nix with flakes enabled on this machine (`experimental-features = nix-command
flakes` in `~/.config/nix/nix.conf`).

Building on the target is the default because nearly everything comes prebuilt from
cache.nixos.org, and the target already has most of its system. `BUILD_LOCAL=1` builds
here instead, which only pays off when something has to be compiled. That requires the
target to trust the deploying user (`nix.settings.trusted-users`, which makes that user
effectively root, so no host sets it); otherwise it falls back to building on the
target.

The flake is always referenced as `path:` (e.g. `nix build path:.#...`), so it sees new
files before they're committed (a git flake only sees files in git's index, and jj
doesn't add them there).

## Updating

`flake.lock` pins nixpkgs (`nixos-26.05`). `UPDATE=1 ./deploy.sh <name>` updates it
before deploying; commit the lock afterwards.

## Machine-generated files

Machine-generated files (`hardware-configuration.nix`, listed in `MACHINE_FILES` in
`deploy.sh`) are committed here, but the machine's `/etc/nixos` is their source of
truth: `deploy.sh` copies them into `hosts/<name>/` before every build, aborts if one is
missing, and at the end lists any that are new or changed and need committing. Don't
edit them here. To refresh one after a hardware change, run `sudo nixos-generate-config`
on the machine.

Apart from those, `/etc/nixos` on the machines isn't used; don't keep a
`configuration.nix` there, or a plain `nixos-rebuild` on the machine would roll it back
to that.

## Editor

`.vscode/settings.json` sets up the Nix IDE extension (`jnoortheen.nix-ide`) with `nixd`
(NixOS option completion, taken from this flake) and `nixfmt`. Install both into your
Nix profile: `nix profile add nixpkgs#nixd nixpkgs#nixfmt`.

## Adding a machine

1. Install NixOS on it as usual (this generates `/etc/nixos/hardware-configuration.nix`).
2. Create `hosts/<name>/configuration.nix` like `hosts/tv-box/configuration.nix`: import
   the modules it needs, set `networking.hostName = "<name>"`, and copy the boot loader
   and `system.stateVersion` from its `/etc/nixos/configuration.nix` (anything else in
   there goes into a module). Don't import `./hardware-configuration.nix`; `flake.nix`
   adds it.
3. Remove `/etc/nixos/configuration.nix` on the machine.
4. `./deploy.sh <name>`, then commit `hosts/<name>/hardware-configuration.nix`.
