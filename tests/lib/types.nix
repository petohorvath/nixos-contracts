{ contractsLib, lib }:
let
  referenceOf =
    value:
    (lib.evalModules {
      modules = [
        {
          options.token = lib.mkOption { type = contractsLib.types.reference; };
          config.token = value;
        }
      ];
    }).config.token;
in
{
  testReferenceByClaimNameNamesThisConfiguration = {
    expr = referenceOf "telegraf-token";
    expected = {
      node = null;
      name = "telegraf-token";
    };
  };

  testReferenceNamesANodeOfTheCollection = {
    expr = referenceOf {
      node = "metrics";
      name = "telegraf-token";
    };
    expected = {
      node = "metrics";
      name = "telegraf-token";
    };
  };

  testReferenceNeedsAClaimName = {
    expr = (referenceOf { node = "metrics"; }).name;
    expectedError.msg = "token\\.name' was accessed but has no value defined";
  };
}
