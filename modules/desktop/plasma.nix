# KDE Plasma 6 desktop on Wayland, with SDDM as the login screen.
{
  services.xserver.enable = false;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  programs.firefox.enable = true;
}
