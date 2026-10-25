# API reference

This reference describes the public interface of nixos-contracts: its modules, options, claim kinds and library functions. [GLOSSARY.md](../GLOSSARY.md) defines the terms.

## Modules

| Export                    | Module class | Checks                                                    |
| ------------------------- | ------------ | --------------------------------------------------------- |
| `nixosModules.default`    | NixOS        | Forwarded from `contracts.failures` to NixOS `assertions` |
| `modules.generic.default` | any          | Left in `contracts.failures` for the caller to read       |

Both import the core and the four shipped claim kinds. The generic module reads no option outside `contracts`, so it also evaluates with a bare `lib.evalModules`, which is how the core is tested.

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
contracts.services.<service>.<kind>.<id>     writable, one claim; service, id, location, name, ref read-only
contracts.claimSets.<kind>.<service>.<id>    read-only
contracts.node                               this configuration's node identity
contracts.nodes.<node>                       the node collection
contracts.lookup, contracts.resolve          read-only, functions of a reference
contracts.checkSends                         whether to check that sends don't depend on what arrived
contracts.kinds.<kind>.*                     kind settings
contracts.adapters.<adapter>.*               adapter settings
contracts.assertions                         checks over all contracts
contracts.failures                           read-only, messages of failed checks
```

### `contracts.services.<service>`

One contract per service, keyed by the service's name, which is a [name](#locations-and-names).

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

A read-only attribute set of every enabled contract's claims of one kind, nested by service and id, as `contracts.claimSets.<kind>.<service>.<id>` ([ADR 0014](adr/0014-name-a-claim-by-its-location.md)). Each entry is the claim as its contract holds it, with the same final values, such as the [owner and group](#ownership), so an adapter reading the claim set and a service module reading its contract agree. A service without claims of the kind has no entry. An adapter that needs a list flattens the claim set, by service and then id.

### `contracts.node`

This configuration's node identity, its name in the node collection (a [name](#locations-and-names) or null, default `null`). Every claim's `ref` and `name` include it. While it is null, a `ref` names a null node, which no lookup resolves, and a claim's `name` is null, so a configuration whose claims are referenced, even by itself, sets it. A check fails when `contracts.nodes` is not empty and has no node of this name. [`nixosModules.cross-config`](#nixosmodulescross-config) defaults it to `crossConfig.name`.

### `contracts.nodes`

The node collection: the nodes a [reference](#references) may name, keyed by node identity, each with its evaluated `config`, such as nixos-cross-config's node collection (default `{ }`). The core resolves references against it ([ADR 0011](adr/0011-resolve-a-reference-in-the-core-from-the-node-collection.md)), reading only each node's `contracts.claimSets`, and a backend adapter reads what else it needs of a node from the same entry. A reference that names `contracts.node` resolves in this configuration itself.

### `contracts.lookup` and `contracts.resolve`

Read-only functions of a [reference](#references) that find the claim it names, of any kind ([ADR 0012](adr/0012-address-a-claim-by-an-absolute-reference.md)). `contracts.lookup reference` returns `{ claim; reason; }`: the claim-set entry and a null reason, or a null claim and why the reference names none. `contracts.resolve reference` returns the entry, or fails with ``nixos-contracts: cannot resolve `<node>:<kind>.<service>.<id>`: <reason>``. Both read the entry at `claimSets.<kind>.<service>.<id>` of the node the reference names. A reference names no claim when its node is null, is missing from `contracts.nodes`, imports no nixos-contracts module or has no such claim kind, or when no enabled contract on it holds the claim. A module reading another node's claim, such as the port of a backend's bind, resolves its reference rather than reading that node's contracts:

```nix
port = (config.contracts.resolve backend.bind).port;
```

### `contracts.checkSends`

Whether to check that what this node sends doesn't depend on what its [inboxes](#inboxes) received (bool, default `false`). A claim whose `sendTo`, or whose existence, depends on an inbox's `received` or `refs` makes a cycle: the inbox reads the node's sends, which read the claim, which reads the inbox. Without the check, such a configuration fails to evaluate with `infinite recursion encountered`, naming no claim.

With the check, the node is evaluated a second time with `extendModules`, with every inbox's `received` empty, and with it every `refs` and copy, and the node publishes the sends of that evaluation. A check fails for each claim that sends to other inboxes in the two evaluations, such as ``nixos-contracts: secrets claim `telegraf.token` sends to `store:inboxes.influxdb.writers` once its node has received claims, but to nothing before: whether a claim exists and where it is sent must not depend on an inbox's `received` or `refs`.`` When no send depends on what arrived, the sends, `received`, `refs` and copies of every node are those of the default mode, so the check changes nothing a configuration builds.

Each node with the check is evaluated twice. On six nodes of the prototype, evaluation took about a third more CPU time. Turn it on where that cost is paid once, such as in CI, so a send that depends on what arrived is named before it ships, or while diagnosing an infinite recursion, and leave it off where evaluation time matters.

### `contracts.kinds.<kind>`

The settings of one claim kind, such as `contracts.kinds.mounts.classes`, as the kind declares them. A node writes settings, such as the mount classes. A kind may also declare adapter slots, such as the secrets' `backend`, which one adapter fills and a node does not write ([ADR 0010](adr/0010-hold-adapter-data-in-slots-not-kind-settings.md)). They sit under `kinds` rather than at the root, so a kind may take any name but the contract's own fields ([ADR 0008](adr/0008-keep-kind-settings-under-contracts-kinds.md)).

### `contracts.assertions`

A list of checks, each `{ assertion; message; }`, with the message written without the library's prefix. The option follows the name and shape of NixOS `assertions`. Each claim kind adds one check per pair of claims, failing when its clash rule rejects them, and one per claim of a kind with a check rule, failing when the rule rejects it. Two claims never clash by their names alone, since no two locations make one name. Adapters add their own.

### `contracts.failures`

A read-only list of the messages of the failed checks in `contracts.assertions`, each prefixed with `nixos-contracts: `, such as ``nixos-contracts: mount class `state` has no preservation root in `contracts.adapters.preservation.roots`.`` `nixosModules.default` forwards them to NixOS `assertions`; with the generic module the caller reads them.

## Claim kinds

Besides its kind's fields, every claim at `contracts.services.<service>.<kind>.<id>` carries five read-only fields:

- `service`: the name of its service.
- `id`: its id within the contract.
- `location`: the names that place it within its node, `[ <service> <id> ]`.
- `name`: its claim name, `<node>_<service>_<id>`, or null while `contracts.node` is null.
- `ref`: its [reference](#references), `{ node; kind; service; id; }`, with `contracts.node` as its node.

A read-only field cannot be defined, so copying a whole claim into another contract fails; copy the kind's fields instead.

A claim of every kind but inboxes also has a writable `sendTo` (list of [`lib.types.referenceTo "inboxes"`](#libtypesreferenceto), default `[ ]`): the [inboxes](#inboxes) it is sent to.

### Locations and names

A claim's `location` places it within its node, and its `name` names it across the node collection ([ADR 0014](adr/0014-name-a-claim-by-its-location.md)):

```nix
# The claim contracts.services.influxdb.secrets.admin-token, on the node beta-influxdb
location = [ "influxdb" "admin-token" ];
name = "beta-influxdb_influxdb_admin-token";
```

Service names, claim ids and node identities are names: non-empty, and made of lowercase letters, digits and hyphens only. Any other, such as `ssh_host_ed25519_key` or `Influxdb`, fails at evaluation with an error naming it and the allowed characters, such as ``nixos-contracts: secrets claim id `ssh_host_ed25519_key` of service `openssh` may contain only lowercase letters, digits and hyphens.`` No name contains `_`, so joining a location with `_` makes a name no other location makes:

- A backend adapter names its entry for a claim by joining the location with `_`, such as `age.secrets.influxdb_admin-token`.
- A claim's `name` joins its node identity, service and id with `_`, so a value built from several nodes' claims, such as an htpasswd user name, takes `name` and never collides.
- Check messages name a claim by its location joined with `.`, such as ``nixos-contracts: secrets claim `influxdb.admin-token`: …``.

### References

A reference names one claim by its node, kind, service and id, `{ node; kind; service; id; }`, and always names its node, so it means the same claim on every node that reads it ([ADR 0012](adr/0012-address-a-claim-by-an-absolute-reference.md)). A claim's `ref` is its reference, built from `contracts.node` alone, so a module that hands its own claim to another node, such as through a nixos-cross-config contribution, passes the `ref` rather than writing it out:

```nix
crossConfig.contributions.store.example.influxdb.writers.${config.contracts.node} =
  config.contracts.services.telegraf.secrets.token.ref;
