# KTorrent for the entertainment account, with its ports open in the firewall.
{ pkgs, ... }:
{
  users.users."entertainment".packages = [ pkgs.kdePackages.ktorrent ];

  # KTorrent's default listening ports, so peers can connect in: 6881 for peers,
  # 7881 for DHT. Update these if they're changed in KTorrent's settings.
  networking.firewall.allowedTCPPorts = [ 6881 ];
  networking.firewall.allowedUDPPorts = [ 7881 ];
}
