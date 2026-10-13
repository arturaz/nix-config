# NixOS configurations

A flake with one `nixosConfigurations.<name>` per machine. `flake.nix` picks up every
directory in `hosts/` automatically.

- `modules/`: settings shared between machines, one topic per file (`locale.nix`,
  `desktop/audio.nix`, ...). Add new things here, as a new file when it's a new topic.
- `hosts/<name>/configuration.nix`: imports the modules a machine uses, plus what's
  specific to it (hostname, boot loader, `system.stateVersion`).
- `hosts/<name>/hardware/`: hardware only that machine has (e.g. a particular disk).
  Hardware settings several machines could share go in `modules/hardware/`.

Current hosts:

- `tv-box` (`tv-box.lan`)

## Deploying

`./deploy.sh <name>` evaluates the configuration on this machine, then builds and
activates it on `arturas@<name>.lan`. Pass `test`, `boot`, `dry-activate` or `build` as a
second argument to do that instead of `switch` (as in `nixos-rebuild`), and set
`TARGET=user@host` if the machine isn't reachable at the default address.

It asks for the target's sudo password once, at the start, and checks it right away (up
to 3 tries), so a typo doesn't cost a build. It does the same steps as `nixos-rebuild
--build-host/--target-host --sudo`, but itself, so that when one fails it says which, and
whether the machine was changed (and how to roll back if it was).

Needs Nix on this machine; the script enables flakes for its own commands.

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

A weekly garbage collection (`modules/nix.nix`) deletes system generations older than
30 days, so you can only roll back (boot menu or `nixos-rebuild switch --rollback`) to
deploys from the last 30 days. The current generation is never deleted.

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

## Plasma panel layouts

Each user's panel layout (`~/.config/plasma-org.kde.plasma.desktop-appletsrc` and
`plasmashellrc`, which also hold the desktop's widgets and wallpaper) is saved in
`hosts/<name>/plasma/<user>/`. Like the machine-generated files, the machine is the
source of truth: change panels there as usual, and `deploy.sh` copies every normal
user's files back here (reading them with sudo, so even a `build` asks for the sudo
password on such hosts) and lists them for
committing. A boot service (`modules/desktop/plasma-panels.nix`) copies them into a
home only where they're missing, e.g. after a reinstall or for a fresh account, and
never overwrites what's there. To restore a saved layout over a changed one, log out,
delete the user's two files on the machine and reboot. For a new host, create
`hosts/<name>/plasma/` and set `desktop.plasmaPanels = ./plasma;`.

## tv-box's HDD

`hosts/tv-box/hardware/hdd.nix` mounts an ext4 disk at `/mnt/hdd` (skipped if it's
unplugged) and, on every boot and whenever it gets mounted, moves each user's Downloads, Music, Pictures and Videos
onto it, leaving symlinks in their place. It's mounted again when it's plugged back in,
and the `entertainment` account shows a warning dialog while it's missing. Underneath the
mount point (on the SSD), each linked folder holds only a read-only "USB HARD DRIVE IS
NOT CONNECTED.txt", which is what the links show if it isn't mounted. It spins down
after 20 minutes without reads or writes (`hd-idle`). To set up a new disk (this wipes
it): `sudo mkfs.ext4 -L hdd /dev/sdX1`, put its UUID (`lsblk -o NAME,UUID`) into that
file's `uuid` and the disk's `/dev/disk/by-id/ata-...` link into `disk`, deploy, then
reboot.

## Secrets

There are no secrets yet; [sops-nix](https://github.com/Mic92/sops-nix) is set up for
when one is needed. Secrets live encrypted in `secrets/*.yaml` (safe to commit; anyone
with read access to the repo sees only ciphertext and the key names). `.sops.yaml` lists
who can decrypt them: your `~/.ssh/id_ed25519` and each machine's SSH host key, so a
machine decrypts its secrets itself at activation, into `/run/secrets/` (never into the
world-readable Nix store).

Adding the first one:

1. `nix shell nixpkgs#sops -c sops secrets/common.yaml` opens an editor; add
   `wifi-password: hunter2` and save. sops asks for your SSH key's passphrase whenever
   it decrypts.
2. In a module:

   ```nix
   sops.defaultSopsFile = ../secrets/common.yaml;
   sops.secrets.wifi-password = { };   # /run/secrets/wifi-password, root-only
   ```

   Point the service at the file path (`config.sops.secrets.wifi-password.path`); for a
   secret inside a config file, see `sops.templates`. Set `owner`/`mode`/`restartUnits`
   on the secret as needed.

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
5. If it needs secrets: add its key to `.sops.yaml` (the command is in there), then
   `nix shell nixpkgs#sops -c sops updatekeys secrets/*.yaml`.
