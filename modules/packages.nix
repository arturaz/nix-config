# Packages installed system-wide. Search: https://search.nixos.org/packages
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vim
    wget
    kdePackages.kate
    vlc
  ];
}
