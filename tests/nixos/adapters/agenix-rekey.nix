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
  # The backend's directories, and a value set on agenix-rekey under the
  # name of its claim's location.
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
  # own secrets directories under its name.
  nodesOf = import ../../fixtures/nodes.nix {
    evaluate = configuration;
    modulesOf = node: [
      {
        age.rekey = {
          secretsDir = ./. + "/${node}";
          generatedSecretsDir = ./generated + "/${node}";
        };
      }
    ];
  };
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

  # Influxdb's `writers` inbox on the store node, holding a copy of each
  # token it receives, and telegraf sending its token there.
  writers = {
    node = "store";
    service = "influxdb";
    id = "writers";
  };
  influxdbWriters = {
    imports = [ (influxdb { }) ];
    contracts.services.influxdb.inboxes.writers.copy = { };
  };
  sendingTelegraf = {
    imports = [ telegraf ];
    contracts.services.telegraf.secrets.token.sendTo = [ writers ];
  };
  # The store node's configuration, sharing one node collection with a
  # metrics node that `evaluateMetrics` evaluates, neither with secrets
  # directories.
  storeWithMetrics =
    evaluateMetrics:
    let
      nodeOf = node: {
        contracts = { inherit node nodes; };
      };
      nodes = {
        metrics.config = evaluateMetrics [
          (nodeOf "metrics")
          sendingTelegraf
        ];
        store.config = configuration [
          (nodeOf "store")
          influxdbWriters
        ];
      };
    in
    nodes.store.config;
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

  testDynamicIdentityWithoutDeliveryCannotReadItsSecret = {
    expr = failures [
      services
      values
    ];
    expected = [
      "nixos-contracts: secrets claim `alloy.password`: its dynamic identity cannot read it; import a delivery adapter such as `nixosModules.systemd-credentials`, or give the identity a `sharedGroup` and the secret that group."
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

  testInboxCopyTakesTheEncryptedFileOfTheSecretSentFromAnotherNode = {
    expr =
      secretOf "influxdb_writers_metrics_telegraf_token"
        (nodesOf {
          metrics = [ sendingTelegraf ];
          store = [ influxdbWriters ];
        }).store.config;
    expected = {
      owner = "root";
      group = "influxdb2";
      mode = "0440";
      rekeyFile = ./generated/metrics/telegraf_token.age;
      generator = null;
    };
  };

  testInboxCopyOfASecretSentFromItsOwnNodeReadsThisConfiguration =
    let
      inherit
        ((nodesOf {
          store = [
            sendingTelegraf
            influxdbWriters
          ];
        }).store
        )
        config
        ;
    in
    {
      expr = {
        inherit (config.age.secrets.influxdb_writers_store_telegraf_token) rekeyFile;
        inherit (config.contracts) failures;
      };
      expected = {
        rekeyFile = ./generated/store/telegraf_token.age;
        failures = [ ];
      };
    };

  testFileSetOnTheBackendWinsOverAnInboxCopys = {
    expr =
      (nodesOf {
        metrics = [ sendingTelegraf ];
        store = [
          influxdbWriters
          { age.secrets.influxdb_writers_metrics_telegraf_token.rekeyFile = ./agenix-rekey.nix; }
        ];
      }).store.config.age.secrets.influxdb_writers_metrics_telegraf_token.rekeyFile;
    expected = ./agenix-rekey.nix;
  };

  testDisabledReceivingContractInstallsNoCopies = {
    expr =
      builtins.attrNames
        (nodesOf {
          metrics = [ sendingTelegraf ];
          store = [
            influxdbWriters
            { contracts.services.influxdb.enable = lib.mkForce false; }
          ];
        }).store.config.age.secrets;
    expected = [ ];
  };

  # The metrics node sets no secrets directories, so its token has no
  # encrypted file.
  testInboxCopyOfASecretWithoutAFileNamesTheSentSecret = {
    expr = (storeWithMetrics configuration).contracts.failures;
    expected = [
      "nixos-contracts: secret `influxdb.writers.metrics.telegraf.token` copies `metrics:secrets.telegraf.token`, which has no encrypted file: give it one on its node, or set `age.secrets.influxdb_writers_metrics_telegraf_token.rekeyFile`."
    ];
  };

  # The metrics node holds its contracts, but no secret backend.
  testInboxCopyFromANodeWithoutTheAdapterFailsItsCheck = {
    expr = (storeWithMetrics (modules: nixos.evaluate ([ contracts ] ++ modules))).contracts.failures;
    expected = [
      "nixos-contracts: secret `influxdb.writers.metrics.telegraf.token` references `metrics:secrets.telegraf.token`, whose node has no `nixosModules.agenix-rekey`."
    ];
  };

  # Each node holds a copy of the token the other sends it.
  testNodesCopyingEachOthersSecretsEvaluateWithoutACycle =
    let
      nodes = nodesOf {
        metrics = [
          sendingTelegraf
          { contracts.services.telegraf.inboxes.outputs.copy = { }; }
        ];
        store = [
          influxdbWriters
          {
            contracts.services.influxdb.secrets.token = {
              value.generated = "alnum";
              sendTo = [
                {
                  node = "metrics";
                  service = "telegraf";
                  id = "outputs";
                }
              ];
            };
          }
        ];
      };
    in
    {
      expr = {
        outputs = nodes.metrics.config.age.secrets.telegraf_outputs_store_influxdb_token.rekeyFile;
        writers = nodes.store.config.age.secrets.influxdb_writers_metrics_telegraf_token.rekeyFile;
        failures = map (node: node.config.contracts.failures) [
          nodes.metrics
          nodes.store
        ];
      };
      expected = {
        outputs = ./generated/store/influxdb_token.age;
        writers = ./generated/metrics/telegraf_token.age;
        failures = [
          [ ]
          [ ]
        ];
      };
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

  testReferenceToANodeWithoutTheAdapterFailsItsCheck = {
    expr =
      (configuration [
        (influxdb {
          token.value.copied = metricsToken;
        })
        {
          # The metrics node holds its contracts, but no secret backend.
          contracts.nodes.metrics.config = nixos.evaluate [
            contracts
            telegraf
          ];
        }
      ]).contracts.failures;
    expected = [
      "nixos-contracts: secret `influxdb.token` references `metrics:secrets.telegraf.token`, whose node has no `nixosModules.agenix-rekey`."
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
          # no encrypted file.
          contracts.nodes.metrics.config = configuration [ telegraf ];
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

  testBackendPathNamesTheEntryByTheLocation = {
    expr =
      (configuration [
        services
        values
      ]).contracts.kinds.secrets.backend.path
        [
          "influxdb"
          "admin-token"
        ];
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

  testEntriesAreNamedByTheLocationJoinedWithUnderscores = {
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
