# Never dim or turn off the screen when idle: playing a video doesn't always keep it on
# (VLC didn't).
{ pkgs, lib, ... }:

{
  # Set in the user's own ~/.config/powerdevilrc before PowerDevil starts, on every login,
  # so changes made in System Settings > Power Management last until the next login.
  systemd.user.services.entertainment-screen-settings = {
    description = "Keep the screen on when idle";
    wantedBy = [ "plasma-powerdevil.service" ];
    before = [ "plasma-powerdevil.service" ];
    unitConfig.ConditionUser = "entertainment";
    serviceConfig.Type = "oneshot";
    script =
      lib.concatMapStrings
        (
          { key, value }:
          ''
            ${lib.getExe' pkgs.kdePackages.kconfig "kwriteconfig6"} --file powerdevilrc \
              --group AC --group Display --key ${key} ${value}
          ''
        )
        [
          {
            key = "DimDisplayWhenIdle";
            value = "false";
          }
          {
            key = "DimDisplayIdleTimeoutSec";
            value = "-- -1";
          }
          {
            key = "TurnOffDisplayWhenIdle";
            value = "false";
          }
          {
            key = "TurnOffDisplayIdleTimeoutSec";
            value = "-- -1";
          }
        ];
  };
}
