{
  description = "NixOS configurations";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { nixpkgs, ... }:
    let
      # Every directory in hosts/ is a machine, named after the directory.
      hostNames = builtins.attrNames
        (nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts));

      mkHost = name: nixpkgs.lib.nixosSystem {
        modules = [
          (./hosts + "/${name}/configuration.nix")
          # Machine-generated: deploy.sh copies it from the machine's /etc/nixos.
          (./hosts + "/${name}/hardware-configuration.nix")
        ];
      };
    in {
      nixosConfigurations = nixpkgs.lib.genAttrs hostNames mkHost;
    };
}
