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
          ddns.generate = "base64";
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
  # claim name.
  values = {
    age = {
      rekey = {
        secretsDir = ./.;
        generatedSecretsDir = ./generated;
      };
      secrets.alloy-password.rekeyFile = ./agenix-rekey.nix;
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

  # Configurations by node name, each given the whole collection as its
  # node collection, as nixos-cross-config's would be.
  nodesOf =
    modulesByNode:
    lib.fix (
      nodes:
      lib.mapAttrs (node: modules: {
        config = configuration (
          [
            {
              age.rekey = {
                secretsDir = ./. + "/${node}";
                generatedSecretsDir = ./generated + "/${node}";
              };
              contracts = { inherit nodes; };
            }
          ]
          ++ modules
        );
      }) modulesByNode
    );
  # A telegraf node generating its token, and an influxdb node.
  telegraf.contracts.services.telegraf = {
    enable = true;
    identity.static.user = "telegraf";
    secrets.token.generate = "alnum";
  };
  influxdb = secrets: {
    contracts.services.influxdb = {
      enable = true;
      identity.static.user = "influxdb2";
      inherit secrets;
    };
  };
in
{
  testGeneratorSetOnTheBackendWinsOverTheClaim = {
    expr =
      (configuration [
        services
        values
        { age.secrets.kea-ddns.generator.script = "hex"; }
      ]).age.secrets.kea-ddns.generator.script;
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
        { age.secrets.kea-ddns.generator.dependencies = [ ]; }
      ]).age.secrets.kea-ddns.generator.script;
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
              age.secrets.kea-ddns.generator.dependencies = {
                inherit (config.age.secrets) kea-token;
              };
            }
          )
        ]).age.secrets.kea-ddns.generator.dependencies;
    expected = [ "kea-token" ];
  };

  testNodeRemovesTheGeneratorOfADefaultClaim = {
    expr =
      (configuration [
        values
        {
          contracts.services.kea = contractsLib.mkDefaultContract {
            enable = true;
            identity.static.user = "kea";
            secrets.ddns.generate = "alnum";
          };
        }
        { contracts.services.kea.secrets.ddns.generate = null; }
      ]).age.secrets.kea-ddns.generator;
    expected = null;
  };

  testSecretNamingAGeneratorTheBackendLacksFailsItsCheck = {
    expr =
      map
        (lib.hasPrefix "nixos-contracts: secrets claim `kea-ddns`: the secret backend provides no generator `alnm`; name one of ")
        (failures [
          keaWithoutValues
          values
          { contracts.services.kea.secrets.ddns.generate = "alnm"; }
        ]);
    expected = [ true ];
  };

  testSecretTakesItsGeneratorFromTheClaim = {
    expr = secretOf "kea-ddns" (configuration [
      services
      values
    ]);
    expected = {
      owner = "root";
      group = "dhcp";
      mode = "0440";
      rekeyFile = ./generated/kea-ddns.age;
      generator = "base64";
    };
  };

  testSecretWithoutAGeneratorFollowsTheBackendsSecretsDir = {
    expr = secretOf "kea-token" (configuration [
      services
      values
    ]);
    expected = {
      owner = "root";
      group = "dhcp";
      mode = "0440";
      rekeyFile = ./kea-token.age;
      generator = null;
    };
  };

  testValueSetOnTheBackendIsKept = {
    expr =
      (configuration [
        services
        values
      ]).age.secrets.alloy-password.rekeyFile;
    expected = ./agenix-rekey.nix;
  };

  testSecretWithoutAFileFailsItsCheck = {
    expr = failures [
      keaWithoutValues
      { contracts.services.kea.secrets.ddns.generate = "base64"; }
    ];
    expected = [
      "nixos-contracts: secret `kea-ddns` has no encrypted file: set its `age.secrets.kea-ddns.rekeyFile`, or agenix-rekey's `age.rekey.generatedSecretsDir` when it has a generator and `age.rekey.secretsDir` when it has none."
      "nixos-contracts: secret `kea-token` has no encrypted file: set its `age.secrets.kea-token.rekeyFile`, or agenix-rekey's `age.rekey.generatedSecretsDir` when it has a generator and `age.rekey.secretsDir` when it has none."
    ];
  };

  testAdapterLeavesTheSecretsDirectoriesToTheBackend = {
    expr =
      (configuration [
        keaWithoutValues
        # Another adapter's setting, so `contracts.adapters` exists.
        ({ lib, ... }: { options.contracts.adapters.other = lib.mkOption { default = null; }; })
        { contracts.adapters.agenixRekey.secretsDir = ./.; }
      ]).age.secrets.kea-token.rekeyFile;
    expectedError.msg = "contracts\\.adapters\\.agenixRekey' does not exist";
  };

  testDynamicIdentityWithoutDeliveryCannotReadItsSecret = {
    expr = failures [
      services
      values
    ];
    expected = [
      "nixos-contracts: secrets claim `alloy-password`: its dynamic identity cannot read it; import a delivery adapter such as `nixosModules.systemd-credentials`, or give the identity a `sharedGroup` and the secret that group."
    ];
  };

  testCopyTakesTheEncryptedFileOfTheSecretItReferences = {
    expr = secretOf "kea-copy" (configuration [
      services
      values
      { contracts.services.kea.secrets.copy.from = [ "kea-token" ]; }
    ]);
    expected = {
      owner = "root";
      group = "dhcp";
      mode = "0440";
      rekeyFile = ./kea-token.age;
      generator = null;
    };
  };

  testCopyTakesTheEncryptedFileOfAnotherNodesSecret = {
    expr =
      secretOf "influxdb-telegraf-token"
        (nodesOf {
          metrics = [ telegraf ];
          store = [
            (influxdb {
              telegraf-token.from = [
                {
                  node = "metrics";
                  name = "telegraf-token";
                }
              ];
            })
          ];
        }).store.config;
    expected = {
      owner = "root";
      group = "influxdb2";
      mode = "0440";
      rekeyFile = ./generated/metrics/telegraf-token.age;
      generator = null;
    };
  };

  testCopyReferencingItsOwnNodeByNameReadsThisConfiguration =
    let
      inherit
        ((nodesOf {
          store = [
            (influxdb {
              origin.generate = "alnum";
              copy.from = [
                {
                  node = "store";
                  name = "influxdb-origin";
                }
              ];
            })
          ];
        }).store
        )
        config
        ;
    in
    {
      expr = {
        inherit (config.age.secrets.influxdb-copy) rekeyFile;
        inherit (config.contracts) failures;
      };
      expected = {
        rekeyFile = ./generated/store/influxdb-origin.age;
        failures = [ ];
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
              local.generate = "alnum";
              hashes = {
                generate = "basic-auth";
                from = [
                  {
                    node = "metrics";
                    name = "telegraf-token";
                  }
                  "influxdb-local"
                ];
              };
            })
          ];
        };
        inherit (nodes.store) config;
      in
      {
        inherit (config.age.secrets.influxdb-hashes.generator) script;
        dependencies = map (dependency: {
          inherit (dependency) id rekeyFile;
        }) config.age.secrets.influxdb-hashes.generator.dependencies;
      };
    expected = {
      script = "basic-auth";
      dependencies = [
        {
          id = "telegraf-token";
          rekeyFile = ./generated/metrics/telegraf-token.age;
        }
        {
          id = "influxdb-local";
          rekeyFile = ./generated/store/influxdb-local.age;
        }
      ];
    };
  };

  testReferenceToANodeWithoutTheAdapterFailsItsCheck = {
    expr =
      (configuration [
        (influxdb {
          token.from = [
            {
              node = "metrics";
              name = "telegraf-token";
            }
          ];
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
      "nixos-contracts: secret `influxdb-token` references `metrics:telegraf-token`, whose node has no `nixosModules.agenix-rekey`."
    ];
  };

  testCopyOfASecretWithoutAFileNamesTheSecretItReferences = {
    expr =
      (configuration [
        (influxdb {
          token.from = [
            {
              node = "metrics";
              name = "telegraf-token";
            }
          ];
        })
        {
          # The metrics node sets no secrets directories, so its token has
          # no encrypted file.
          contracts.nodes.metrics.config = configuration [ telegraf ];
        }
      ]).contracts.failures;
    expected = [
      "nixos-contracts: secret `influxdb-token` copies `metrics:telegraf-token`, which has no encrypted file: give it one on its node, or set `age.secrets.influxdb-token.rekeyFile`."
    ];
  };

  testCopyWithARejectedReferenceFailsOnlyTheReferenceCheck = {
    expr =
      (nodesOf {
        store = [
          (influxdb {
            token.from = [
              {
                node = "metrics";
                name = "telegraf-token";
              }
            ];
          })
        ];
      }).store.config.contracts.failures;
    expected = [
      "nixos-contracts: secrets claim `influxdb-token`: it references node `metrics`, which is not in `contracts.nodes`."
    ];
  };

  testClaimReadsTheInstalledPath = {
    expr =
      (configuration [
        services
        values
      ]).contracts.services.kea.secrets.token.path;
    expected = "/run/agenix/kea-token";
  };
}
