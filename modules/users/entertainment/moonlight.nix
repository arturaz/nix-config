# Moonlight, to stream games from razor (which runs Sunshine) to the entertainment account.
# Pairing is a one-time manual step: add the host in Moonlight, then enter its PIN in
# Sunshine's web UI on razor. Video is decoded on the GPU (see hardware/intel-graphics.nix).
{ pkgs, ... }:
{
  users.users."entertainment".packages = [ pkgs.moonlight-qt ];

  # Moonlight finds hosts on the LAN over mDNS, whose replies arrive unsolicited on this
  # port. Without it, the host can still be added by name (razor.lan).
  networking.firewall.allowedUDPPorts = [ 5353 ];
}
