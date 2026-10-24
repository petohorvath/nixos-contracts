# PROTOTYPE, throwaway: nixos-config-style service modules wired through
# `to` and inboxes alone. `fleet` stands in for the registry, which also
# carries the inbox references senders use. No module declares a receiving
# option, and no node contributes configuration to another.
{
  config,
  contractsLib,
  lib,
  hostName,
  fleet,
  ...
}:
let
  inherit (lib) mkIf mkMerge;
  contracts = config.contracts.services;
  role = fleet.roles.${hostName};
  has = r: builtins.elem r role;
  inherit (fleet) inbox;
in
{
  config = mkMerge [
    # telegraf, on every node, the influxdb node and the guest included:
    # sends its token to influxdb's writers, and receives influxdb's bind.
    {
      services.telegraf.enable = true;
      contracts.services.telegraf = contractsLib.mkDefaultContract {
        enable = true;
        identity.static.user = "telegraf";
        secrets.metrics-token = {
          value.generate = "alnum";
          to = [ fleet.inboxes.influxdbWriters ];
        };
        inboxes.stores.kind = "binds";
      };
      services.telegraf.extraConfig.outputs.influxdb_v2 = lib.concatMap (
        byService:
        lib.concatMap (
          byId:
          map (entry: {
            urls = [ "http://${entry.ref.node}:${toString entry.claim.port}" ];
          }) (lib.attrValues byId)
        ) (lib.attrValues byService)
      ) (lib.attrValues contracts.telegraf.inboxes.stores.received);
    }

    # influxdb: one copy per writer, readable by influxdb, and its bind
    # sent to every telegraf.
    (mkIf (has "influxdb") (
      let
        contract = contracts.influxdb;
      in
      {
        contracts.services.influxdb = {
          enable = true;
          identity.static.user = "influxdb2";
          secrets = {
            admin-password.value.generate = "alnum";
            admin-token.value.generate = "alnum";
            grafana-token.value.generate = "alnum";
          };
          inboxes.writers.copy.mode = "0400";
          binds.http = {
            port = 8086;
            to = map (node: inbox node "telegraf" "stores") (lib.attrNames fleet.roles);
          };
        };
        services.influxdb2 = {
          enable = true;
          provision = {
            enable = true;
            initialSetup = {
              organization = "main";
              bucket = "telegraf";
              passwordFile = contract.secrets.admin-password.path;
              tokenFile = contract.secrets.admin-token.path;
            };
            organizations.main.auths =
              lib.concatMapAttrs (
                node: byService:
                lib.concatMapAttrs (
                  service: byId:
                  lib.mapAttrs' (
                    id: entry:
                    lib.nameValuePair "${service}-${node}" {
                      writeBuckets = [ "telegraf" ];
                      tokenFile = entry.copy.path;
                    }
                  ) byId
                ) byService
              ) contract.inboxes.writers.received
              // {
                grafana = {
                  readBuckets = [ "telegraf" ];
                  tokenFile = contract.secrets.grafana-token.path;
                };
              };
          };
        };
      }
    ))

    # grafana: copies influxdb's grafana token by reference, and sends its
    # loki password to the proxy's realm inbox.
    (mkIf (has "grafana") {
      contracts.services.grafana = {
        enable = true;
        identity.static.user = "grafana";
        secrets = {
          secret-key.value.generate = "alnum";
          influxdb-token.value.copy = {
            node = fleet.influxdb;
            service = "influxdb";
            id = "grafana-token";
          };
          loki-password = {
            value.generate = "alnum";
            to = [ fleet.inboxes.lokiClients ];
          };
        };
      };
      services.grafana = {
        enable = true;
        settings.security.secret_key = "$__file{${contracts.grafana.secrets.secret-key.path}}";
      };
    })

    # alloy: a dynamic identity whose secret systemd-credentials delivers;
    # a loki client of the proxy's realm.
    (mkIf (has "alloy") {
      services.alloy.enable = true;
      contracts.services.alloy = {
        enable = true;
        identity.dynamic.unit = "alloy.service";
        secrets.loki-password = {
          value.generate = "alnum";
          to = [ fleet.inboxes.lokiClients ];
        };
      };
      environment.etc."alloy/config.alloy".text = ''
        password_file = "${contracts.alloy.secrets.loki-password.path}"
      '';
    })

    # loki: sends its bind to the proxy's upstreams.
    (mkIf (has "loki") {
      contracts.services.loki = {
        enable = true;
        identity.static.user = "loki";
        binds.http = {
          port = 3100;
          to = [ fleet.inboxes.upstreams ];
        };
      };
    })

    # nginx: an htpasswd derived from whatever its realm inbox received,
    # and one upstream per bind its upstreams inbox received.
    (mkIf (has "nginx") (
      let
        contract = contracts.nginx;
      in
      {
        services.nginx.enable = true;
        contracts.services.nginx = {
          enable = true;
          identity.static.user = "nginx";
          inboxes.loki-clients-main = { };
          inboxes.upstreams.kind = "binds";
          secrets.basic-auth-loki-main.value.derive = {
            generator = "basic-auth";
            from = contract.inboxes.loki-clients-main.refs;
          };
        };
        services.nginx.upstreams = lib.concatMapAttrs (
          node:
          lib.concatMapAttrs (
            service:
            lib.mapAttrs' (
              _: entry:
              lib.nameValuePair "${service}-${node}" {
                servers."${node}:${toString entry.claim.port}" = { };
              }
            )
          )
        ) contract.inboxes.upstreams.received;
        services.nginx.virtualHosts."loki.example" = {
          locations."/".proxyPass = "http://loki-beta-loki";
          basicAuthFile = contract.secrets.basic-auth-loki-main.path;
        };
      }
    ))

    # The host runs microvms and holds a copy of each guest's provided SSH
    # host key, which it hands to the guest as a credential.
    (mkIf (has "microvm-host") {
      contracts.services.microvm = {
        enable = true;
        identity.static = {
          user = "microvm";
          group = "kvm";
        };
        inboxes.guest-keys.copy.mode = "0440";
      };
    })

    # The guest provides its SSH host key and sends it to its host.
    (mkIf (has "guest") {
      contracts.services.openssh = {
        enable = true;
        identity.static.user = "root";
        secrets.host-key.to = [ (inbox fleet.hostOf.${hostName} "microvm" "guest-keys") ];
      };
    })
  ];
}
