# One auto-started Spotify web player per person for the entertainment account, with
# ~/bin/spotify-<name> launchers and app menu entries.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  home = config.users.users."entertainment".home;

  # One Spotify web player per person, each logged into their own account. `hue` tints
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

  # Runs open.spotify.com in its own Firefox profile, so each person stays logged in.
  # The native client can't do this: copies in one session make each other quit, and on
  # Wayland all their windows look the same. --name sets the Wayland app id, which
  # Plasma matches to the menu entry for the window's name and icon. Firefox keeps
  # DRM (needed by Spotify) on via its policies in desktop/plasma.nix.
  spotifyLauncher =
    name:
    pkgs.writeShellScriptBin "spotify-${name}" ''
      profile="$HOME/.local/share/spotify-profiles/${name}"
      # Already running: do nothing, a second window would be a second player.
      if ${pkgs.procps}/bin/pgrep -u "$(id -u)" -f -- "--profile $profile" >/dev/null; then
        exit 0
      fi
      mkdir -p "$profile"
      # Skip first-run pages and the default browser prompt; don't reopen tabs after a
      # crash (the URL below already opens the player).
      cat > "$profile/user.js" <<'PREFS'
      user_pref("browser.aboutwelcome.enabled", false);
      user_pref("browser.shell.checkDefaultBrowser", false);
      user_pref("browser.startup.homepage_override.mstone", "ignore");
      user_pref("browser.sessionstore.resume_from_crash", false);
      user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
      PREFS
      exec ${lib.getExe config.programs.firefox.package} --profile "$profile" \
        --name spotify-${name} --new-window https://open.spotify.com "$@"
    '';

  # The launcher plus an app menu entry with its own name and tinted icon (the Spotify
  # logo in spotify.png, taken from the native client).
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
        startupWMClass = "spotify-${name}";
        exec = lib.getExe launcher;
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
        magick ${./spotify.png} \
          -modulate 100,100,${toString hue} \
          $out/share/icons/hicolor/256x256/apps/spotify-${name}.png
      '';

  spotifyPackages = lib.mapAttrs spotifyProfile spotifyProfiles;
in
{
  users.users."entertainment".packages = lib.attrValues spotifyPackages;

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
      serviceConfig.ExecStart = lib.getExe package;
      serviceConfig.Restart = "on-failure";
    }
  ) spotifyPackages;
}
