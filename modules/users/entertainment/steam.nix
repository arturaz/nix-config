# Steam, to play simple games on the machine itself instead of streaming them from razor
# (see moonlight.nix). `programs.steam` installs it system-wide, with 32-bit graphics
# libraries and udev rules for Steam/PlayStation/Xbox controllers.
{
  programs.steam = {
    enable = true;
    # Steam Remote Play (e.g. streaming from razor's Steam, or to a phone).
    remotePlay.openFirewall = true;
    # Copying installed games from other PCs on the LAN instead of downloading them.
    localNetworkGameTransfers.openFirewall = true;
  };
}
