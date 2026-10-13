# The 2 TB USB HDD (ext4) mounted at /mnt/hdd, with every normal user's
# large home folders (Videos, Downloads, ...) moved onto it and symlinked back, and a
# warning for the entertainment account while it's missing. Spins down when idle.
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  mountPoint = "/mnt/hdd";
  mountUnit = "${utils.escapeSystemdPath mountPoint}.mount";
  # By UUID (`lsblk -o NAME,UUID`), so another disk can't be mounted here by mistake.
  # Changes if the disk is reformatted.
  uuid = "09f4888d-2069-4ff9-916a-bd96775ba202";
  # The whole disk (the UUID above is its partition), by model and serial number.
  disk = "/dev/disk/by-id/ata-HGST_HUS722T2TALA604_WMC6N0J4ZZZR";

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

  # Shown in the (empty) folders the links lead to whenever the HDD isn't mounted.
  noteName = "USB HARD DRIVE IS NOT CONNECTED.txt";
  note = pkgs.writeText "hdd-not-connected.txt" ''
    The big USB hard drive isn't connected (or didn't mount), so this folder is empty.
    Its files are on that drive. Check that it's plugged in and powered on.

    Nothing can be saved here until it's back.
  '';
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
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="${uuid}", ENV{SYSTEMD_WANTS}+="${mountUnit}"
  '';

  # Spin down after 20 minutes without reads or writes; the next access spins it back up
  # (taking a few seconds). hd-idle rather than the drive's own timer (`hdparm -S`),
  # which USB bridges often don't pass on or keep. Started with the mount, so after a
  # replug it finds the disk again even under a new /dev/sdX name.
  systemd.services.hdd-idle = {
    description = "Spin down the HDD at ${mountPoint} when idle";
    wantedBy = [ mountUnit ];
    bindsTo = [ mountUnit ];
    after = [ mountUnit ];
    # `-i 0` leaves other disks alone; `-c ata` sends ATA STANDBY, which this enclosure's
    # bridge (JMicron JMS578) passes through.
    serviceConfig.ExecStart = "${lib.getExe pkgs.hd-idle} -i 0 -c ata -a ${disk} -i 1200";
    serviceConfig.Restart = "on-failure";
  };

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

  # Puts the note into /mnt/hdd and every linked folder's target on the SSD, underneath
  # where the HDD gets mounted: hidden while it's mounted, the only thing there when it's
  # not. They're root's and read-only, so nothing gets saved to the SSD by mistake.
  # Works while the HDD is mounted too: it writes through a bind mount of just the root
  # file system, in a mount namespace of its own.
  systemd.services.hdd-missing-notes = {
    description = "Put a 'drive not connected' note under ${mountPoint}";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      PrivateMounts = true;
      RuntimeDirectory = "hdd-missing-notes";
    };
    path = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    script = ''
      root="$RUNTIME_DIRECTORY"
      mount --bind / "$root"

      put_note() {
        install -d -m 0755 "$root$1"
        install -m 0444 ${note} "$root$1/${noteName}"
      }

      put_note ${mountPoint}
      ${lib.concatStrings (
        lib.mapAttrsToList (
          _: user:
          lib.concatMapStrings (dir: ''
            put_note ${lib.escapeShellArg "${mountPoint}/home/${user.name}/${dir}"}
          '') dirs
        ) users
      )}
    '';
  };

  # Runs on every boot, before anyone can log in, and again whenever the HDD is mounted
  # (e.g. plugged back in after booting without it). Existing folders are moved onto the
  # HDD (never overwriting anything already there) and replaced with the symlink; a
  # folder that can't be fully moved is left alone with a warning in the journal.
  systemd.services.hdd-home-links = {
    description = "Link large home folders to ${mountPoint}";
    wantedBy = [
      "multi-user.target"
      mountUnit
    ];
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
