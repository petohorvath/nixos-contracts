# API reference

This reference describes the public interface of nixos-contracts: its modules, options, claim kinds and library functions. [GLOSSARY.md](../GLOSSARY.md) defines the terms.

## Modules

| Export                    | Module class | Checks                                                    |
| ------------------------- | ------------ | --------------------------------------------------------- |
| `nixosModules.default`    | NixOS        | Forwarded from `contracts.failures` to NixOS `assertions` |
| `modules.generic.default` | any          | Left in `contracts.failures` for the caller to read       |

Both import the core and the three shipped claim kinds. The generic module reads no option outside `contracts`, so it also evaluates with a bare `lib.evalModules`, which is how the core is tested.

The [adapters](#adapters) are further NixOS modules, each importing `nixosModules.default`. The generic module carries a module key, so a configuration that imports several of them declares its options once.

To import the modules by path without the flake, apply their directory to the `nix-libnet` library. `nixos` returns the NixOS modules by export name, and `modules` the generic module:

```nix
(import "${nixos-contracts}/nixos" { libnet = nix-libnet.lib; }).default
import "${nixos-contracts}/modules" { libnet = nix-libnet.lib; }
```

### Node identity and collection from nixos-cross-config

nixos-contracts ships no module for a fleet's node collection, so a fleet sets [`contracts.node`](#contractsnode) and [`contracts.nodes`](#contractsnodes) itself, from whatever carries its nodes. A configuration that takes part in [nixos-cross-config](https://github.com/petohorvath/nixos-cross-config) takes both from there:

```nix
contracts = {
  node = config.crossConfig.name;
  nodes = config.crossConfig.nodeConfigurations;
};
```

## Options

```text
contracts.services.<service>.enable          writable
contracts.services.<service>.identity        writable, required
contracts.services.<service>.<kind>.<id>     writable, one claim; service, id, name, ref read-only
contracts.claimSets.<kind>.<service>.<id>    read-only
contracts.node                               this configuration's node identity, required
contracts.nodes.<node>                       the node collection
contracts.resolve                            read-only, function of a reference
contracts.resolveService                     read-only, function of a node, kind and service
contracts.kinds.<kind>.*                     kind settings
contracts.adapters.<adapter>.*               adapter settings
contracts.assertions                         checks over all contracts
contracts.failures                           read-only, messages of failed checks
```

### `contracts.services.<service>`

One contract per service, keyed by the service's name, which is a [name](#names).

`enable` (bool, default `false`)
: Whether the contract counts. Only enabled contracts enter claim sets and clash checks. A service module usually ties it to the daemon's own enable.

`identity` ([tag](#libtypestag), required)
: What the service effectively runs as, exactly one of:

- `static = { user; group ? null; }`: a named account. A null group takes the user's like-named primary group.
- `dynamic = { unit; sharedGroup ? null; }`: the user systemd allocates for `unit`, such as `"alloy.service"`, while it runs. `sharedGroup` is a static supplementary group the dynamic user shares.

The identity must match what the daemon actually becomes, which is not always the unit's `User=`: chrony's unit starts as root and the daemon drops to `chrony` itself.

A contract has no other fields. A service's own settings stay in the service module's namespace, and a helper daemon such as an exporter gets a contract of its own ([ADR 0003](adr/0003-hold-a-claim-on-the-contract-of-the-process-that-reads-it.md)).

Several modules may define one contract, and the module system merges their claims by id. A feature of a service, such as an output that needs a token, adds its claims to the service's contract from its own module, derived from or conditioned on its own settings. A `lib.mkIf` that wraps a whole contract and reads `contracts.*` recurses, since the set of contracts then depends on itself, while one at a claim does not.

### `contracts.claimSets.<kind>`

A read-only attribute set of every enabled contract's claims of one kind, nested by service and id, as `contracts.claimSets.<kind>.<service>.<id>` ([ADR 0009](adr/0009-name-a-claim-by-node-kind-service-and-id.md)). Each entry is the claim as its contract holds it, with the same final values, such as the [owner and group](#ownership), so an adapter reading the claim set and a service module reading its contract agree. A service without claims of the kind has no entry. An adapter that needs a list flattens the claim set, by service and then id.

### `contracts.node`

This configuration's node identity, its name in the node collection (a [name](#names), required). Every claim's `ref` and `name` include it. A configuration without one fails to evaluate its checks, with an error naming `contracts.node`, whether or not it uses references ([ADR 0010](adr/0010-require-a-node-identity.md)). A configuration outside a fleet still names itself, such as by its host name. A check fails when `contracts.nodes` is not empty and has no node of this name. A fleet sets it, for example [from nixos-cross-config](#node-identity-and-collection-from-nixos-cross-config).

### `contracts.nodes`

The node collection: the nodes a [reference](#references) may name, keyed by node identity, each with its evaluated `config`, such as nixos-cross-config's node collection (default `{ }`). The core resolves references against it ([ADR 0011](adr/0011-resolve-and-check-a-reference-in-the-core.md)), reading only each node's `contracts.claimSets`, and for [`contracts.resolveService`](#contractsresolveservice) whether the service's contract is enabled. A backend adapter reads what else it needs of a node from the same entry. A reference that names `contracts.node` resolves in this configuration itself.

### `contracts.resolve`

A read-only function of a [reference](#references) that finds the claim it names, of any kind ([ADR 0008](adr/0008-address-a-claim-by-an-absolute-reference.md), [ADR 0011](adr/0011-resolve-and-check-a-reference-in-the-core.md)). `contracts.resolve reference` returns `{ claim; config; reason; }`: the entry at `claimSets.<kind>.<service>.<id>` of the node the reference names, that node's evaluated configuration (this configuration for a reference that names `contracts.node`) and a null reason, or the reason the reference names no claim. A reference names no claim when its node identity, kind name, service name or id breaks its [name rule](#names), giving a reason such as ``service name `web_proxy` may contain only lowercase letters, digits and hyphens``, when its node is missing from `contracts.nodes`, imports no nixos-contracts module or has no such claim kind, or when no enabled contract on it holds the claim. Reading `claim` or `config` while `reason` is set fails with ``nixos-contracts: cannot resolve `<node>:<kind>.<service>.<id>`: <reason>``; reading `reason` never fails, so a check reads the reason and a module the claim from the same result. A value that is not an attribute set, or that misses one of `node`, `kind`, `service` and `id` or holds any other field, cannot be named, so resolving it fails with a message naming the reference, such as ``nixos-contracts: reference `metrics:?.telegraf.token` has no `kind` ``. A module reading another node's claim, such as the port of a backend's bind, resolves its reference rather than reading that node's contracts:

```nix
port = (config.contracts.resolve backend.bind).claim.port;
```

### `contracts.resolveService`

A read-only function that finds every claim of one kind that one service holds on a node, such as a firewall reading all of a backend's binds ([ADR 0012](adr/0012-resolve-a-services-claims-beside-a-reference.md)). `contracts.resolveService { node; kind; service; }` returns `{ claims; config; reason; }`: the entries at `claimSets.<kind>.<service>` of the node, keyed by id, that node's evaluated configuration (this configuration for a service of `contracts.node`) and a null reason, or the reason the service has none. An enabled contract without claims of the kind gives `claims = { }`. The selection's names follow their [name rules](#names), and its node and kind give the reasons of [`contracts.resolve`](#contractsresolve), and a service whose contract is missing or disabled gives ``no enabled contract on `<node>` describes service `<service>` ``. Reading `claims` or `config` while `reason` is set fails with ``nixos-contracts: cannot resolve service `<node>:<kind>.<service>`: <reason>``; reading `reason` never fails. A value that is not an attribute set, or that misses one of `node`, `kind` and `service` or holds any other field, such as a reference's `id`, fails on resolving with a message naming it, such as ``nixos-contracts: service `backend:?.web` has no `kind` ``. It reads the node's contracts alone, so two nodes that each resolve a service of the other evaluate without cycles, as long as neither keys its own claims by what it resolved:

```nix
ports = lib.mapAttrsToList (_: bind: bind.port) (config.contracts.resolveService {
  node = "backend";
  kind = "binds";
  service = "web";
}).claims;
```

### `contracts.kinds.<kind>`

The settings of one claim kind, such as `contracts.kinds.mounts.classes`, as the kind declares them. A node writes settings, such as the mount classes. A kind may also declare adapter slots, such as the secrets' `backend`, which one adapter fills and a node does not write ([ADR 0005](adr/0005-hold-adapter-data-in-slots-not-kind-settings.md)). They sit under `kinds` rather than at the root, so a kind may take any name but the contract's own fields ([ADR 0004](adr/0004-keep-kind-settings-under-contracts-kinds.md)).

### `contracts.assertions`

A list of checks, each `{ assertion; message; }`, with the message written without the library's prefix. The option follows the name and shape of NixOS `assertions`. Each claim kind adds one check per pair of claims, failing when its clash rule rejects them, and one per claim of a kind with a check rule, failing when the rule rejects it. Two claims never clash by their names alone, since no two claims of a node share a service and id. Adapters add their own.

### `contracts.failures`

A read-only list of the messages of the failed checks in `contracts.assertions`, each prefixed with `nixos-contracts: `, such as ``nixos-contracts: mount class `state` has no preservation root in `contracts.adapters.preservation.roots`.`` `nixosModules.default` forwards them to NixOS `assertions`; with the generic module the caller reads them.

## Claim kinds

Besides its kind's fields, every claim at `contracts.services.<service>.<kind>.<id>` carries four read-only fields:

- `service`: the name of its service.
- `id`: its id within the contract.
- `name`: its claim name, `<node>_<kind>_<service>_<id>`.
- `ref`: its [reference](#references), `{ node; kind; service; id; }`, with `contracts.node` as its node.

A read-only field cannot be defined, so copying a whole claim into another contract fails; copy the kind's fields instead.

### Names

A claim's kind, `service` and `id` place it within its node, and its `name` names it across the node collection ([ADR 0009](adr/0009-name-a-claim-by-node-kind-service-and-id.md)):

```nix
# The claim contracts.services.influxdb.secrets.admin-token, on the node beta-influxdb
service = "influxdb";
id = "admin-token";
name = "beta-influxdb_secrets_influxdb_admin-token";
```

Node identities, kind names and service names are non-empty, and made of lowercase letters, digits and hyphens only. Claim ids may also contain `_`, such as `ssh_host_ed25519_key`, so a receiver can give a copy the sent claim's `name` as its id ([ADR 0009](adr/0009-name-a-claim-by-node-kind-service-and-id.md)). Any other name, such as the service name `web_proxy` or the claim id `Host-Key`, fails at evaluation with an error naming it and the allowed characters, such as ``nixos-contracts: secrets claim id `Host-Key` of service `openssh` may contain only lowercase letters, digits, hyphens and `_`.`` No node identity, kind name or service name contains `_`, so the first `_` of a backend name `<service>_<id>` ends the service, and the first three of a claim `name` end the node, the kind and the service. Both names therefore stay unique however many `_` an id holds:

- A backend adapter names its entry for a claim `<service>_<id>`, such as `age.secrets.influxdb_admin-token`, which [`lib.backendNameOf`](#libbackendnameof) builds.
- A claim's `name` joins its node identity, kind, service and id with `_`, so a value built from several nodes' claims, such as an htpasswd user name, takes `name` and never collides, even with a claim of another kind.
- Check messages name a claim `<service>.<id>`, such as ``nixos-contracts: secrets claim `influxdb.admin-token`: …``, and a reference `<node>:<kind>.<service>.<id>`, such as `metrics:secrets.telegraf.token`, which [`lib.labels`](#liblabels) builds.

### References

A reference names one claim by its node, kind, service and id, `{ node; kind; service; id; }`, and always names its node, so it means the same claim on every node that reads it ([ADR 0008](adr/0008-address-a-claim-by-an-absolute-reference.md)). A claim's `ref` is its reference, built from `contracts.node` alone, so a module that names its own claim in another of its settings passes the `ref` rather than writing it out:

```nix
secrets.htpasswd.value.generated.from = [ config.contracts.services.alloy.secrets.loki-password.ref ];
```

nixos-contracts carries no reference between nodes. A node relates to another through references carried in shared data the fleet chooses, as [Relating nodes](#relating-nodes) shows, so no node writes into another node's options.

A field that takes references of one kind, such as a secret's `value.copied`, has the type [`lib.types.referenceTo`](#libtypesreferenceto) of that kind, so a reference written by hand omits `kind`, and one of another kind fails as a type error at its definition. A reference whose node identity, kind name, service name or id breaks its [name rule](#names) names no claim, so it fails as a type error at its definition too.

A reference built in code, outside a typed field, comes from [`lib.mkReference`](#libmkreference), which takes the kind first and checks the reference as a typed field does:

```nix
value.copied = contractsLib.mkReference "secrets" { node = "metrics"; service = "telegraf"; id = "token"; };
```

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

| Field         | Type                                                            | Default  |
| ------------- | --------------------------------------------------------------- | -------- |
| `mode`        | a mode string                                                   | `"0440"` |
| `owner`       | an account name                                                 | `"root"` |
| `group`       | a group name                                                    | derived  |
| `value`       | a [tag](#libtypestag): `provided`, `generated` or `copied`      | provided |
| `generator`   | read-only, a `generated` value's generator and sources, or null | derived  |
| `copyOf`      | read-only, a `copied` value's source, or null                   | derived  |
| `unit`        | the unit the secret is delivered to, or null                    | derived  |
| `delivered`   | read-only, whether the secret names a `unit`                    | derived  |
| `backendPath` | read-only, where the backend installs the secret                | derived  |
| `path`        | read-only, where the daemon reads the secret                    | derived  |

A secret holds no value. Its `value` says where the value comes from, as one of three tags ([ADR 0006](adr/0006-settle-a-tag-by-the-priority-of-its-definitions.md), [ADR 0007](adr/0007-say-where-a-secrets-value-comes-from-on-the-secret.md)):

- `provided = { }`, the default: a person or another party provides it. `provided` takes no options.
- `generated = { generator; from; }`: the named generator, such as `alnum`, makes the value from the secrets `from` references, in order. `from` defaults to `[ ]`, for a generator that reads no other secret. A backend adapter turns the generator into the backend's own.
- `copied = <reference>`: the secret is a copy of the one secret the reference names. It reads the same value, owned, installed and delivered as its own claim says.

A secret's `generator` and `copyOf` tell a reader where its value comes from, so a backend adapter reads them rather than the tags ([ADR 0016](adr/0016-hold-a-secrets-sources-on-its-copy-and-its-generator.md)). `generator` is `{ name; sources; }` for a `generated` value, the generator it names and a source for each reference of its `from`, in order, and null for a `provided` or `copied` value. `copyOf` is the source of a `copied` value, and null for a `provided` or `generated` one.

```nix
secrets.admin-password.value.generated.generator = "alnum";

# A copy of a token the `metrics` node generates
secrets.writer-token.value.copied = { node = "metrics"; service = "telegraf"; id = "token"; };

# An htpasswd file the generator makes from two clients' passwords
secrets.htpasswd.value.generated = {
  generator = "basic-auth";
  from = [
    { node = "grafana"; service = "grafana"; id = "loki-password"; }
    config.contracts.services.alloy.secrets.loki-password.ref
  ];
};
```

Anything else about the value, such as a provided secret's encrypted file, is set on the backend under the claim's [backend name](#names) `<service>_<id>` ([ADR 0007](adr/0007-say-where-a-secrets-value-comes-from-on-the-secret.md)). `value` settles by priority, so a node switches a module's tag by writing another at normal priority, which wins when the service module wrote the claim at default priority, such as through `lib.mkDefaultContract`: `value.provided = { };` makes a module's generated secret provided, and `value.copied = <reference>;` makes it a copy. Two tags written at one priority fail, naming the option, and a misspelt tag, such as `value.generate`, fails as a type error that lists the accepted tags.

The references of `copied` and `generated.from` are [references](#references) of the type `lib.types.referenceTo "secrets"`, `{ node; service; id; }` ([ADR 0008](adr/0008-address-a-claim-by-an-absolute-reference.md)), so a reference of another kind fails as a type error at its definition. Each names `contracts.node` or a node in `contracts.nodes`. A value takes either one reference or a generator, so a copy of several secrets cannot be written.

The core resolves each reference of `copied` and `generated.from` into a source, `{ reference; reason; }`: the reference as written, and a null reason, or why the secret cannot read the secret it names ([ADR 0011](adr/0011-resolve-and-check-a-reference-in-the-core.md), [ADR 0016](adr/0016-hold-a-secrets-sources-on-its-copy-and-its-generator.md)). A reason is one [`contracts.resolve`](#contractsresolve) returns, prefixed with the reference, such as ``it references `metrics:secrets.telegraf.token`: node `metrics` is not in `contracts.nodes` ``, or one of the value's rules: a reference to a copy, which also catches two copies referencing each other, and a `from` reference to a secret generated from others itself. The secret's check fails once for each reason. A source holds no claim: a backend adapter skips a source whose `reason` is set, and resolves the `reference` of any other with `contracts.resolve` for the claim and the configuration of its node, and finds the claim's backend entry by the reference's `service` and `id`. A copy may reference a secret generated from others, such as an htpasswd, and reads its value; a generator reads only secrets that reference none. The core reads a referenced node's claim set alone and does not follow a referenced secret's own references, so references across nodes, in either direction, evaluate without cycles. `generated.from` is a list, so a node that sets it replaces the service module's at default priority, and a module that adds references merges its list with the others. A node that adds references to a module's generated secret writes `value.generated.from` alone, which keeps the module's generator.

`path` is computed from two adapter slots under `contracts.kinds.secrets`. A slot holds the data of one adapter, not a setting a node writes, and is null while no such adapter is imported ([ADR 0005](adr/0005-hold-adapter-data-in-slots-not-kind-settings.md)):

```nix
# Set by a backend adapter, such as nixosModules.agenix-rekey
contracts.kinds.secrets.backend = {
  path = { service, id }: "/run/agenix/${service}_${id}";
  generators = [ "alnum" "hex" ];
};

# Set by a delivery adapter, such as nixosModules.systemd-credentials
contracts.kinds.secrets.delivery = {
  path = { unit, service, id }: "/run/credentials/${unit}/${service}_${id}";
};
```

- `backend.path` (function of `{ service, id }`): where the secret backend installs a secret. It must answer for any service and id, including those of claims of disabled contracts, which the backend does not install, since a service module may read a claim's `path` or `backendPath` regardless.
- `backend.generators` (list of strings): the generators a `generated` value may name. A check fails for a claim whose generator is not in it, and lists the ones the backend provides. While `backend` is null, the generator is not checked.
- `delivery.path` (function of `{ unit, service, id }`): where a unit reads a delivered secret, given the secret's `unit`, service and id.

A configuration imports at most one backend adapter and one delivery adapter: a second definition of `backend` or `delivery` fails once the slot is read, naming both, unless the definitions differ in priority. A slot takes its adapter's data as one definition, so a module that replaces part of it, such as the backend's `path`, replaces the whole slot with `lib.mkForce`, generators included.

A secret names the unit it is delivered to in `unit` ([ADR 0014](adr/0014-name-the-unit-a-secret-is-delivered-to-on-the-secret.md)). Its default is a dynamic identity's unit, or null for a static identity. A static identity is an account that may run several units, and a delivered secret's `path` differs per unit, so the module that hands `path` to the daemon names the one unit that reads it:

```nix
contracts.services.grafana = contractsLib.mkDefaultContract {
  identity.static.user = "grafana";
  secrets.secret-key.unit = "grafana.service";
};

# A dynamic identity's secret read through its sharedGroup instead
contracts.services.alloy.secrets.loki-password.unit = null;
```

A secret is `delivered` when its `unit` is not null, whichever adapters are imported. Its `path` is then what `delivery.path` answers for its unit, service and id; otherwise it is what `backend.path` answers for its service and id. Every secret's `backendPath` is what `backend.path` answers for its service and id, so it equals `path` for an undelivered secret and is where the backend installs a delivered one. A secret has no path while `backend` is null, or while `delivery` is null for a delivered secret, so reading one fails with an error naming the missing adapter, as does serialising `contracts.claimSets.secrets`, and a service module that wires a daemon from `path` needs the adapters imported. Reading `backendPath` while `backend` is null fails the same way.

The backend still installs a delivered secret, and the delivery adapter loads it from there, so a delivered secret's `group` defaults to `root` and the account's other units cannot read the installed file.

Checks fail for a delivered secret while `delivery` is null, and for a dynamic identity's secret delivered to a unit other than the identity's. A dynamic identity's user exists only while its unit runs, so it reads an undelivered secret only through its `sharedGroup`: a check fails for a dynamic identity's undelivered secret unless the secret's `group` is the identity's `sharedGroup`. Mode bits are not checked.

Secrets have no clash rule.

## Relating nodes

nixos-contracts carries nothing between nodes ([ADR 0013](adr/0013-leave-carrying-a-reference-between-nodes-to-the-fleet.md)). A sending node makes its claim's `ref` available in shared data the fleet already has, and the receiving node writes its own claims from the references it reads there:

- a copy of each, as one [secret](#secrets) per reference with `value.copied`;
- one secret generated from all of them, with `value.generated.from`, such as an htpasswd;
- for a claim of another kind, such as a backend's bind, a value read through [`contracts.resolve`](#contractsresolve).

```nix
# On the store: a copy of each writer's token, `writers` being a list of
# `lib.types.referenceTo "secrets"` values read from shared data
contracts.services.influxdb.secrets = contractsLib.copiesOf writers;

# Or the same copies, each with its own owner and mode, merged by claim name
contracts.services.influxdb.secrets = lib.mkMerge [
  (contractsLib.copiesOf writers)
  (lib.genAttrs (map contractsLib.claimNameOf writers) (_: {
    owner = "influxdb2";
    mode = "0400";
  }))
];

# On the proxy: an htpasswd with one line per client, in a stable order
contracts.services.nginx.secrets.htpasswd.value.generated = {
  generator = "basic-auth";
  from = lib.sortOn contractsLib.claimNameOf clients;
};
```

A copy is an ordinary secret of the receiving service. It is in `contracts.claimSets.secrets`, its `owner` and `group` default from the receiving identity, it passes the secrets kind's checks, and every adapter installs and delivers it like any other secret. The receiving daemon reads it at its `path`. A sender added on another node adds a copy or a source, with no change on the receiving node.

A copy's id is the sent claim's `name`, which [`lib.claimNameOf`](#libclaimnameof) builds from the reference's own `node`, `kind`, `service` and `id`, so no two references give one id (see [Names](#names)). A receiver does not resolve a reference to choose an id. The keys of its claim set would then read the sender's claim set, and two receivers that each did so would recurse into each other. A receiver resolves references only in the values it builds, as a secret's sources do.

A receiver gets the references in the order its shared data gives them. Where the order shows in what it builds, such as the lines of an htpasswd, it sorts them, for example by their claim names through `claimNameOf`.

The receiver's checks report a reference that does not resolve, naming the reference and the reason, such as ``nixos-contracts: secrets claim `influxdb.alhpa_secrets_telegraf_token`: it references `alhpa:secrets.telegraf.token`: node `alhpa` is not in `contracts.nodes`.`` A copy of a copy fails as any copy does, as does a generator that reads a copy or a secret generated from others. A reference of another kind fails as a type error where it is written, in a field typed [`lib.types.referenceTo`](#libtypesreferenceto). Nothing reports a missing or disabled receiver, since the core does not know who reads a reference.

Across a fleet, [nixos-registry](https://github.com/petohorvath/nixos-registry) carries the references. Each sender contributes its claim's `ref` to a registry field of `lib.types.referenceTo` values, keyed by the claim's `name`, and each receiver reads the combined data. nixos-registry reads each node's contributions and never its claim sets, so two nodes that hand each other references evaluate without a cycle. A node whose contribution reads what it received still recurses. Where the nodes are evaluated together, a `let`-bound list of their `ref`s does the same, as the [shared-token example](examples.md#shared-token-one-value-on-two-nodes) shows.

## Ownership

A mount's or secret's `owner` and `group` default to values derived from the service's identity:

| Identity                                     | Mount owner / group | Secret owner / group |
| -------------------------------------------- | ------------------- | -------------------- |
| `static.user = "chrony"`                     | chrony / chrony     | root / chrony        |
| `static = { user = "kea"; group = "dhcp"; }` | kea / dhcp          | root / dhcp          |
| `dynamic.unit = "alloy.service"`             | root / root         | root / root          |
| `dynamic` with `sharedGroup = "logs"`        | root / logs         | root / root          |

A delivered secret's group is `root`, and an undelivered one's is the identity's group. The table shows each secret with its default `unit`: a static identity's undelivered, a dynamic identity's delivered. A dynamic identity's secret with `unit = null` gets its `sharedGroup`, `logs`. An explicit `owner` or `group` on the claim wins. A mount's group otherwise falls back to the identity's group and then to its owner. A secret stays root-owned unless its claim says otherwise, so the service reads it through its group but cannot change it. A dynamic identity has no account at activation time, so nothing is owned by it; its secrets reach the daemon through a delivery adapter or its `sharedGroup`.

## Adapters

An adapter maps one claim set onto one backend. Importing it turns it on, and it requires its backend's NixOS module, since it defines that backend's options. Adapter checks join `contracts.assertions`, and their failures `contracts.failures`.

The shipped adapters use only the public library and the options this reference documents, so an adapter written outside this library can do anything a shipped one does. Each adapter file is a function of the library, `contractsLib`, which `nixosModules` applies, and names no parent path, so it imports nothing else of this repository; the `lint` check fails, naming the file, when one does. Between them they use:

- [`lib.claimsOf`](#libclaimsof), to list the claims of their kind;
- [`lib.backendNameOf`](#libbackendnameof), to name their entries `<service>_<id>`;
- [`lib.labels`](#liblabels), to label claims and references in their messages as the core does;
- [`contracts.claimSets.<kind>`](#contractsclaimsetskind), the claims they install, with the fields of [their kind](#claim-kinds), such as a mount's `path`, `class` and `owner`, or a secret's `generator`, `copyOf`, `unit`, `delivered` and `backendPath`, which tell an adapter what it needs of the secret's `value`;
- [`contracts.resolve`](#contractsresolve), whose `config` gives the configuration of the node a secret's source is on;
- a contract's `identity`, to tell a dynamic identity's secrets;
- the [secret adapter slots](#secrets) `contracts.kinds.secrets.backend` and `contracts.kinds.secrets.delivery`, which they fill;
- [`contracts.assertions`](#contractsassertions), to which they add their checks.

A project's adapter gets the same library from the flake's `lib` output, as a module argument such as `specialArgs.contractsLib`, or by importing the library directory by path with the configuration's `lib`, as [`lib.mkDefaultContract`](#libmkdefaultcontract) shows.

### `nixosModules.preservation`

Adds every mount to `preservation.preserveAt` under the root mapped to its class, as a directory or a file entry with the mount's `owner` as its `user`, and its `group` and `mode`. It requires the [preservation](https://github.com/nix-community/preservation) module.

`contracts.adapters.preservation.roots` (attribute set of strings, default `{ }`)
: The `preservation.preserveAt` key of each class, such as `{ state = "/persist/state"; }`. Every class a mount uses needs a root, or an assertion fails; a declared class no mount uses needs none.

### `nixosModules.agenix-rekey`

Defines one `age.secrets` entry per claim of `contracts.claimSets.secrets`, named `<service>_<id>`, such as `age.secrets.influxdb_admin-token` or, for a [copy](#relating-nodes) whose id joins a reference's fields, `age.secrets.influxdb_metrics_secrets_telegraf_token`, with the claim's `owner`, `group` and `mode`, and, when the claim's value is `generated`, `generator.script` set to its generator at default priority. For a copy, the adapter sets the entry's `rekeyFile` at default priority to the `rekeyFile` of the entry the copy references. For a secret generated from others, it sets `generator.dependencies` to the entries of its generator's sources. A module sets anything else about the value on that entry, such as a provided secret's `rekeyFile`; a `rekeyFile` it sets wins over a copy's, and a `generator.script` over the claim's, while `generator.dependencies` alone keeps it. The entry cannot remove the claim's generator with `generator = null`; write the claim's `value.provided = { };` instead. Without a `rekeyFile`, agenix-rekey takes its default from `age.rekey.generatedSecretsDir` when the entry has a generator and from `age.rekey.secretsDir` when it has none. A check fails for a secret that ends up with no `rekeyFile`. The adapter also sets the `contracts.kinds.secrets.backend` slot: `path` to the installed `age.secrets.<service>_<id>.path`, and `generators` to the names of `age.generators`, agenix-rekey's built-in generators and any a configuration adds. It requires the [agenix](https://github.com/ryantm/agenix) and [agenix-rekey](https://github.com/oddlama/agenix-rekey) modules.

The adapter has no settings. It reads a secret's references from the sources of its `copyOf` and `generator`, and the `age.secrets` entry of each source without a reason from the `config` that [`contracts.resolve`](#contractsresolve) returns for its reference. It takes the names of its own entries from its own claim set alone, never from another node's entries, so entries across nodes, in either direction, evaluate without cycles. A copy's `rekeyFile` is the referenced secret's, read from its entry on its own node, or from this configuration for a secret of its own node, so one encrypted file serves both nodes. A generated secret's dependencies are its sources' entries on their own nodes, so an htpasswd is built from clients on several nodes. Its check fails for a reference to a secret on a node without this adapter. A copy whose reference the core rejects gets no `rekeyFile` and no second failure for it. A copy of a secret without an encrypted file fails a check that names the referenced secret, since the file is missing on that node, such as ``nixos-contracts: secret `influxdb.token` copies `metrics:secrets.telegraf.token`, which has no encrypted file: …``.

A generated secret with references defines its entry's `generator.dependencies` as a list, so a module adding dependencies to that entry adds a list too, or adds the references to `value.generated.from`; agenix-rekey's attribute-set form of `generator.dependencies` does not merge with a list.

### `nixosModules.systemd-credentials`

For every delivered secret in `contracts.claimSets.secrets`, copies included, adds `<service>_<id>:<backendPath>` to the `LoadCredential=` of the secret's `unit`, naming the credential `<service>_<id>`, such as `alloy_loki-password`, and sets the `contracts.kinds.secrets.delivery` slot so the claim's `path` becomes `/run/credentials/<unit>/<service>_<id>`. It loads from the secret's `backendPath`, which `contracts.kinds.secrets.backend` gives, so it needs a backend adapter such as `nixosModules.agenix-rekey` beside it. It has no settings.

Without a backend adapter, its `LoadCredential=` fails to evaluate with an error naming the missing adapter. Its checks fail when a unit a secret is delivered to does not end in `.service` or is not defined by another module, and when a dynamic identity's unit does not set `DynamicUser`. The units of static identities need not set it. The adapter's own `LoadCredential=` definition creates the unit's `systemd.services` entry, so the unit counts as defined only if it has an `ExecStart`, set directly or through `script`.

## Library

### `lib.backendNameOf`

`backendNameOf claim` is the name a backend adapter gives its entry for a claim, `<service>_<id>` (see [Names](#names)). It takes anything with `service` and `id`, such as a claim or a reference. A service module names a secret's backend entry with it, such as to set a provided secret's encrypted file when it is not at the backend's default:

```nix
age.secrets.${contractsLib.backendNameOf config.contracts.services.influxdb.secrets.admin-token}.rekeyFile =
  ./secrets/influxdb-admin-token.age;
# sets age.secrets.influxdb_admin-token.rekeyFile
```

### `lib.claimsOf`

`claimsOf claimSet` is the claims of one kind's [claim set](#contractsclaimsetskind) in a list, by service and then id. An adapter installs each claim of its kind from it:

```nix
map (secret: secret.name) (contractsLib.claimsOf config.contracts.claimSets.secrets)
# => [ "beta_secrets_influxdb_admin-token" "beta_secrets_telegraf_token" ]
```

### `lib.labels`

`labels.claim claim` and `labels.reference reference` are the labels check messages give a claim and a reference, `<service>.<id>` and `<node>:<kind>.<service>.<id>` (see [Names](#names)), so an adapter's messages read like the core's:

```nix
contractsLib.labels.claim { service = "influxdb"; id = "admin-token"; }
# => "influxdb.admin-token"
contractsLib.labels.reference { node = "metrics"; kind = "secrets"; service = "telegraf"; id = "token"; }
# => "metrics:secrets.telegraf.token"
```

### `lib.claimNameOf`

`claimNameOf reference` is the `name` of the claim a [reference](#references) names, `<node>_<kind>_<service>_<id>`. It is built from the reference alone and never resolves it, so a receiver can key the claims it builds from references with it without reading the sender's claim set. Every claim's `name` is built the same way:

```nix
contractsLib.claimNameOf { node = "metrics"; kind = "secrets"; service = "telegraf"; id = "token"; }
# => "metrics_secrets_telegraf_token"
```

### `lib.copiesOf`

`copiesOf references` is a [copy](#relating-nodes) of each referenced secret, for a contract's `secrets`: one claim per reference, keyed by its claim name, with `value.copied` set to the reference. A receiver that gives each copy further fields, such as an owner and mode, defines them under the same keys in a second definition, which the module system merges into each copy:

```nix
contractsLib.copiesOf [ { node = "metrics"; kind = "secrets"; service = "telegraf"; id = "token"; } ]
# => { metrics_secrets_telegraf_token.value.copied = { node = "metrics"; kind = "secrets"; service = "telegraf"; id = "token"; }; }
```

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
: The kind's name: the contract field, the claim set, the settings root and part of every claim's `name`. It may contain only lowercase letters, digits and hyphens, so a name such as `api_tokens` fails as the kind is built, and the contract's own fields `enable` and `identity` are reserved.

`description`
: The description of the contract field.

`claim`
: A function of `{ service, identity, config }` returning the submodule of one claim, where `identity` is the contract's identity resolved to `{ user, group, unit }` (`user` null for a dynamic identity, `group` null for a dynamic identity without a shared group, `unit` null for a static identity) and `config` the top-level configuration. Inside the submodule, the module argument `name` is the claim's id. A value that follows from the identity, such as a file owner, is an option defaulting to it. The constructor declares `service`, `id`, `name` and `ref` on every claim, so a claim type cannot declare options with these names, and reads a claim's own service and id from `config.service` and `config.id`.

`clash`
: The kind's clash rule: a function of two claim-set entries returning null or a reason string. Omit it when no two claims of the kind can clash.

`check`
: The kind's check rule: a function of `{ identity, claim, settings, config }`, with the same resolved `identity`, a claim-set entry, the kind's settings at `contracts.kinds.<name>` and the top-level configuration, returning null, a reason string or a list of them. Only claims of enabled contracts are checked, and each reason reads ``nixos-contracts: <kind> claim `<service>.<id>`: <reason>.`` in `contracts.failures`.

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

### `lib.mkReference`

`mkReference kind { node; service; id; }` is the [reference](#references) to the claim of kind `kind` that the node, service and id name, so a reference written as a literal never writes `kind`. It equals the `ref` of the claim it names, and the value a [`lib.types.referenceTo`](#libtypesreferenceto) field of `kind` holds:

```nix
mkReference "secrets" { node = "metrics"; service = "telegraf"; id = "token"; }
# => { node = "metrics"; kind = "secrets"; service = "telegraf"; id = "token"; }
```

It fails with a message naming the reference on a missing field, on any field other than `node`, `service` and `id`, including `kind`, and on a node identity, kind name, service name or id that breaks its [name rule](#names), with the message the claim constructor gives for that name, such as ``nixos-contracts: reference `metrics:api_tokens.telegraf.token`: claim kind name `api_tokens` may contain only lowercase letters, digits and hyphens.``

### `lib.types.reference`

The option type of a [reference](#references) of any kind, `{ node; kind; service; id; }`, all required strings, each following its [name rule](#names), so a reference with an invalid name fails as a type error at its definition. A claim's `ref` has this shape.

### `lib.types.referenceTo`

`referenceTo kind` is the option type of a [reference](#references) of one kind, `{ node; service; id; }`, whose `kind` defaults to `kind` and accepts no other. Its other names follow their [name rules](#names) as in `lib.types.reference`, and a `kind` that breaks the kind name rule fails as the type is built. A secret's `value.copied` and `value.generated.from` take `referenceTo "secrets"`. A service module whose own settings carry references, such as the writer tokens a fleet's shared data provides, types the setting with it, so the value it receives is already a reference of the kind it uses, and one of another kind fails where it is written:

```nix
options.example.influxdb.writers = lib.mkOption {
  type = lib.types.listOf (contractsLib.types.referenceTo "secrets");
  default = [ ];
};

config.contracts.services.influxdb.secrets = contractsLib.copiesOf config.example.influxdb.writers;
```

A registry field that carries references across a fleet, such as a nixos-registry field, takes the same type.

### `lib.types.tag`

`tag tags` is the option type of a field that holds exactly one of several cases. It takes the same tag declarations as `lib.types.attrTag`, an attribute set of options, and settles definitions that name different tags by priority ([ADR 0006](adr/0006-settle-a-tag-by-the-priority-of-its-definitions.md)). A contract's `identity` has this type, and a project's claim kind uses it for its own tags, so a node switches them as it switches an identity.

The tag rule:

- A definition counts at the priority of its strongest leaf. Each leaf has the priority of its innermost `lib.mkOverride`, including `lib.mkDefault` and `lib.mkForce`, or the normal priority when nothing wraps it.
- `lib.mkIf` passes the priority of its content through when its condition is true. A false condition contributes no priority, so a definition with no leaf left gives way to any other tag.
- `lib.mkMerge` counts at the strongest of its contents.
- A tag counts at its strongest definition. The strongest tag keeps its definitions, which merge as in `lib.types.attrTag`, and the other tags' definitions are dropped.
- Two different tags at the same priority fail with an error naming the option, as in `lib.types.attrTag`.
- `lib.mkForce` or `lib.mkOverride` on the whole field still drops the weaker definitions before the tags settle.

To find each definition's priority, the tag type reads the overrides of every leaf in every definition, including the definitions of a tag it drops, so a leaf that throws or recurses fails the option even in a losing tag.

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
