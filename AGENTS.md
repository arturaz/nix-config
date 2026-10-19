# Agent notes

NixOS configurations for the user's machines, as a flake. `README.md` is the
human-facing documentation (deploying, updating, adding a machine); read it for anything
not covered here. This file records what an agent would otherwise have to rederive.

## Layout

- `flake.nix`: `nixosConfigurations.<name>` for every directory in `hosts/`
  (auto-discovered, nothing to register). Each gets `hosts/<name>/configuration.nix` +
  `hosts/<name>/hardware-configuration.nix` + the sops-nix module. Inputs: `nixpkgs` on
  `nixos-26.05`, `sops-nix` (following our nixpkgs).
- `.sops.yaml` + `secrets/*.yaml` (`tv-box.yaml`: `restic-password`): sops-nix secrets,
  decryptable by arturas's SSH key and each host's SSH host key; see "Secrets" in the
  README. Encrypting needs only the public keys, so a new secret can be generated and
  piped into `sops --encrypt --filename-override secrets/<f>.yaml /dev/stdin` without
  ever being shown. Never put a
  plaintext secret in a `.nix` file: the repo will be shared read-only with friends,
  and the Nix store is world-readable.
- `packages/<name>/package.nix`: packages nixpkgs lacks, `callPackage`d by the module
  using them, pinned and updated by hand: `any-sync-bundle` (Go, built as upstream's
  flake.nix does; take `vendorHash` from there), `valkey-bloom` (Rust; upstream has no
  Cargo.lock, so ours is generated next to it).
- `hosts/<name>/configuration.nix`: imports from `modules/` and `./hardware/`, plus
  only host-specific settings (hostname, boot loader, `system.stateVersion`).
- `hosts/<name>/hardware/`: hardware only that machine has (e.g. a particular disk),
  one topic per file. Hardware settings several machines could share (e.g. a GPU
  driver) go in `modules/hardware/`.
