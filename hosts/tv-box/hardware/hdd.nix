# The 2 TB USB HDD (ext4) mounted at /mnt/hdd, with every normal user's
# large home folders (Videos, Downloads, ...) moved onto it and symlinked back, and a
# warning for the entertainment account while it's missing.
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  mountPoint = "/mnt/hdd";
  # By UUID (`lsblk -o NAME,UUID`), so another disk can't be mounted here by mistake.
  # Changes if the disk is reformatted.
  uuid = "09f4888d-2069-4ff9-916a-bd96775ba202";

  # Home folders that get big. Each becomes ~/<dir> -> /mnt/hdd/home/<user>/<dir>.
  dirs = [
    "Downloads"
    "Music"
    "Pictures"
    "Videos"
  ];

  users = lib.filterAttrs (_: user: user.isNormalUser) config.users.users;

  linkUser =
    _: user:
    lib.concatMapStrings (dir: ''
      link_dir ${
        lib.escapeShellArgs [
          user.name
          user.group
          user.home
          dir
        ]
      }
    '') dirs;
in
{
  fileSystems.${mountPoint} = {
    device = "/dev/disk/by-uuid/${uuid}";
    fsType = "ext4";
    # It's on USB: if it's unplugged, boot without it instead of dropping to an
    # emergency shell, and don't wait the default 90 s for it to appear.
    options = [
      "nofail"
      "x-systemd.device-timeout=10s"
    ];
  };

  # systemd unmounts it when it's unplugged; this mounts it again when it's plugged back
  # in (otherwise that only happens on boot).
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="${uuid}", ENV{SYSTEMD_WANTS}+="${utils.escapeSystemdPath mountPoint}.mount"
  '';

  # While the HDD isn't mounted, the entertainment account gets a dialog saying so (once
  # per unplug, closed again when it's back). Rechecks on every mount/unmount.
  systemd.user.services.hdd-missing-warning = {
    description = "Warn when the HDD at ${mountPoint} is missing";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    unitConfig.ConditionUser = "entertainment";
    serviceConfig.Restart = "on-failure";
    path = [
      pkgs.util-linux
      pkgs.kdePackages.kdialog
    ];
    script = ''
      dialog=
      # One line now, then one per mount table change.
      { echo; findmnt --poll; } | while read -r _; do
        if mountpoint -q ${mountPoint}; then
          if [ -n "$dialog" ]; then kill "$dialog" 2>/dev/null || true; fi
          dialog=
        elif [ -z "$dialog" ]; then
          kdialog --title "Drive missing" --sorry \
            "The big USB hard drive isn't connected, so Videos, Downloads, Music and Pictures are unavailable. Check that it's plugged in and powered on." &
          dialog=$!
        fi
      done
    '';
  };

  # Runs on every boot, before anyone can log in. Existing folders are moved onto the HDD
  # (never overwriting anything already there) and replaced with the symlink; a folder
  # that can't be fully moved is left alone with a warning in the journal. If the HDD
  # isn't mounted, this doesn't run and the links point nowhere until it is.
  systemd.services.hdd-home-links = {
    description = "Link large home folders to ${mountPoint}";
    wantedBy = [ "multi-user.target" ];
    before = [ "systemd-user-sessions.service" ];
    unitConfig.RequiresMountsFor = mountPoint;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [
      pkgs.coreutils
      pkgs.findutils
    ];
    script = ''
      install -d -m 0755 ${mountPoint}/home

      link_dir() {
        local user="$1" group="$2" home="$3" dir="$4"
        local target="${mountPoint}/home/$user/$dir" link="$home/$dir"

        install -d -o "$user" -g "$group" -m 0700 "${mountPoint}/home/$user"
        install -d -o "$user" -g "$group" -m 0755 "$target"

        if [ -L "$link" ]; then
          [ "$(readlink "$link")" = "$target" ] && return
          echo "$link is a symlink to $(readlink "$link"), leaving it alone" >&2
          return
        fi
        if [ -d "$link" ]; then
          find "$link" -mindepth 1 -maxdepth 1 \
            -exec mv --update=none -t "$target" -- {} + || true
          if ! rmdir "$link" 2>/dev/null; then
            echo "$link: some files already exist in $target, leaving it alone" >&2
            return
          fi
        elif [ -e "$link" ]; then
          echo "$link is not a directory, leaving it alone" >&2
          return
        fi
        ln -s "$target" "$link"
        chown -h "$user:$group" "$link"
      }

      ${lib.concatStrings (lib.mapAttrsToList linkUser users)}
    '';
  };
}
