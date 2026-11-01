{
  contractsLib,
  helpers,
  lib,
  ...
}:
let
  inherit (helpers.contracts) evaluate failures;
  inherit (contractsLib) mkClaimKind;

  databases = mkClaimKind {
    name = "databases";
    description = "Databases the service owns.";
    settings = {
      engines = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "postgresql" ];
        description = "Engines a database may use.";
      };
      shared = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Databases several services may own.";
      };
    };
    clash =
      {
        first,
        second,
        settings,
        ...
      }:
      if first.database == second.database && !builtins.elem first.database settings.shared then
        "both own `${first.database}`"
      else
        null;
    claimType =
      {
        service,
        identity,
        settings,
        ...
      }:
      {
        config,
        lib,
        name,
        ...
      }:
      {
        options = {
          engine = lib.mkOption {
            type = lib.types.enum settings.engines;
            default = builtins.head settings.engines;
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
            default = "${config.service}/${config.id}";
            description = "The claim's service and id, read from the claim.";
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

  # A kind of words, given its claim type or one rule at a time, so a test
  # sees what each receives.
  wordKind =
    rules:
    mkClaimKind (
      {
        name = "words";
        description = "Words.";
        claimType = _: { };
      }
      // rules
    );

  wordClaims.contracts.services.a = {
    enable = true;
    identity.static.user = "a";
    words = {
      first = { };
      second = { };
    };
  };

  # The name of the database `reference` names, or null when it names
  # none, read through the `resolve` a kind receives.
  aliasedDatabase =
    resolve: reference:
    let
      result = resolve reference;
    in
    if result.reason == null then result.claim.database else null;

  # A kind whose claims alias a database, resolving the reference in its
  # claim type and each of its rules.
  aliases = mkClaimKind {
    name = "aliases";
    description = "Aliases of databases.";
    claimType =
      { resolve, ... }:
      { config, lib, ... }:
      {
        options = {
          of = lib.mkOption {
            type = contractsLib.types.referenceTo "databases";
            description = "The database the alias names.";
          };
          database = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            readOnly = true;
            default = aliasedDatabase resolve config.of;
            description = "The name of the aliased database, or null.";
          };
        };
      };
    check =
      { claim, resolve, ... }:
      let
        inherit (resolve claim.of) reason;
      in
      if reason == null then
        null
      else
        "it aliases `${contractsLib.labels.reference claim.of}`: ${reason}";
    clash =
      {
        first,
        second,
        resolve,
        ...
      }:
      let
        databaseOf = alias: aliasedDatabase resolve alias.of;
      in
      if databaseOf first != null && databaseOf first == databaseOf second then
        "both alias `${databaseOf first}`"
      else
        null;
  };

  aliasClaims.contracts.services.app = {
    enable = true;
    identity.static.user = "app";
    aliases = {
      grafana.of = {
        node = "local";
        service = "grafana";
        id = "main";
      };
      vault.of = {
        node = "local";
        service = "vaultwarden";
        id = "main";
      };
      missing.of = {
        node = "local";
        service = "unused";
        id = "main";
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
        name = "local_databases_grafana_main";
        engine = "postgresql";
        database = "grafana_main";
        unit = null;
        label = "grafana/main";
        ref = {
          node = "local";
          kind = "databases";
          service = "grafana";
          id = "main";
        };
      };
      vaultwarden.main = {
        service = "vaultwarden";
        id = "main";
        name = "local_databases_vaultwarden_main";
        engine = "postgresql";
        database = "vault";
        unit = "vaultwarden.service";
        label = "vaultwarden/main";
        ref = {
          node = "local";
          kind = "databases";
          service = "vaultwarden";
          id = "main";
        };
      };
    };
  };

  testClaimNameJoinsNodeKindServiceAndIdWithUnderscores = {
    expr =
      (evaluate [
        databases
        services
        { contracts.node = "beta-db"; }
      ]).contracts.claimSets.databases.grafana.main.name;
    expected = "beta-db_databases_grafana_main";
  };

  testClaimsOfTwoKindsWithOneServiceAndIdHaveDifferentNames = {
    expr =
      let
        config = evaluate [
          databases
          (mkClaimKind {
            name = "tokens";
            description = "Tokens.";
            claimType = _: { };
          })
          {
            contracts.node = "beta";
            contracts.services.grafana = {
              enable = true;
              identity.static.user = "grafana";
              databases.main = { };
              tokens.main = { };
            };
          }
        ];
      in
      [
        config.contracts.claimSets.databases.grafana.main.name
        config.contracts.claimSets.tokens.grafana.main.name
      ];
    expected = [
      "beta_databases_grafana_main"
      "beta_tokens_grafana_main"
    ];
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
      (config.contracts.resolve config.contracts.services.vaultwarden.databases.main.ref).claim.database;
    expected = "vault";
  };

  testCustomKindDeclaresItsSettings = {
    expr = (evaluate [ databases ]).contracts.kinds.databases;
    expected = {
      engines = [ "postgresql" ];
      shared = [ ];
    };
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

  testCustomKindClaimTypeReadsTheSettingsANodeWrites = {
    expr =
      (evaluate [
        databases
        services
        { contracts.kinds.databases.engines = [ "mysql" ]; }
      ]).contracts.claimSets.databases.grafana.main.engine;
    expected = "mysql";
  };

  testCustomKindClaimTypeReadsIdentityServiceAndId = {
    expr =
      lib.mapAttrs
        (_: contract: {
          inherit (contract.databases.main) label unit;
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
          claimType =
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

  testClashRuleReadsTheKindSettings = {
    expr = failures [
      databases
      services
      {
        contracts.kinds.databases.shared = [ "vault" ];
        contracts.services.grafana.databases.main.database = "vault";
      }
    ];
    expected = [ ];
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
            claimType = _: { };
          })
          {
            contracts.node = "n";
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
        names = [
          config.contracts.claimSets.tokens.a.b-c.name
          config.contracts.claimSets.tokens.a-b.c.name
        ];
      };
    expected = {
      failures = [ ];
      names = [
        "n_tokens_a_b-c"
        "n_tokens_a-b_c"
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
        claimType =
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
        claimType =
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

  testClaimTypeReceivesServiceIdentitySettingsAndResolve = {
    expr =
      (evaluate [
        (wordKind {
          claimType =
            arguments:
            { lib, ... }:
            {
              options.arguments = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                readOnly = true;
                default = builtins.attrNames arguments;
                description = "The names of the claim type's arguments.";
              };
            };
        })
        wordClaims
      ]).contracts.claimSets.words.a.first.arguments;
    expected = [
      "identity"
      "resolve"
      "service"
      "settings"
    ];
  };

  testCheckRuleReceivesIdentityClaimSettingsAndResolve = {
    expr = failures [
      (wordKind {
        check = arguments: "it received ${lib.concatStringsSep ", " (builtins.attrNames arguments)}";
      })
      wordClaims
    ];
    expected = [
      "nixos-contracts: words claim `a.first`: it received claim, identity, resolve, settings."
      "nixos-contracts: words claim `a.second`: it received claim, identity, resolve, settings."
    ];
  };

  testClashRuleReceivesFirstSecondSettingsAndResolve = {
    expr = failures [
      (wordKind {
        clash = arguments: "they received ${lib.concatStringsSep ", " (builtins.attrNames arguments)}";
      })
      wordClaims
    ];
    expected = [
      "nixos-contracts: words claims `a.first` and `a.second` clash: they received first, resolve, second, settings."
    ];
  };

  testClaimTypeResolvesAReference = {
    expr =
      lib.mapAttrs (_: alias: alias.database)
        (evaluate [
          databases
          aliases
          services
          aliasClaims
        ]).contracts.claimSets.aliases.app;
    expected = {
      grafana = "grafana_main";
      missing = null;
      vault = "vault";
    };
  };

  testCheckRuleResolvesAReference = {
    expr = failures [
      databases
      aliases
      services
      aliasClaims
    ];
    expected = [
      "nixos-contracts: aliases claim `app.missing`: it aliases `local:databases.unused.main`: no enabled contract on `local` holds it."
    ];
  };

  testClashRuleResolvesAReference = {
    expr = failures [
      databases
      aliases
      services
      aliasClaims
      {
        contracts.services.app.aliases.again.of = {
          node = "local";
          service = "grafana";
          id = "main";
        };
      }
    ];
    expected = [
      "nixos-contracts: aliases claims `app.again` and `app.grafana` clash: both alias `grafana_main`."
      "nixos-contracts: aliases claim `app.missing`: it aliases `local:databases.unused.main`: no enabled contract on `local` holds it."
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
        claimType =
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
          claimType =
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
          claimType =
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

  testClaimTypeMayDeclareALocation = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "tokens";
          description = "Tokens.";
          claimType =
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
    expected = "mine";
  };

  testClaimTypeMayDeclareASendTo = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "tokens";
          description = "Tokens.";
          claimType =
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
    expected = "mine";
  };

  testClaimIdMayContainDigitsAndHyphens =
    let
      engineOf =
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
      expr = engineOf "main-2";
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
      name = "beta_databases_grafana_main_db_2";
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

  testClaimIdWithADotFails = {
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
            claimType = _: { };
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

  testKindMayBeNamedInboxes = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "inboxes";
          description = "Mailboxes the service delivers to.";
          claimType =
            _:
            { lib, ... }:
            {
              options.address = lib.mkOption {
                type = lib.types.str;
                description = "The mailbox's address.";
              };
            };
        })
        {
          contracts.services.postfix = {
            enable = true;
            identity.static.user = "postfix";
            inboxes.postmaster.address = "postmaster@example.test";
          };
        }
      ]).contracts.claimSets.inboxes.postfix.postmaster.address;
    expected = "postmaster@example.test";
  };

  testNodeSwitchesADefaultTagOfACustomKind = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "backups";
          description = "Backups of the service's state.";
          claimType =
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

  testEnableKindNameFails = {
    expr = mkClaimKind {
      name = "enable";
      description = "Clashes with the contract's enable.";
      claimType = _: { };
    };
    expectedError.msg = "claim kind name `enable` is reserved for the contract's own `enable` field; choose another name";
  };

  testKindNameMayContainDigitsAndHyphens = {
    expr =
      (evaluate [
        (mkClaimKind {
          name = "tokens-2";
          description = "Tokens.";
          claimType = _: { };
        })
        {
          contracts.node = "beta";
          contracts.services.a = {
            enable = true;
            identity.static.user = "a";
            tokens-2.t = { };
          };
        }
      ]).contracts.claimSets.tokens-2.a.t.name;
    expected = "beta_tokens-2_a_t";
  };

  testKindNameWithAnUnderscoreFails = {
    expr = mkClaimKind {
      name = "api_tokens";
      description = "Tokens.";
      claimType = _: { };
    };
    expectedError.msg = "claim kind name `api_tokens` may contain only lowercase letters, digits and hyphens";
  };

  testKindNameWithAnUppercaseLetterFails = {
    expr = mkClaimKind {
      name = "Tokens";
      description = "Tokens.";
      claimType = _: { };
    };
    expectedError.msg = "claim kind name `Tokens` may contain only lowercase letters, digits and hyphens";
  };

  testIdentityKindNameFails = {
    expr = mkClaimKind {
      name = "identity";
      description = "Clashes with the contract's identity.";
      claimType = _: { };
    };
    expectedError.msg = "claim kind name `identity` is reserved for the contract's own `identity` field; choose another name";
  };
}
