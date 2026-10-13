# tv-box. Shared settings live in ../../modules; only what's specific to this
# machine belongs here.
{
  imports = [
    ../../modules/nix.nix
    ../../modules/locale.nix
    ../../modules/networking.nix
    ../../modules/packages.nix
    ../../modules/users/arturas.nix
    ../../modules/users/entertainment
    ../../modules/desktop/plasma.nix
    ../../modules/desktop/audio.nix
    ../../modules/desktop/printing.nix
    ../../modules/hardware/intel-graphics.nix
    ../../modules/hardware/hdd.nix
  ];

  networking.hostName = "tv-box";

  # The 2 TB USB HDD (see ../../modules/hardware/hdd.nix).
  fileSystems."/mnt/hdd".device = "/dev/disk/by-uuid/09f4888d-2069-4ff9-916a-bd96775ba202";

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
