# arturas: the admin account (wheel), with a profile photo.
{
  imports = [ ./avatars.nix ];

  users.avatars."arturas" = ./arturas.jpg;

  # Set the password with `passwd`.
  users.users."arturas" = {
    isNormalUser = true;
    description = "Artūras Šlajus";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };
}
