# Valkey (Redis's open-source fork) instead of Redis for every `services.redis.servers`
# instance. Each service runs its own instance (`services.redis.servers.<name>`) rather
# than sharing one. Bloom filters (RedisBloom's BF.* commands): load
# ../../packages/valkey-bloom with `settings.loadmodule`.
#
# Background: Valkey was forked from Redis in 2024, when Redis changed its license; it
# speaks the same protocol and reads the same config, so programs written for Redis use
# it unchanged. NixOS has no separate Valkey module: its Redis module
# (`services.redis`) runs whichever package it's given, and Valkey is a drop-in one.
# Why Valkey here: nixpkgs builds Redis without its extra modules, and RedisBloom (which
# Anytype's sync server needs) can't easily be built on its own, while Valkey's bloom
# module can (packages/valkey-bloom).
#
# This file only picks the program. Nothing runs until a service module adds an
# instance. Each instance `<name>` is its own valkey-server process: the systemd service
# `redis-<name>`, running as user and group `redis-<name>`, with its data in
# /var/lib/redis-<name> (readable by that user only). Instances share nothing.
#
# Who may connect depends on how it listens:
#
# - Unix socket only (the default for a named instance: `port = 0`, no TCP at all). The
#   socket, /run/redis-<name>/redis.sock, is only usable by user and group
#   `redis-<name>`, so adding the service's user to that group is the whole access
#   control; no password or firewall rule needed. Prefer this:
#
#     services.redis.servers.foo.enable = true;
#     users.users.foo.extraGroups = [ "redis-foo" ];
#     # foo connects to unix:///run/redis-foo/redis.sock
#
# - TCP (`port = <n>`), for programs that can't use a socket. Any local user can
#   connect to a TCP port, so it needs protecting: a password (`requirePassFile`) or a
#   firewall rule allowing only the service's user. Each such instance needs its own
#   port. services/anytype.nix is one (port 6379, its firewall rule), since the Anytype
#   sync server only accepts redis://host:port addresses.
{ pkgs, ... }:
{
  # One setting for all instances (NixOS has no per-instance package option).
  services.redis.package = pkgs.valkey;
}
