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

  # One Spotify instance per person, each logged into their own account. `hue` tints
  # the app menu icon (ImageMagick -modulate: 100 keeps Spotify green, 200 is +180°).
  spotifyProfiles = {
    arturas = {
      displayName = "Artūras";
      hue = 144; # blue
    };
    agne = {
      displayName = "Agnė";
      hue = 194; # magenta
    };
    ugne = {
      displayName = "Ugnė";
      hue = 39; # orange
    };
  };

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

  # The launcher plus an app menu entry with its own name and tinted icon.
  spotifyProfile =
    name:
    { displayName, hue }:
    let
      launcher = spotifyLauncher name;
      desktopItem = pkgs.makeDesktopItem {
        name = "spotify-${name}";
        desktopName = "Spotify (${displayName})";
        genericName = "Music Player";
        icon = "spotify-${name}";
        exec = "${lib.getExe launcher} %U";
        categories = [
          "Audio"
          "Music"
          "Player"
          "AudioVideo"
        ];
      };
    in
    pkgs.runCommand "spotify-${name}"
      {
        nativeBuildInputs = [ pkgs.imagemagick ];
        meta.mainProgram = "spotify-${name}";
      }
      ''
        mkdir -p $out/bin $out/share/applications $out/share/icons/hicolor/256x256/apps
        ln -s ${lib.getExe launcher} $out/bin/
        ln -s ${desktopItem}/share/applications/* $out/share/applications/
        magick ${pkgs.spotify}/share/spotify/icons/spotify-linux-256.png \
          -modulate 100,100,${toString hue} \
          $out/share/icons/hicolor/256x256/apps/spotify-${name}.png
      '';

  spotifyPackages = lib.mapAttrs spotifyProfile spotifyProfiles;
in
{
  users.users."entertainment" = {
    isNormalUser = true;
    description = "Entertainment";
    extraGroups = [ "networkmanager" ];
    # Empty password: the screen locker and login screen unlock with just Enter.
    # sshd still refuses empty passwords (PermitEmptyPasswords defaults to no).
    hashedPassword = "";
    packages =
      with pkgs;
      [
        kdePackages.ktorrent
      ]
      ++ lib.attrValues spotifyPackages;
  };

  # The launchers, as ~/bin/spotify-<name> (symlinks, recreated on every boot/deploy).
  systemd.tmpfiles.rules = [
    "d ${home}/bin 0755 entertainment users -"
  ]
  ++ lib.mapAttrsToList (
    name: package: "L+ ${home}/bin/spotify-${name} - - - - ${lib.getExe package}"
  ) spotifyPackages;
  # Puts ~/bin on PATH, so they can be run by name.
  environment.homeBinInPath = true;

  # Start every instance with the graphical session; log in to each window once.
  systemd.user.services = lib.mapAttrs' (
    name: package:
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
      serviceConfig.ExecStart = lib.getExe package;
      serviceConfig.Restart = "on-failure";
    }
  ) spotifyPackages;

  # KTorrent's default listening ports, so peers can connect in: 6881 for peers,
  # 7881 for DHT. Update these if they're changed in KTorrent's settings.
  networking.firewall.allowedTCPPorts = [ 6881 ];
  networking.firewall.allowedUDPPorts = [ 7881 ];
}
