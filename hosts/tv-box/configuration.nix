# tv-box. Shared settings live in ../../modules; only what's specific to this
# machine belongs here.
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
    ../../modules/desktop/audio.nix
    ../../modules/desktop/printing.nix
    ../../modules/hardware/intel-graphics.nix
    ./hardware/hdd.nix
    ./hardware/usb-speakers.nix
  ];

  networking.hostName = "tv-box";

  # Panel layouts, copied from this machine by deploy.sh.
  desktop.plasmaPanels = ./plasma;

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
