---
status: superseded in part by ADR-0017 and ADR-0018
---

# Name a claim by its location

A claim set is nested by service and id, `contracts.claimSets.<kind>.<service>.<id>`, and every claim holds its read-only `location`, the list of names that place it within its node: `[ <service> <id> ]` for a claim its contract holds. A backend adapter names its entry for a claim by joining the location with `_`, such as `influxdb_admin-token`, and the backend slot's `path` takes a location. Service names, claim ids and node identities consist of lowercase letters, digits and hyphens, so no name contains `_` and two locations never make one name. A claim's read-only `name` joins its node identity, service and id with `_`, such as `beta-influxdb_influxdb_admin-token`, and names it across the node collection, such as in an htpasswd user name. This supersedes ADR-0012 in part, which kept claim sets keyed by claim name and rejected both a nested claim set and a separator ids cannot contain, and ADR-0003 in part, which keyed claim sets by `<service>-<id>` and checked that no two entries share a name.

A claim name joined with a hyphen cannot always be split back, so the lookup compared each entry's service and id, a name clash check guarded the key, and every backend adapter repeated that check for its own names. ADR-0015 holds copies whose location has five names, `[ <service> <inbox> <node> <service> <id> ]`, which no `<service>-<id>` key places. A location is exact, so the lookup indexes the claim set and the clash check goes; a separator the names forbid keeps a backend's names exact too. Each other separator fails a backend: `.` needs quoting in a Nix attribute name, `:` ends a systemd credential's name, `/` makes a directory, `+` already joins host and client in nixos-config's htpasswd user names, and `__` needs a rule against `_` at either end of a name. A claim is called by its `location` because a bind already has `addresses`.

## Considered Options

- **Keep the claim name as the key.** Encrypted files keep their names, but a copy needs a key the claim name cannot express, and the clash check stays in the core and in every backend adapter.
- **An adapter-chosen name with its own clash check.** A backend keeps its names short, but each adapter restates the check, and a clash surfaces only on a node that imports the adapter.
- **A hash of the location.** It is collision-free without restricting names, but no person can tell an encrypted file or an htpasswd user from it.

## Consequences

- Every backend entry and encrypted file is renamed, such as `influxdb-admin-token.age` to `influxdb_admin-token.age`, which agenix-rekey rekeys once.
- A service name, claim id or node identity with `_` or an uppercase letter fails as a type error, so nixos-config renames ids such as `ssh_host_ed25519_key`.
- An adapter flattens a nested claim set when it needs a list, which the preservation adapter now does for mounts.
- The secret backend slot's `location` becomes `path`, and the delivery slot's `path` takes `{ unit, location }`, superseding ADR-0010 in part.
- nixos-config's `basic-auth` generator joins host and client with `_` rather than `+`, so each htpasswd user name is the client's `name`.
- A prototype on the `prototype/claim-inboxes` branch, commit `c64870d`, nested the claim sets and named backend entries from locations across six NixOS nodes. It joined the names with `-`, and the claim's `name` was not part of it.
