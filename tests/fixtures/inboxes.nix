# Services that send claims to each other's inboxes, shared by the tests of
# inboxes, sends and copies.
rec {
  service = name: claims: {
    contracts.services.${name} = {
      enable = true;
      identity.static.user = name;
    }
    // claims;
  };

  # Inboxes of nginx on the `proxy` node: `upstreams` takes binds and
  # `clients` takes secrets.
  upstreams = {
    node = "proxy";
    service = "nginx";
    id = "upstreams";
  };
  clients = upstreams // {
    id = "clients";
  };
  nginx = service "nginx" {
    inboxes = {
      upstreams.kind = "binds";
      clients = { };
    };
  };

  # A loki bind sent to nginx's upstreams.
  loki =
    sendTo:
    service "loki" {
      binds.http = {
        port = 3100;
        addresses = "10.0.0.2";
        inherit sendTo;
      };
    };

  # An upstream per received bind, as a service module builds it.
  nginxUpstreams =
    { config, lib, ... }:
    {
      options.upstreams = lib.mkOption { type = lib.types.attrsOf (lib.types.listOf lib.types.str); };
      config.upstreams = lib.concatMapAttrs (
        _:
        lib.concatMapAttrs (
          _: lib.mapAttrs' (_: entry: lib.nameValuePair entry.claim.name entry.claim.bindpoints)
        )
      ) config.contracts.services.nginx.inboxes.upstreams.received;
    };

  receivedBy = config: inbox: config.contracts.services.nginx.inboxes.${inbox}.received;
  failuresOf = node: node.config.contracts.failures;

  # A telegraf token sent to nginx's clients.
  telegraf =
    sendTo:
    service "telegraf" {
      secrets.token = {
        value.generated = "alnum";
        inherit sendTo;
      };
    };
  tokenOf = node: {
    inherit node;
    kind = "secrets";
    service = "telegraf";
    id = "token";
  };

  # Influxdb's inbox on the `store` node, which takes secrets, and
  # telegraf's on the `metrics` node, which takes binds.
  writers = {
    node = "store";
    service = "influxdb";
    id = "writers";
  };
  outputs = {
    node = "metrics";
    service = "telegraf";
    id = "outputs";
  };
  # Influxdb holding a copy of each token its writers receive, with the
  # settings `copy`.
  copyingInfluxdb = identity: copy: {
    contracts.services.influxdb = {
      enable = true;
      inherit identity;
      inboxes.writers = { inherit copy; };
    };
  };
}
