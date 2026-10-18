{
  lib,
  nixos,
  adapter,
  backend,
}:
let
  inherit (nixos) evaluate failures;

  influxdb = {
    contracts.mounts.classes = [
      "state"
      "cache"
    ];
    contracts.services.influxdb = {
      enable = true;
      identity.static.user = "influxdb";
      mounts = {
        data = {
          path = "/var/lib/influxdb2";
          class = "state";
        };
        token = {
          path = "/etc/influxdb/token";
          class = "state";
          kind = "file";
          mode = "0600";
        };
        cache = {
          path = "/var/cache/influxdb";
          class = "cache";
        };
      };
    };
    users.users.influxdb = {
      isSystemUser = true;
      group = "influxdb";
    };
    users.groups.influxdb = { };
  };
  roots.contracts.adapters.preservation.roots = {
    state = "/persist/state";
    cache = "/persist/cache";
  };
  configuration = evaluate [
    backend
    adapter
    influxdb
    roots
  ];
  pick = entry: { inherit (entry) user group mode; };
in
{
  testMountsLandUnderTheirClassRoot = {
    expr = {
      stateDirectories = map (
        entry: entry.directory
      ) configuration.preservation.preserveAt."/persist/state".directories;
      stateFiles = map (entry: entry.file) configuration.preservation.preserveAt."/persist/state".files;
      cacheDirectories = map (
        entry: entry.directory
      ) configuration.preservation.preserveAt."/persist/cache".directories;
    };
    expected = {
      stateDirectories = [ "/var/lib/influxdb2" ];
      stateFiles = [ "/etc/influxdb/token" ];
      cacheDirectories = [ "/var/cache/influxdb" ];
    };
  };

  testMountsCarryTheirResolvedOwnership = {
    expr = {
      directory = pick (builtins.head configuration.preservation.preserveAt."/persist/state".directories);
      file = pick (builtins.head configuration.preservation.preserveAt."/persist/state".files);
    };
    expected = {
      directory = {
        user = "influxdb";
        group = "influxdb";
        mode = "0700";
      };
      file = {
        user = "influxdb";
        group = "influxdb";
        mode = "0600";
      };
    };
  };

  testDisabledContractsPersistNothing = {
    expr =
      (evaluate [
        backend
        adapter
        influxdb
        roots
        { contracts.services.influxdb.enable = lib.mkForce false; }
      ]).preservation.preserveAt;
    expected = { };
  };

  testEveryClassNeedsARoot = {
    expr = failures [
      backend
      adapter
      influxdb
      { contracts.adapters.preservation.roots.state = "/persist/state"; }
    ];
    expected = [
      "nixos-contracts: mount class `cache` has no preservation root in `contracts.adapters.preservation.roots`."
    ];
  };
}
