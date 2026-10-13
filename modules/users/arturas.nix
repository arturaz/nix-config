{ pkgs, ... }:

{
  # Set the password with `passwd`.
  users.users."arturas" = {
    isNormalUser = true;
    description = "Artūras Šlajus";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [
    ];
  };
}
