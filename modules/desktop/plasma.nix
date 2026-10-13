# KDE Plasma 6 desktop on Wayland, with SDDM as the login screen, and Firefox.
{
  services.xserver.enable = false;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  # Makes nixpkgs' Chromium-based browsers and Electron apps run natively on Wayland
  # (newer versions already default to it; Firefox ignores this).
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  programs.firefox = {
    enable = true;
    # Allow DRM-protected video (Netflix etc.) without asking; Firefox downloads the
    # Widevine plugin on first use.
    policies.EncryptedMediaExtensions.Enabled = true;
    # Firefox blocks videos with sound from starting on their own, which stops LRT
    # (EPIKA) from playing the next episode.
    policies.Permissions.Autoplay.Allow = [
      "https://www.lrt.lt"
      "https://lrt.lt"
    ];
  };
}
