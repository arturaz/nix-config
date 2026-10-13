# Each user's Plasma panel layout, saved from the machine by deploy.sh: restored into
# a home that doesn't have it (e.g. a new install), never overwriting what's there.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  dir = config.desktop.plasmaPanels;
  users =
    if dir == null then
      [ ]
    else
      lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir));
in
{
  options.desktop.plasmaPanels = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = ''
      Directory with a <user>/ subdirectory per user, holding that user's
      ~/.config/plasma-org.kde.plasma.desktop-appletsrc and plasmashellrc. deploy.sh
      copies them from the machine (which is their source of truth) on every deploy.
    '';
  };

  config = lib.mkIf (users != [ ]) {
    assertions = map (user: {
      assertion = config.users.users ? ${user};
      message = "desktop.plasmaPanels has files for ${user}, who isn't a user here.";
    }) users;

    # Before the display manager, so an auto-login session starts with them.
    systemd.services.restore-plasma-panels = {
      description = "Restore missing Plasma panel layouts";
      wantedBy = [ "multi-user.target" ];
      before = [ "display-manager.service" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.coreutils ];
      script = lib.concatMapStrings (
        user:
        let
          u = config.users.users.${user};
          owner = "-o ${lib.escapeShellArg user} -g ${lib.escapeShellArg u.group}";
          config_ = lib.escapeShellArg "${u.home}/.config";
        in
        ''
          [ -d ${config_} ] || install -d -m 700 ${owner} ${config_}
          for f in ${dir + "/${user}"}/*; do
            dest=${config_}/"$(basename "$f")"
            [ -e "$dest" ] || install -m 600 ${owner} "$f" "$dest"
          done
        ''
      ) users;
    };
  };
}