- `modules/`: shared settings, one topic per file, each starting with a one-line comment
  saying what it covers. New settings go into a module (a new file for a new topic), not
  into a host file, unless they are truly machine-specific. Modules are plain attrsets;
  take `{ pkgs, ... }:` only when needed.
  - `nix.nix` (flakes, `allowUnfree`, weekly GC of generations older than 30 days),
    `locale.nix` (Europe/Vilnius, en_US + lt_LT formats, `us` + `lt` keyboard layouts, Win+Space switches; set both for localed/SDDM and as Plasma's default `/etc/xdg/kxkbrc`, since KWin ignores localed),
    `networking.nix` (NetworkManager, sshd on port 22, arturas's ssh key, which can log
    into every user; ssh logins as root are off, so root goes through sudo),
    `packages.nix` (system packages), `zram.nix` (compressed swap in RAM; no disk swap),
    `claude-code.nix` (a `claude` wrapper that, on a user's first run, installs the
    official native Claude Code into their `~/.local` via `claude.ai/install.sh`; that
    copy auto-updates itself and, with `localBinInPath`, shadows the wrapper; needs
    `nix-ld`. nixpkgs' `claude-code` is avoided because it can't self-update),
    `users/avatars.nix` (a `users.avatars.<user> = <photo>` option; a boot service
    sets each via AccountsService's `SetIconFile`, which is where SDDM and KDE read
    it, overriding photos changed in System Settings),
    `users/arturas.nix`
    (admin user, wheel; photo `arturas.jpg`, a 512 px crop with EXIF stripped),
    `users/entertainment/` (`default.nix`: non-admin account, empty password, tv-box
    auto-logs into it, Plasma's stock "Gamepad" avatar; `ktorrent.nix`: KTorrent + its firewall ports; `screen.nix`: never dim or turn off the screen
    when idle (VLC didn't keep it on), written into its `powerdevilrc` by a user service
    before PowerDevil starts on each login; `moonlight.nix`:
    Moonlight game streaming client, streaming from `razor` (Sunshine, not managed by
    this repo); `steam.nix`: Steam (system-wide, as `programs.steam` installs it), to
    play simple games locally, with Remote Play and LAN game-transfer ports open; `spotify.nix`: one auto-started native Spotify per person via systemd user
    services, each with its own HOME (`~/.local/share/spotify-homes/<name>`) and a
    private D-Bus session from `dbus-run-session`, since copies in one session make
    each other quit (its config can't start services, else e.g. a KDE wallet daemon
    starts per instance and asks to create a wallet); an `xdg-open` wrapper restores the real HOME and bus so login links
    open in the normal Firefox (Spotify opens links via GTK, so each instance's
    `mimeapps.list` points web links at a desktop entry running that wrapper). Plus `~/bin/spotify-<name>` and app menu entries with
    hue-shifted icons. Known costs: Plasma's media controls/keys don't see them, and the
    windows all have Wayland app id `spotify`, so they look alike in the task bar. A
    Firefox web player per person was tried before; its windows' icons reverted to
    Firefox's).
  - `desktop/`: `plasma.nix` (Plasma 6, Wayland, SDDM, Firefox as default browser,
    with DRM on and autoplay allowed on lrt.lt), `plasma-panels.nix` (`desktop.plasmaPanels = ./plasma;`:
    each user's panel files from `hosts/<name>/plasma/<user>/`, copied into homes
    missing them at boot; `deploy.sh` pulls them from the machine, which wins), `plasma-widgets.nix`
    (third-party widgets those layouts use, from nixpkgs; widgets installed in Plasma
    to `~/.local/share/plasma/plasmoids/` aren't saved), `ad-blocker.nix` (uBlock Origin force-installed in Firefox
    and uBlock Origin Lite in Google Chrome via browser policies; `programs.chromium` only
    writes the policy files, Chrome reads its copy in `/etc/opt/chrome`), `power.nix` (never auto-suspend on AC: a
    system-wide `/etc/xdg/powerdevilrc` default that users' own settings override), `audio.nix` (PipeWire), `printing.nix` (CUPS)
  - `hardware/`: `intel-graphics.nix` (VA-API video decoding via intel-media-driver)
  - `backups.nix`: `backups.dir` (tv-box: `/mnt/hdd/backups`), where services put
    nightly backups (units `RequiresMountsFor` it); `backups.files` (directories rsynced
    to `<dir>/files<path>`; unused now); `backups.restore.{stopUnits,script}` (each
    module's part of the `backups-restore` command, which gets the backup in `$src`);
    `backups.offsite.{sftp,passwordFile}` (restic `offsite` over SFTP to
    `devsrv.arturaz.net`, a.k.a. arturaz-dev: Hetzner, Debian, not managed here; logs in
    with the host's SSH host key; the server's host key is pinned in `serverHostKey`;
    password from sops).
  - `services/valkey.nix`: `services.redis.package = valkey` for all instances; each
    service gets its own `services.redis.servers.<name>` instead of sharing one.
    Prefer socket-only instances (the default, `port = 0`; access = membership in group
    `redis-<name>`); a TCP one is open to every local user, so it needs a password or a
    firewall rule (anytype.nix: port 6379 + its iptables chain).
- `deploy.sh`: remote deploy, doing `nixos-rebuild --build-host/--target-host --sudo`'s
  steps itself (eval, copy the .drv, build on target, `nix-env --set` +
  `switch-to-configuration` via `systemd-run`) so it can check the sudo password before
  building and explain each failure. Usage and env vars (`TARGET`, `UPDATE`,
  `BUILD_LOCAL`) are documented at its top and in the README.
- `upgrade.sh`: `UPDATE=1 ./deploy.sh "$@"` (updates the flake inputs, then deploys),
  for now.
- `.vscode/settings.json`: nixd + nixfmt. Its `options.nixos` expression hardcodes the
  `tv-box` host; update it if that host is ever removed or renamed. Add new
  domain words to `cSpell.words` there when they trip the spell checker.

Hosts: `tv-box` (reached as `arturas@tv-box.lan`; Intel, systemd-boot/EFI). Its
`hardware/hdd.nix`: the 2 TB USB HDD, ext4 by UUID, mounted `nofail` at `/mnt/hdd`; a
boot service (rerun whenever the HDD gets mounted) moves every normal user's `~/{Downloads,Music,Pictures,Videos}` to
`/mnt/hdd/home/<user>/` and symlinks them back; a udev rule remounts it when it's plugged
back in, and `entertainment` gets a KDE dialog (`hdd-missing-warning` user service)
while it's not mounted. `hdd-missing-notes` writes a read-only "USB HARD DRIVE IS NOT
CONNECTED.txt" into the SSD directories underneath the mount point (through a bind mount of
`/` in a private namespace), so the links show it when the HDD isn't mounted. `hdd-idle` (hd-idle, started with the
mount) spins it down after 20 minutes without I/O. Its `hardware/usb-speakers.nix`: the USB speakers
(TI PCM2902, 08bb:2902) only have a 28 dB hardware volume range, so low volumes were
silent; WirePlumber uses a soft mixer for them and a udev rule keeps the hardware volume
at 100%.

## Rules

- Never edit `hosts/*/hardware-configuration.nix` or `hosts/*/plasma/`. They're copied
  from the machine on every deploy (`MACHINE_FILES` and `PLASMA_FILES` in `deploy.sh`)
  and would be overwritten.
  Hardware tweaks go into the host's `configuration.nix` or a module.
- Never change `system.stateVersion`.
- Never set `nix.settings.trusted-users` (deliberate: it makes that user effectively
  root). `BUILD_LOCAL=1` falls back to building on the target because of this.
- Always reference the flake as `path:.` (not `.`): the repo is a colocated jj + git
  repo, and jj doesn't add new files to git's index, so a git flake wouldn't see them.
- Format Nix with `nixfmt` (the style already in the repo, apart from the generated
  hardware files).
- Version control is jj (colocated with git). Prefer `jj` commands; `deploy.sh` handles
  both.
- Put every change the user asks for in its own jj change: before editing any file,
  run `jj new -m "<what this request does>"` so the work lands on top of the current
  change instead of being mixed into it (if `@` is already empty and undescribed, just
  `jj describe -m` it). One request, one change; follow-up fixes to
  the same request stay in that change. Don't describe, squash or rewrite existing
  changes unless asked.
- Deploying touches a real machine and asks for a sudo password interactively; don't run
  `./deploy.sh` unless the user asks. Keep `README.md` in sync when changing how things
  work.

## Checking changes without deploying

Evaluate a host (~5 s, catches option/type errors):

```sh
nix eval --raw path:.#nixosConfigurations.tv-box.config.system.build.toplevel.drvPath
```

Query a value: `nix eval path:.#nixosConfigurations.tv-box.config.<option>`.
See what a build would fetch or compile:
`nix build --dry-run path:.#nixosConfigurations.tv-box.config.system.build.toplevel`
(drop `--dry-run` for a full local build, which downloads a lot).