```

A field that takes references of one kind, such as a secret's `value.copied`, has the type [`lib.types.referenceTo`](#libtypesreferenceto) of that kind, so a reference written by hand omits `kind`, and one of another kind fails as a type error at its definition.

### Inboxes

`contracts.services.<service>.inboxes.<id>`: a place where claims of one kind arrive from any node, the node itself included ([ADR 0015](adr/0015-carry-claims-between-nodes-through-inboxes.md)).

| Field      | Type                                               | Default     |
| ---------- | -------------------------------------------------- | ----------- |
| `kind`     | the name of a claim kind                           | `"secrets"` |
| `copy`     | null, or the settings of a copy of each secret     | `null`      |
| `received` | read-only, `<node>.<service>.<id>` of what arrived | derived     |
| `refs`     | read-only, the references of `received`, sorted    | derived     |

A claim reaches an inbox when its `sendTo` names the inbox's node, service and id, as `{ node; service; id; }`. One claim may name several inboxes, on other nodes or its own:

```nix
# On the node logs: send loki's bind to nginx's upstreams on the node proxy
contracts.services.loki.binds.http = {
  port = 3100;
  sendTo = [ { node = "proxy"; service = "nginx"; id = "upstreams"; } ];
};

# On the node proxy: take binds, and build an upstream from each
contracts.services.nginx.inboxes.upstreams.kind = "binds";
services.nginx.upstreams = lib.concatMapAttrs (
  node: lib.concatMapAttrs (
    service: lib.mapAttrs' (
      id: entry: lib.nameValuePair "${node}_${service}_${id}" {
        servers = lib.genAttrs entry.claim.bindpoints (_: { });
      }
    )
  )
) config.contracts.services.nginx.inboxes.upstreams.received;
```

Each node publishes what it sends, built from its own claim sets, and an inbox reads the sends meant for it from every node in [`contracts.nodes`](#contractsnodes) and from its own configuration. The sender writes nothing on the receiving node, and the receiver declares no option of its own for a relation. Only claims of enabled contracts are sent. Two nodes that send to each other evaluate without a cycle, as long as no claim's `sendTo` or existence reads what its node received. One that does recurses, and [`contracts.checkSends`](#contractschecksends) names it.

`received` holds each claim sent to the inbox, by the sender's node, service and id, as `{ ref; claim; copy; }`:

- `ref`: the sent claim's [reference](#references).
- `claim`: the sent claim as its node's claim set holds it, such as a bind's `bindpoints` or a secret's `name`.
- `copy`: the copy the receiving service holds of a sent secret, or null.

An inbox receives only claims of its `kind`, and only while its contract is enabled and `contracts.node` is set, which every sent `ref` names. A claim that names one inbox twice arrives once.

`refs` lists the references of `received`, sorted by their label `<node>:<kind>.<service>.<id>`, so it is in the same order on every evaluation and empty whenever `received` is. `-` sorts before `:`, so a sender on `beta-vm` comes before one on `beta`.

Checks fail for a send on the sending node, naming the claim by its location and the inbox by its reference:

- For each reason [`contracts.lookup`](#contractslookup-and-contractsresolve) gives for the inbox's reference: an unknown node, a node without nixos-contracts, or an inbox no enabled contract holds, such as ``nixos-contracts: secrets claim `telegraf.token` sends to `proxy:inboxes.nginx.client`: no enabled contract on `proxy` holds it.``
- When the inbox takes another kind, naming both, such as ``nixos-contracts: binds claim `loki.http` sends to `proxy:inboxes.nginx.clients`, which takes `secrets`, not `binds`.``

Checks also fail for an inbox whose `kind` is no claim kind of its node or is `inboxes`, and for an inbox of a kind other than secrets that sets `copy`.

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

| Field       | Type                                                                  | Default  |
| ----------- | --------------------------------------------------------------------- | -------- |
| `mode`      | a mode string                                                         | `"0440"` |
| `owner`     | an account name                                                       | `"root"` |
| `group`     | a group name                                                          | derived  |
| `value`     | a [tag](#libtypestag): `provided`, `generated`, `copied` or `derived` | provided |
| `sources`   | read-only, each reference of the value with its resolved claim        | derived  |
| `unit`      | read-only, the dynamic identity's unit, or null                       | derived  |
| `delivered` | read-only, whether the secret is delivered                            | derived  |
| `path`      | read-only, where the daemon reads the secret                          | derived  |

A secret holds no value. Its `value` says where the value comes from, as one of four tags ([ADR 0013](adr/0013-settle-a-tag-by-the-priority-of-its-definitions.md)):

- `provided = { }`, the default: a person or another party provides it. `provided` takes no options.
- `generated = "<generator>"`: the service makes its own value with the named generator, such as `alnum`. A backend adapter turns the generator into the backend's own.
- `copied = <reference>`: the secret is a copy of the one secret the reference names. It reads the same value, owned, installed and delivered as its own claim says.
- `derived = { generator; from; }`: the generator makes the value from the secrets `from` references, in order. `from` defaults to `[ ]`, for a generator that needs no other secret.

```nix
secrets.admin-password.value.generated = "alnum";

