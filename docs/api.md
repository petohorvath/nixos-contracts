# API reference

This reference describes the public interface of nixos-contracts: its modules, options, claim kinds and library functions. [GLOSSARY.md](../GLOSSARY.md) defines the terms.

## Modules

| Export                    | Module class | Checks                                                    |
| ------------------------- | ------------ | --------------------------------------------------------- |
| `nixosModules.default`    | NixOS        | Forwarded from `contracts.failures` to NixOS `assertions` |
| `modules.generic.default` | any          | Left in `contracts.failures` for the caller to read       |

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
contracts.failures                           read-only, messages of failed checks
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

A list of checks, each `{ assertion; message; }`, with the message written without the library's prefix. The option follows the name and shape of NixOS `assertions`. Each claim kind adds one check per `<service>-<id>` name, failing when several claims share it, one per pair of claims, failing when its clash rule rejects them, and one per claim of a kind with a check rule, failing when the rule rejects it. Adapters add their own.

### `contracts.failures`

A read-only list of the messages of the failed checks in `contracts.assertions`, each prefixed with `nixos-contracts: `, such as ``nixos-contracts: mount class `state` has no preservation root in `contracts.adapters.preservation.roots`.`` `nixosModules.default` forwards them to NixOS `assertions`; with the generic module the caller reads them.

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
| `protocols`  | `tcp`, `udp` or `sctp`, or a list of them  | `[ "tcp" ]`     |
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

| Field       | Type                                            | Default  |
| ----------- | ----------------------------------------------- | -------- |
| `mode`      | a mode string                                   | `"0440"` |
| `owner`     | an account name                                 | `"root"` |
| `group`     | a group name                                    | derived  |
| `generate`  | a generator name, or null                       | `null`   |
| `from`      | a list of references                            | `[ ]`    |
| `unit`      | read-only, the dynamic identity's unit, or null | derived  |
| `delivered` | read-only, whether the secret is delivered      | derived  |
| `path`      | read-only, where the daemon reads the secret    | derived  |

A secret holds no value. `generate` names the generator that makes it, such as `alnum`, when the service makes its own value, and is null when a person or another party provides it. A backend adapter turns the generator into the backend's own. Anything else about the value, such as a provided secret's encrypted file, is set on the backend under the `<service>-<id>` claim name ([ADR 0006](adr/0006-mark-a-secret-the-service-generates.md)). A node turns generation off with `generate = null`, which wins when the service module wrote the claim at default priority, such as through `lib.mkDefaultContract`.

`from` references the secrets the value comes from ([ADR 0007](adr/0007-reference-another-secret-by-node-and-claim-name.md)). A reference is a claim name, for a secret of this node, or `{ node; name; }`, for one another node holds:

```nix
# A copy of a token the `metrics` node generates
secrets.writer-token.from = [ { node = "metrics"; name = "telegraf-token"; } ];

# An htpasswd file the generator makes from two clients' passwords
secrets.htpasswd = {
  generate = "basic-auth";
  from = [ { node = "grafana"; name = "grafana-loki-password"; } "alloy-loki-password" ];
};
```

Without `generate`, the secret is a copy of the one secret it references: it reads the same value, owned, installed and delivered as its own claim says. With `generate`, the generator makes the value from the secrets it references. A backend adapter resolves the references, and its checks reject one it cannot resolve. A check fails for a claim that references several secrets without a `generate`. `from` is a list, so a node that sets it replaces the service module's at default priority, and a module that adds references merges its list with the others.

`contracts.secrets.generators` (list of strings, or null; default null) is the vocabulary `generate` may name. A backend adapter sets it to the generators its backend provides. A check fails for a claim whose `generate` is not in it; while it is null, no backend adapter is imported and `generate` is not checked.

`path` is computed from two rules that adapters set under `contracts.secrets`:

- `location` (function of the `<service>-<id>` name): where the secret backend installs a secret. It must answer for any claim name, including claims of disabled contracts, which the backend does not install, since a service module may read `path` regardless. Without a backend adapter, it fails with an error naming the missing adapter.
- `delivery` (function of `{ unit, name }`, or null): where a dynamic identity's unit reads a delivered secret, such as `/run/credentials/<unit>/<name>`.

A secret is `delivered` when its identity is dynamic and a delivery rule is set. `path` is then the delivered location; otherwise it is the backend's location. A secret has no path without a backend adapter, so reading one fails, as does serialising `contracts.claimSets.secrets`, and a service module that wires a daemon from `path` needs one imported.

A dynamic identity's user exists only while its unit runs, so it reads a secret the backend installs only through its `sharedGroup`. A check fails for a dynamic identity's secret that no adapter delivers, unless the secret's `group` is the identity's `sharedGroup`. Mode bits are not checked.

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

An adapter maps one claim set onto one backend. Importing it turns it on, and it requires its backend's NixOS module, since it defines that backend's options. Adapter checks join `contracts.assertions`, and their failures `contracts.failures`.

### `nixosModules.preservation`

Adds every mount to `preservation.preserveAt` under the root mapped to its class, as a directory or a file entry with the mount's `owner` as its `user`, and its `group` and `mode`. It requires the [preservation](https://github.com/nix-community/preservation) module.

`contracts.adapters.preservation.roots` (attribute set of strings, default `{ }`)
: The `preservation.preserveAt` key of each class, such as `{ state = "/persist/state"; }`. Every class a mount uses needs a root, or an assertion fails; a declared class no mount uses needs none.

### `nixosModules.agenix-rekey`

