# KDE Plasma 6 desktop on Wayland, with SDDM as the login screen, and Firefox.
{
  services.xserver.enable = false;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  programs.firefox = {
    enable = true;
    # Allow DRM-protected video (Netflix etc.) without asking; Firefox downloads the
    # Widevine plugin on first use.
    policies.EncryptedMediaExtensions.Enabled = true;
  };
}
