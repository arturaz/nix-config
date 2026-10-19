# VM test of modules/services/anytype.nix: a client (nixpkgs' anytype-cli) syncs a page and
# files through it; the firewall rules; backup, losing all data, restore, syncing again.
# Run it after changing the module or updating its packages:
#   nix build -L --no-link path:.#checks.x86_64-linux.anytype
#
# How NixOS VM tests work: Nix builds a full NixOS system for each machine in `nodes`,
# boots each in a QEMU virtual machine on a private network (where they reach each
# other by name: `server`, `client`), and runs `testScript`, a Python script driving
# them: `machine.succeed(cmd)` runs a shell command as root and fails the test if it
# fails, `machine.fail(cmd)` fails the test if it succeeds, `wait_until_succeeds`
# retries until it does. Nothing here touches tv-box or the internet; it takes about a
# minute.
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "anytype-sync";
  # The machines use the `pkgs` given here (which allows unfree MongoDB) as is.
  node.pkgsReadOnly = true;

  # Plays tv-box: the module under test, as tv-box imports it.
  nodes.server = {
    imports = [ ../modules/services/anytype.nix ];
    # The client reaches it as `server`.
    anytype.externalAddrs = [ "server" ];
    backups.dir = "/backups";
    virtualisation.memorySize = 3072;
    virtualisation.diskSize = 4096;
    # Tools the checks below use to look inside.
    environment.systemPackages = [
      pkgs.mongosh
      pkgs.valkey
      pkgs.netcat
      pkgs.yq-go
    ];
  };

  # Plays an Anytype app: anytype-cli is Anytype's command-line app (the same engine as
  # the desktop app, without the window), driven through its local REST API.
  nodes.client = {
    virtualisation.memorySize = 2048;
    # For the LAN check below: something on the "LAN" listening.
    networking.firewall.allowedTCPPorts = [ 9999 ];
    environment.systemPackages = [
      pkgs.anytype-cli
      pkgs.jq
      pkgs.curl
    ];
  };

  testScript = ''
    import json

    start_all()
    # The bundle logs "bundle_ready" once all its nodes are listening.
    server.wait_for_unit("any-sync.service")
    server.wait_until_succeeds("journalctl -u any-sync | grep -q bundle_ready", timeout=120)

    # The databases have no passwords, so the firewall decides who may connect: the
    # bundle's user may, any other user (here `nobody`) is refused. And Valkey has the
    # bloom filter module ("bf") loaded.
    with subtest("only the bundle reaches MongoDB and Valkey"):
        server.succeed("runuser -u any-sync -- valkey-cli -p 6379 PING | grep PONG")
        server.fail("runuser -u nobody -- valkey-cli -p 6379 PING")
        server.fail("runuser -u nobody -- nc -z -w 3 127.0.0.1 27017")
        server.succeed("runuser -u any-sync -- nc -z -w 3 127.0.0.1 27017")
        server.succeed("valkey-cli -p 6379 MODULE LIST | grep -x bf")

    # The test network is a LAN range (192.168.1.x). root on the server can connect to
    # the client, but the bundle's user can't open a connection to it.
    with subtest("the bundle can't open connections into the LAN"):
        client.succeed("systemd-run --unit listener nc -lk 9999")
        client.wait_for_open_port(9999)
        server.succeed("nc -z -w 3 client 9999")
        server.fail("runuser -u any-sync -- nc -z -w 3 client 9999")

    # What a person does in the app, step by step: load the server's client-config.yml
    # (as in the README), create an account on that network, create a space with a page
    # in it, attach a file. Then check the server got them.
    with subtest("a client syncs through it"):
        # Copy client-config.yml from the server to the client.
        cfg = server.succeed("cat /var/lib/any-sync/client-config.yml")
        client.succeed(f"cat > /root/network.yml <<'EOF'\n{cfg}\nEOF")
        # Start the app in the background; it listens for its API on 31010-31012.
        client.succeed("systemd-run --unit anytype -p Environment=HOME=/root anytype-cli serve --no-update-check")
        client.wait_for_open_port(31010)
        # A new account on the self-hosted network, and an API key to drive it with.
        client.succeed("HOME=/root anytype-cli auth create tester --no-update-check --network-config /root/network.yml")
        key = client.succeed("HOME=/root anytype-cli auth apikey create t --no-update-check 2>&1 | sed -n 's/^Key: //p'").strip()
        h = f"-H 'Authorization: Bearer {key}' -H 'Anytype-Version: 2025-11-08'"
        api = "http://127.0.0.1:31012/v1"
        # A space, a page in it, and a 2 MB file (random, so it can't be compressed).
        space = json.loads(client.succeed(f"curl -sf {h} -H 'Content-Type: application/json' -X POST {api}/spaces -d '{{\"name\":\"Sync test\"}}'"))["space"]
        client.succeed(f"curl -sf {h} -H 'Content-Type: application/json' -X POST {api}/spaces/{space['id']}/objects -d '{{\"type_key\":\"page\",\"name\":\"Hello\",\"body\":\"hi\"}}'")
        client.succeed("head -c 2000000 /dev/urandom > /root/blob.bin")
        client.succeed(f"curl -sf {h} -X POST {api}/spaces/{space['id']}/files -F file=@/root/blob.bin")
        # The coordinator (in MongoDB) knows both spaces: the account's own one, created
        # with it, and "Sync test".
        server.wait_until_succeeds(
            "mongosh --quiet mongodb://127.0.0.1:27017/coordinator --eval 'db.spaces.countDocuments()' | grep -E '^[2-9]'",
            timeout=120,
        )
        # The file's 2 MB arrived in the file node's storage.
        server.wait_until_succeeds("[ $(du -sm /var/lib/any-sync/storage | cut -f1) -ge 2 ]", timeout=120)
        # And the file node indexed it in Valkey.
        server.succeed("valkey-cli -p 6379 DBSIZE | grep -v '^0$'")

    # The nightly backup, then a disaster: all three services' data deleted, as on a
    # newly installed machine. After `backups-restore`, the server must be the same
    # network (same id, so apps still recognise it) with the same data.
    with subtest("backup and restore"):
        network_id = server.succeed("grep networkId /var/lib/any-sync/client-config.yml")
        spaces = server.succeed("mongosh --quiet mongodb://127.0.0.1:27017/coordinator --eval 'db.spaces.countDocuments()'")
        keys = server.succeed("valkey-cli -p 6379 DBSIZE")
        # Run the backup now instead of at 01:00; it stops and starts the services, so
        # "bundle_ready" appears a second time.
        server.succeed("systemctl start any-sync-backup.service")
        server.succeed("ls /backups/any-sync/bundle/bundle-config.yml /backups/any-sync/mongodb/storage.bson /backups/any-sync/valkey/appendonlydir")
        server.wait_for_unit("any-sync.service")
        server.wait_until_succeeds("journalctl -u any-sync | grep -c bundle_ready | grep -x 2", timeout=120)

        # Lose everything, as on a new machine.
        server.succeed("systemctl stop any-sync mongodb redis-any-sync")
        server.succeed("rm -rf /var/lib/any-sync /var/db/mongodb /var/lib/redis-any-sync")
        # It asks for confirmation; `echo y` answers it.
        server.succeed("echo y | backups-restore")
        server.wait_for_unit("any-sync.service")
        server.wait_until_succeeds("journalctl -u any-sync | grep -c bundle_ready | grep -x 3", timeout=120)
        server.succeed(f"grep -x '{network_id.strip()}' /var/lib/any-sync/client-config.yml")
        assert spaces == server.succeed("mongosh --quiet mongodb://127.0.0.1:27017/coordinator --eval 'db.spaces.countDocuments()'")
        assert keys == server.succeed("valkey-cli -p 6379 DBSIZE")

        # The client still syncs: another file reaches the server.
        size = int(server.succeed("du -sm /var/lib/any-sync/storage | cut -f1"))
        client.succeed("head -c 3000000 /dev/urandom > /root/blob2.bin")
        client.succeed(f"curl -sf {h} -X POST {api}/spaces/{space['id']}/files -F file=@/root/blob2.bin")
        server.wait_until_succeeds(f"[ $(du -sm /var/lib/any-sync/storage | cut -f1) -ge {size + 3} ]", timeout=180)

    # The bundle reads the addresses from its environment only on the first start;
    # any-sync.service's preStart puts `anytype.externalAddrs` back into its config on
    # every start. Simulate a stale config ("old"), restart, and check both its config
    # and the client-config.yml it writes have the configured address again.
    with subtest("the addresses in its config follow anytype.externalAddrs"):
        server.succeed("yq -i '.externalAddr = [\"old\"]' /var/lib/any-sync/bundle-config.yml")
        server.succeed("systemctl restart any-sync")
        server.succeed("yq -o json -I0 .externalAddr /var/lib/any-sync/bundle-config.yml | grep -Fx '[\"server\"]'")
        server.wait_until_succeeds("grep -q 'server:33010' /var/lib/any-sync/client-config.yml")
  '';
}
