---
status: superseded in part by ADR-0018
---

# Allow `_` in a claim id, and name a claim without a location

A claim id may contain `_` besides lowercase letters, digits and hyphens. A service name or node identity still may not. A claim no longer holds a `location`:

- A backend adapter names its entry for a claim `<service>_<id>`, such as `influxdb_admin-token`.
- A claim's `name` stays `<node>_<service>_<id>`.
- The secret backend slot's `path` takes `{ service, id }`, and the delivery slot's `path` takes `{ unit, service, id }`.

This supersedes ADR-0014 in part, which forbade `_` in every name and placed a claim by its location.

Under ADR-0016, a receiver writes one copy for each reference it reads, so it needs an id for each copy that no other reference produces. A copy's id can't be the sender's `name` while ids forbid `_`. Joining a reference's parts with `-` makes `a-b` + `c` and `a` + `b-c` the same id, and `lib.listToAttrs` silently keeps only one of the two. Neither a node identity nor a service name contains `_`, so the first `_` of a backend name ends the service, and the first two of a claim name end the node and the service. Both names therefore stay unique however many `_` an id holds. ADR-0014 placed a claim by its location because an inbox's copies needed five names. Without copies, a location is always `[ <service> <id> ]`, which repeats two fields every claim already has.

## Considered Options

- **Keep the rule and provide a helper that turns a reference into a safe id.** It adds interface to work around a problem the rule itself creates, and every receiver must know to use it.
- **A hash of the reference as the id**, which ADR-0014 rejected for backend names: no one can tell an encrypted file from it.

## Consequences

- The backend names of existing claims are unchanged, and ids such as `ssh_host_ed25519_key` are valid again.
- A copy whose id is the sent claim's `name` is installed under a name such as `influxdb_beta_telegraf_token`.
- A receiver builds that id by joining the reference's `node`, `service` and `id` with `_`, without resolving the reference. If each of two receivers keyed its copies by a resolved claim's `name`, each claim set's keys would read the other's, and the two recursed into each other.
- Check messages still name a claim as `<service>.<id>`, and a reference as `<node>:<kind>.<service>.<id>`. Ids still forbid `.` and `:`.
