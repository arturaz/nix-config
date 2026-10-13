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
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIm/5r39Ldi7+51YW4tBME+mOztxnlN1d+/jauhxP20W Arturas Šlajus"
    ];
    packages = with pkgs; [
    ];
  };
}
