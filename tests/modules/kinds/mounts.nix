{ contracts }:
let
  inherit (contracts) evaluate failures;

  classes = {
    contracts.kinds.mounts.classes = [
      "state"
      "cache"
    ];
  };
  service = name: identity: mounts: {
    contracts.services.${name} = {
      enable = true;
      inherit identity mounts;
    };
  };
  ownerOf =
    identity: mount:
    let
      claim =
        (evaluate [
          classes
          (service "svc" identity {
            data = {
              class = "state";
              path = "/var/lib/svc";
            }
            // mount;
          })
        ]).contracts.services.svc.mounts.data;
    in
    {
      inherit (claim) owner group;
    };
in
{
  testMountDefaultsToAPrivateDirectory = {
    expr =
      (evaluate [
        classes
        (service "influxdb" { static.user = "influxdb"; } {
          data = {
            path = "/var/lib/influxdb2";
            class = "state";
          };
        })
      ]).contracts.claimSets.mounts.influxdb.data;
    expected = {
      service = "influxdb";
      id = "data";
      location = [
        "influxdb"
        "data"
      ];
      name = null;
      sendTo = [ ];
      ref = {
        node = null;
        kind = "mounts";
        service = "influxdb";
        id = "data";
      };
      path = "/var/lib/influxdb2";
      class = "state";
      type = "directory";
      mode = "0700";
      owner = "influxdb";
      group = "influxdb";
    };
  };

  testStaticIdentityWithGroupOwnsTheMount = {
    expr = ownerOf {
      static = {
        user = "kea";
        group = "dhcp";
      };
    } { };
    expected = {
      owner = "kea";
      group = "dhcp";
    };
  };

  testDynamicIdentityLeavesTheMountToRoot = {
    expr = ownerOf { dynamic.unit = "alloy.service"; } { };
    expected = {
      owner = "root";
      group = "root";
    };
  };

  testDynamicIdentitySharedGroupGroupsTheMount = {
    expr = ownerOf {
      dynamic = {
        unit = "alloy.service";
        sharedGroup = "logs";
      };
    } { };
    expected = {
      owner = "root";
      group = "logs";
    };
  };

  testExplicitMountOwnerKeepsTheIdentityGroup = {
    expr = ownerOf { static.user = "chrony"; } { owner = "ntp"; };
    expected = {
      owner = "ntp";
      group = "chrony";
    };
  };

  testExplicitOwnerOfADynamicIdentityGroupsTheMount = {
    expr = ownerOf { dynamic.unit = "alloy.service"; } { owner = "alloy"; };
    expected = {
      owner = "alloy";
      group = "alloy";
    };
  };

  testMountRejectsAnUndeclaredClass = {
    expr =
      (evaluate [
        classes
        (service "svc" { static.user = "svc"; } {
          data = {
            path = "/var/lib/svc";
            class = "persist";
          };
        })
      ]).contracts.services.svc.mounts.data.class;
    expectedError.msg = "contracts\\.services\\.svc\\.mounts\\.data\\.class' is not of type";
  };

  testMountRejectsARelativePath = {
    expr =
      (evaluate [
        classes
        (service "svc" { static.user = "svc"; } {
          data = {
            path = "var/lib/svc";
            class = "state";
          };
        })
      ]).contracts.services.svc.mounts.data.path;
    expectedError.msg = "contracts\\.services\\.svc\\.mounts\\.data\\.path' is not of type";
  };

  testMountsOfTheSamePathClash = {
    expr = failures [
      classes
      (service "first" { static.user = "first"; } {
        data = {
          path = "/var/lib/shared";
          class = "state";
        };
      })
      (service "second" { static.user = "second"; } {
        data = {
          path = "/var/lib/shared/";
          class = "cache";
        };
      })
    ];
    expected = [
      "nixos-contracts: mounts claims `first.data` and `second.data` clash: both persist `/var/lib/shared`."
    ];
  };

  testNestedMountsDoNotClash = {
    expr = failures [
      classes
      (service "first" { static.user = "first"; } {
        data = {
          path = "/var/lib";
          class = "state";
        };
      })
      (service "second" { static.user = "second"; } {
        data = {
          path = "/var/lib/second";
          class = "state";
        };
      })
    ];
    expected = [ ];
  };
}
