{
  contractsLib,
  fixtures,
  helpers,
  lib,
  self,
  ...
}:
let
  inherit (helpers.nixos) agenixRekeyBackends backends optionsOf;
  systems = [
    "aarch64-linux"
    "x86_64-linux"
  ];
  outputs = [
    "checks"
    "devShells"
    "formatter"
  ];
  token = {
    node = "local";
    kind = "secrets";
    service = "telegraf";
    id = "token";
  };
  inherit (fixtures) sourceFiles;
in
{
  testRootLibraryExportsItsFunctions = {
    expr = builtins.attrNames self.lib;
    expected = [
      "backendNameOf"
      "claimNameOf"
      "claimsOf"
      "copiesOf"
      "labels"
      "mkClaimKind"
      "mkDefaultContract"
      "mkReference"
      "types"
    ];
  };

  testRootExportsTheGenericAndNixosModules = {
    expr = {
      generic = builtins.attrNames self.modules.generic;
      nixos = builtins.attrNames self.nixosModules;
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
    expr = lib.genAttrs outputs (name: builtins.attrNames self.${name}) // {
      tests = builtins.attrNames self.tests.systems;
    };
    expected = lib.genAttrs (outputs ++ [ "tests" ]) (_: systems);
  };

  testRootChecksKeepTheirNames = {
    expr = lib.genAttrs systems (system: builtins.attrNames self.checks.${system});
    expected = lib.genAttrs systems (_: [
      "formatting"
      "lint"
      "nix-unit"
    ]);
  };

  # The suites test the code that test-context.nix imports from source.
  testRootOutputsAreTheSourceCode = {
    expr = {
      claimName = self.lib.claimNameOf token;
      generic =
        (lib.evalModules { modules = [ self.modules.generic.default ]; })
        .options.contracts.node.declarations;
      nixos =
        builtins.elem (toString sourceFiles.assertions)
          (optionsOf [ self.nixosModules.default ]).assertions.files;
      preservation =
        (optionsOf [
          backends.preservation
          self.nixosModules.preservation
        ]).contracts.adapters.preservation.roots.declarations;
      agenix-rekey =
        (optionsOf (agenixRekeyBackends ++ [ self.nixosModules.agenix-rekey ]))
        .contracts.kinds.secrets.backend.files;
      systemd-credentials =
        (optionsOf [ self.nixosModules.systemd-credentials ]).contracts.kinds.secrets.delivery.files;
    };
    expected = {
      claimName = contractsLib.claimNameOf token;
      generic = [ (toString sourceFiles.core) ];
      nixos = true;
      preservation = [ (toString sourceFiles.preservation) ];
      agenix-rekey = [ (toString sourceFiles.agenix-rekey) ];
      systemd-credentials = [ (toString sourceFiles.systemd-credentials) ];
    };
  };
}
