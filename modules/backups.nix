# Nightly backups of the services into `backups.dir` (each service in its own
# subdirectory; plus `files/`, copies of the directories in `backups.files`), an
# encrypted off-site copy of it all with restic (`backups.offsite`), and a
# `backups-restore` command that puts a backup back on a (new) machine.
#
# How it fits together. This module doesn't know what to back up; it's a framework that
# service modules (e.g. services/anytype.nix) plug into:
#
#   1. Each service module adds its own nightly backup unit, which writes into
#      `<backups.dir>/<service>/` (anytype.nix: `any-sync-backup` at 01:00). Plain
#      directories can instead be listed in `backups.files`, and this module's
#      `backup-files` unit copies them.
#   2. At 03:00, restic copies the whole of `backups.dir` to the off-site server,
#      encrypted, keeping older snapshots (`restic-backups-offsite`, from NixOS's
#      `services.restic` module).
#   3. To restore, `sudo backups-restore` stops every service listed in
#      `backups.restore.stopUnits`, runs each service's `backups.restore.script` with
#      the backup's location in `$src`, then starts them again.
#
# The host sets `backups.dir` (and `backups.offsite`); without `backups.dir`, none of
# this exists.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.backups;
  enabled = cfg.dir != null;
  # An ssh known_hosts file with just the off-site server's key, so ssh refuses to talk
  # to anything else claiming to be that server (rather than trusting it on first use).
  knownHosts =
    host: pkgs.writeText "backups-offsite-known-hosts" "${host} ${cfg.offsite.serverHostKey}\n";
