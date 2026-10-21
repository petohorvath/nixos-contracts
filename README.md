# nixos-contracts

nixos-contracts is a Nix library that gives the services of one NixOS configuration a typed **contract**: what each service runs as, where it listens, which paths must survive and which secrets it reads. Other modules derive their configuration from contracts instead of restating it per service, such as persistence entries from mounts, secret installation from secrets, and clash checks across all services.

## Overview

A **contract** describes one service through its **identity** and its **claims**. A claim is the service's hold on one unit of something: a **bind** (a protocol, port and addresses it listens on), a **mount** (a path that must survive, under a storage **class**) or a **secret** (a credential it reads, whose value a backend supplies). A mount's or secret's owner and group follow from the service's identity unless the claim sets them. The library folds the claims of enabled contracts into one read-only **claim set** per kind, keyed by claim name, and reports clashes, such as two services listening on the same port, as failed checks. [GLOSSARY.md](GLOSSARY.md) defines these terms.

The set of claim kinds is open: binds, mounts and secrets are built with the same constructor, `lib.mkClaimKind`, that a project can use for a kind of its own.

A contract only knows its own configuration. It names no network or firewall policy, and names another node only where a secret references a secret that node holds. Fleet-wide modules can be built on top of the claim sets. It also holds none of a service's own settings: the service module keeps those and wires the daemon from the contract.

**Adapters** are opt-in NixOS modules that map one claim set onto one backend: preservation for mounts, agenix-rekey for secrets, and systemd credentials for delivering the secrets of a dynamic identity into its unit.

## Status

Pre-release. The core, the three shipped claim kinds, the three adapters and the [examples](docs/examples.md) exist with their tests. Expect breaking changes before `v0.1.0`.

## Requirements

- Nix with the `nix-command` and `flakes` experimental features, for the flake outputs.
- A Nixpkgs library with `lib.types.attrTag` and `lib.types.pathWith`. CI tests the locked `nixos-26.05` revision on `x86_64-linux` and `aarch64-linux`.

## Install

Add the flake as an input:

```nix
inputs.nixos-contracts = {
  url = "github:petohorvath/nixos-contracts";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

The flake exports:

- `nixosModules.default`: the contracts for a NixOS configuration, with their failed checks forwarded to `assertions`.
- `nixosModules.preservation`, `nixosModules.agenix-rekey` and `nixosModules.systemd-credentials`: one adapter each, also importing `nixosModules.default`. Importing an adapter turns it on; its backend's own NixOS module must be imported too.
- `modules.generic.default`: the same contracts for any module class, with failed checks left in `contracts.failures`.
- `lib.mkDefaultContract` and `lib.mkClaimKind`.

## Usage

A service module states the contract once, at default priority, and wires the daemon from it:

```nix
{ config, inputs, ... }:
let
  inherit (inputs.nixos-contracts.lib) mkDefaultContract;
  contract = config.contracts.services.chrony;
in
{
  # Usually declared once per configuration, beside the adapters.
  contracts.mounts.classes = [ "state" ];

  contracts.services.chrony = mkDefaultContract {
    enable = config.services.chrony.enable;
    identity.static.user = "chrony";
    binds.ntp = {
      protocols = "udp";
      port = 123;
    };
    mounts.state = {
      path = "/var/lib/chrony";
      class = "state";
    };
  };

  services.chrony.extraConfig = ''
    port ${toString contract.binds.ntp.port}
  '';
}
```

A node that differs overrides one field at normal priority, and the rest of the contract stays in place:

```nix
contracts.services.chrony.binds.ntp.addresses = [ "127.0.0.1" ];
```

The resolved claims are then readable in one place:

```nix
config.contracts.claimSets.mounts.chrony-state
# => { service = "chrony"; id = "state"; name = "chrony-state";
#      path = "/var/lib/chrony"; class = "state"; type = "directory";
#      mode = "0700"; owner = "chrony"; group = "chrony"; }
```

With the adapters imported, the same contract also persists `/var/lib/chrony` and installs the service's secrets:

```nix
{ inputs, ... }:
{
  imports = [
    inputs.preservation.nixosModules.default
    inputs.agenix.nixosModules.default
    inputs.agenix-rekey.nixosModules.default
    inputs.nixos-contracts.nixosModules.preservation
    inputs.nixos-contracts.nixosModules.agenix-rekey
    inputs.nixos-contracts.nixosModules.systemd-credentials
  ];

  contracts.adapters.preservation.roots.state = "/persist/state";
  age.rekey.secretsDir = ./secrets;
}
```

The [examples](docs/examples.md) show complete contracts for nixpkgs' influxdb2 and alloy, a token shared between two nodes, and a claim kind of a project's own. The [API reference](docs/api.md) describes every option, the ownership rules, the clash rules and how to define a claim kind.

## Related projects

- [RFC 189](https://github.com/NixOS/rfcs/pull/189) and nixpkgs PR [#506343](https://github.com/NixOS/nixpkgs/pull/506343) also use the name "contracts", for routing one requirement, such as a secret file, to a swappable provider. This library instead describes a whole service. If nixpkgs declares a `contracts` option, this library's option root will be renamed, as [ADR 0001](docs/adr/0001-keep-the-contracts-option-root.md) records.
- [Modular services](https://nixos.org/manual/nixos/unstable/#modular-services) describe how to run a service's process. Contracts describe its identity and claims, and the generic module is written so it could later be imported into one.

## Development

See the [development guide](docs/development.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE).
