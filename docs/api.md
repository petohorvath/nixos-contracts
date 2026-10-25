# API reference

This reference describes the public interface of nixos-contracts: its modules, options, claim kinds and library functions. [GLOSSARY.md](../GLOSSARY.md) defines the terms.

## Modules

| Export                    | Module class | Checks                                                    |
| ------------------------- | ------------ | --------------------------------------------------------- |
| `nixosModules.default`    | NixOS        | Forwarded from `contracts.failures` to NixOS `assertions` |
| `modules.generic.default` | any          | Left in `contracts.failures` for the caller to read       |

Both import the core and the three shipped claim kinds. The generic module reads no option outside `contracts`, so it also evaluates with a bare `lib.evalModules`, which is how the core is tested.

The [adapters](#adapters) and [`nixosModules.cross-config`](#nixosmodulescross-config) are further NixOS modules, each importing `nixosModules.default`. The generic module carries a module key, so a configuration that imports several of them declares its options once.

To import the modules by path without the flake, apply their directory to the `nix-libnet` library. `nixos` returns the NixOS modules by export name, and `modules` the generic module:

```nix
(import "${nixos-contracts}/nixos" { libnet = nix-libnet.lib; }).default
import "${nixos-contracts}/modules" { libnet = nix-libnet.lib; }
```

### `nixosModules.cross-config`

Defaults [`contracts.node`](#contractsnode) to `crossConfig.name` and [`contracts.nodes`](#contractsnodes) to `crossConfig.nodeConfigurations`, so a configuration that takes part in [nixos-cross-config](https://github.com/petohorvath/nixos-cross-config) states its node identity and node collection once. It reads only options that nixos-cross-config's own NixOS module declares, which it requires beside it, and pulls in no flake input. It has no settings and adds no checks.

## Options

```text
contracts.services.<service>.enable          writable
contracts.services.<service>.identity        writable, required
contracts.services.<service>.<kind>.<id>     writable, one claim; service, id, name, ref read-only
contracts.claimSets.<kind>.<service>-<id>    read-only
contracts.node                               this configuration's node identity
contracts.nodes.<node>                       the node collection
contracts.lookup, contracts.resolve          read-only, functions of a reference
contracts.kinds.<kind>.*                     kind settings
contracts.adapters.<adapter>.*               adapter settings
contracts.assertions                         checks over all contracts
contracts.failures                           read-only, messages of failed checks
```

### `contracts.services.<service>`

One contract per service, keyed by the service's name.

`enable` (bool, default `false`)
: Whether the contract counts. Only enabled contracts enter claim sets and clash checks. A service module usually ties it to the daemon's own enable.

`identity` ([tag](#libtypestag), required)
: What the service effectively runs as, exactly one of:

- `static = { user; group ? null; }`: a named account. A null group takes the user's like-named primary group.
- `dynamic = { unit; sharedGroup ? null; }`: the user systemd allocates for `unit`, such as `"alloy.service"`, while it runs. `sharedGroup` is a static supplementary group the dynamic user shares.

The identity must match what the daemon actually becomes, which is not always the unit's `User=`: chrony's unit starts as root and the daemon drops to `chrony` itself.

A contract has no other fields. A service's own settings stay in the service module's namespace, and a helper daemon such as an exporter gets a contract of its own ([ADR 0009](adr/0009-hold-a-claim-on-the-contract-of-the-process-that-reads-it.md)).

Several modules may define one contract, and the module system merges their claims by id. A feature of a service, such as an output that needs a token, adds its claims to the service's contract from its own module, derived from or conditioned on its own settings. A `lib.mkIf` that wraps a whole contract and reads `contracts.*` recurses, since the set of contracts then depends on itself, while one at a claim does not.

### `contracts.claimSets.<kind>`

A read-only attribute set of every enabled contract's claims of one kind, keyed by `<service>-<id>`. Each entry is the claim as its contract holds it, with the same final values, such as the [owner and group](#ownership), so an adapter reading the claim set and a service module reading its contract agree.

### `contracts.node`

This configuration's node identity, its name in the node collection (string or null, default `null`). Every claim's `ref` names it, and while it is null a `ref` names a null node, which no lookup resolves, so a configuration whose claims are referenced, even by itself, sets it. A check fails when `contracts.nodes` is not empty and has no node of this name. [`nixosModules.cross-config`](#nixosmodulescross-config) defaults it to `crossConfig.name`.

### `contracts.nodes`

The node collection: the nodes a [reference](#references) may name, keyed by node identity, each with its evaluated `config`, such as nixos-cross-config's node collection (default `{ }`). The core resolves references against it ([ADR 0011](adr/0011-resolve-a-reference-in-the-core-from-the-node-collection.md)), reading only each node's `contracts.claimSets`, and a backend adapter reads what else it needs of a node from the same entry. A reference that names `contracts.node` resolves in this configuration itself.

### `contracts.lookup` and `contracts.resolve`

Read-only functions of a [reference](#references) that find the claim it names, of any kind ([ADR 0012](adr/0012-address-a-claim-by-an-absolute-reference.md)). `contracts.lookup reference` returns `{ claim; reason; }`: the claim-set entry and a null reason, or a null claim and why the reference names none. `contracts.resolve reference` returns the entry, or fails with ``nixos-contracts: cannot resolve `<node>:<kind>.<service>.<id>`: <reason>``. A reference names no claim when its node is null, is missing from `contracts.nodes`, imports no nixos-contracts module or has no such claim kind, or when no enabled contract on it holds the claim. A module reading another node's claim, such as the port of a backend's bind, resolves its reference rather than reading that node's contracts:

```nix
port = (config.contracts.resolve backend.bind).port;
```

### `contracts.kinds.<kind>`

The settings of one claim kind, such as `contracts.kinds.mounts.classes`, as the kind declares them. A node writes settings, such as the mount classes. A kind may also declare adapter slots, such as the secrets' `backend`, which one adapter fills and a node does not write ([ADR 0010](adr/0010-hold-adapter-data-in-slots-not-kind-settings.md)). They sit under `kinds` rather than at the root, so a kind may take any name but the contract's own fields ([ADR 0008](adr/0008-keep-kind-settings-under-contracts-kinds.md)).

### `contracts.assertions`

A list of checks, each `{ assertion; message; }`, with the message written without the library's prefix. The option follows the name and shape of NixOS `assertions`. Each claim kind adds one check per `<service>-<id>` name, failing when several claims share it, one per pair of claims, failing when its clash rule rejects them, and one per claim of a kind with a check rule, failing when the rule rejects it. Adapters add their own.

### `contracts.failures`

A read-only list of the messages of the failed checks in `contracts.assertions`, each prefixed with `nixos-contracts: `, such as ``nixos-contracts: mount class `state` has no preservation root in `contracts.adapters.preservation.roots`.`` `nixosModules.default` forwards them to NixOS `assertions`; with the generic module the caller reads them.

## Claim kinds

Besides its kind's fields, every claim at `contracts.services.<service>.<kind>.<id>` carries four read-only fields:

- `service`: the name of its service.
- `id`: its id within the contract.
- `name`: its claim name, `<service>-<id>`, the key of its claim set and of its backend's entry.
- `ref`: its [reference](#references), `{ node; kind; service; id; }`, with `contracts.node` as its node.

A read-only field cannot be defined, so copying a whole claim into another contract fails; copy the kind's fields instead.

### References

A reference names one claim by its node, kind, service and id, `{ node; kind; service; id; }`, and always names its node, so it means the same claim on every node that reads it ([ADR 0012](adr/0012-address-a-claim-by-an-absolute-reference.md)). A claim's `ref` is its reference, built from `contracts.node` alone, so a module that hands its own claim to another node, such as through a nixos-cross-config contribution, passes the `ref` rather than writing it out:

```nix
crossConfig.contributions.store.example.influxdb.writers.${config.contracts.node} =
  config.contracts.services.telegraf.secrets.token.ref;
```

A field that takes references of one kind, such as a secret's `from`, has the type [`lib.types.referenceTo`](#libtypesreferenceto) of that kind, so a reference written by hand omits `kind`, and one of another kind fails as a type error at its definition.

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

| Field   | Type                                    | Default     |
| ------- | --------------------------------------- | ----------- |
| `path`  | an absolute path outside the store      | required    |
| `class` | one of `contracts.kinds.mounts.classes` | required    |
| `type`  | `directory` or `file`                   | `directory` |
| `mode`  | a mode string                           | `"0700"`    |
| `owner` | an account name                         | derived     |
| `group` | a group name                            | derived     |

`contracts.kinds.mounts.classes` (list of strings, default `[ ]`) declares the classes mounts may name, such as `state` or `cache`. A mount naming an undeclared class fails to evaluate. Where a class physically lives is up to an adapter.

Two mounts clash when their paths are equal, ignoring a trailing slash. Nested paths do not clash.

### Secrets

`contracts.services.<service>.secrets.<id>`: a runtime credential the service needs.

| Field        | Type                                              | Default  |
| ------------ | ------------------------------------------------- | -------- |
| `mode`       | a mode string                                     | `"0440"` |
| `owner`      | an account name                                   | `"root"` |
| `group`      | a group name                                      | derived  |
| `generate`   | a generator name, or null                         | `null`   |
| `from`       | a list of references                              | `[ ]`    |
| `referenced` | read-only, each reference with its resolved claim | derived  |
| `unit`       | read-only, the dynamic identity's unit, or null   | derived  |
| `delivered`  | read-only, whether the secret is delivered        | derived  |
| `path`       | read-only, where the daemon reads the secret      | derived  |

A secret holds no value. `generate` names the generator that makes it, such as `alnum`, when the service makes its own value, and is null when a person or another party provides it. A backend adapter turns the generator into the backend's own. Anything else about the value, such as a provided secret's encrypted file, is set on the backend under the `<service>-<id>` claim name ([ADR 0006](adr/0006-mark-a-secret-the-service-generates.md)). A node turns generation off with `generate = null`, which wins when the service module wrote the claim at default priority, such as through `lib.mkDefaultContract`.

`from` references the secrets the value comes from ([ADR 0007](adr/0007-reference-another-secret-by-node-and-claim-name.md), [ADR 0012](adr/0012-address-a-claim-by-an-absolute-reference.md)), each a [reference](#references) of the type `lib.types.referenceTo "secrets"`, `{ node; service; id; }`:

```nix
# A copy of a token the `metrics` node generates
secrets.writer-token.from = [ { node = "metrics"; service = "telegraf"; id = "token"; } ];

# An htpasswd file the generator makes from two clients' passwords
secrets.htpasswd = {
  generate = "basic-auth";
  from = [
    { node = "grafana"; service = "grafana"; id = "loki-password"; }
    config.contracts.services.alloy.secrets.loki-password.ref
  ];
};
```

Without `generate`, the secret is a copy of the one secret it references: it reads the same value, owned, installed and delivered as its own claim says. With `generate`, the generator makes the value from the secrets it references. A check fails for a claim that references several secrets without a `generate`.

The core resolves each reference into `referenced`, in the order of `from`, as `{ node; kind; service; id; claim; }`: the reference with the claim-set entry of the secret it names, or a null `claim` when a check rejects the reference ([ADR 0011](adr/0011-resolve-a-reference-in-the-core-from-the-node-collection.md)). A backend adapter reads `referenced` rather than resolving references itself, and finds a resolved claim's backend entry by the claim's `name`. A check fails, once per reference, for each reason [`contracts.lookup`](#contractslookup-and-contractsresolve) returns, and for a reference to a secret with `from` of its own, which also catches two copies referencing each other. The core reads a referenced node's claim set alone and does not follow a referenced secret that references secrets itself, so references across nodes, in either direction, evaluate without cycles. `from` is a list, so a node that sets it replaces the service module's at default priority, and a module that adds references merges its list with the others.

`path` is computed from two adapter slots under `contracts.kinds.secrets`. A slot holds the data of one adapter, not a setting a node writes, and is null while no such adapter is imported ([ADR 0010](adr/0010-hold-adapter-data-in-slots-not-kind-settings.md)):

```nix
# Set by a backend adapter, such as nixosModules.agenix-rekey
contracts.kinds.secrets.backend = {
  location = name: "/run/agenix/${name}";
  generators = [ "alnum" "hex" ];
};

# Set by a delivery adapter, such as nixosModules.systemd-credentials
contracts.kinds.secrets.delivery = {
  path = { unit, name }: "/run/credentials/${unit}/${name}";
};
```

- `backend.location` (function of the `<service>-<id>` name): where the secret backend installs a secret. It must answer for any claim name, including claims of disabled contracts, which the backend does not install, since a service module may read `path` regardless.
- `backend.generators` (list of strings): the generators `generate` may name. A check fails for a claim whose `generate` is not in it, and lists the ones the backend provides. While `backend` is null, `generate` is not checked.
- `delivery.path` (function of `{ unit, name }`): where a dynamic identity's unit reads a delivered secret.

A configuration imports at most one backend adapter and one delivery adapter: a second definition of `backend` or `delivery` fails once the slot is read, naming both, unless the definitions differ in priority. A slot takes its adapter's data as one definition, so a module that replaces part of it, such as the backend's location, replaces the whole slot with `lib.mkForce`, generators included.

A secret is `delivered` when its identity is dynamic and `delivery` is set. `path` is then the delivered location; otherwise it is the backend's location. A secret has no path while `backend` is null, so reading one fails with an error naming the missing adapter, as does serialising `contracts.claimSets.secrets`, and a service module that wires a daemon from `path` needs a backend adapter imported.

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

Defines one `age.secrets.<service>-<id>` per secret claim with the claim's `owner`, `group` and `mode`, and, when the claim has a `generate`, `generator.script` set to it at default priority. For a copy, the adapter sets the entry's `rekeyFile` at default priority to the `rekeyFile` of the entry the copy references. For a generated secret, it sets `generator.dependencies` to the entries the secret references. A module sets anything else about the value on that entry, such as a provided secret's `rekeyFile`, and a `generator.script` it sets wins over the claim's, while `generator.dependencies` alone keeps it. The entry cannot remove the claim's generator with `generator = null`; set the claim's `generate = null` instead. Without a `rekeyFile`, agenix-rekey takes its default from `age.rekey.generatedSecretsDir` when the entry has a generator and from `age.rekey.secretsDir` when it has none. A check fails for a secret that ends up with no `rekeyFile`. The adapter also sets the `contracts.kinds.secrets.backend` slot: `location` to the installed `age.secrets.<name>.path`, and `generators` to the names of `age.generators`, agenix-rekey's built-in generators and any a configuration adds. It requires the [agenix](https://github.com/ryantm/agenix) and [agenix-rekey](https://github.com/oddlama/agenix-rekey) modules.

The adapter has no settings. It reads the claims a secret's references resolve to from its `referenced`, and the `age.secrets` entry of each resolved one from that node's `config` in `contracts.nodes`. It takes the names of its own entries from its own claim set alone, so entries across nodes, in either direction, evaluate without cycles. Its check fails for a reference to a secret on a node without this adapter. A copy whose reference the core rejects gets no `rekeyFile` and no second failure for it. A copy of a secret without an encrypted file fails a check that names the referenced secret, since the file is missing on that node.

A generated secret with `from` defines its entry's `generator.dependencies` as a list, so a module adding dependencies to that entry adds a list too, or adds the references to `from`; agenix-rekey's attribute-set form of `generator.dependencies` does not merge with a list.

### `nixosModules.systemd-credentials`

For every secret of a dynamic-identity service, adds `<service>-<id>:<location>` to the unit's `LoadCredential=`, and sets the `contracts.kinds.secrets.delivery` slot so the claim's `path` becomes `/run/credentials/<unit>/<service>-<id>`. It loads from the location in `contracts.kinds.secrets.backend`, so it needs a backend adapter such as `nixosModules.agenix-rekey` beside it. It has no settings.

Without a backend adapter, its `LoadCredential=` fails to evaluate with an error naming the missing adapter. Its checks fail when a dynamic identity's `unit` does not end in `.service` or is not defined by another module, and when it does not set `DynamicUser`. The adapter's own `LoadCredential=` definition creates the unit's `systemd.services` entry, so the unit counts as defined only if it has an `ExecStart`, set directly or through `script`.

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

A node switches a tagged field to its other tag, such as a static identity to a dynamic one, by writing the other tag at normal priority. A [tag](#libtypestag) settles by priority, and the service module's tag is at default priority, so the node's tag wins and every leaf of the service module's tag is dropped:

```nix
# Service module
contracts.services.chrony = mkDefaultContract {
  identity.static.user = "chrony";
};

# Node: the identity is { dynamic = { unit = "chronyd.service"; sharedGroup = null; }; }
contracts.services.chrony.identity.dynamic.unit = "chronyd.service";
```

A node that writes a leaf of the service module's own tag, such as `identity.static.group`, keeps the tag's other leaves.

To use it without the flake, import the library directory with a caller-owned library:

```nix
(import "${nixos-contracts}/lib" { inherit lib; }).mkDefaultContract
```

### `lib.mkClaimKind`

`mkClaimKind { name; description; claim; clash ? null; check ? null; settings ? { }; }` returns a module that adds one claim kind. Import it beside `nixosModules.default` or `modules.generic.default`.

`name`
: The kind's name: the contract field, the claim set and the settings root. The contract's own fields `enable` and `identity` are reserved.

`description`
: The description of the contract field.

`claim`
: A function of `{ service, identity, config }` returning the submodule of one claim, where `identity` is the contract's identity resolved to `{ user, group, unit }` (`user` null for a dynamic identity, `group` null for a dynamic identity without a shared group, `unit` null for a static identity) and `config` the top-level configuration. Inside the submodule, the module argument `name` is the claim's id and `claimName` its claim name, `<service>-<id>`. A value that follows from the identity, such as a file owner, is an option defaulting to it. The constructor declares `service`, `id`, `name` and `ref` on every claim, so a claim type cannot declare options with these names.

`clash`
: The kind's clash rule: a function of two claim-set entries returning null or a reason string. Omit it when sharing a name is the only clash.

`check`
: The kind's check rule: a function of `{ identity, claim, settings, config }`, with the same resolved `identity`, a claim-set entry, the kind's settings at `contracts.kinds.<name>` and the top-level configuration, returning null, a reason string or a list of them. Only claims of enabled contracts are checked, and each reason reads ``nixos-contracts: <kind> claim `<service>-<id>`: <reason>.`` in `contracts.failures`.

`settings`
: Option declarations placed under `contracts.kinds.<name>`.

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

### `lib.types.reference`

The option type of a [reference](#references) of any kind, `{ node; kind; service; id; }`, all required: `node` a node identity, or null for the `ref` of a claim whose configuration has none, and the others strings. A claim's `ref` has this shape.

### `lib.types.referenceTo`

`referenceTo kind` is the option type of a [reference](#references) of one kind, `{ node; service; id; }`, whose `kind` defaults to `kind` and accepts no other. A secret's `from` takes `referenceTo "secrets"`. A service module whose own settings carry a reference, such as one a nixos-cross-config contribution delivers, types the setting with it, so the value it receives is already a reference of the kind it uses:

```nix
options.example.influxdb.writers = lib.mkOption {
  type = lib.types.attrsOf (contractsLib.types.referenceTo "secrets");
  default = { };
};

config.contracts.services.influxdb.secrets = lib.mapAttrs' (
  writer: token: lib.nameValuePair "writer-${writer}" { from = [ token ]; }
) config.example.influxdb.writers;
```

### `lib.types.tag`

`tag tags` is the option type of a field that holds exactly one of several cases. It takes the same tag declarations as `lib.types.attrTag`, an attribute set of options, and settles definitions that name different tags by priority ([ADR 0013](adr/0013-settle-a-tag-by-the-priority-of-its-definitions.md)). A contract's `identity` has this type, and a project's claim kind uses it for its own tags, so a node switches them as it switches an identity.

The tag rule:

- A definition counts at the priority of its strongest leaf. Each leaf has the priority of its innermost `lib.mkOverride`, including `lib.mkDefault` and `lib.mkForce`, or the normal priority when nothing wraps it.
- `lib.mkIf` passes the priority of its content through when its condition is true. A false condition contributes no priority, so a definition with no leaf left gives way to any other tag.
- `lib.mkMerge` counts at the strongest of its contents.
- A tag counts at its strongest definition. The strongest tag keeps its definitions, which merge as in `lib.types.attrTag`, and the other tags' definitions are dropped.
- Two different tags at the same priority fail with an error naming the option, as in `lib.types.attrTag`.
- `lib.mkForce` or `lib.mkOverride` on the whole field still drops the weaker definitions before the tags settle.

A claim type's field, a service module's default through `mkDefaultContract`, and a node's switch:

```nix
options.target = lib.mkOption {
  type = contractsLib.types.tag {
    local = lib.mkOption { type = lib.types.str; };
    remote = lib.mkOption { type = lib.types.str; };
  };
};

# Service module
contracts.services.app = mkDefaultContract { backups.state.target.local = "/var/backup/app"; };

# Node: the target is { remote = "backup.example"; }
contracts.services.app.backups.state.target.remote = "backup.example";
```
