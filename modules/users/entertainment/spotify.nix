# One auto-started native Spotify per person for the entertainment account, with
# ~/bin/spotify-<name> launchers and app menu entries.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (config.users.users."entertainment") home group;

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

  # Opens links (e.g. the login page) from inside an instance's private environment
  # with the real HOME and session bus, so they land in the normal Firefox.
  xdgOpen = pkgs.writeShellScriptBin "xdg-open" ''
    export HOME="$SPOTIFY_REAL_HOME" DBUS_SESSION_BUS_ADDRESS="$SPOTIFY_REAL_BUS"
    unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME
    exec ${pkgs.xdg-utils}/bin/xdg-open "$@"
  '';

  # Spotify opens links via GTK, which looks up the browser in the instance's HOME;
  # this makes it use the xdg-open above for web links (instead of whatever browser
  # it finds first, started with the instance's HOME as a fresh profile).
  openUrlDesktopItem = pkgs.makeDesktopItem {
    name = "spotify-open-url";
    desktopName = "Open in the default browser";
    exec = "${lib.getExe xdgOpen} %u";
    noDisplay = true;
    mimeTypes = [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
  };
  instanceMimeapps = pkgs.writeText "mimeapps.list" ''
    [Default Applications]
    text/html=spotify-open-url.desktop
    x-scheme-handler/http=spotify-open-url.desktop
    x-scheme-handler/https=spotify-open-url.desktop
  '';

  # The private session bus for each instance. Unlike the stock session config it can't
  # start services on demand: those would run with the instance's HOME, e.g. a KDE
  # wallet daemon asking to create a new wallet for each instance.
  privateBusConfig = pkgs.writeText "spotify-session-bus.conf" ''
    <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
      "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
    <busconfig>
      <type>session</type>
      <listen>unix:tmpdir=/tmp</listen>
      <auth>EXTERNAL</auth>
      <policy context="default">
        <allow send_destination="*" eavesdrop="true"/>
        <allow eavesdrop="true"/>
        <allow own="*"/>
      </policy>
    </busconfig>
  '';

  # Spotify has no multi-account support and allows one instance per config/cache
  # directory, so each instance gets its own HOME (Spotify keeps its data in
  # ~/.config/spotify and ~/.cache/spotify). Copies sharing a D-Bus session make each
  # other quit, so each also gets a private session bus; the cost is that Plasma's
  # media controls and media keys don't see them.
  spotifyLauncher =
    name:
    pkgs.writeShellScriptBin "spotify-${name}" ''
      export SPOTIFY_REAL_HOME="$HOME" SPOTIFY_REAL_BUS="$DBUS_SESSION_BUS_ADDRESS"
      export HOME="$HOME/.local/share/spotify-homes/${name}"
      export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
      export XDG_DATA_HOME="$HOME/.local/share"
      export PATH="${xdgOpen}/bin:$PATH"
      mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME/applications"
      ln -sfn ${instanceMimeapps} "$XDG_CONFIG_HOME/mimeapps.list"
      ln -sfn ${openUrlDesktopItem}/share/applications/spotify-open-url.desktop \
        "$XDG_DATA_HOME/applications/"
      # Already running: do nothing, a second copy would be a second player.
      # --password-store=basic: Chromium's own storage, no keyring (wallet) lookups.
      exec ${pkgs.util-linux}/bin/flock -n -E 0 "$HOME/.lock" \
        ${pkgs.dbus}/bin/dbus-run-session --config-file=${privateBusConfig} -- \
        ${lib.getExe pkgs.spotify} --password-store=basic "$@"
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
  users.users."entertainment".packages = lib.attrValues spotifyPackages;

  # The launchers, as ~/bin/spotify-<name> (symlinks, recreated on every boot/deploy).
  systemd.tmpfiles.rules = [
    "d ${home}/bin 0755 entertainment ${group} -"
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
}
