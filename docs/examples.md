# Examples

Each example below is a function that returns a JSON-compatible `result`. The root checks evaluate every example and assert its result, so the values shown here are the ones `nix flake check --no-update-lock-file` verifies. The NixOS examples are configuration evaluations: nothing is built and no VM boots.

The NixOS examples take:

- `nixpkgs`: the flake input whose `lib.nixosSystem` selects the module system.
- `exports`: this flake's `lib`, `modules` and `nixosModules`.
- `backends`: the `preservation`, `agenix` and `agenix-rekey` NixOS modules.
- `system`: optional, default `x86_64-linux`.

## influxdb: a static identity with persistence and secrets

The [service module](../examples/influxdb/service.nix) wraps nixpkgs' `services.influxdb2`. It writes the contract through `mkDefaultContract`: the static user `influxdb2`, a bind on port 8086, the mount `/var/lib/influxdb2` under the class `state`, and an admin password and an admin token. Its password claim names the `alnum` generator, while a person provides the token. It writes no backend option, so it evaluates with any secret backend. It then wires the daemon from the contract: the bind's bindpoint becomes `http-bind-address` and the secret claims' `path` become the provisioning files.

The [node](../examples/influxdb/node.nix) declares the `state` class, maps it to `/persist/state` for the preservation adapter, sets agenix-rekey's directories for provided and generated secrets, and narrows the bind to `127.0.0.1` with one field override.

The [example](../examples/influxdb/default.nix) imports both adapters with their backends. Its result shows:

- `bindAddress`: `127.0.0.1:8086`, the node's address with the service module's port.
- `preserved`: `/var/lib/influxdb2`, owned by `influxdb2:influxdb2` with mode `0700`, under `/persist/state`.
- `secrets`: both installed root-owned with group `influxdb2` and mode `0440`; the password names the `alnum` generator, and each one's encrypted file is named after its claim's location, `influxdb_admin-password.age` in the generated secrets directory and `influxdb_admin-token.age` in the secrets directory.
- `initialSetup`: the daemon reads both from `/run/agenix/<service>_<id>`.
- `failures`: none.

The encrypted files are not part of the example, since an evaluation only refers to them.

## alloy: a dynamic identity with a delivered secret

The [service module](../examples/alloy/service.nix) wraps nixpkgs' `services.alloy`, which runs with `DynamicUser`. Its contract names the unit `alloy.service` and a loopback bind on port 12345, and holds no secret.

A [Loki module](../examples/alloy/loki.nix) ships alloy's logs to the Loki instances its `example.alloy.loki.instances` names. alloy's own process reads each instance's password, so the module adds one secret per instance to alloy's contract, each naming the `alnum` generator, and the daemon's configuration reads each password from its claim's `path`.

The [example](../examples/alloy/default.nix) names one instance, `main`, and imports the agenix-rekey and systemd-credentials adapters. Its result shows:

- `installed`: agenix-rekey installs the secret root-owned at `/run/agenix/alloy_loki-main-password`, since a dynamic user has no account to own it.
- `loadCredential`: the unit loads it as `alloy_loki-main-password`.
- `passwordFile`: the daemon reads `/run/credentials/alloy.service/alloy_loki-main-password`.
- `failures`: none, since the unit exists and sets `DynamicUser`.

## exporter: a helper daemon as a service of its own

The [chrony module](../examples/exporter/chrony.nix) wraps nixpkgs' `services.chrony` with a contract of the static user `chrony` and a UDP bind on port 123. It never mentions the exporter.

The [exporter module](../examples/exporter/exporter.nix) wraps nixpkgs' chrony exporter, a helper with a process of its own, in a contract named `chrony-exporter`. The contract takes its identity from the exporter's own `user`, which nixpkgs sets to `chrony` so the exporter can read chronyd's socket. The exporter listens at the address and port of the contract's loopback bind.

The [example](../examples/exporter/default.nix) enables both with only `nixosModules.default`, since neither holds a mount or a secret. Its result shows:

- `binds`: `chrony.ntp` at `0.0.0.0:123`, and the exporter's own claim, `chrony-exporter.metrics`, at `127.0.0.1:9123`.
- `identities`: both contracts run as `chrony`, each stating it.
- `exporterListen`: `127.0.0.1:9123`, from the exporter's bind.
- `failures`: none.

## shared-token: one value on two nodes

A [telegraf module](../examples/shared-token/telegraf.nix) generates the token its node writes metrics with. An [influxdb module](../examples/shared-token/influxdb.nix) takes its writers' tokens as `example.influxdb.writers`, a list of `lib.types.referenceTo "secrets"` values, and [holds a copy](api.md#relating-nodes) of each, owned by `influxdb2` with mode `0400`. Each copy's id joins the reference's node, service and id with `_`, which gives the token's claim name. It provisions one write authorization per copy, named the same way, reads each copy at its `path` and writes no backend option.

The [example](../examples/shared-token/default.nix) evaluates two nodes, `metrics` and `store`, each given its node identity at `contracts.node` and both nodes as its node collection at `contracts.nodes`, as a fleet sets them. Both run telegraf. A `let`-bound list holds every node's telegraf token `ref`, read from the nodes' evaluated configurations, and the store takes it as its writers, its own token included, as a fleet's shared data, such as nixos-registry, would carry it. Neither node writes the other's options. Its result shows:

- `copies`: the store installs its copies as `influxdb_metrics_telegraf_token` and `influxdb_store_telegraf_token`, each owned by `influxdb2` with group `influxdb2` and mode `0400`, from the sender's encrypted file, `metrics/telegraf_token.age` and `store/telegraf_token.age`, without a generator of its own.
- `original`: the metrics node's file is the same one its copy reads.
- `auths`: one authorization per writer, `metrics_telegraf_token` and `store_telegraf_token`, each reading its copy under `/run/agenix/influxdb_…`.
- `failures`: none on either node.

## custom-kind: a claim kind of a project's own

The [databases kind](../examples/custom-kind/databases.nix) is built with `lib.mkClaimKind`. A claim names a database, defaulting to the service's name, and is owned by the service's user, or by a role named after the service for a dynamic identity. Two claims of the same database clash.

The [example](../examples/custom-kind/default.nix) evaluates the generic module with a bare `lib.evalModules`, so it needs only `lib` and `exports`. Grafana claims one database and Vaultwarden two. Its result shows:

- `claimSet`: `grafana.main` owned by `grafana`, and `vaultwarden.main` and `vaultwarden.attachments` owned by `vaultwarden`.
- `validFailures`: none.
- `clashingFailures`: after Vaultwarden's attachments database is renamed to `grafana`, one failed check reports that `grafana.main` and `vaultwarden.attachments` both own `grafana`.
