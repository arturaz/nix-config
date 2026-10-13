# Profile photos, shown by SDDM, the lock screen, the app launcher and System Settings.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  avatars = config.users.avatars;
in
{
  options.users.avatars = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = { };
    description = "Profile photo for each user name (square, at most 1 MB).";
  };

  # Set through AccountsService, which copies the photo to
  # /var/lib/AccountsService/icons/<user> (where SDDM and KDE look for it) and records
  # it in /var/lib/AccountsService/users/<user> (which System Settings reads). Runs on
  # every boot, so a photo changed in System Settings goes back to this one.
  config = lib.mkIf (avatars != { }) {
    systemd.services.set-avatars = {
      description = "Set user profile photos";
      wantedBy = [ "multi-user.target" ];
      after = [ "accounts-daemon.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = lib.concatStrings (
        lib.mapAttrsToList (user: photo: ''
          path=$(${pkgs.systemd}/bin/busctl call org.freedesktop.Accounts \
            /org/freedesktop/Accounts org.freedesktop.Accounts \
            FindUserByName s ${lib.escapeShellArg user} | cut -d'"' -f2)
          ${pkgs.systemd}/bin/busctl call org.freedesktop.Accounts "$path" \
            org.freedesktop.Accounts.User SetIconFile s ${lib.escapeShellArg "${photo}"}
        '') avatars
      );
    };
  };
}
