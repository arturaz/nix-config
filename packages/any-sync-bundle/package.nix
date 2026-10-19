# any-sync-bundle (https://github.com/grishy/any-sync-bundle): Anytype's sync network
# (coordinator, consensus node, file node and sync node) as a single program; not in
# nixpkgs. Built as upstream's own flake.nix builds it. When updating, take the new
# `vendorHash` from upstream's flake.nix too.
#
# Background: Anytype's own servers are four separate programs from anyproto
# (any-sync-coordinator, -consensusnode, -filenode, -node), each normally run as its own
# process with its own config. This community project links all four into one binary
# with one config file, which makes a single-machine setup much simpler. It's only the
# server; the data it stores is encrypted by the apps.
#
# Used by modules/services/anytype.nix (`pkgs.callPackage` on this file), which runs
# `any-sync-bundle start-bundle`.
{
  lib,
  buildGoModule,
  go_1_27,
  fetchFromGitHub,
}:

# buildGoModule is nixpkgs' builder for Go programs. Its default Go is older than the
# 1.27.2 that the bundle's go.mod requires, so it's swapped for Go 1.27.
(buildGoModule.override { go = go_1_27; }) (finalAttrs: {
  pname = "any-sync-bundle";
  # v<bundle version>-<the Anytype release it's compatible with>.
  version = "1.7.0-2026-10-12";

  # The source at the release's git tag. `hash` pins its exact contents: if the tag were
  # ever moved to different code, the build would fail instead of using it.
  src = fetchFromGitHub {
    owner = "grishy";
    repo = "any-sync-bundle";
    tag = "v${finalAttrs.version}";
    hash = "sha256-e/kaoUwJU9XoZZaIf6BGpMXlP0z8WrqDcJWLRc8Yk/Y=";
  };

  # Builds run without network access, so nixpkgs first downloads all Go dependencies
  # (from go.mod/go.sum) in a separate step; this pins the hash of that download.
  # Upstream's flake.nix has the same value, which is where to get it when updating.
  vendorHash = "sha256-lWmHEtDUYYjcMAJmfHhw6Yq7Ie0lBtANaT6eJNJP5hw=";

  # A static binary without C code, as upstream builds its releases.
  env.CGO_ENABLED = 0;
  ldflags = [
    # Leave out debug information (a smaller binary).
    "-s"
    "-w"
    # The version it reports (`any-sync-bundle --version`, and in its startup log).
    "-X github.com/grishy/any-sync-bundle/cmd.version=v${finalAttrs.version}"
  ];

  # The build also runs upstream's tests (`go test`), except these. They need Docker.
  excludedPackages = [ "integration" ];

  meta = {
    description = "Self-hosted Anytype sync server in a single program";
    homepage = "https://github.com/grishy/any-sync-bundle";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    # What `lib.getExe` returns: $out/bin/any-sync-bundle.
    mainProgram = "any-sync-bundle";
  };
})
