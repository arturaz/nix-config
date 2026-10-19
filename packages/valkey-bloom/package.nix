# valkey-bloom, Valkey's bloom filter module (RedisBloom's BF.* commands); not in
# nixpkgs. Upstream has no Cargo.lock, so ./Cargo.lock is generated (`cargo
# generate-lockfile` in the source) and must be regenerated when updating.
#
# Background: a bloom filter answers "have I seen this key before?" using little memory
# (it can say "maybe" for a key it hasn't seen, but never "no" for one it has).
# Anytype's file node keeps its index of stored files in Redis and uses two bloom
# filter commands, BF.ADD and BF.EXISTS, to remember which index entries it has moved
# from Redis into its own on-disk storage. Plain Redis and Valkey don't have those
# commands: they come from a module, a shared library (.so) the server loads at start.
# Redis's is RedisBloom (not in nixpkgs, hard to build); this is Valkey's own,
# compatible version.
#
# Its output is a single file, $out/lib/libvalkey_bloom.so, which
# modules/services/anytype.nix loads into its Valkey (`settings.loadmodule`).
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

# nixpkgs' builder for Rust programs; it runs `cargo build --release` and installs the
# result.
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "valkey-bloom";
  version = "1.0.1";

  # The source at the release's git tag, pinned by the hash of its contents.
  src = fetchFromGitHub {
    owner = "valkey-io";
    repo = "valkey-bloom";
    tag = finalAttrs.version;
    hash = "sha256-v7IjqPA0VdYrRa8DHgzROh6jjprVf1viiIJz11P+fi0=";
  };

  # Builds run without network access, so nixpkgs downloads the Rust dependencies first,
  # and for that it needs the exact versions, which a Cargo.lock lists. Upstream doesn't
  # ship one, so ours (generated from upstream's Cargo.toml) is copied into the source
  # and used for the download.
  postPatch = "cp ${./Cargo.lock} Cargo.lock";
  cargoLock.lockFile = ./Cargo.lock;

  # valkey-module (the Rust library for writing Valkey modules) generates its bindings
  # to the server's C module API with bindgen at build time, which needs libclang; the
  # hook provides it.
  nativeBuildInputs = [ rustPlatform.bindgenHook ];

  # The unit tests need the system allocator feature; the rest need a running server.
  # (It was tested by hand instead: loaded into nixpkgs' Valkey, BF.ADD and BF.EXISTS
  # work, also inside a MULTI transaction as the file node uses them; and the VM test in
  # tests/anytype.nix runs a client against it.)
  doCheck = false;

  meta = {
    description = "Bloom filter module for Valkey";
    homepage = "https://github.com/valkey-io/valkey-bloom";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
})