Defines one `age.secrets.<service>-<id>` per secret claim with the claim's `owner`, `group` and `mode`, and, when the claim has a `generate`, `generator.script` set to it at default priority. For a copy, the adapter sets the entry's `rekeyFile` at default priority to the `rekeyFile` of the entry the copy references. For a generated secret, it sets `generator.dependencies` to the entries the secret references. A module sets anything else about the value on that entry, such as a provided secret's `rekeyFile`, and a `generator.script` it sets wins over the claim's, while `generator.dependencies` alone keeps it. The entry cannot remove the claim's generator with `generator = null`; set the claim's `generate = null` instead. Without a `rekeyFile`, agenix-rekey takes its default from `age.rekey.generatedSecretsDir` when the entry has a generator and from `age.rekey.secretsDir` when it has none. A check fails for a secret that ends up with no `rekeyFile`. The adapter also sets `contracts.secrets.location` to the installed `age.secrets.<name>.path`, and `contracts.secrets.generators` to the names of `age.generators`, agenix-rekey's built-in generators and any a configuration adds. It requires the [agenix](https://github.com/ryantm/agenix) and [agenix-rekey](https://github.com/oddlama/agenix-rekey) modules.

`contracts.adapters.agenix-rekey.nodes` (lazy attribute set, default `{ }`)
: The nodes a reference may name, each with its evaluated `config`, such as nixos-cross-config's node collection. A reference without a node reads this configuration.

The adapter reads a referenced node's claim set before its `age.secrets`, takes the names of its own entries from its own claim set alone, and does not follow a referenced secret that references secrets itself, so references across nodes, in either direction, evaluate without cycles. Its checks fail for a reference to a node missing from `nodes`, to a name that is no secret claim of an enabled contract on that node, to a secret with `from` of its own, which also catches two copies referencing each other, and to a secret on a node without this adapter. A copy whose reference fails its check gets no `rekeyFile` and no second failure for it.

A generated secret with `from` defines its entry's `generator.dependencies` as a list, so a module adding dependencies to that entry adds a list too, or adds the references to `from`; agenix-rekey's attribute-set form of `generator.dependencies` does not merge with a list.

### `nixosModules.systemd-credentials`

For every secret of a dynamic-identity service, adds `<service>-<id>:<location>` to the unit's `LoadCredential=`, and sets `contracts.secrets.delivery` so the claim's `path` becomes `/run/credentials/<unit>/<service>-<id>`. It loads from `contracts.secrets.location`, so it needs a backend adapter such as `nixosModules.agenix-rekey` beside it. It has no settings.

Without a backend adapter, its `LoadCredential=` fails to evaluate with the error of `contracts.secrets.location`. Its checks fail when a dynamic identity's `unit` does not end in `.service` or is not defined by another module, and when it does not set `DynamicUser`. The adapter's own `LoadCredential=` definition creates the unit's `systemd.services` entry, so the unit counts as defined only if it has an `ExecStart`, set directly or through `script`.

## Library

### `lib.mkDefaultContract`

`mkDefaultContract contract` marks every leaf of a contract definition with `lib.mkDefault`, so a node can override any single field at normal priority. Lists, empty attribute sets and derivations count as leaves, so a node that sets a list replaces it. A value that already carries a module property, such as `lib.mkForce`, is kept as written, except `lib.mkIf` and `lib.mkMerge`, whose contents are marked too.

A service module can therefore hold a claim on a condition, and a node can still override one field of it:

```nix
# Service module
contracts.services.nginx = mkDefaultContract {
  inherit (config.services.nginx) enable;
  identity.static.user = "nginx";
  binds.http.port = 80;
  binds.proxyHttp = lib.mkIf cfg.proxyProtocol.enable { port = 8080; };
};

# Node
contracts.services.nginx.binds.proxyHttp.port = 9080;
```

While the condition is false, the service module defines no `proxyHttp` claim, but a node's override still does: the port alone above makes a complete bind, and an override of a field that is not required, such as `addresses`, fails for the missing `port`. A node guards such an override with the service module's condition.

Switching a tagged field to its other tag, such as a static identity to a dynamic one, needs `lib.mkForce` on that field: a default-priority tag still counts as defined, and two tags are an error.

To use it without the flake, import the library directory with a caller-owned library:

```nix
(import "${nixos-contracts}/lib" { inherit lib; }).mkDefaultContract
```

### `lib.mkClaimKind`

`mkClaimKind { name; description; claim; clash ? null; check ? null; settings ? { }; }` returns a module that adds one claim kind. Import it beside `nixosModules.default` or `modules.generic.default`.

`name`
: The kind's name: the contract field, the claim set and the settings root. `services`, `claimSets`, `assertions`, `failures` and `adapters` are reserved.

`description`
: The description of the contract field.

`claim`
: A function of `{ service, identity, config }` returning the submodule of one claim, where `identity` is the contract's identity resolved to `{ user, group, unit }` (`user` null for a dynamic identity, `group` null for a dynamic identity without a shared group, `unit` null for a static identity) and `config` the top-level configuration. Inside the submodule, the module argument `name` is the claim's id and `claimName` its claim name, `<service>-<id>`. A value that follows from the identity, such as a file owner, is an option defaulting to it. The constructor declares `service`, `id` and `name` on every claim, so a claim type cannot declare options with these names.

`clash`
: The kind's clash rule: a function of two claim-set entries returning null or a reason string. Omit it when sharing a name is the only clash.

`check`
: The kind's check rule: a function of `{ identity, claim, settings }`, with the same resolved `identity`, a claim-set entry and the kind's settings at `contracts.<name>`, returning null or a reason string. Only claims of enabled contracts are checked, and a rejected claim reads ``nixos-contracts: <kind> claim `<service>-<id>`: <reason>.`` in `contracts.failures`.

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
