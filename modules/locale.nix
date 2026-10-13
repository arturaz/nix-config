# Time zone, language/regional formats and keyboard layout.
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

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
