{
  contractsLib,
  lib,
  nixos,
  contracts,
  adapter,
  backends,
}:
let
  inherit (nixos) evaluate;

  services = {
    contracts.services = {
      kea = {
        enable = true;
        identity.static = {
          user = "kea";
          group = "dhcp";
        };
        secrets = {
          ddns.value.generated = "base64";
          token = { };
        };
      };
      alloy = {
        enable = true;
        identity.dynamic.unit = "alloy.service";
        secrets.password = { };
      };
    };
  };
  # The backend's directories, and a value set on agenix-rekey under its
  # claim's backend name `<service>_<id>`.
  values = {
    age = {
      rekey = {
        secretsDir = ./.;
        generatedSecretsDir = ./generated;
      };
      secrets.alloy_password.rekeyFile = ./agenix-rekey.nix;
    };
  };
  configuration = modules: evaluate (backends ++ [ adapter ] ++ modules);
  failures = modules: nixos.failures (backends ++ [ adapter ] ++ modules);
  secretOf = name: config: {
    inherit (config.age.secrets.${name}) group mode owner;
    rekeyFile = config.age.secrets.${name}.rekeyFile or null;
    generator = config.age.secrets.${name}.generator.script or null;
  };
  # Kea without the values above, so neither secret has an encrypted file.
  keaWithoutValues.contracts.services.kea = {
    enable = true;
    identity.static.user = "kea";
    secrets = {
      ddns = { };
      token = { };
    };
  };

  # The token the metrics node's telegraf generates.
  metricsToken = {
    node = "metrics";
    service = "telegraf";
    id = "token";
  };

  # Configurations by node identity sharing one node collection, each with its
  # own secrets directories under its name, and with the adapter unless
  # `withoutAdapter` names it.
  nodesWithout =
    withoutAdapter:
    import ../../fixtures/nodes.nix {
      evaluate = modules: evaluate (backends ++ modules);
      modulesOf = node: [
        (if builtins.elem node withoutAdapter then contracts else adapter)
        {
          age.rekey = {
            secretsDir = ./. + "/${node}";
            generatedSecretsDir = ./generated + "/${node}";
          };
        }
      ];
    };
  nodesOf = nodesWithout [ ];
  # A telegraf node generating its token, and an influxdb node.
  telegraf.contracts.services.telegraf = {
    enable = true;
    identity.static.user = "telegraf";
    secrets.token.value.generated = "alnum";
  };
  influxdb = secrets: {
    contracts.services.influxdb = {
      enable = true;
      identity.static.user = "influxdb2";
      inherit secrets;
    };
  };

  # The nodes `alpha` and `beta`, each running telegraf and an influxdb
  # that holds one copy of every node's telegraf token, its id joining the
  # reference's node, kind, service and id with `_`, and an htpasswd
  # derived from all of them. A `let`-bound list carries the tokens' `ref`s,
  # as a fleet's shared data does. The nodes `withoutAdapter` names lack the
  # adapter.
  handingTokensWithout =
    withoutAdapter:
    let
      tokens = map (node: nodes.${node}.config.contracts.services.telegraf.secrets.token.ref) [
        "alpha"
        "beta"
      ];
      receiving = {
        imports = [
          (influxdb (
            lib.listToAttrs (
              map (
                reference:
                lib.nameValuePair "${reference.node}_${reference.kind}_${reference.service}_${reference.id}" {
                  value.copied = reference;
                }
              ) tokens
            )
            // {
              htpasswd.value.derived = {
                generator = "basic-auth";
                from = tokens;
              };
            }
          ))
        ];
        age.generators.basic-auth = _: "true";
      };
      nodes = nodesWithout withoutAdapter {
        alpha = [
          telegraf
          receiving
        ];
        beta = [
          telegraf
          receiving
        ];
      };
    in
    nodes;
  handingTokens = handingTokensWithout [ ];
