# A shared, non-admin account for media/TV use, meant to be logged in automatically.
# Netflix and YouTube run in Firefox; VLC is installed system-wide.
{
  imports = [
    ./ktorrent.nix
    ./moonlight.nix
    ./spotify.nix
  ];

  users.users."entertainment" = {
    isNormalUser = true;
    description = "Entertainment";
    extraGroups = [ "networkmanager" ];
    # Empty password: the screen locker and login screen unlock with just Enter.
    # sshd still refuses empty passwords (PermitEmptyPasswords defaults to no).
    hashedPassword = "";
  };
}
