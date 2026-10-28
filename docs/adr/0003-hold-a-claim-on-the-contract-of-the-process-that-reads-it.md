---
status: accepted
---

# Hold a claim on the contract of the process that reads it

A claim sits on the contract of the process that reads it. Any module of a node may add claims to a contract of that node, and a contract holds no other contract. nixos-config's 22 integrations, slices nested in a service's contract, fall into five shapes, and the rule places each without a concept of its own:

- **A helper with its own process**, such as a metrics exporter or the ACME client beside nginx, is a service with its own contract and identity, even an identity it shares with the service it serves.
- **A feature of a service's own process that holds a claim**, such as the token telegraf writes to each store with, adds the claim to the service's contract from the feature's own module.
- **A relation between services on two nodes**, such as a store reading a client's token, is a claim on each side, one per process that reads the value. The receiving service declares its claim as a copy, from a reference the fleet carries to it ([ADR-0013](0013-leave-carrying-a-reference-between-nodes-to-the-fleet.md)).
- **Publishing through a proxy** names virtual hosts and proxy networks, fleet concepts that no contract names. The one secret it involves, an htpasswd file, is a claim of the proxy generated from references.
- **A feature that holds no claim**, such as nginx's status page on a bind nginx already holds, and settings derived from the fleet, such as chrony's allow-list, leave the contract alone.

## Considered Options

- **Nested integrations.** They need an `enable` of their own, a check against a misspelt integration id, and a fold of each kind over the service's integrations, and they were the largest single source of complexity in nixos-config's design. Their claims take the service's identity, which is wrong for a helper that runs as another account: nginx's `acme` slice states the owner of its own mount to work around it.
- **A claim kind that relates one service to another**, such as `uses`. It has no adapter to read it, since nixos-config opens its firewall from fleet-wide exports and a proxy does not enumerate its clients.
- **A field that names the service a helper serves**, such as `partOf`. It has no reader either.

## Consequences

- An exporter's bind belongs to the exporter's contract, not to the service it observes, and the exporter states an identity, even one it shares with that service. A helper's identity reads the daemon's own option where nixpkgs has one, such as an exporter's `user`, so the contract follows what the unit runs as.
- A contract's claims may come from several modules, which the module system merges by claim id. Two definitions of one field at one priority that differ fail to evaluate, and equal ones merge into one claim.
- A module derives or conditions its claims from its own settings or the daemon's options. A `lib.mkIf` that wraps a whole contract and reads `contracts.*` recurses, since the set of contracts then depends on itself, while one at a claim does not.
- What an integration conveyed beyond its claims, such as "this exporter observes chrony", stays in the helper's name and in the modules that pair the two.
