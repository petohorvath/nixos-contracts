# API reference

This reference describes the public interface of nixos-contracts: its modules, options, claim kinds and library functions. [GLOSSARY.md](../GLOSSARY.md) defines the terms.

## Modules

| Export                    | Module class | Checks                                                      |
| ------------------------- | ------------ | ----------------------------------------------------------- |
| `nixosModules.default`    | NixOS        | Forwarded from `contracts.assertions` to NixOS `assertions` |
| `modules.generic.default` | any          | Left in `contracts.assertions` for the caller to read       |

Both import the core and the three shipped claim kinds. The generic module reads no option outside `contracts`, so it also evaluates with a bare `lib.evalModules`, which is how the core is tested.

The [adapters](#adapters) are further NixOS modules, each importing `nixosModules.default`. The generic module carries a module key, so a configuration that imports several adapters declares its options once.

To import the modules by path without the flake, apply their directory to the `nix-libnet` library. `nixos` returns the NixOS modules by export name, and `modules` the generic module:

```nix
(import "${nixos-contracts}/nixos" { libnet = nix-libnet.lib; }).default
import "${nixos-contracts}/modules" { libnet = nix-libnet.lib; }
```

## Options

```text
contracts.services.<service>.enable          writable
contracts.services.<service>.identity        writable, required
contracts.services.<service>.<kind>.<id>     writable, one claim; service, id, name read-only
contracts.claimSets.<kind>.<service>-<id>    read-only
contracts.<kind>.*                           kind settings
contracts.adapters.<adapter>.*               adapter settings
contracts.assertions                         checks over all contracts
```

### `contracts.services.<service>`

One contract per service, keyed by the service's name.

`enable` (bool, default `false`)
: Whether the contract counts. Only enabled contracts enter claim sets and clash checks. A service module usually ties it to the daemon's own enable.

`identity` (attribute tag, required)
: What the service effectively runs as, exactly one of:

- `static = { user; group ? null; }`: a named account. A null group takes the user's like-named primary group.
- `dynamic = { unit; sharedGroup ? null; }`: the user systemd allocates for `unit`, such as `"alloy.service"`, while it runs. `sharedGroup` is a static supplementary group the dynamic user shares.

The identity must match what the daemon actually becomes, which is not always the unit's `User=`: chrony's unit starts as root and the daemon drops to `chrony` itself.

A contract has no other fields. A service's own settings stay in the service module's namespace, and a helper daemon such as an exporter gets a contract of its own ([ADR 0002](adr/0002-describe-a-helper-daemon-as-its-own-service.md)).

### `contracts.claimSets.<kind>`

A read-only attribute set of every enabled contract's claims of one kind, keyed by `<service>-<id>`. Each entry is the claim as its contract holds it, with the same final values, such as the [owner and group](#ownership), so an adapter reading the claim set and a service module reading its contract agree.

### `contracts.assertions`

A list of `{ assertion; message; }`. Each claim kind adds one check per `<service>-<id>` name, failing when several claims share it, and one per pair of claims, failing when its clash rule rejects them. `nixosModules.default` forwards them to NixOS `assertions`; with the generic module the caller reads them.

## Claim kinds

Besides its kind's fields, every claim at `contracts.services.<service>.<kind>.<id>` carries three read-only fields:

- `service`: the name of its service.
- `id`: its id within the contract.
- `name`: its claim name, `<service>-<id>`.

A read-only field cannot be defined, so copying a whole claim into another contract fails; copy the kind's fields instead.

### Binds

`contracts.services.<service>.binds.<id>`: where the service accepts traffic.

| Field        | Type                                       | Default         |
| ------------ | ------------------------------------------ | --------------- |
| `proto`      | `tcp`, `udp` or `sctp`, or a list of them  | `[ "tcp" ]`     |
| `port`       | a port, or a range written `"<from>-<to>"` | required        |
| `addresses`  | an IP address or a list of them            | `[ "0.0.0.0" ]` |
| `bindpoints` | read-only `"<address>:<port>"` per address | derived         |

IPv6 addresses appear in brackets in `bindpoints`. A bind says where the service listens, never who may reach it.

Two binds clash when they share a protocol, their ports or ranges overlap, and some pair of their addresses overlaps: the addresses are equal, one is `0.0.0.0` and the other an IPv4 address, or one is `::`, which covers addresses of both families. Linux lets an IPv6 wildcard socket accept IPv4 unless the daemon sets `IPV6_V6ONLY`, so `0.0.0.0:80` and `[::]:80` clash; a daemon that listens on both with `IPV6_V6ONLY` set declares one bind with both addresses, since claims of one bind are not compared with each other. Binds of one service clash with each other too.

### Mounts

`contracts.services.<service>.mounts.<id>`: a path whose contents must survive.

| Field   | Type                               | Default     |
| ------- | ---------------------------------- | ----------- |
| `path`  | an absolute path outside the store | required    |
| `class` | one of `contracts.mounts.classes`  | required    |
| `type`  | `directory` or `file`              | `directory` |
| `mode`  | a mode string                      | `"0700"`    |
| `owner` | an account name                    | derived     |
| `group` | a group name                       | derived     |

`contracts.mounts.classes` (list of strings, default `[ ]`) declares the classes mounts may name, such as `state` or `cache`. A mount naming an undeclared class fails to evaluate. Where a class physically lives is up to an adapter.

Two mounts clash when their paths are equal, ignoring a trailing slash. Nested paths do not clash.

### Secrets

`contracts.services.<service>.secrets.<id>`: a runtime credential the service needs.

| Field        | Type                                                    | Default  |
| ------------ | ------------------------------------------------------- | -------- |
| `provenance` | exactly one of `provided = { }` or `generated = <name>` | required |
| `mode`       | a mode string                                           | `"0440"` |
| `owner`      | an account name                                         | `"root"` |
| `group`      | a group name                                            | derived  |
| `unit`       | read-only, the dynamic identity's unit, or null         | derived  |
| `path`       | read-only, where the daemon reads the secret            | derived  |

`provenance.generated` names a generator that the secret backend resolves, such as `"alnum"`; the library attaches no meaning to the name.

`path` is computed from two rules that adapters set under `contracts.secrets`:

- `location` (function of the `<service>-<id>` name, or null): where the secret backend installs a secret.
- `delivery` (function of `{ unit, name }`, or null): where a dynamic identity's unit reads a delivered secret, such as `/run/credentials/<unit>/<name>`.

For a dynamic identity with a delivery rule, `path` is the delivered location; otherwise it is the backend's location, or null when no adapter has set a rule.

Secrets clash only by sharing a name.

## Ownership

A mount's or secret's `owner` and `group` default to values derived from the service's identity:

| Identity                                     | Mount owner / group | Secret owner / group |
| -------------------------------------------- | ------------------- | -------------------- |
| `static.user = "chrony"`                     | chrony / chrony     | root / chrony        |
| `static = { user = "kea"; group = "dhcp"; }` | kea / dhcp          | root / dhcp          |
| `dynamic.unit = "alloy.service"`             | root / root         | root / root          |
| `dynamic` with `sharedGroup = "logs"`        | root / logs         | root / logs          |

An explicit `owner` or `group` on the claim wins. A mount's group otherwise falls back to the identity's group and then to its owner. A secret stays root-owned unless its claim says otherwise, so the service reads it through its group but cannot change it. A dynamic identity has no account at activation time, so nothing is owned by it; its secrets reach the daemon through a delivery adapter.

## Adapters

An adapter maps one claim set onto one backend. Importing it turns it on, and it requires its backend's NixOS module, since it defines that backend's options. Adapter checks join `contracts.assertions`.

### `nixosModules.preservation`

Adds every mount to `preservation.preserveAt` under the root mapped to its class, as a directory or a file entry with the mount's `owner` as its `user`, and its `group` and `mode`. It requires the [preservation](https://github.com/nix-community/preservation) module.

`contracts.adapters.preservation.roots` (attribute set of strings, default `{ }`)
: The `preservation.preserveAt` key of each class, such as `{ state = "/persist/state"; }`. Every class a mount uses needs a root, or an assertion fails; a declared class no mount uses needs none.

### `nixosModules.agenix-rekey`

Defines one `age.secrets.<service>-<id>` per secret claim with the claim's `owner`, `group` and `mode`. A generated secret sets `generator.script` to its generator's name. A provided secret sets `rekeyFile` to its `rekeyFiles` entry or else `<secretsDir>/<service>-<id>.age`, and evaluation fails when neither is available. The adapter also sets `contracts.secrets.location` to the installed `age.secrets.<name>.path`. It requires the [agenix](https://github.com/ryantm/agenix) and [agenix-rekey](https://github.com/oddlama/agenix-rekey) modules.

`contracts.adapters.agenixRekey.secretsDir` (path or null, default `null`)
: The directory holding provided secrets as `<service>-<id>.age`.

`contracts.adapters.agenixRekey.rekeyFiles` (attribute set of paths, default `{ }`)
: Encrypted files of provided secrets that do not follow the `secretsDir` convention, by `<service>-<id>` name.

### `nixosModules.systemd-credentials`

For every secret of a dynamic-identity service, adds `<service>-<id>:<location>` to the unit's `LoadCredential=`, and sets `contracts.secrets.delivery` so the claim's `path` becomes `/run/credentials/<unit>/<service>-<id>`. It loads from `contracts.secrets.location`, so it needs a backend adapter such as `nixosModules.agenix-rekey` beside it. It has no settings.

Its assertions fail when a dynamic-identity secret exists but no backend adapter has set a location, when a dynamic identity's `unit` does not end in `.service` or is not defined by another module, and when it does not set `DynamicUser`. The adapter's own `LoadCredential=` definition creates the unit's `systemd.services` entry, so the unit counts as defined only if it has an `ExecStart`, set directly or through `script`.

## Library

### `lib.mkDefaultContract`

`mkDefaultContract contract` marks every leaf of a contract definition with `lib.mkDefault`, so a host can override any single field at normal priority. Lists, empty attribute sets and derivations count as leaves, so a host that sets a list replaces it. A value that already carries a module property, such as `lib.mkForce`, is kept as written.

Switching a tagged field to its other tag, such as a static identity to a dynamic one, needs `lib.mkForce` on that field: a default-priority tag still counts as defined, and two tags are an error.

To use it without the flake, import the library directory with a caller-owned library:

```nix
(import "${nixos-contracts}/lib" { inherit lib; }).mkDefaultContract
```

### `lib.mkClaimKind`

`mkClaimKind { name; description; claim; clash ? null; settings ? { }; }` returns a module that adds one claim kind. Import it beside `nixosModules.default` or `modules.generic.default`.

`name`
: The kind's name: the contract field, the claim set and the settings root. `services`, `claimSets`, `assertions` and `adapters` are reserved.

`description`
: The description of the contract field.

`claim`
: A function of `{ service, identity, config }` returning the submodule of one claim, where `identity` is the contract's identity resolved to `{ user, group, unit }` (`user` null for a dynamic identity, `group` null for a dynamic identity without a shared group, `unit` null for a static identity) and `config` the top-level configuration. Inside the submodule, the module argument `name` is the claim's id and `claimName` its claim name, `<service>-<id>`. A value that follows from the identity, such as a file owner, is an option defaulting to it. The constructor declares `service`, `id` and `name` on every claim, so a claim type cannot declare options with these names.

`clash`
: The kind's clash rule: a function of two claim-set entries returning null or a reason string. Omit it when sharing a name is the only clash.

`settings`
: Option declarations placed under `contracts.<name>`.

```nix
mkClaimKind {
  name = "databases";
  description = "Databases the service owns.";
  clash = a: b: if a.database == b.database then "both own `${a.database}`" else null;
  claim =
    { service, ... }:
    { lib, name, ... }:
    {
      options.database = lib.mkOption {
        type = lib.types.str;
        default = "${service}_${name}";
        description = "The database name.";
      };
    };
}
```
