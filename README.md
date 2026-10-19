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

`flake.lock` pins nixpkgs (`nixos-26.05`), and the packages that aren't in nixpkgs
(`packages/`) are pinned to a release in their own files. `./upgrade.sh <name>` (same
arguments as `deploy.sh`) updates all of them, then runs the VM tests (`tests/`: a few
minutes, in VMs on this computer), and deploys only if they pass. Commit the updated
files afterwards (it lists them). For nixpkgs alone, without the packages and the tests,
`UPDATE=1 ./deploy.sh <name>` still works.

The packages are updated with [nix-update](https://github.com/Mic92/nix-update) to their
newest stable 1.x release (never a development branch or a release candidate). Each
`package.nix` declares that itself (`passthru.updateScript`), and `nix run
path:.#update-packages` runs them all (without testing or deploying). A new major
version (2.0) is left alone, since it may need manual steps: read its release notes,
then change `1` to `2` in that package's `updateScript` and run `./upgrade.sh`.

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

Those files only reference widgets; ones installed with "Get New Widgets" live in
`~/.local/share/plasma/plasmoids/`, which isn't saved, so a restored layout would show
"widget not found" in their place. Add such widgets to
`modules/desktop/plasma-widgets.nix` instead (search nixpkgs for them; the
`plugin=` lines in the saved `plasma-org.kde.plasma.desktop-appletsrc` show their ids).

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

## Anytype (sync server)

tv-box runs a self-hosted sync server for [Anytype](https://anytype.io)
(`modules/services/anytype.nix`): [any-sync-bundle](https://github.com/grishy/any-sync-bundle),
which is all of Anytype's own server programs in one, built from source
(`packages/any-sync-bundle/`). Its MongoDB and Valkey (Redis's open-source fork, with the
bloom filter module from `packages/valkey-bloom/`) are only for it. Apps reach it on TCP
33010 and UDP 33020, at `tv-box.lan` at home and `anytype.arturaz.net` elsewhere (they
try both, in that order; `anytype.externalAddrs` in tv-box's configuration; after
changing those, load the new client-config.yml into the apps again). What it
stores is end-to-end encrypted by the apps, so tv-box (and its backups) only ever see
ciphertext. The bundle can't open connections into the LAN, and only it can reach its
databases (firewall rules on uids), so a break-in through it stays on tv-box.

Outside this repo, it needs:

- **DNS** (Cloudflare, DNS only / grey cloud): an A record for `anytype.arturaz.net` to
  the home IP.
- **Router**: forward TCP 33010 and UDP 33020 to tv-box.

Its keys and the network's identity are generated on the first start, in
`/var/lib/any-sync/bundle-config.yml`; losing them means a new network, so they're in the
backups. To join it, get the network's settings for the apps:
`./anytype-client-config.sh` (asks for tv-box's sudo password, since the file is
root-only, and saves it as `anytype-tv-box.yml`; `./anytype-client-config.sh <name>
<file>` for another host or file name, `-` for the file to print it).
In the Anytype app (desktop or phone), before logging in, open the settings (gear icon)
on the start screen, choose the "Self-hosted" network and load that file; then create a
vault, or log in with an existing key. Notes on Anytype's own network don't move along:
export them first (Any-Block) and import them after switching.

`./upgrade.sh` updates it to its newest 1.x release (see "Updating"); its version names
the Anytype release it's compatible with, so run that when the apps have updated. Its
test (a client syncing through it in VMs, then backup and restore) runs there before
deploying; alone: `nix build -L --no-link path:.#checks.x86_64-linux.anytype`. Logs:
`journalctl -u any-sync -u mongodb -u redis-any-sync`.

## Backups and restoring

Every night tv-box backs up its services into `/mnt/hdd/backups/` (`backups.dir`):

| When | What | Where |
|------|------|-------|
| 01:00 | Anytype's sync server: its keys and file storage, MongoDB, Valkey | `any-sync/` |
| 03:00 | all of the above, encrypted with restic, to the Hetzner server | `devsrv.arturaz.net` |

Anytype's sync server is stopped for those few seconds (it can only be copied while
stopped); the apps catch up afterwards. The local backups fail while the HDD is missing
(`systemctl --failed` shows them). The off-site copy keeps 7 daily, 5 weekly and 12
monthly snapshots; its password is in `secrets/tv-box.yaml` (sops). The repository is
encrypted, so the Hetzner server only ever sees ciphertext. `sudo restic-offsite
snapshots` lists them.

### Setting up the off-site copy (once)

On the Hetzner server (Debian), as root, create a user that can only use SFTP in its
own directory:

```sh
useradd --system --no-create-home --home-dir /srv/tv-box-backup \
  --shell /usr/sbin/nologin tv-box-backup
mkdir -p /srv/tv-box-backup/restic /etc/ssh/authorized_keys
chown tv-box-backup: /srv/tv-box-backup/restic
cat >> /etc/ssh/sshd_config <<'END'

Match User tv-box-backup
    ChrootDirectory /srv/tv-box-backup
    ForceCommand internal-sftp
    AuthorizedKeysFile /etc/ssh/authorized_keys/tv-box-backup
    AllowTcpForwarding no
    X11Forwarding no
END
sshd -t && systemctl reload ssh
```

tv-box logs in with its SSH host key, so put its public half (`cat
/etc/ssh/ssh_host_ed25519_key.pub` on tv-box) into
`/etc/ssh/authorized_keys/tv-box-backup` on the server, then run the first backup:
`ssh arturas@tv-box.lan sudo systemctl start restic-backups-offsite`. Mind the free
space there (about as much as `/mnt/hdd/backups` takes). The server's own host key is
pinned in tv-box's configuration (`backups.offsite.serverHostKey`); update it if the
server is reinstalled.

### Restoring onto a new machine

1. Install NixOS and add the machine as in "Adding a machine". For a replacement tv-box,
   update its `hardware-configuration.nix`, and the HDD's UUID in
   `hosts/tv-box/hardware/hdd.nix` if the HDD is new too.
2. A new install has a new SSH host key: put it in `.sops.yaml` (see "Secrets") and run
   `nix shell nixpkgs#sops -c sops updatekeys secrets/*.yaml`, so the machine can decrypt
   the restic password, and replace the old key in the Hetzner server's
   `/etc/ssh/authorized_keys/tv-box-backup` (needed for the off-site copy).
3. Deploy. The services start empty, with new keys.
4. With the HDD's backups: `sudo backups-restore` (it asks before replacing anything).
   From the off-site copy instead:
   `sudo restic-offsite restore latest --target /root/restore`, then
   `sudo backups-restore /root/restore/mnt/hdd/backups`.
5. Check `systemctl --failed`. The Anytype apps reconnect by themselves (it's the same
   network again) and upload whatever changed since the backup.

`backups-restore` stops the services, replaces their data with the backup's and starts
them again. Each service module adds its part (`backups.restore`; `backups.files` for
plain directories).

## Secrets

Secrets for [sops-nix](https://github.com/Mic92/sops-nix) live encrypted in
`secrets/*.yaml` (safe to commit; anyone with read access to the repo sees only
ciphertext and the key names). `.sops.yaml` lists
who can decrypt them: your `~/.ssh/id_ed25519` and each machine's SSH host key, so a
machine decrypts its secrets itself at activation, into `/run/secrets/` (never into the
world-readable Nix store).

Adding one (`secrets/tv-box.yaml` holds tv-box's restic password):

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
