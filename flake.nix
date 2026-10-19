{
  description = "NixOS configurations";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  # Secrets (see "Secrets" in README.md).
  inputs.sops-nix.url = "github:Mic92/sops-nix";
  inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { nixpkgs, sops-nix, ... }:
    let
      # Every directory in hosts/ is a machine, named after the directory.
      hostNames = builtins.attrNames (
        nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts)
      );

      mkHost =
        name:
        nixpkgs.lib.nixosSystem {
          modules = [
            (./hosts + "/${name}/configuration.nix")
            # Machine-generated: deploy.sh copies it from the machine's /etc/nixos.
            (./hosts + "/${name}/hardware-configuration.nix")
            # Does nothing until a host defines sops.secrets.
            sops-nix.nixosModules.sops
          ];
        };
    in
    {
      nixosConfigurations = nixpkgs.lib.genAttrs hostNames mkHost;

      # VM tests of modules (tests/); `nix build -L --no-link path:.#checks.x86_64-linux.<name>`.
      # They boot throwaway VMs on this machine; nothing is deployed. Their nixpkgs is the
      # hosts' one (same flake input), with unfree packages allowed like on the hosts
      # (modules/nix.nix), since the Anytype test needs MongoDB.
      checks.x86_64-linux =
        let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
        in
        {
          anytype = import ./tests/anytype.nix { inherit pkgs; };
        };
    };
}
