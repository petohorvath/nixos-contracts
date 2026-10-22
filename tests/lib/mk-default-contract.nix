{
  contracts,
  contractsLib,
  lib,
}:
let
  inherit (contracts) evaluate;
  inherit (contractsLib) mkDefaultContract;

  chrony = mkDefaultContract {
    enable = true;
    identity.static.user = "chrony";
    binds.ntp = {
      protocols = "udp";
      port = 123;
      addresses = [
        "0.0.0.0"
        "::"
      ];
    };
  };
  evaluateChrony =
    node:
    (evaluate [
      { contracts.services.chrony = chrony; }
      node
    ]).contracts.services.chrony;

  evaluateNginx =
    binds: node:
    (evaluate [
      {
        contracts.services.nginx = mkDefaultContract {
          enable = true;
          identity.static.user = "nginx";
          inherit binds;
        };
      }
      node
    ]).contracts.services.nginx.binds;
in
{
  testWithoutOverridesTheDefaultsApply = {
    expr = (evaluateChrony { }).binds.ntp;
    expected = {
      service = "chrony";
      id = "ntp";
      name = "chrony-ntp";
      protocols = [ "udp" ];
      port = 123;
      addresses = [
        "0.0.0.0"
        "::"
      ];
      bindpoints = [
        "0.0.0.0:123"
        "[::]:123"
      ];
    };
  };

  testNodeOverridesOneFieldAndKeepsItsSiblings = {
    expr =
      let
        bind = (evaluateChrony { contracts.services.chrony.binds.ntp.port = 1123; }).binds.ntp;
      in
      {
        inherit (bind) port protocols;
      };
    expected = {
      port = 1123;
      protocols = [ "udp" ];
    };
  };

  testNodeListReplacesTheDefaultList = {
    expr =
      (evaluateChrony { contracts.services.chrony.binds.ntp.addresses = [ "127.0.0.1" ]; })
      .binds.ntp.addresses;
    expected = [ "127.0.0.1" ];
  };

  testNodeOverridesTheIdentityTagFields = {
    expr = (evaluateChrony { contracts.services.chrony.identity.static.group = "time"; }).identity;
    expected.static = {
      user = "chrony";
      group = "time";
    };
  };

  testSwitchingTheIdentityTagNeedsForce = {
    expr =
      (evaluateChrony { contracts.services.chrony.identity.dynamic.unit = "chronyd.service"; }).identity;
    expectedError.msg = "contracts\\.services\\.chrony\\.identity";
  };

  testForcedIdentitySwitchesTheTag = {
    expr =
      (evaluateChrony {
        contracts.services.chrony.identity = lib.mkForce { dynamic.unit = "chronyd.service"; };
      }).identity;
    expected.dynamic = {
      unit = "chronyd.service";
      sharedGroup = null;
    };
  };

  testExplicitPropertiesAreKept = {
    expr =
      (evaluate [
        {
          contracts.services.chrony = mkDefaultContract {
            identity.static.user = lib.mkForce "chrony";
          };
        }
        { contracts.services.chrony.identity.static.user = "other"; }
      ]).contracts.services.chrony.identity.static.user;
    expected = "chrony";
  };

  testNodeOverridesAFieldOfAConditionalClaim = {
    expr =
      let
        bind =
          (evaluateNginx { proxyHttp = lib.mkIf true { port = 8080; }; } {
            contracts.services.nginx.binds.proxyHttp.port = 9090;
          }).proxyHttp;
      in
      {
        inherit (bind) port protocols;
      };
    expected = {
      port = 9090;
      protocols = [ "tcp" ];
    };
  };

  testNodeOverridesAFieldOfAMergedClaim = {
    expr =
      (evaluateNginx (lib.mkMerge [
        { http.port = 80; }
        { proxyHttp.port = 8080; }
      ]) { contracts.services.nginx.binds.proxyHttp.port = 9090; }).proxyHttp.port;
    expected = 9090;
  };

  testFalseConditionDropsTheClaim = {
    expr = evaluateNginx { proxyHttp = lib.mkIf false { port = 8080; }; } { };
    expected = { };
  };

  testNodeOverrideDefinesAClaimWhoseConditionIsFalse = {
    expr =
      (evaluateNginx { proxyHttp = lib.mkIf false { port = 8080; }; } {
        contracts.services.nginx.binds.proxyHttp.port = 9080;
      }).proxyHttp.port;
    expected = 9080;
  };

  testNodeOverrideOfAConditionalClaimNeedsItsRequiredFields = {
    expr =
      (evaluateNginx { proxyHttp = lib.mkIf false { port = 8080; }; } {
        contracts.services.nginx.binds.proxyHttp.addresses = "127.0.0.1";
      }).proxyHttp.port;
    expectedError.msg = "contracts\\.services\\.nginx\\.binds\\.proxyHttp\\.port";
  };

  testExplicitPropertiesInAConditionalClaimAreKept = {
    expr =
      (evaluateNginx { proxyHttp = lib.mkIf true { port = lib.mkForce 8080; }; } {
        contracts.services.nginx.binds.proxyHttp.port = 9090;
      }).proxyHttp.port;
    expected = 8080;
  };

  testLeavesBecomeDefaults = {
    expr = mkDefaultContract {
      enable = true;
      secrets = {
        key.mode = "0400";
        token = { };
      };
    };
    expected = {
      enable = lib.mkDefault true;
      secrets = {
        key.mode = lib.mkDefault "0400";
        token = lib.mkDefault { };
      };
    };
  };
}
