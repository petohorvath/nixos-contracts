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
    host:
    (evaluate [
      { contracts.services.chrony = chrony; }
      host
    ]).contracts.services.chrony;
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

  testHostOverridesOneFieldAndKeepsItsSiblings = {
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

  testHostListReplacesTheDefaultList = {
    expr =
      (evaluateChrony { contracts.services.chrony.binds.ntp.addresses = [ "127.0.0.1" ]; })
      .binds.ntp.addresses;
    expected = [ "127.0.0.1" ];
  };

  testHostOverridesTheIdentityTagFields = {
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

  testLeavesBecomeDefaults = {
    expr = mkDefaultContract {
      enable = true;
      secrets.key.provenance.provided = { };
    };
    expected = {
      enable = lib.mkDefault true;
      secrets.key.provenance.provided = lib.mkDefault { };
    };
  };
}
