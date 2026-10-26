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
      let
        topConfig = config;
      in
      {
        config,
        lib,
        name,
        ...
      }:
      {
        options = {
          engine = lib.mkOption {
            type = lib.types.enum topConfig.contracts.kinds.databases.engines;
            default = builtins.head topConfig.contracts.kinds.databases.engines;
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
          label = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            default = lib.concatStringsSep "/" config.location;
            description = "The claim's location, read from the claim.";
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
  testCustomKindNestsEnabledClaimsByServiceAndId = {
    expr =
      (evaluate [
        databases
        services
      ]).contracts.claimSets.databases;
    expected = {
      grafana.main = {
        service = "grafana";
        id = "main";
        location = [
          "grafana"
          "main"
        ];
        name = null;
        engine = "postgresql";
        database = "grafana_main";
        unit = null;
        label = "grafana/main";
        sendTo = [ ];
        ref = {
          node = null;
          kind = "databases";
          service = "grafana";
          id = "main";
        };
      };
      vaultwarden.main = {
        service = "vaultwarden";
        id = "main";
        location = [
          "vaultwarden"
          "main"
        ];
        name = null;
        engine = "postgresql";
        database = "vault";
        unit = "vaultwarden.service";
        label = "vaultwarden/main";
        sendTo = [ ];
        ref = {
          node = null;
          kind = "databases";
          service = "vaultwarden";
          id = "main";
        };
      };
    };
  };

  testClaimNameJoinsNodeServiceAndIdWithUnderscores = {
    expr =
      (evaluate [
        databases
        services
        { contracts.node = "beta-db"; }
      ]).contracts.claimSets.databases.grafana.main.name;
    expected = "beta-db_grafana_main";
  };

  testClaimSetLeavesOutServicesWithoutClaimsOfTheKind = {
    expr =
      (evaluate [
        databases
        services
        {
          contracts.services.chrony = {
            enable = true;
            identity.static.user = "chrony";
          };
        }
      ]).contracts.claimSets.databases
        ? chrony;
    expected = false;
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
        service: lib.mapAttrs (id: entry: entry == config.contracts.services.${service}.databases.${id})
      ) config.contracts.claimSets.databases;
    expected = {
      grafana.main = true;
      vaultwarden.main = true;
    };
  };

  testCustomKindClaimRefNamesTheNodeIdentity = {
    expr =
      (evaluate [
        databases
        services
        { contracts.node = "db"; }
      ]).contracts.services.grafana.databases.main.ref;
    expected = {
      node = "db";
      kind = "databases";
      service = "grafana";
      id = "main";
    };
  };

  testCustomKindClaimResolvesByItsRef = {
    expr =
      let
        config = evaluate [
          databases
          services
          { contracts.node = "db"; }
        ];
      in
      (config.contracts.resolve config.contracts.services.vaultwarden.databases.main.ref).database;
    expected = "vault";
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

  testCustomKindClaimTypeReadsIdentityAndLocation = {
    expr =
      lib.mapAttrs
        (_: contract: {
          inherit (contract.databases.main) unit label;
        })
        (evaluate [
          databases
          services
        ]).contracts.services;
    expected = {
      grafana = {
        unit = null;
        label = "grafana/main";
      };
      vaultwarden = {
        unit = "vaultwarden.service";
        label = "vaultwarden/main";
      };
      unused = {
        unit = null;
        label = "unused/main";
      };
    };
  };

  testClaimTypeTakesNoClaimNameArgument = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "tokens";
          description = "Tokens.";
          claim =
            _:
            { lib, claimName, ... }:
            {
              options.label = lib.mkOption {
                type = lib.types.str;
                default = claimName;
                description = "The claim name.";
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
      ]).contracts.services.a.tokens.t.label;
    expectedError.msg = "claimName";
  };

  testCustomKindReportsItsClashes = {
    expr = failures [
      databases
      services
      { contracts.services.grafana.databases.main.database = "vault"; }
    ];
    expected = [
      "nixos-contracts: databases claims `grafana.main` and `vaultwarden.main` clash: both own `vault`."
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

  testClaimsWhoseHyphenJoinsMeetDoNotClash = {
    expr =
      let
        config = evaluate [
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
      in
      {
        inherit (config.contracts) failures;
        locations = [
          config.contracts.claimSets.tokens.a.b-c.location
          config.contracts.claimSets.tokens.a-b.c.location
        ];
      };
    expected = {
      failures = [ ];
      locations = [
        [
          "a"
          "b-c"
        ]
        [
          "a-b"
          "c"
        ]
      ];
    };
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
    expected = [ "nixos-contracts: tokens claim `a.short`: it is too short." ];
  };

  testCheckRuleReportsEachReason = {
    expr = failures [
      (mkClaimKind {
        name = "tokens";
        description = "Tokens.";
        check =
          { claim, ... }:
          map (word: "it uses the reserved word `${word}`") (
            lib.intersectLists [
              "admin"
              "root"
            ] claim.words
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
      {
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
      "nixos-contracts: tokens claim `a.main`: it uses the reserved word `admin`."
      "nixos-contracts: tokens claim `a.main`: it uses the reserved word `root`."
    ];
  };

  testCheckRuleReadsTheConfiguration = {
    expr = failures [
      (mkClaimKind {
        name = "tokens";
        description = "Tokens.";
        check =
          { claim, config, ... }:
          if builtins.elem claim.word config.reserved then "it uses a reserved word" else null;
        claim =
          _:
          { lib, ... }:
          {
            options.word = lib.mkOption {
              type = lib.types.str;
              description = "The word of the token.";
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
        reserved = [ "admin" ];
        contracts.services.a = {
          enable = true;
          identity.static.user = "a";
          tokens = {
            admin.word = "admin";
            plain.word = "plain";
          };
        };
      }
    ];
    expected = [ "nixos-contracts: tokens claim `a.admin`: it uses a reserved word." ];
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
      "nixos-contracts: tokens claim `a.short`: a dynamic identity needs at least 32 characters."
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
      ]).contracts.claimSets.tokens.a.t.name;
    expectedError.msg = "tokens\\.t\\.name' .* already declared in .*mk-claim-kind\\.nix";
  };

  testClaimTypeCannotDeclareTheRef = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "tokens";
          description = "Tokens.";
          claim =
            _:
            { lib, ... }:
            {
              options.ref = lib.mkOption {
                type = lib.types.str;
                default = "mine";
                description = "A ref of the kind's own.";
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
      ]).contracts.claimSets.tokens.a.t.ref;
    expectedError.msg = "tokens\\.t\\.ref' .* already declared in .*mk-claim-kind\\.nix";
  };

  testClaimTypeCannotDeclareTheLocation = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "tokens";
          description = "Tokens.";
          claim =
            _:
            { lib, ... }:
            {
              options.location = lib.mkOption {
                type = lib.types.str;
                default = "mine";
                description = "A location of the kind's own.";
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
      ]).contracts.claimSets.tokens.a.t.location;
    expectedError.msg = "tokens\\.t\\.location' .* already declared in .*mk-claim-kind\\.nix";
  };

  testClaimTypeCannotDeclareTheSendTo = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "tokens";
          description = "Tokens.";
          claim =
            _:
            { lib, ... }:
            {
              options.sendTo = lib.mkOption {
                type = lib.types.str;
                default = "mine";
                description = "A sendTo of the kind's own.";
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
      ]).contracts.claimSets.tokens.a.t.sendTo;
    expectedError.msg = "tokens\\.t\\.sendTo' .* already declared in .*mk-claim-kind\\.nix";
  };

  testClaimOfANewKindIsSentToAnInbox = {
    expr =
      builtins.attrNames
        (evaluate [
          databases
          services
          {
            contracts = {
              node = "db";
              services.grafana.databases.main.sendTo = [
                {
                  node = "db";
                  service = "backup";
                  id = "databases";
                }
              ];
              services.backup = {
                enable = true;
                identity.static.user = "backup";
                inboxes.databases.kind = "databases";
              };
            };
          }
        ]).contracts.services.backup.inboxes.databases.received.db.grafana;
    expected = [ "main" ];
  };

  testClaimOfAKindThatIsNotSendableIsSentNowhere = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "tokens";
          description = "Tokens.";
          sendable = false;
          claim = _: { };
        })
        {
          contracts.services.a = {
            enable = true;
            identity.static.user = "a";
            tokens.t.sendTo = [ ];
          };
        }
      ]).contracts.claimSets.tokens.a.t.id;
    expectedError.msg = "tokens\\.t\\.sendTo' does not exist";
  };

  testInboxTakingAKindThatIsNotSendableFailsACheck = {
    expr = failures [
      (mkClaimKind {
        name = "tokens";
        description = "Tokens.";
        sendable = false;
        claim = _: { };
      })
      {
        contracts.services.backup = {
          enable = true;
          identity.static.user = "backup";
          inboxes.tokens.kind = "tokens";
        };
      }
    ];
    expected = [
      "nixos-contracts: inboxes claim `backup.tokens`: it takes `tokens`, which no claim can be sent as."
    ];
  };

  testLocationIsReadOnly = {
    expr =
      (evaluate [
        databases
        services
        { contracts.services.grafana.databases.main.location = [ "elsewhere" ]; }
      ]).contracts.services.grafana.databases.main.location;
    expectedError.msg = "databases\\.main\\.location' is read-only";
  };

  testClaimIdMayContainDigitsAndHyphens =
    let
      idOf =
        id:
        (evaluate [
          databases
          {
            contracts.services.grafana = {
              enable = true;
              identity.static.user = "grafana";
              databases.${id} = { };
            };
          }
        ]).contracts.claimSets.databases.grafana.${id}.engine;
    in
    {
      expr = idOf "main-2";
      expected = "postgresql";
    };

  testClaimIdMayContainAnUnderscore = {
    expr =
      let
        claim =
          (evaluate [
            databases
            {
              contracts.node = "beta";
              contracts.services.grafana = {
                enable = true;
                identity.static.user = "grafana";
                databases.main_db_2 = { };
              };
            }
          ]).contracts.claimSets.databases.grafana.main_db_2;
      in
      {
        inherit (claim) id name;
      };
    expected = {
      id = "main_db_2";
      name = "beta_grafana_main_db_2";
    };
  };

  testClaimIdWithAnUppercaseLetterFails = {
    expr =
      (evaluate [
        databases
        {
          contracts.services.grafana = {
            enable = true;
            identity.static.user = "grafana";
            databases.Main = { };
          };
        }
      ]).contracts.claimSets.databases;
    expectedError.msg = "databases claim id `Main` of service `grafana` may contain only lowercase letters, digits, hyphens and `_`";
  };

  testInvalidClaimIdFailsTheChecks = {
    expr = failures [
      databases
      {
        contracts.services.grafana = {
          enable = true;
          identity.static.user = "grafana";
          databases."main.db" = { };
        };
      }
    ];
    expectedError.msg = "databases claim id `main\\.db` of service `grafana` may contain only lowercase letters, digits, hyphens and `_`";
  };

  testClaimIdWithAColonFails = {
    expr =
      (evaluate [
        databases
        {
          contracts.services.grafana = {
            enable = true;
            identity.static.user = "grafana";
            databases."main:db" = { };
          };
        }
      ]).contracts.claimSets.databases;
    expectedError.msg = "databases claim id `main:db` of service `grafana` may contain only lowercase letters, digits, hyphens and `_`";
  };

  testClaimIdWithASlashFails = {
    expr =
      (evaluate [
        databases
        {
          contracts.services.grafana = {
            enable = true;
            identity.static.user = "grafana";
            databases."main/db" = { };
          };
        }
      ]).contracts.claimSets.databases;
    expectedError.msg = "databases claim id `main/db` of service `grafana` may contain only lowercase letters, digits, hyphens and `_`";
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
        ids = builtins.attrNames config.contracts.claimSets.services.a;
        inherit (config.contracts.kinds.services) limit;
      };
    expected = {
      ids = [ "b" ];
      limit = 3;
    };
  };

  testNodeSwitchesADefaultTagOfACustomKind = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "backups";
          description = "Backups of the service's state.";
          claim =
            _:
            { lib, ... }:
            {
              options.target = lib.mkOption {
                type = contractsLib.types.tag {
                  local = lib.mkOption {
                    type = lib.types.submodule {
                      options.path = lib.mkOption {
                        type = lib.types.str;
                        description = "The directory the backup goes to.";
                      };
                    };
                    description = "A backup on this node.";
                  };
                  remote = lib.mkOption {
                    type = lib.types.submodule {
                      options.host = lib.mkOption {
                        type = lib.types.str;
                        description = "The host the backup goes to.";
                      };
                    };
                    description = "A backup on another host.";
                  };
                };
                description = "Where the backup goes.";
              };
            };
        })
        {
          contracts.services.a = contractsLib.mkDefaultContract {
            enable = true;
            identity.static.user = "a";
            backups.state.target.local.path = "/var/backup/a";
          };
        }
        { contracts.services.a.backups.state.target.remote.host = "backup.example"; }
      ]).contracts.claimSets.backups.a.state.target;
    expected.remote.host = "backup.example";
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
