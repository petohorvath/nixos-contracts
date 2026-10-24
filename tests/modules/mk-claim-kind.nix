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
            type = lib.types.enum config.contracts.kinds.databases.engines;
            default = builtins.head config.contracts.kinds.databases.engines;
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
  testCustomKindFoldsEnabledClaims = {
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
      };
      vaultwarden-main = {
        service = "vaultwarden";
        id = "main";
        name = "vaultwarden-main";
        engine = "postgresql";
        database = "vault";
        unit = "vaultwarden.service";
        claimName = "vaultwarden-main";
      };
    };
  };

  testClaimSetEntryIsTheClaim = {
    expr =
      let
        config = evaluate [
          databases
          services
        ];
      in
      lib.mapAttrs (
        _: entry: entry == config.contracts.services.${entry.service}.databases.${entry.id}
      ) config.contracts.claimSets.databases;
    expected = {
      grafana-main = true;
      vaultwarden-main = true;
    };
  };

  testCustomKindDeclaresItsSettings = {
    expr = (evaluate [ databases ]).contracts.kinds.databases.engines;
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
      "nixos-contracts: tokens claims `b-c` of `a` and `c` of `a-b` share the claim name `a-b-c`, since a claim name joins its service and id with `-`; give all but one of them another id."
    ];
  };

  testThreeClaimsSharingANameFailOneCheck = {
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
            tokens.b-c-d = { };
          };
          a-b = {
            enable = true;
            identity.static.user = "ab";
            tokens.c-d = { };
          };
          a-b-c = {
            enable = true;
            identity.static.user = "abc";
            tokens.d = { };
          };
        };
      }
    ];
    expected = [
      "nixos-contracts: tokens claims `b-c-d` of `a` and `c-d` of `a-b` and `d` of `a-b-c` share the claim name `a-b-c-d`, since a claim name joins its service and id with `-`; give all but one of them another id."
    ];
  };

  testCheckRuleReadsTheKindSettings = {
    expr = failures [
      (mkClaimKind {
        name = "tokens";
        description = "Tokens.";
        settings.minimum = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = "The shortest token allowed.";
        };
        check =
          { claim, settings, ... }:
          if claim.length < settings.minimum then "it is too short" else null;
        claim =
          _:
          { lib, ... }:
          {
            options.length = lib.mkOption {
              type = lib.types.int;
              description = "The token length.";
            };
          };
      })
      {
        contracts.kinds.tokens.minimum = 32;
        contracts.services.a = {
          enable = true;
          identity.static.user = "a";
          tokens = {
            short.length = 16;
            long.length = 32;
          };
        };
      }
    ];
    expected = [ "nixos-contracts: tokens claim `a-short`: it is too short." ];
  };

  testCheckRuleReportsEachReasonAndReadsTheConfiguration = {
    expr = failures [
      (mkClaimKind {
        name = "tokens";
        description = "Tokens.";
        check =
          { claim, config, ... }:
          map (reserved: "it uses the reserved word `${reserved}`") (
            lib.intersectLists config.reserved claim.words
          );
        claim =
          _:
          { lib, ... }:
          {
            options.words = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "The words of the token.";
            };
          };
      })
      (
        { lib, ... }:
        {
          options.reserved = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Words no token may use.";
          };
        }
      )
      {
        reserved = [
          "admin"
          "root"
        ];
        contracts.services.a = {
          enable = true;
          identity.static.user = "a";
          tokens.main.words = [
            "admin"
            "plain"
            "root"
          ];
        };
      }
    ];
    expected = [
      "nixos-contracts: tokens claim `a-main`: it uses the reserved word `admin`."
      "nixos-contracts: tokens claim `a-main`: it uses the reserved word `root`."
    ];
  };

  testCheckRuleReportsFailingClaimsOfEnabledContracts = {
    expr = failures [
      (mkClaimKind {
        name = "tokens";
        description = "Tokens.";
        check =
          { identity, claim, ... }:
          if identity.user == null && claim.length < 32 then
            "a dynamic identity needs at least 32 characters"
          else
            null;
        claim =
          _:
          { lib, ... }:
          {
            options.length = lib.mkOption {
              type = lib.types.int;
              default = 32;
              description = "The token length.";
            };
          };
      })
      {
        contracts.services = {
          a = {
            enable = true;
            identity.dynamic.unit = "a.service";
            tokens = {
              short.length = 16;
              long = { };
            };
          };
          b = {
            enable = true;
            identity.static.user = "b";
            tokens.short.length = 16;
          };
          c = {
            identity.dynamic.unit = "c.service";
            tokens.short.length = 16;
          };
        };
      }
    ];
    expected = [
      "nixos-contracts: tokens claim `a-short`: a dynamic identity needs at least 32 characters."
    ];
  };

  testClaimTypeCannotDeclareTheClaimName = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "tokens";
          description = "Tokens.";
          claim =
            _:
            { lib, ... }:
            {
              options.name = lib.mkOption {
                type = lib.types.str;
                default = "mine";
                description = "A name of the kind's own.";
              };
            };
        })
        {
          contracts.services.a = {
            enable = true;
            identity.static.user = "a";
            tokens.t = { };
          };
        }
      ]).contracts.claimSets.tokens.a-t.name;
    expectedError.msg = "tokens\\.t\\.name' .* already declared in .*mk-claim-kind\\.nix";
  };

  testKindMayTakeANameOfTheContractsRoot = {
    expr =
      let
        config = evaluate [
          (mkClaimKind {
            name = "services";
            description = "Services the service depends on.";
            settings.limit = lib.mkOption {
              type = lib.types.int;
              default = 3;
              description = "A setting of the kind's own.";
            };
            claim = _: { };
          })
          {
            contracts.services.a = {
              enable = true;
              identity.static.user = "a";
              services.b = { };
            };
          }
        ];
      in
      {
        claimNames = builtins.attrNames config.contracts.claimSets.services;
        inherit (config.contracts.kinds.services) limit;
      };
    expected = {
      claimNames = [ "a-b" ];
      limit = 3;
    };
  };

  testEnableKindNameIsRejected = {
    expr = mkClaimKind {
      name = "enable";
      description = "Clashes with the contract's enable.";
      claim = _: { };
    };
    expectedError.msg = "claim kind name `enable` is reserved for the contract's own `enable` field; choose another name";
  };

  testIdentityKindNameIsRejected = {
    expr = mkClaimKind {
      name = "identity";
      description = "Clashes with the contract's identity.";
      claim = _: { };
    };
    expectedError.msg = "claim kind name `identity` is reserved for the contract's own `identity` field; choose another name";
  };
}
