---
status: accepted
---

# Resolve a service's claims beside a reference

`contracts.resolveService { node; kind; service; }` returns `{ claims; config; reason; }`: every claim of one kind that one service holds on a node, keyed by id, that node's configuration and a null reason, or why no enabled contract on the node describes the service. It sits beside `contracts.resolve`, which keeps resolving one reference to one claim ([ADR-0011](0011-resolve-and-check-a-reference-in-the-core.md)). A module such as a firewall, which reads all of a backend's binds, otherwise needs a reference per bind, and so must know every id the backend's modules define.

## Considered Options

- **A reference with a null or missing `id`.** One function would keep a single entry point, but `claim` would hold one entry or a set of them by the reference's shape, and a reference without an id names no claim, so its checks and types would no longer hold.
- **Leave it to the caller, reading the result's `config`.** A caller resolving any one claim of the service gets its node's configuration, but needs an id it may not know, and reading `claimSets` itself repeats the core's choice between this configuration and the node collection.

## Consequences

- The selection is checked as a reference is: a malformed selection fails, naming it, and a name that breaks its rule gives a `reason`. Its node and kind give the reasons of `contracts.resolve`.
- An enabled contract without claims of the kind resolves to no claims rather than a reason, since its claim set has no entry for the service only because it is empty.
- A module reading a service's claims of one kind on another node calls `contracts.resolveService` and reads `claims`; a check reads `reason` from the same result.
- It reads the node's claim set and whether its contract is enabled, so two nodes that each resolve a service of the other evaluate without cycles unless one keys its own claims by what it resolved.
