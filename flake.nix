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

      # For the outputs below: the hosts' nixpkgs (same flake input), with unfree
      # packages allowed like on the hosts (modules/nix.nix), since the Anytype test
      # needs MongoDB.
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
      inherit (nixpkgs) lib;

      # The packages nixpkgs lacks (packages/), as the modules using them build them.
      packages = {
        any-sync-bundle = pkgs.callPackage ./packages/any-sync-bundle/package.nix { };
        valkey-bloom = pkgs.callPackage ./packages/valkey-bloom/package.nix { };
      };
    in
    {
      nixosConfigurations = nixpkgs.lib.genAttrs hostNames mkHost;

      # `nix build path:.#<name>`. Also how nix-update finds them (below).
      packages.x86_64-linux = packages;

      # `nix run path:.#update-packages`, run by upgrade.sh: updates every package above
      # that declares how (`passthru.updateScript`, nixpkgs' convention: a nix-update
      # command with that package's options), one after the other, stopping at the first
      # failure. Each package's file says which versions it accepts.
      apps.x86_64-linux.update-packages = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "update-packages";
            text = lib.concatStrings (
              lib.mapAttrsToList (name: package: ''
                echo "Updating ${name}..." >&2
                ${lib.escapeShellArgs package.updateScript} --flake ${name}
              '') (lib.filterAttrs (_: package: package ? updateScript) packages)
            );
          }
        );
      };

      # VM tests of modules (tests/); `nix build -L --no-link path:.#checks.x86_64-linux.<name>`.
      # They boot throwaway VMs on this machine; nothing is deployed. upgrade.sh runs them
      # all before deploying.
      checks.x86_64-linux = {
        anytype = import ./tests/anytype.nix { inherit pkgs; };
      };
    };
}
