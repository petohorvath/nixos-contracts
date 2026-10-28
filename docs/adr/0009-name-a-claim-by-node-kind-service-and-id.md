---
status: accepted
---

# Name a claim by node, kind, service and id

A claim set is nested by service and id, `contracts.claimSets.<kind>.<service>.<id>`, and names join with `_`: a backend adapter names its entry for a claim `<service>_<id>`, such as `influxdb_admin-token`, and a claim's read-only `name`, `<node>_<kind>_<service>_<id>`, such as `beta-influxdb_secrets_influxdb_admin-token`, names it across the node collection. Node identities, kind names and service names consist of lowercase letters, digits and hyphens, and claim ids may also contain `_`, so the first `_` of a backend name ends the service, the first three of a claim name end the node, the kind and the service, and both names stay unique however many `_` an id holds. A nested claim set is exact, so neither the core nor a backend adapter needs a check that no two claims share a name.

## Considered Options

- **A hyphen-joined claim name, `<service>-<id>`, as the key.** Such a name cannot always be split back: service `chrony-exporter` with claim `metrics` and service `chrony` with claim `exporter-metrics` share one. A lookup would compare each entry's service and id, and a name clash check would guard the key in the core and in every backend adapter.
- **Another separator.** `.` needs quoting in a Nix attribute name, `:` ends a systemd credential's name, `/` makes a directory, `+` already joins host and client in nixos-config's htpasswd user names, and `__` needs a rule against `_` at either end of a name.
- **An adapter-chosen name with its own clash check.** A backend keeps its names short, but each adapter restates the check, and a clash surfaces only on a node that imports the adapter.
- **A hash of the names.** It is collision-free without restricting names, but no person can tell an encrypted file or an htpasswd user from it.
- **Forbid `_` in ids, with a helper that turns a reference into a safe id.** A receiver writes one copy for each reference it reads ([ADR-0013](0013-leave-carrying-a-reference-between-nodes-to-the-fleet.md)) and needs an id for each that no other reference produces. The sent claim's `name` is such an id, while joining a reference's parts with `-` makes `a-b` + `c` and `a` + `b-c` one id, of which `lib.listToAttrs` silently keeps one. The helper adds a library function to work around a problem the rule itself creates, and every receiver must know to use it.
- **A claim name without the kind.** One service may hold claims of two kinds with one id, such as `mounts.data` and `secrets.data`, so the name would be unique only within its kind. The glossary's claim name would need a caveat, and a key built across kinds would need the whole `ref`.
- **A check that no service holds one id in two kinds.** The name stays short and unique, but the check rejects natural contracts, such as a service's `data` mount beside its `data` secret, only to protect the name.

## Consequences

- Each kind's clash rule still compares every pair of its claims; only the check on names goes.
- An adapter installs claims of one kind, so its backend names need no kind.
- A name that breaks its rule, such as the service name `web_proxy` or the claim id `Host-Key`, fails at evaluation, naming it and its allowed characters. A kind with such a name fails as it is built.
- A receiver builds a copy's id with `lib.claimNameOf`, by joining the reference's fields, without resolving it. If two receivers each keyed their copies by a resolved claim's `name`, each claim set's keys would read the other's, and the two would recurse into each other.
- nixos-config's `basic-auth` generator joins host and client with `_`, so each htpasswd user name is the client's claim `name`.
- An adapter flattens a nested claim set when it needs a list.
- Check messages name a claim `<service>.<id>`, and a reference `<node>:<kind>.<service>.<id>`. Ids may not contain `.` or `:`.