# A copy of a token the `metrics` node generates
secrets.writer-token.value.copied = { node = "metrics"; service = "telegraf"; id = "token"; };

# An htpasswd file the generator makes from two clients' passwords
secrets.htpasswd.value.derived = {
  generator = "basic-auth";
  from = [
    { node = "grafana"; service = "grafana"; id = "loki-password"; }
    config.contracts.services.alloy.secrets.loki-password.ref
  ];
};
```

Anything else about the value, such as a provided secret's encrypted file, is set on the backend under the name the adapter makes from the claim's [location](#locations-and-names) ([ADR 0006](adr/0006-mark-a-secret-the-service-generates.md)). `value` settles by priority, so a node switches a module's tag by writing another at normal priority, which wins when the service module wrote the claim at default priority, such as through `lib.mkDefaultContract`: `value.provided = { };` makes a module's generated secret provided, and `value.copied = <reference>;` makes it a copy. Two tags written at one priority fail, naming the option, and a misspelt tag, such as `value.generate`, fails as a type error that lists the accepted tags.

The references of `copied` and `derived.from` are [references](#references) of the type `lib.types.referenceTo "secrets"`, `{ node; service; id; }` ([ADR 0012](adr/0012-address-a-claim-by-an-absolute-reference.md)), so a reference of another kind fails as a type error at its definition. Each names `contracts.node` or a node in `contracts.nodes`. A value takes either one reference or a generator, so a copy of several secrets cannot be written.

The core resolves the references into `sources`, the one of `copied` or those of `derived.from` in order, each as `{ node; kind; service; id; claim; }`: the reference with the claim-set entry of the secret it names, or a null `claim` when a check rejects the reference ([ADR 0011](adr/0011-resolve-a-reference-in-the-core-from-the-node-collection.md)). `sources` is empty for a `provided` or `generated` value. A backend adapter reads `sources` rather than resolving references itself, and finds a resolved claim's backend entry by the claim's `location`. A check fails, once per reference, for each reason [`contracts.lookup`](#contractslookup-and-contractsresolve) returns, and for a reference to a secret that is copied or derived itself, which also catches two copies referencing each other. The core reads a referenced node's claim set alone and does not follow a referenced secret's own references, so references across nodes, in either direction, evaluate without cycles. `derived.from` is a list, so a node that sets it replaces the service module's at default priority, and a module that adds references merges its list with the others.

`path` is computed from two adapter slots under `contracts.kinds.secrets`. A slot holds the data of one adapter, not a setting a node writes, and is null while no such adapter is imported ([ADR 0010](adr/0010-hold-adapter-data-in-slots-not-kind-settings.md)):

```nix
# Set by a backend adapter, such as nixosModules.agenix-rekey
contracts.kinds.secrets.backend = {
  path = location: "/run/agenix/${lib.concatStringsSep "_" location}";
  generators = [ "alnum" "hex" ];
};

