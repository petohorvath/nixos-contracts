{ helpers, lib, ... }:
let
  inherit (helpers.nixos) evaluate failures;
  adapter = helpers.nixos.nixosModules.preservation;
  backend = helpers.nixos.backends.preservation;

  influxdb = {
    contracts.kinds.mounts.classes = [
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
          type = "file";
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
  pick = entry: { inherit (entry) group mode user; };
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

  testMountsOfEveryServiceArePreserved = {
    expr =
      map (entry: entry.directory)
        (evaluate [
          backend
          adapter
          influxdb
          roots
          {
            contracts.services.grafana = {
              enable = true;
              identity.static.user = "influxdb";
              mounts.data = {
                path = "/var/lib/grafana";
                class = "state";
              };
            };
          }
        ]).preservation.preserveAt."/persist/state".directories;
    # In the order the claim-name-keyed claim sets gave.
    expected = [
      "/var/lib/influxdb2"
      "/var/lib/grafana"
    ];
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

  testUnusedClassNeedsNoRoot = {
    expr = failures [
      backend
      adapter
      influxdb
      roots
      { contracts.kinds.mounts.classes = [ "archive" ]; }
    ];
    expected = [ ];
  };

  testEveryUsedClassNeedsARoot = {
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

  testAdapterImportedTwiceAddsEachMountOnce = {
    expr =
      map (entry: entry.directory)
        (evaluate [
          backend
          adapter
          adapter
          influxdb
          roots
        ]).preservation.preserveAt."/persist/cache".directories;
    expected = [ "/var/cache/influxdb" ];
  };
}
