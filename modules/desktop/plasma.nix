# KDE Plasma 6 desktop on Wayland, with SDDM as the login screen, and Firefox as the
# default browser.
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
    # (EPIKA) from playing the next episode. Wildcards (*.lrt.lt) aren't supported, so
    # each subdomain is listed.
    policies.Permissions.Autoplay.Allow = [
      "https://lrt.lt"
      "https://www.lrt.lt"
      "https://epika.lrt.lt"
    ];
  };

  # Default browser for everyone (/etc/xdg/mimeapps.list); a user's own choice in
  # ~/.config/mimeapps.list still wins. Without it apps that don't ask Plasma may pick
  # Google Chrome (packages.nix).
  xdg.mime.defaultApplications = {
    "text/html" = "firefox.desktop";
    "application/xhtml+xml" = "firefox.desktop";
    "x-scheme-handler/http" = "firefox.desktop";
    "x-scheme-handler/https" = "firefox.desktop";
  };
}