in
{
  testGeneratorSetOnTheBackendWinsOverTheClaim = {
    expr =
      (configuration [
        services
        values
        { age.secrets.kea_ddns.generator.script = "hex"; }
      ]).age.secrets.kea_ddns.generator.script;
    expected = "hex";
  };

  testAdapterProvidesTheBackendsGenerators = {
    expr =
      let
        config = configuration [
          services
          values
          { age.generators.htpasswd = _: "true"; }
        ];
      in
      builtins.filter
        (generator: !builtins.elem generator config.contracts.kinds.secrets.backend.generators)
        [
          "alnum"
          "base64"
          "htpasswd"
        ];
    expected = [ ];
  };

  testDependenciesSetOnTheBackendKeepTheClaimsGenerator = {
    expr =
      (configuration [
        services
        values
        { age.secrets.kea_ddns.generator.dependencies = [ ]; }
      ]).age.secrets.kea_ddns.generator.script;
    expected = "base64";
  };

  testDependenciesSetOnTheBackendByNameAreKept = {
    expr =
      builtins.attrNames
        (configuration [
          services
          values
          (
            { config, ... }:
            {
              age.secrets.kea_ddns.generator.dependencies = {
                inherit (config.age.secrets) kea_token;
              };
            }
          )
        ]).age.secrets.kea_ddns.generator.dependencies;
    expected = [ "kea_token" ];
  };

  testNodeWritesProvidedOverADefaultGenerated = {
    expr =
      (configuration [
        values
        {
          contracts.services.kea = contractsLib.mkDefaultContract {
            enable = true;
            identity.static.user = "kea";
            secrets.ddns.value.generated = "alnum";
          };
        }
        { contracts.services.kea.secrets.ddns.value.provided = { }; }
      ]).age.secrets.kea_ddns.generator;
    expected = null;
  };

  testSecretNamingAGeneratorTheBackendLacksFailsItsCheck = {
    expr =
      map
        (lib.hasPrefix "nixos-contracts: secrets claim `kea.ddns`: the secret backend provides no generator `alnm`; name one of ")
        (failures [
          keaWithoutValues
          values
          { contracts.services.kea.secrets.ddns.value.generated = "alnm"; }
        ]);
    expected = [ true ];
  };

  testSecretTakesItsGeneratorFromTheClaim = {
    expr = secretOf "kea_ddns" (configuration [
      services
      values
    ]);
    expected = {
      owner = "root";
      group = "dhcp";
      mode = "0440";
      rekeyFile = ./generated/kea_ddns.age;
      generator = "base64";
    };
  };

  testSecretWithoutAGeneratorFollowsTheBackendsSecretsDir = {
    expr = secretOf "kea_token" (configuration [
      services
      values
    ]);
    expected = {
      owner = "root";
      group = "dhcp";
      mode = "0440";
      rekeyFile = ./kea_token.age;
      generator = null;
    };
  };

  testSecretWithAnUnderscoreInItsIdKeepsItInItsNames = {
    expr =
      let
        config = configuration [
          {
            age.rekey.secretsDir = ./.;
            contracts = {
              node = "beta";
              services.openssh = {
                enable = true;
                identity.static.user = "root";
                secrets.ssh_host_ed25519_key = { };
              };
            };
          }
        ];
      in
      {
        inherit (config.contracts.claimSets.secrets.openssh.ssh_host_ed25519_key) name;
        entries = builtins.attrNames config.age.secrets;
        inherit (config.age.secrets.openssh_ssh_host_ed25519_key) rekeyFile;
      };
    expected = {
      name = "beta_secrets_openssh_ssh_host_ed25519_key";
      entries = [ "openssh_ssh_host_ed25519_key" ];
      rekeyFile = ./openssh_ssh_host_ed25519_key.age;
    };
  };

  testValueSetOnTheBackendIsKept = {
    expr =
      (configuration [
        services
        values
      ]).age.secrets.alloy_password.rekeyFile;
    expected = ./agenix-rekey.nix;
  };

  testSecretWithoutAFileFailsItsCheck = {
    expr = failures [
      keaWithoutValues
      { contracts.services.kea.secrets.ddns.value.generated = "base64"; }
    ];
    expected = [
      "nixos-contracts: secret `kea.ddns` has no encrypted file: set its `age.secrets.kea_ddns.rekeyFile`, or agenix-rekey's `age.rekey.generatedSecretsDir` when it has a generator and `age.rekey.secretsDir` when it has none."
      "nixos-contracts: secret `kea.token` has no encrypted file: set its `age.secrets.kea_token.rekeyFile`, or agenix-rekey's `age.rekey.generatedSecretsDir` when it has a generator and `age.rekey.secretsDir` when it has none."
    ];
  };

  testAdapterLeavesTheSecretsDirectoriesToTheBackend = {
    expr =
      (configuration [
        keaWithoutValues
        # Another adapter's setting, so `contracts.adapters` exists.
        ({ lib, ... }: { options.contracts.adapters.other = lib.mkOption { default = null; }; })
        { contracts.adapters.agenixRekey.secretsDir = ./.; }
      ]).age.secrets.kea_token.rekeyFile;
    expectedError.msg = "contracts\\.adapters\\.agenixRekey' does not exist";
  };

  testDynamicIdentitySecretWithoutADeliveryAdapterFailsItsCheck = {
    expr = failures [
      services
      values
    ];
    expected = [
      "nixos-contracts: secrets claim `alloy.password`: it is delivered to `alloy.service`, but no delivery adapter is imported; import one such as `nixosModules.systemd-credentials`, or set its `unit` to null."
    ];
  };

  testCopyTakesTheEncryptedFileOfTheSecretItReferences = {
    expr = secretOf "kea_copy" (configuration [
      services
      values
      (
        { config, ... }:
        {
          contracts.node = "dhcp";
          contracts.services.kea.secrets.copy.value.copied = config.contracts.services.kea.secrets.token.ref;
        }
      )
    ]);
    expected = {
      owner = "root";
      group = "dhcp";
      mode = "0440";
      rekeyFile = ./kea_token.age;
      generator = null;
    };
  };

  testCopyTakesTheEncryptedFileOfAnotherNodesSecret = {
    expr =
      secretOf "influxdb_telegraf-token"
        (nodesOf {
          metrics = [ telegraf ];
          store = [
            (influxdb {
              telegraf-token.value.copied = metricsToken;
            })
          ];
        }).store.config;
    expected = {
      owner = "root";
      group = "influxdb2";
      mode = "0440";
      rekeyFile = ./generated/metrics/telegraf_token.age;
      generator = null;
    };
  };

  testCopyReferencingItsOwnNodeReadsThisConfiguration =
    let
      inherit
        ((nodesOf {
          store = [
            (influxdb {
              origin.value.generated = "alnum";
              copy.value.copied = {
                node = "store";
                service = "influxdb";
                id = "origin";
              };
            })
          ];
        }).store
        )
        config
        ;
    in
    {
      expr = {
        inherit (config.age.secrets.influxdb_copy) rekeyFile;
        inherit (config.contracts) failures;
      };
      expected = {
        rekeyFile = ./generated/store/influxdb_origin.age;
        failures = [ ];
      };
    };

  # Alpha's copy of its own token reads this configuration's entry.
  testCopyOfEachReferenceTakesTheEncryptedFileFromTheSendersNode = {
    expr = lib.mapAttrs (_: node: {
      copies = lib.genAttrs [
        "influxdb_alpha_secrets_telegraf_token"
        "influxdb_beta_secrets_telegraf_token"
      ] (name: secretOf name node.config);
      inherit (node.config.contracts) failures;
    }) handingTokens;
    expected =
      let
        copyOf = node: {
          owner = "root";
          group = "influxdb2";
          mode = "0440";
          rekeyFile = ./generated + "/${node}/telegraf_token.age";
          generator = null;
        };
      in
      lib.genAttrs [ "alpha" "beta" ] (_: {
        copies = {
          influxdb_alpha_secrets_telegraf_token = copyOf "alpha";
          influxdb_beta_secrets_telegraf_token = copyOf "beta";
        };
        failures = [ ];
      });
  };

  testGeneratorMakesTheValueFromTheSecretsItReferences = {
    expr =
      let
        nodes = nodesOf {
          metrics = [ telegraf ];
          store = [
            { age.generators.basic-auth = _: "true"; }
            (influxdb {
              local.value.generated = "alnum";
              hashes.value.derived = {
                generator = "basic-auth";
                from = [
                  metricsToken
                  {
                    node = "store";
                    service = "influxdb";
                    id = "local";
                  }
                ];
              };
            })
          ];
        };
        inherit (nodes.store) config;
      in
      {
        inherit (config.age.secrets.influxdb_hashes.generator) script;
        dependencies = map (dependency: {
          inherit (dependency) id rekeyFile;
        }) config.age.secrets.influxdb_hashes.generator.dependencies;
      };
    expected = {
      script = "basic-auth";
      dependencies = [
        {
          id = "telegraf_token";
          rekeyFile = ./generated/metrics/telegraf_token.age;
        }
        {
          id = "influxdb_local";
          rekeyFile = ./generated/store/influxdb_local.age;
        }
      ];
    };
  };

  # Each dependency is the sender's entry, read from its own node.
  testDerivedValueOfReferencesTakesTheSendersEntriesOnTheirNodes = {
    expr =
      let
        inherit (handingTokens.alpha) config;
      in
      {
        inherit (config.age.secrets.influxdb_htpasswd.generator) script;
        dependencies = map (dependency: {
          inherit (dependency) id rekeyFile;
        }) config.age.secrets.influxdb_htpasswd.generator.dependencies;
      };
    expected = {
      script = "basic-auth";
      dependencies = [
        {
          id = "telegraf_token";
          rekeyFile = ./generated/alpha/telegraf_token.age;
        }
        {
          id = "telegraf_token";
          rekeyFile = ./generated/beta/telegraf_token.age;
        }
      ];
    };
  };

  testDerivedValueWithoutSourcesTakesItsGeneratorAlone = {
    expr =
      let
        inherit
          ((nodesOf {
            store = [
              { age.generators.basic-auth = _: "true"; }
              (influxdb { hashes.value.derived.generator = "basic-auth"; })
            ];
          }).store
          )
          config
          ;
      in
      {
        inherit (config.age.secrets.influxdb_hashes.generator) script dependencies;
        inherit (config.contracts) failures;
      };
    expected = {
      script = "basic-auth";
      dependencies = [ ];
      failures = [ ];
    };
  };

  testFileAndGeneratorSetOnTheBackendWinOverACopyOrDerivedValue = {
    expr =
      let
        inherit
          ((nodesOf {
            metrics = [ telegraf ];
            store = [
              { age.generators.basic-auth = _: "true"; }
              (influxdb {
                copy.value.copied = metricsToken;
                hashes.value.derived = {
                  generator = "basic-auth";
                  from = [ metricsToken ];
                };
              })
              {
                age.secrets = {
                  influxdb_copy.rekeyFile = ./agenix-rekey.nix;
                  influxdb_hashes.generator.script = "hex";
                };
              }
            ];
          }).store
          )
          config
          ;
      in
      {
        inherit (config.age.secrets.influxdb_copy) rekeyFile;
        inherit (config.age.secrets.influxdb_hashes.generator) script;
      };
    expected = {
      rekeyFile = ./agenix-rekey.nix;
      script = "hex";
    };
  };

  # Alpha's copy of beta's token and its htpasswd each reference beta.
  testReferenceToANodeWithoutTheAdapterFailsItsCheck = {
    expr = (handingTokensWithout [ "beta" ]).alpha.config.contracts.failures;
    expected = [
      "nixos-contracts: secret `influxdb.beta_secrets_telegraf_token` references `beta:secrets.telegraf.token`, whose node has no `nixosModules.agenix-rekey`."
      "nixos-contracts: secret `influxdb.htpasswd` references `beta:secrets.telegraf.token`, whose node has no `nixosModules.agenix-rekey`."
    ];
  };

  testCopyOfASecretWithoutAFileNamesTheSecretItReferences = {
    expr =
      (configuration [
        (influxdb {
          token.value.copied = metricsToken;
        })
        {
          # The metrics node sets no secrets directories, so its token has
          # no encrypted file. `local` names this configuration, whose entry
          # is never read.
          contracts.nodes = {
            metrics.config = configuration [
              telegraf
              { contracts.node = "metrics"; }
            ];
            local.config = { };
          };
        }
      ]).contracts.failures;
    expected = [
      "nixos-contracts: secret `influxdb.token` copies `metrics:secrets.telegraf.token`, which has no encrypted file: give it one on its node, or set `age.secrets.influxdb_token.rekeyFile`."
    ];
  };

  testCopyWithARejectedReferenceFailsOnlyTheReferenceCheck = {
    expr =
      (nodesOf {
        store = [
          (influxdb {
            token.value.copied = metricsToken;
          })
        ];
      }).store.config.contracts.failures;
    expected = [
      "nixos-contracts: secrets claim `influxdb.token`: it references `metrics:secrets.telegraf.token`: node `metrics` is not in `contracts.nodes`."
    ];
  };

  testBackendPathNamesTheEntryByServiceAndId = {
    expr =
      (configuration [
        services
        values
      ]).contracts.kinds.secrets.backend.path
        {
          service = "influxdb";
          id = "admin-token";
        };
    expected = "/run/agenix/influxdb_admin-token";
  };

  testBackendPathFollowsAnEntrysOwnPath = {
    expr =
      (configuration [
        services
        values
        { age.secrets.kea_token.path = "/run/keys/kea"; }
      ]).contracts.services.kea.secrets.token.path;
    expected = "/run/keys/kea";
  };

  testEntriesAreNamedByServiceAndIdJoinedWithAnUnderscore = {
    expr =
      builtins.attrNames
        (configuration [
          services
          values
          {
            contracts.services.kea-dhcp6 = {
              enable = true;
              identity.static.user = "kea";
              secrets.admin-token = { };
            };
          }
        ]).age.secrets;
    expected = [
      "alloy_password"
      "kea-dhcp6_admin-token"
      "kea_ddns"
      "kea_token"
    ];
  };

  testClaimReadsTheInstalledPath = {
    expr =
      (configuration [
        services
        values
      ]).contracts.services.kea.secrets.token.path;
    expected = "/run/agenix/kea_token";
  };
}
