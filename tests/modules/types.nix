{ contractsLib, lib }:
let
  valueOf =
    type: value:
    (lib.evalModules {
      modules = [
        {
          options.token = lib.mkOption { inherit type; };
          config.token = value;
        }
      ];
    }).config.token;
  referenceOf = valueOf contractsLib.types.reference;
  secretReferenceOf = valueOf (contractsLib.types.referenceTo "secrets");

  token = {
    node = "metrics";
    service = "telegraf";
    id = "token";
  };
in
{
  testReferenceNamesANodeKindServiceAndId = {
    expr = referenceOf (token // { kind = "secrets"; });
    expected = token // {
      kind = "secrets";
    };
  };

  testReferenceNeedsAKind = {
    expr = (referenceOf token).kind;
    expectedError.msg = "token\\.kind' was accessed but has no value defined";
  };

  testReferenceTakesNoClaimName = {
    expr = referenceOf "telegraf-token";
    expectedError.msg = "token' is not of type `submodule'";
  };

  testReferenceToOneKindDefaultsItsKind = {
    expr = secretReferenceOf token;
    expected = token // {
      kind = "secrets";
    };
  };

  testReferenceToOneKindRejectsAnotherKind = {
    expr = (secretReferenceOf (token // { kind = "binds"; })).kind;
    expectedError.msg = "token\\.kind' is not of type `value \"secrets\"";
  };

  testReferenceToOneKindTakesAKindsName = {
    expr = contractsLib.types.referenceTo null;
    expectedError.msg = "nixos-contracts: `types\\.referenceTo` takes a kind's name";
  };

  testReferenceNeedsANode = {
    expr = (secretReferenceOf (removeAttrs token [ "node" ])).node;
    expectedError.msg = "token\\.node' was accessed but has no value defined";
  };
}