in
{
  options.backups = {
    dir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/mnt/hdd/backups";
      description = ''
        Directory for nightly backups, each service in its own subdirectory. Backups
        wait for it to be mounted and fail (rather than fill the disk underneath) if it
        can't be. Unset, nothing is backed up.
      '';
    };

    files = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Directories (e.g. generated secrets) copied nightly as they are into
        `<dir>/files/<path>`, and back to `<path>` by `backups-restore`.
      '';
    };

    restore = {
      stopUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Units `backups-restore` stops before restoring and starts after.";
      };
      script = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Each service's restore steps, run by `backups-restore` with those units stopped
          and the backup in `$src`.
        '';
      };
    };

    offsite = {
      sftp = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "tv-box-backup@backup.example.com:/restic";
        description = ''
          Where to keep an encrypted restic copy of `dir` (`user@host:path`, over SFTP).
          It logs in with this machine's SSH host key, so that key's public half
          (/etc/ssh/ssh_host_ed25519_key.pub) must be authorized there.
        '';
      };
      serverHostKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "ssh-ed25519 AAAA...";
        description = "The server's SSH host key (`ssh-keyscan -t ed25519 <host>`).";
      };
      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The restic repository's password (e.g. a sops secret).";
      };
    };
  };

  # Everything below exists only when the host has set `backups.dir`.
  config = lib.mkIf enabled (
    lib.mkMerge [
      {
        # Copies the directories in `backups.files` (if any) into `<dir>/files/`, keeping
        # their full path: /var/lib/foo/secrets ends up in <dir>/files/var/lib/foo/secrets.
        systemd.services.backup-files = lib.mkIf (cfg.files != [ ]) {
          description = "Copy ${lib.concatStringsSep ", " cfg.files} into ${cfg.dir}/files";
          # `startAt` makes NixOS create a timer (backup-files.timer) running it then.
          startAt = "*-*-* 01:00:00";
          # Waits for the HDD's mount, and fails if it can't be mounted, so the copy
          # never lands in the empty directory underneath the mount point (on the SSD).
          unitConfig.RequiresMountsFor = [ cfg.dir ];
          serviceConfig = {
            Type = "oneshot";
            # The copies are readable by root only (they may hold secrets).
            UMask = "0077";
          };
          path = [ pkgs.rsync ];
          # `rsync -a --delete`: an exact mirror (owners, permissions, times; files
          # deleted at the source are deleted in the copy too).
          script = lib.concatMapStrings (dir: ''
            if [ -e ${dir} ]; then
              mkdir -p ${cfg.dir}/files${dir}
              rsync -a --delete ${dir}/ ${cfg.dir}/files${dir}/
            fi
          '') cfg.files;
        };
        # Persistent: if the machine was off at 01:00, run it as soon as it's on again.
        systemd.timers.backup-files = lib.mkIf (cfg.files != [ ]) {
          timerConfig.Persistent = true;
        };

        # `sudo backups-restore [DIR]`, installed system-wide. Its steps, in order:
        #   1. refuse to run without root or without a backup directory;
        #   2. ask for confirmation (it replaces the services' current data);
        #   3. stop every unit in `backups.restore.stopUnits`, so nothing writes to the
        #      data while it's replaced;
        #   4. copy `backups.files` back, then run each service's `backups.restore.script`
        #      (which finds the backup in `$src`);
        #   5. start the units again.
        # writeShellApplication runs it with `set -euo pipefail`, so it stops at the
        # first failing command.
        environment.systemPackages = [
          (pkgs.writeShellApplication {
            name = "backups-restore";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.rsync
              config.systemd.package
            ];
            text = ''
              src=''${1:-${cfg.dir}}
              if [ "$(id -u)" != 0 ] || [ ! -d "$src" ]; then
                echo "Usage: sudo backups-restore [DIR]" >&2
                echo "Replaces this machine's service data with the backup in DIR" >&2
                echo "(default ${cfg.dir}). From the off-site copy: first" >&2
                echo "  sudo restic-offsite restore latest --target /root/restore" >&2
                echo "then  sudo backups-restore /root/restore${cfg.dir}" >&2
                exit 1
              fi
              src=$(realpath "$src")
              read -rp "Replace this machine's data with the backup in $src? [y/N] " answer
              [ "$answer" = y ] || exit 1

              # (`systemctl stop` with no units at all is an error, hence the check.)
              units=(${lib.escapeShellArgs cfg.restore.stopUnits})
              [ ''${#units[@]} = 0 ] || systemctl stop "''${units[@]}"
              # One by one: copying /var etc. from the backup would change their permissions.
              ${lib.concatMapStrings (dir: ''
                if [ -d "$src/files${dir}" ]; then
                  mkdir -p ${dir}
                  rsync -a --delete "$src/files${dir}/" ${dir}/
                fi
              '') cfg.files}
              ${cfg.restore.script}
              [ ''${#units[@]} = 0 ] || systemctl start "''${units[@]}"
              echo "Restored. Check: systemctl --failed"
            '';
          })
        ];
      }

      # The off-site copy, only if the host has set `backups.offsite.sftp`. NixOS's
      # restic module does the work: it creates the `restic-backups-offsite` service and
      # timer, and a `restic-offsite` command (restic with this repository and password
      # already set, e.g. `sudo restic-offsite snapshots`).
      (lib.mkIf (cfg.offsite.sftp != null) {
        services.restic.backups.offsite =
          let
            # sftp.command needs the login without the path.
            # "tv-box-backup@devsrv.arturaz.net:/restic" -> login
            # "tv-box-backup@devsrv.arturaz.net" -> host "devsrv.arturaz.net".
            login = builtins.head (lib.splitString ":" cfg.offsite.sftp);
            host = lib.last (lib.splitString "@" login);
          in
          {
            # restic encrypts everything (file contents and names) with a key derived
            # from the password, before it leaves this machine: the server only stores
            # ciphertext.
            repository = "sftp:${cfg.offsite.sftp}";
            inherit (cfg.offsite) passwordFile;
            # Creates the repository on the first run if it isn't there yet.
            initialize = true;
            paths = [ cfg.dir ];
            # After the local backups (from 01:00) have run.
            timerConfig = {
              OnCalendar = "*-*-* 03:00:00";
              Persistent = true;
            };
            # After each backup, forget older snapshots except: one per day for the last
            # 7 days, one per week for 5 weeks, one per month for 12 months. Data only
            # those snapshots used is then deleted.
            pruneOpts = [
              "--keep-daily 7"
              "--keep-weekly 5"
              "--keep-monthly 12"
            ];
            # How restic reaches the server: ssh as `login`, authenticating with this
            # machine's own SSH host key (root-only, already there on every NixOS
            # machine, so no extra key to manage), and only accepting the pinned server
            # key. `-s sftp` asks the server for its SFTP subsystem.
            extraOptions = [
              "sftp.command='ssh -i /etc/ssh/ssh_host_ed25519_key -o UserKnownHostsFile=${knownHosts host} -o StrictHostKeyChecking=yes ${login} -s sftp'"
            ];
          };

        # Like the local backups: never back up an empty mount point (it would look like
        # everything had been deleted, and pruning would eventually forget the old data).
        systemd.services.restic-backups-offsite.unitConfig.RequiresMountsFor = [ cfg.dir ];
      })
    ]
  );
}
