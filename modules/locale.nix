# Time zone, language/regional formats and keyboard layouts.
{ config, ... }:
{
  time.timeZone = "Europe/Vilnius";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "lt_LT.UTF-8";
    LC_IDENTIFICATION = "lt_LT.UTF-8";
    LC_MEASUREMENT = "lt_LT.UTF-8";
    LC_MONETARY = "lt_LT.UTF-8";
    LC_NAME = "lt_LT.UTF-8";
    LC_NUMERIC = "lt_LT.UTF-8";
    LC_PAPER = "lt_LT.UTF-8";
    LC_TELEPHONE = "lt_LT.UTF-8";
    LC_TIME = "lt_LT.UTF-8";
  };

  # Despite the name, not X11-only: this is the system keyboard config (systemd-localed),
  # which SDDM's Wayland greeter uses. Win+Space switches between the layouts.
  services.xserver.xkb = {
    layout = "us,lt";
    variant = "";
    options = "grp:win_space_toggle";
  };

  # Plasma sessions ignore the above (KWin reads only ~/.config/kxkbrc, falling back to
  # plain `us`), so give them the same layouts as a system-wide default. A user's own
  # choice in System Settings > Keyboard overrides it.
  environment.etc."xdg/kxkbrc".text =
    let
      xkb = config.services.xserver.xkb;
    in
    ''
      [Layout]
      Use=true
      LayoutList=${xkb.layout}
      VariantList=${xkb.variant}
      Options=${xkb.options}
      ResetOldOptions=true
    '';
}
