---
status: superseded in part by ADR-0011
---

# Reference another secret by node and claim name

A secret claim names the secrets its value comes from in a `from` field. Each reference is a claim name, with the name of the node that holds the secret when that is another configuration, such as `{ node = "beta-grafana"; name = "telegraf-metrics-token"; }`. Without `generate`, the secret is a copy of the one secret it references; with `generate`, the generator makes its value from the secrets it references. This supersedes ADR-0006 in part, which left copies and derived values to backend entries that the fleet layer writes. In nixos-config the sending configuration wrote those entries in the receiving configuration's terms, its group, mode and installed path, so a change to the receiving service broke every sender without an error, and the copies escaped the receiving contract's ownership, clash checks and `path`. A reference is plain data that nixos-cross-config carries into the receiving service's settings, so the receiving service holds the claim and wires its daemon from it. A backend adapter resolves the reference: the agenix-rekey adapter reads the named node's `age.secrets` entry. agenix-rekey finds the node of a dependency by its name and encrypted file, and the entry gives both, which ADR-0005 found a value name could not.

## Considered Options

Keeping ADR-0006, with the receiving service module writing the backend entry of a copy itself, needs no library change, but leaves part of each secret outside its claim and ties every receiving service module to agenix-rekey. An opaque handle, a read-only field a backend adapter sets on every secret and a module passes into `from`, keeps node names out of contracts, but needs a field and a backend rule more, cannot be checked before the backend uses it, does not serialise, and `lib.mkDefaultContract` would recurse into it. A claim name alone is unique only within one configuration: every node running telegraf holds `telegraf-metrics-token`.

## Consequences

- A contract may name another node, in `from` only. The generic module treats a node's name as an opaque string; a backend adapter resolves it from a collection of nodes it is given.
- A prototype on the `prototype/secret-references` branch evaluated, across nixos-cross-config and to complete NixOS systems without cycles, telegraf tokens copied to an influxdb node, a copy in the opposite direction and an nginx htpasswd generated from four clients' passwords. It holds under three constraints on the adapter: it takes the names of backend entries from the claim set alone, since an entry whose existence depends on another node's entries recurses; it does not follow a referenced secret that has `from` of its own; and it resolves a broken reference to nothing, so a check reports it.
- Checks fail for a reference to an unknown node, for one to a node without nixos-contracts, for one to a name that is no secret claim of an enabled contract on that node, for one to a secret with `from` of its own, which also catches two copies referencing each other, to a secret on a node without the adapter, and for several references without `generate`.
- One value read by two claims of one configuration is a copy whose reference omits the node.
- Claim names become part of other configurations' references, and with agenix-rekey's `basic-auth` generator part of an htpasswd user name, so renaming a service or a claim fails the references to it and changes those user names.
- Key pairs whose public half other configurations read, such as WireGuard keys, still need a claim kind of their own.
