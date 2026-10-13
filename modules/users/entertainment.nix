# A shared, non-admin account for media/TV use, meant to be logged in automatically.
# Netflix and YouTube run in Firefox; VLC is installed system-wide.
{ pkgs, ... }:

{
  users.users."entertainment" = {
    isNormalUser = true;
    description = "Entertainment";
    extraGroups = [ "networkmanager" ];
    # Empty password: the screen locker and login screen unlock with just Enter.
    # sshd still refuses empty passwords (PermitEmptyPasswords defaults to no).
    hashedPassword = "";
    packages = with pkgs; [
      kdePackages.ktorrent
    ];
  };

  # KTorrent's default listening ports, so peers can connect in: 6881 for peers,
  # 7881 for DHT. Update these if they're changed in KTorrent's settings.
  networking.firewall.allowedTCPPorts = [ 6881 ];
  networking.firewall.allowedUDPPorts = [ 7881 ];
}