# Set by a delivery adapter, such as nixosModules.systemd-credentials
contracts.kinds.secrets.delivery = {
  path = { unit, location }: "/run/credentials/${unit}/${lib.concatStringsSep "_" location}";
};
```

- `backend.path` (function of a [location](#locations-and-names)): where the secret backend installs a secret. It must answer for any location, including those of claims of disabled contracts, which the backend does not install, since a service module may read a claim's `path` regardless.
- `backend.generators` (list of strings): the generators a `generated` or `derived` value may name. A check fails for a claim whose generator is not in it, and lists the ones the backend provides. While `backend` is null, the generator is not checked.
- `delivery.path` (function of `{ unit, location }`): where a dynamic identity's unit reads a delivered secret, given the secret's unit and location.

A configuration imports at most one backend adapter and one delivery adapter: a second definition of `backend` or `delivery` fails once the slot is read, naming both, unless the definitions differ in priority. A slot takes its adapter's data as one definition, so a module that replaces part of it, such as the backend's `path`, replaces the whole slot with `lib.mkForce`, generators included.

A secret is `delivered` when its identity is dynamic and `delivery` is set. Its `path` is then what `delivery.path` answers for its unit and location; otherwise it is what `backend.path` answers for its location. A secret has no path while `backend` is null, so reading one fails with an error naming the missing adapter, as does serialising `contracts.claimSets.secrets`, and a service module that wires a daemon from `path` needs a backend adapter imported.

A dynamic identity's user exists only while its unit runs, so it reads a secret the backend installs only through its `sharedGroup`. A check fails for a dynamic identity's secret that no adapter delivers, unless the secret's `group` is the identity's `sharedGroup`. Mode bits are not checked.

Secrets have no clash rule.

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

Defines one `age.secrets` entry per secret claim, named by its location joined with `_`, such as `age.secrets.influxdb_admin-token`, with the claim's `owner`, `group` and `mode`, and, when the claim's value is `generated` or `derived`, `generator.script` set to its generator at default priority. For a copy, the adapter sets the entry's `rekeyFile` at default priority to the `rekeyFile` of the entry the copy references. For a derived secret, it sets `generator.dependencies` to the entries of its `sources`. A module sets anything else about the value on that entry, such as a provided secret's `rekeyFile`; a `rekeyFile` it sets wins over a copy's, and a `generator.script` over the claim's, while `generator.dependencies` alone keeps it. The entry cannot remove the claim's generator with `generator = null`; write the claim's `value.provided = { };` instead. Without a `rekeyFile`, agenix-rekey takes its default from `age.rekey.generatedSecretsDir` when the entry has a generator and from `age.rekey.secretsDir` when it has none. A check fails for a secret that ends up with no `rekeyFile`. The adapter also sets the `contracts.kinds.secrets.backend` slot: `path` to the installed `age.secrets.<name>.path` of the name a location makes, and `generators` to the names of `age.generators`, agenix-rekey's built-in generators and any a configuration adds. It requires the [agenix](https://github.com/ryantm/agenix) and [agenix-rekey](https://github.com/oddlama/agenix-rekey) modules.

The adapter has no settings. It reads the claims a secret's references resolve to from its `sources`, and the `age.secrets` entry of each resolved one from that node's `config` in `contracts.nodes`. It takes the names of its own entries from its own claim set alone, so entries across nodes, in either direction, evaluate without cycles. Its check fails for a reference to a secret on a node without this adapter. A copy whose reference the core rejects gets no `rekeyFile` and no second failure for it. A copy of a secret without an encrypted file fails a check that names the referenced secret, since the file is missing on that node.

A derived secret with references defines its entry's `generator.dependencies` as a list, so a module adding dependencies to that entry adds a list too, or adds the references to `value.derived.from`; agenix-rekey's attribute-set form of `generator.dependencies` does not merge with a list.

### `nixosModules.systemd-credentials`

For every secret of a dynamic-identity service, adds `<name>:<backend path>` to the unit's `LoadCredential=`, where the credential's name joins the secret's location with `_`, such as `alloy_loki-password`, and sets the `contracts.kinds.secrets.delivery` slot so the claim's `path` becomes `/run/credentials/<unit>/<name>`. It loads from the path `contracts.kinds.secrets.backend` gives, so it needs a backend adapter such as `nixosModules.agenix-rekey` beside it. It has no settings.

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
: A function of `{ service, identity, config }` returning the submodule of one claim, where `identity` is the contract's identity resolved to `{ user, group, unit }` (`user` null for a dynamic identity, `group` null for a dynamic identity without a shared group, `unit` null for a static identity) and `config` the top-level configuration. Inside the submodule, the module argument `name` is the claim's id. A value that follows from the identity, such as a file owner, is an option defaulting to it. The constructor declares `service`, `id`, `location`, `name` and `ref` on every claim, and `sendTo` on every claim of a kind other than inboxes, so a claim type cannot declare options with these names, and reads a claim's own `location` from `config.location`.

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

### `lib.types.reference`

The option type of a [reference](#references) of any kind, `{ node; kind; service; id; }`, all required: `node` a node identity, or null for the `ref` of a claim whose configuration has none, and the others strings. A claim's `ref` has this shape.

### `lib.types.referenceTo`

`referenceTo kind` is the option type of a [reference](#references) of one kind, `{ node; service; id; }`, whose `kind` defaults to `kind` and accepts no other. A secret's `value.copied` and `value.derived.from` take `referenceTo "secrets"`. A service module whose own settings carry a reference, such as one a nixos-cross-config contribution delivers, types the setting with it, so the value it receives is already a reference of the kind it uses:

```nix
options.example.influxdb.writers = lib.mkOption {
  type = lib.types.attrsOf (contractsLib.types.referenceTo "secrets");
  default = { };
};

config.contracts.services.influxdb.secrets = lib.mapAttrs' (
  writer: token: lib.nameValuePair "writer-${writer}" { value.copied = token; }
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
