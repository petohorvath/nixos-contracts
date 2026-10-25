# PROTOTYPE, throwaway. Fleet service modules: each states its contract,
# contributes its own claims' references to the registry, and builds its
# daemon's configuration from contracts and `registry.combined`. No module
# writes another node's options and none uses `sendTo` or inboxes.
let
  # The claim name keys a contribution, so two services on one node, or
  # one service on two nodes, never meet in one key.
  contribute = claim: { ${claim.name} = claim.ref; };
in
{
  loki =
    {
      config,
      contractsLib,
      ...
    }:
    {
      contracts.services.loki = contractsLib.mkDefaultContract {
        inherit (config.services.loki) enable;
        identity.static.user = "loki";
        binds.http.port = 3100;
      };
      services.loki.configuration = {
        auth_enabled = false;
        server.http_listen_port = config.contracts.services.loki.binds.http.port;
      };
    };

  # Ships logs to Loki instances behind their proxy's basic auth.
  alloy =
    {
      config,
      lib,
      registry,
      contractsLib,
      ...
    }:
    let
      instances = config.proto.alloy.lokiInstances;
      contract = config.contracts.services.alloy;
      password = instance: contract.secrets."loki-${instance}-password";
      vhostOf =
        instance: (lib.head (lib.attrValues registry.combined.services.loki.${instance}.exports)).vhost;
    in
    {
      options.proto.alloy.lokiInstances = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      config = {
        contracts.services.alloy = contractsLib.mkDefaultContract {
          inherit (config.services.alloy) enable;
          identity.dynamic.unit = "alloy.service";
          secrets = lib.genAttrs (map (instance: "loki-${instance}-password") instances) (_: {
            value.generated = "alnum";
          });
        };
        registry.services.loki = lib.mkIf config.services.alloy.enable (
          lib.genAttrs instances (instance: {
            clients = contribute (password instance);
          })
        );
        environment.etc."alloy/loki.alloy".text = lib.concatMapStrings (instance: ''
          loki.write "${instance}" {
            endpoint {
              url = "https://${(vhostOf instance).domain}/loki/api/v1/push"
              basic_auth {
                username      = "${(password instance).name}"
                password_file = "${(password instance).path}"
              }
            }
          }
        '') instances;
      };
    };

  # Reads metrics from stores and logs from Loki instances.
  grafana =
    {
      config,
      lib,
      registry,
      contractsLib,
      ...
    }:
    let
      cfg = config.proto.grafana;
      contract = config.contracts.services.grafana;
      lokiPassword = instance: contract.secrets."loki-${instance}-password";
      storeToken = store: contract.secrets."${store}-token";
      file = secret: "$__file{${secret.path}}";
    in
    {
      options.proto.grafana = {
        lokiInstances = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        stores = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };
      config = {
        contracts.services.grafana = contractsLib.mkDefaultContract {
          inherit (config.services.grafana) enable;
          identity.static.user = "grafana";
          secrets =
            lib.genAttrs
              (
                [ "secret-key" ]
                ++ map (i: "loki-${i}-password") cfg.lokiInstances
                ++ map (s: "${s}-token") cfg.stores
              )
              (_: {
                value.generated = "alnum";
              });
        };
        registry = lib.mkIf config.services.grafana.enable {
          services.loki = lib.genAttrs cfg.lokiInstances (instance: {
            clients = contribute (lokiPassword instance);
          });
          stores = lib.genAttrs cfg.stores (store: {
            readers = contribute (storeToken store);
          });
        };
        services.grafana.settings.security.secret_key = file contract.secrets.secret-key;
        services.grafana.provision.datasources.settings.datasources =
          map (instance: {
            name = "loki-${instance}";
            type = "loki";
            url = "https://${
              (lib.head (lib.attrValues registry.combined.services.loki.${instance}.exports)).vhost.domain
            }";
            basicAuth = true;
            basicAuthUser = (lokiPassword instance).name;
            secureJsonData.basicAuthPassword = file (lokiPassword instance);
          }) cfg.lokiInstances
          ++ map (store: {
            name = "influxdb-${store}";
            type = "influxdb";
            jsonData = {
              version = "Flux";
              inherit (registry.combined.stores.${store}) organization;
            };
            secureJsonData.token = file (storeToken store);
          }) cfg.stores;
      };
    };

  # Writes metrics to stores, each with its own token.
  telegraf =
    {
      config,
      lib,
      registry,
      contractsLib,
      ...
    }:
    let
      stores = config.proto.telegraf.stores;
      contract = config.contracts.services.telegraf;
      token = store: contract.secrets."${store}-token";
    in
    {
      options.proto.telegraf.stores = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      config = {
        contracts.services.telegraf = contractsLib.mkDefaultContract {
          inherit (config.services.telegraf) enable;
          identity.static.user = "telegraf";
          secrets = lib.genAttrs (map (store: "${store}-token") stores) (_: {
            value.generated = "alnum";
          });
        };
        registry.stores = lib.mkIf config.services.telegraf.enable (
          lib.genAttrs stores (store: {
            writers = contribute (token store);
          })
        );
        services.telegraf.extraConfig.outputs.influxdb_v2 = map (store: {
          urls = [ "https://metrics.example.test" ];
          token = "$TOKEN_FROM_${(token store).path}";
          inherit (registry.combined.stores.${store}) organization bucket;
        }) stores;
      };
    };

  # Holds a copy of every writer's and reader's token, and authorises each.
  influxdb =
    {
      config,
      lib,
      registry,
      contractsLib,
      ...
    }:
    let
      contract = config.contracts.services.influxdb;
      myStores = lib.filterAttrs (_: store: store.node == config.contracts.node) registry.combined.stores;

      # The receiver picks each copy's id. Ids allow no `_`, so this join
      # is ambiguous in principle (`a-b` + `c` and `a` + `b-c`).
      copyId =
        store: role: ref:
        "${store}-${role}-${ref.node}-${ref.service}-${ref.id}";

      # Every token contributed to one of this node's stores, as
      # `{ store; role; name; ref; }`.
      tokens = lib.concatLists (
        lib.mapAttrsToList (
          store: entry:
          lib.concatMap
            (
              role:
              lib.mapAttrsToList (name: ref: {
                inherit
                  store
                  role
                  name
                  ref
                  ;
              }) entry.${role}
            )
            [
              "writers"
              "readers"
            ]
        ) myStores
      );
    in
    {
      contracts.services.influxdb = contractsLib.mkDefaultContract {
        inherit (config.services.influxdb2) enable;
        identity.static.user = "influxdb2";
        binds.http.port = 8086;
        secrets = {
          admin-password.value.generated = "alnum";
          admin-token.value.generated = "alnum";
        }
        // lib.listToAttrs (
          map (
            token: lib.nameValuePair (copyId token.store token.role token.ref) { value.copied = token.ref; }
          ) tokens
        );
      };
      services.influxdb2.provision = {
        enable = true;
        initialSetup = {
          organization = "main";
          bucket = "main";
          passwordFile = contract.secrets.admin-password.path;
          tokenFile = contract.secrets.admin-token.path;
        };
        organizations = lib.mapAttrs' (
          store: entry:
          lib.nameValuePair entry.organization {
            buckets.${entry.bucket} = { };
            auths = lib.listToAttrs (
              map (
                token:
                lib.nameValuePair token.name (
                  {
                    readBuckets = [ entry.bucket ];
                    tokenFile = contract.secrets.${copyId token.store token.role token.ref}.path;
                  }
                  // lib.optionalAttrs (token.role == "writers") { writeBuckets = [ entry.bucket ]; }
                )
              ) (lib.filter (token: token.store == store) tokens)
            );
          }
        ) myStores;
      };
    };

  # Fronts every export whose vhost names this proxy: upstream, vhost and,
  # for basic auth, an htpasswd derived from the instance's clients.
  nginx =
    {
      config,
      lib,
      registry,
      contractsLib,
      ...
    }:
    let
      inherit (registry) combined;
      proxy = config.proto.nginx.proxyName;
      contract = config.contracts.services.nginx;

      fronted = lib.flatten (
        lib.mapAttrsToList (
          service:
          lib.mapAttrsToList (
            instanceName: instance:
            lib.mapAttrsToList
              (_: export: {
                inherit service instance;
                inherit (export) bind vhost;
                upstream = "${service}-${instanceName}";
                htpasswd = "htpasswd-${service}-${instanceName}";
              })
              (lib.filterAttrs (_: export: export.vhost != null && export.vhost.proxy == proxy) instance.exports)
          )
        ) combined.services
      );
      authed = lib.filter (entry: entry.vhost.basicAuth) fronted;
      flatten = lib.concatLists;
    in
    {
      options.proto.nginx.proxyName = lib.mkOption { type = lib.types.str; };
      config = {
        contracts.services.nginx = contractsLib.mkDefaultContract {
          inherit (config.services.nginx) enable;
          identity.static.user = "nginx";
          binds.https.port = 443;
          secrets = lib.listToAttrs (
            map (
              entry:
              lib.nameValuePair entry.htpasswd {
                value.derived = {
                  generator = "basic-auth";
                  from = lib.attrValues entry.instance.clients;
                };
              }
            ) authed
          );
        };

        # One htpasswd line per client, its user the client claim's name:
        # agenix-rekey passes each dependency's host and entry id, which
        # join into it.
        age.generators.basic-auth =
          {
            lib,
            decrypt,
            deps,
            ...
          }:
          lib.concatMapStrings (dep: ''
            echo "${lib.removePrefix "nixos:" dep.host}_${dep.name}:$(${decrypt} ${dep.file} | htpasswd -niB x | cut -d: -f2)"
          '') deps;

        services.nginx.upstreams = lib.listToAttrs (
          map (
            entry:
            lib.nameValuePair entry.upstream {
              servers."${
                combined.nodes.${entry.instance.node}.address
              }:${toString (config.contracts.resolve entry.bind).port}" =
                { };
            }
          ) fronted
        );
        services.nginx.virtualHosts = lib.listToAttrs (
          map (
            entry:
            lib.nameValuePair entry.vhost.domain {
              extraConfig = "client_max_body_size ${entry.vhost.maxBodySize};";
              locations."/" = {
                proxyPass = "http://${entry.upstream}";
                proxyWebsockets = entry.vhost.websockets;
                extraConfig = lib.concatStrings (flatten [
                  (lib.optional (entry.vhost.readTimeout != null) "proxy_read_timeout ${entry.vhost.readTimeout};\n")
                  (lib.optional entry.vhost.basicAuth ''
                    auth_basic "Authentication required";
                    auth_basic_user_file ${contract.secrets.${entry.htpasswd}.path};
                  '')
                ]);
              };
            }
          ) fronted
        );
      };
    };
}
