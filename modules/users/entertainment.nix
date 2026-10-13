# A shared, non-admin account for media/TV use, meant to be logged in automatically.
# Netflix and YouTube run in Firefox; VLC is installed system-wide.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  home = config.users.users."entertainment".home;

  # One Spotify instance per person, each logged into their own account.
  spotifyProfiles = [
    "arturas"
    "agne"
    "ugne"
  ];

  # Spotify has no multi-account support and allows one instance per config/cache
  # directory, so each instance gets its own HOME (Spotify keeps its data in
  # ~/.config/spotify and ~/.cache/spotify). Running it again while that instance is
  # up just brings its window forward.
  spotifyLauncher =
    name:
    pkgs.writeShellScriptBin "spotify-${name}" ''
      export HOME="$HOME/.local/share/spotify-profiles/${name}"
      export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
      export XDG_DATA_HOME="$HOME/.local/share"
      mkdir -p "$HOME"
      exec ${lib.getExe pkgs.spotify} "$@"
    '';
in
{
  users.users."entertainment" = {
    isNormalUser = true;
    description = "Entertainment";
    extraGroups = [ "networkmanager" ];
    # Empty password: the screen locker and login screen unlock with just Enter.
    # sshd still refuses empty passwords (PermitEmptyPasswords defaults to no).
    hashedPassword = "";
    packages = with pkgs; [
      kdePackages.ktorrent
    ];
  };

  # The launchers, as ~/bin/spotify-<name> (symlinks, recreated on every boot/deploy).
  systemd.tmpfiles.rules = [
    "d ${home}/bin 0755 entertainment users -"
  ]
  ++ map (
    name: "L+ ${home}/bin/spotify-${name} - - - - ${lib.getExe (spotifyLauncher name)}"
  ) spotifyProfiles;
  # Puts ~/bin on PATH, so they can be run by name.
  environment.homeBinInPath = true;

  # Start every instance with the graphical session; log in to each window once.
  systemd.user.services = lib.listToAttrs (
    map (
      name:
      lib.nameValuePair "spotify-${name}" {
        description = "Spotify (${name})";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        unitConfig.ConditionUser = "entertainment";
        # So links (and the browser login) can open: xdg-open, Firefox, etc.
        path = [
          "/etc/profiles/per-user/entertainment"
          "/run/current-system/sw"
        ];
        serviceConfig.ExecStart = lib.getExe (spotifyLauncher name);
        serviceConfig.Restart = "on-failure";
      }
    ) spotifyProfiles
  );

  # KTorrent's default listening ports, so peers can connect in: 6881 for peers,
  # 7881 for DHT. Update these if they're changed in KTorrent's settings.
  networking.firewall.allowedTCPPorts = [ 6881 ];
  networking.firewall.allowedUDPPorts = [ 7881 ];
}
