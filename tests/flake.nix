{ flake, lib }:
let
  systems = [
    "aarch64-linux"
    "x86_64-linux"
  ];
  outputs = [
    "checks"
    "devShells"
    "formatter"
    "tests"
  ];
in
{
  testRootLibraryExportsItsFunctions = {
    expr = builtins.attrNames flake.lib;
    expected = [
      "mkClaimKind"
      "mkDefaultContract"
    ];
  };

  testRootExportsTheGenericAndNixosModules = {
    expr = {
      generic = builtins.attrNames flake.modules.generic;
      nixos = builtins.attrNames flake.nixosModules;
    };
    expected = {
      generic = [ "default" ];
      nixos = [
        "agenix-rekey"
        "default"
        "preservation"
        "systemd-credentials"
      ];
    };
  };

  testRootSystemOutputsCoverOnlyLinuxSystems = {
    expr = lib.genAttrs outputs (name: builtins.attrNames flake.${name});
    expected = lib.genAttrs outputs (_: systems);
  };

  testRootChecksKeepTheirNames = {
    expr = lib.genAttrs systems (system: builtins.attrNames flake.checks.${system});
    expected = lib.genAttrs systems (_: [
      "evaluation"
      "formatting"
      "lint"
      "workflows"
    ]);
  };
}
