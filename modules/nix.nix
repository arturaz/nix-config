# Nix and nixpkgs settings, including garbage collection of old generations.
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Deletes generations older than 30 days and whatever only they used. Missed runs
  # (machine off) happen at the next boot.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nixpkgs.config.allowUnfree = true;
}
