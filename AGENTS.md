# Agent notes

NixOS configurations for the user's machines, as a flake. `README.md` is the
human-facing documentation (deploying, updating, adding a machine); read it for anything
not covered here. This file records what an agent would otherwise have to rederive.

## Layout

- `flake.nix`: `nixosConfigurations.<name>` for every directory in `hosts/`
  (auto-discovered, nothing to register). Each gets `hosts/<name>/configuration.nix` +
  `hosts/<name>/hardware-configuration.nix`. Single input: `nixpkgs` on `nixos-26.05`.
- `hosts/<name>/configuration.nix`: imports from `modules/` plus only host-specific
  settings (hostname, boot loader, `system.stateVersion`).
- `modules/`: shared settings, one topic per file, each starting with a one-line comment
  saying what it covers. New settings go into a module (a new file for a new topic), not
  into a host file, unless they are truly machine-specific. Modules are plain attrsets;
  take `{ pkgs, ... }:` only when needed.
  - `nix.nix` (flakes, `allowUnfree`), `locale.nix` (Europe/Vilnius, en_US + lt_LT
    formats, `us` keyboard), `networking.nix` (NetworkManager, sshd, port 22,
    arturas's ssh key, which can log into every user incl. root), `packages.nix`
    (system packages), `users/arturas.nix` (admin user, wheel),
    `users/entertainment/` (`default.nix`: non-admin account, empty password, tv-box
    auto-logs into it; `ktorrent.nix`: KTorrent + its firewall ports; `moonlight.nix`:
    Moonlight game streaming client, streaming from `razor` (Sunshine, not managed by
    this repo); `spotify.nix`: one auto-started Spotify web player per person, each a Firefox profile with its own
    Wayland app id, via systemd user services, `~/bin/spotify-<name>` and app menu
    entries with hue-shifted icons from `spotify.png`). The native Spotify client
    was tried and dropped: copies in one D-Bus session quit, and its Wayland app id is
    fixed to `spotify`.
  - `desktop/`: `plasma.nix` (Plasma 6, Wayland, SDDM, Firefox with DRM on and
    autoplay allowed on lrt.lt), `audio.nix` (PipeWire), `printing.nix` (CUPS)
  - `hardware/`: `intel-graphics.nix` (VA-API video decoding via intel-media-driver)
- `deploy.sh`: remote deploy via `nixos-rebuild --target-host`. Usage and env vars
  (`TARGET`, `UPDATE`, `BUILD_LOCAL`) are documented at its top and in the README.
- `.vscode/settings.json`: nixd + nixfmt. Its `options.nixos` expression hardcodes the
  `tv-box` host; update it if that host is ever removed or renamed. Add new
  domain words to `cSpell.words` there when they trip the spell checker.

Hosts: `tv-box` (reached as `arturas@tv-box.lan`; Intel, systemd-boot/EFI).

## Rules

- Never edit `hosts/*/hardware-configuration.nix`. It's copied from the machine's
  `/etc/nixos` on every deploy (`MACHINE_FILES` in `deploy.sh`) and would be overwritten.
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
