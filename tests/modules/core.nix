{ contracts }:
let
  inherit (contracts) evaluate;
in
{
  testContractsAreDisabledByDefault = {
    expr =
      (evaluate [ { contracts.services.chrony.identity.static.user = "chrony"; } ])
      .contracts.services.chrony.enable;
    expected = false;
  };

  testStaticIdentityGroupDefaultsToNull = {
    expr =
      (evaluate [ { contracts.services.chrony.identity.static.user = "chrony"; } ])
      .contracts.services.chrony.identity;
    expected.static = {
      user = "chrony";
      group = null;
    };
  };

  testDynamicIdentityNamesItsUnit = {
    expr =
      (evaluate [ { contracts.services.alloy.identity.dynamic.unit = "alloy.service"; } ])
      .contracts.services.alloy.identity;
    expected.dynamic = {
      unit = "alloy.service";
      sharedGroup = null;
    };
  };

  testIdentityIsRequired = {
    expr =
      (evaluate [ { contracts.services.chrony.enable = true; } ]).contracts.services.chrony.identity;
    expectedError.msg = "contracts\\.services\\.chrony\\.identity' was accessed but has no value defined";
  };

  testIdentityTakesExactlyOneTag = {
    expr =
      (evaluate [
        {
          contracts.services.chrony.identity = {
            static.user = "chrony";
            dynamic.unit = "chronyd.service";
          };
        }
      ]).contracts.services.chrony.identity;
    expectedError.msg = "contracts\\.services\\.chrony\\.identity";
  };

  testNoContractsMeanNoAssertions = {
    expr = (evaluate [ ]).contracts.assertions;
    expected = [ ];
  };

  testFailuresArePrefixedMessagesOfFailedChecks = {
    expr =
      (evaluate [
        {
          contracts.assertions = [
            {
              assertion = false;
              message = "the first check fails.";
            }
            {
              assertion = true;
              message = "the second check holds.";
            }
          ];
        }
      ]).contracts.failures;
    expected = [ "nixos-contracts: the first check fails." ];
  };

  testFailuresAreReadOnly = {
    expr = (evaluate [ { contracts.failures = [ "set by hand" ]; } ]).contracts.failures;
    expectedError.msg = "contracts\\.failures' is read-only";
  };
}
