# A big, slow ext4 HDD mounted at /mnt/hdd, with every normal user's
# large home folders (Videos, Downloads, ...) moved onto it and symlinked back.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  mountPoint = "/mnt/hdd";

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
  # The host sets `fileSystems."/mnt/hdd".device`, by UUID (`lsblk -o NAME,UUID`).
  fileSystems.${mountPoint} = {
    fsType = "ext4";
    # It's on USB: if it's unplugged, boot without it instead of dropping to an
    # emergency shell, and don't wait the default 90 s for it to appear.
    options = [
      "nofail"
      "x-systemd.device-timeout=10s"
    ];
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
