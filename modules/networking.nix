# Network connectivity and remote access.
{
  networking.networkmanager.enable = true;

  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
}
