# Network connectivity and remote access.
{
  networking.networkmanager.enable = true;

  # Listens on port 22, which it opens in the firewall itself (openFirewall).
  services.openssh.enable = true;
  # No ssh logins as root at all; log in as a user and use sudo.
  services.openssh.settings.PermitRootLogin = "no";

  # Keys in this file can log in as any user except root. Per-user keys still go in
  # users.users.<name>.openssh.authorizedKeys.
  services.openssh.authorizedKeysFiles = [ "/etc/ssh/authorized_keys_all_users" ];
  environment.etc."ssh/authorized_keys_all_users" = {
    # A real file rather than a symlink into the store, as sshd's StrictModes expects.
    mode = "0444";
    text = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIm/5r39Ldi7+51YW4tBME+mOztxnlN1d+/jauhxP20W Artūras Šlajus
    '';
  };
}
