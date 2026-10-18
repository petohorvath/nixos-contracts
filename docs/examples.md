# Examples

Each example below is a function that returns a JSON-compatible `result`. The root checks evaluate every example and assert its result, so the values shown here are the ones `nix flake check --no-update-lock-file` verifies. The NixOS examples are configuration evaluations: nothing is built and no VM boots.

The NixOS examples take:

- `nixpkgs`: the flake input whose `lib.nixosSystem` selects the module system.
- `exports`: this flake's `lib`, `modules` and `nixosModules`.
- `backends`: the `preservation`, `agenix` and `agenix-rekey` NixOS modules.
- `system`: optional, default `x86_64-linux`.

## influxdb: a static identity with persistence and secrets

The [service module](../examples/influxdb/service.nix) wraps nixpkgs' `services.influxdb2`. It writes the contract through `mkDefaultContract`: the static user `influxdb2`, a bind on port 8086, the mount `/var/lib/influxdb2` under the class `state`, a generated admin password and a provided admin token. It then wires the daemon from the contract: the bind's bindpoint becomes `http-bind-address` and the secret claims' `path` become the provisioning files.

The [host](../examples/influxdb/host.nix) declares the `state` class, maps it to `/persist/state` for the preservation adapter, points the agenix-rekey adapter at a secrets directory, and narrows the bind to `127.0.0.1` with one field override.

The [example](../examples/influxdb/default.nix) imports both adapters with their backends. Its result shows:

- `bindAddress`: `127.0.0.1:8086`, the host's address with the service module's port.
- `preserved`: `/var/lib/influxdb2`, owned by `influxdb2:influxdb2` with mode `0700`, under `/persist/state`.
- `secrets`: both installed root-owned with group `influxdb2` and mode `0440`; the password names the `alnum` generator and the token's encrypted file is `influxdb-admin-token.age` in the secrets directory.
- `initialSetup`: the daemon reads both from `/run/agenix/<service>-<id>`.
- `failures`: none.

The encrypted files are not part of the example, since an evaluation only refers to them.

## alloy: a dynamic identity with a delivered secret

The [service module](../examples/alloy/service.nix) wraps nixpkgs' `services.alloy`, which runs with `DynamicUser`. Its contract names the unit `alloy.service`, a loopback bind on port 12345 and a generated Loki password, and the daemon's configuration reads the password from the claim's `path`.

The [example](../examples/alloy/default.nix) imports the agenix-rekey and systemd-credentials adapters. Its result shows:

- `installed`: agenix-rekey installs the secret root-owned at `/run/agenix/alloy-loki-password`, since a dynamic user has no account to own it.
- `loadCredential`: the unit loads it as `alloy-loki-password`.
- `passwordFile`: the daemon reads `/run/credentials/alloy.service/alloy-loki-password`.
- `failures`: none, since the unit exists and sets `DynamicUser`.

## custom-kind: a claim kind of a project's own

The [databases kind](../examples/custom-kind/databases.nix) is built with `lib.mkClaimKind`. A claim names a database, defaulting to the service's name, and is owned by the service's user, or by a role named after the service for a dynamic identity. Two claims of the same database clash.

The [example](../examples/custom-kind/default.nix) evaluates the generic module with a bare `lib.evalModules`, so it needs only `lib` and `exports`. Grafana claims one database and Vaultwarden two. Its result shows:

- `claimSet`: `grafana-main` owned by `grafana`, and `vaultwarden-main` and `vaultwarden-attachments` owned by `vaultwarden`.
- `validFailures`: none.
- `clashingFailures`: after Vaultwarden's attachments database is renamed to `grafana`, one failed check reports that `grafana-main` and `vaultwarden-attachments` both own `grafana`.
