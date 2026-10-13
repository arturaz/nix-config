# Packages installed system-wide. Search: https://search.nixos.org/packages
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vim
    wget
    kdePackages.kate
    vlc
    # Fallback for sites that only work in Chrome.
    google-chrome
    # Password manager: desktop app and `bw` CLI.
    bitwarden-desktop
    bitwarden-cli
  ];
}
