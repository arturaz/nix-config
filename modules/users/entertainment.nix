# A shared, non-admin account for media/TV use, meant to be logged in automatically.
{
  users.users."entertainment" = {
    isNormalUser = true;
    description = "Entertainment";
    extraGroups = [ "networkmanager" ];
    # Empty password: the screen locker and login screen unlock with just Enter.
    # sshd still refuses empty passwords (PermitEmptyPasswords defaults to no).
    hashedPassword = "";
  };
}
