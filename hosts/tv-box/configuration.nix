# tv-box. Shared settings live in ../../modules; only what's specific to this
# machine belongs here.
{ config, ... }:
{
  imports = [
    ../../modules/nix.nix
    ../../modules/zram.nix
    ../../modules/locale.nix
    ../../modules/networking.nix
    ../../modules/packages.nix
    ../../modules/claude-code.nix
    ../../modules/users/arturas.nix
    ../../modules/users/entertainment
    ../../modules/desktop/plasma.nix
    ../../modules/desktop/plasma-panels.nix
    ../../modules/desktop/plasma-widgets.nix
    ../../modules/desktop/ad-blocker.nix
    ../../modules/desktop/power.nix
    ../../modules/desktop/audio.nix
    ../../modules/desktop/printing.nix
    ../../modules/hardware/intel-graphics.nix
    ../../modules/backups.nix
    ./hardware/hdd.nix
    ./hardware/usb-speakers.nix
  ];

  networking.hostName = "tv-box";

  # Panel layouts, copied from this machine by deploy.sh.
  desktop.plasmaPanels = ./plasma;

  # Nightly backups of the services, onto the USB HDD, and an encrypted copy of them
  # on the Hetzner server (see "Backups" in the README).
  backups.dir = "/mnt/hdd/backups";
  backups.offsite = {
    # User `tv-box-backup` on the Hetzner server (set up by hand, see the README), which
    # can only use SFTP inside its own directory; the restic repository is its /restic.
    sftp = "tv-box-backup@devsrv.arturaz.net:/restic";
    # The server's SSH host key (from `ssh-keyscan -t ed25519 devsrv.arturaz.net`), so
    # tv-box only ever sends backups to that server.
    serverHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKYPKgH7ScwpIFbP46kO1sKtRm8Jgd1gn4Lfs7Dehw7j";
    # The repository's encryption password: decrypted by sops-nix at boot into
    # /run/secrets/restic-password (root-only), never into the world-readable Nix store.
    passwordFile = config.sops.secrets.restic-password.path;
  };
  # The `restic-password` key in this sops file, which tv-box's SSH host key can decrypt.
  sops.secrets.restic-password.sopsFile = ../../secrets/tv-box.yaml;

  services.displayManager.autoLogin = {
    enable = true;
    user = "entertainment";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # The NixOS release this machine was installed with. It keeps stateful data (e.g.
  # databases) compatible and does NOT pin the NixOS version; never change it without
  # reading https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05";
}
