{
  contracts,
  contractsLib,
  lib,
}:
let
  inherit (contracts) evaluate failures;
  inherit (contractsLib) mkClaimKind;

  databases = mkClaimKind {
    name = "databases";
    description = "Databases the service owns.";
    settings.engines = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "postgresql" ];
      description = "Engines a database may use.";
    };
    ownership =
      { identity, claim }:
      {
        owner = if identity.user != null then identity.user else claim.engine;
        group = null;
      };
    clash =
      first: second: if first.database == second.database then "both own `${first.database}`" else null;
    claim =
      {
        service,
        identity,
        config,
      }:
      {
        lib,
        name,
        claimName,
        ...
      }:
      {
        options = {
          engine = lib.mkOption {
            type = lib.types.enum config.contracts.databases.engines;
            default = builtins.head config.contracts.databases.engines;
            description = "The database engine.";
          };
          database = lib.mkOption {
            type = lib.types.str;
            default = "${service}_${name}";
            description = "The database name.";
          };
          unit = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            readOnly = true;
            default = identity.unit;
            description = "The unit of the owning service's identity.";
          };
          claimName = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            default = claimName;
            description = "The claim's name, read from the claim.";
          };
        };
      };
  };

  services = {
    contracts.services = {
      grafana = {
        enable = true;
        identity.static.user = "grafana";
        databases.main = { };
      };
      vaultwarden = {
        enable = true;
        identity.dynamic.unit = "vaultwarden.service";
        databases.main.database = "vault";
      };
      unused = {
        identity.static.user = "unused";
        databases.main = { };
      };
    };
  };
in
{
  testCustomKindFoldsEnabledClaimsWithOwnership = {
    expr =
      (evaluate [
        databases
        services
      ]).contracts.claimSets.databases;
    expected = {
      grafana-main = {
        service = "grafana";
        id = "main";
        name = "grafana-main";
        engine = "postgresql";
        database = "grafana_main";
        unit = null;
        claimName = "grafana-main";
        owner = "grafana";
        group = null;
      };
      vaultwarden-main = {
        service = "vaultwarden";
        id = "main";
        name = "vaultwarden-main";
        engine = "postgresql";
        database = "vault";
        unit = "vaultwarden.service";
        claimName = "vaultwarden-main";
        owner = "postgresql";
        group = null;
      };
    };
  };

  testCustomKindDeclaresItsSettings = {
    expr = (evaluate [ databases ]).contracts.databases.engines;
    expected = [ "postgresql" ];
  };

  testCustomKindClaimTypeReadsTheSettings = {
    expr =
      (evaluate [
        databases
        services
        { contracts.services.grafana.databases.main.engine = "mysql"; }
      ]).contracts.services.grafana.databases.main.engine;
    expectedError.msg = "contracts\\.services\\.grafana\\.databases\\.main\\.engine' is not of type";
  };

  testCustomKindClaimTypeReadsIdentityAndClaimName = {
    expr =
      lib.mapAttrs
        (_: contract: {
          inherit (contract.databases.main) unit claimName;
        })
        (evaluate [
          databases
          services
        ]).contracts.services;
    expected = {
      grafana = {
        unit = null;
        claimName = "grafana-main";
      };
      vaultwarden = {
        unit = "vaultwarden.service";
        claimName = "vaultwarden-main";
      };
      unused = {
        unit = null;
        claimName = "unused-main";
      };
    };
  };

  testCustomKindReportsItsClashes = {
    expr = failures [
      databases
      services
      { contracts.services.grafana.databases.main.database = "vault"; }
    ];
    expected = [
      "nixos-contracts: databases claims `grafana-main` and `vaultwarden-main` clash: both own `vault`."
    ];
  };

  testDisabledContractsDoNotClash = {
    expr = failures [
      databases
      services
      { contracts.services.unused.databases.main.database = "vault"; }
    ];
    expected = [ ];
  };

  testClaimsSharingANameClash = {
    expr = failures [
      (mkClaimKind {
        name = "tokens";
        description = "Tokens.";
        claim = _: { };
      })
      {
        contracts.services = {
          a = {
            enable = true;
            identity.static.user = "a";
            tokens.b-c = { };
          };
          a-b = {
            enable = true;
            identity.static.user = "ab";
            tokens.c = { };
          };
        };
      }
    ];
    expected = [
      "nixos-contracts: tokens claims `b-c` of `a` and `c` of `a-b` share the name `a-b-c`."
    ];
  };

  testKindWithoutOwnershipAddsNoOwner = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "tokens";
          description = "Tokens.";
          claim = _: { };
        })
        {
          contracts.services.a = {
            enable = true;
            identity.static.user = "a";
            tokens.t = { };
          };
        }
      ]).contracts.claimSets.tokens;
    expected.a-t = {
      service = "a";
      id = "t";
      name = "a-t";
    };
  };

  testReservedKindNamesAreRejected = {
    expr = mkClaimKind {
      name = "services";
      description = "Clashes with the contracts root.";
      claim = _: { };
    };
    expectedError.msg = "claim kind name `services` is reserved";
  };
}
