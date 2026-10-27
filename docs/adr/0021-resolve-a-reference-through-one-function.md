---
status: superseded in part by ADR-0022
---

# Resolve a reference through one function

`contracts.resolve reference` returns `{ claim; config; reason; }`: the claim-set entry the reference names, the evaluated configuration of the node that holds it (this configuration for a reference naming `contracts.node`) and a null reason, or the reason the reference names no claim. Reading `claim` or `config` while `reason` is set fails with ``nixos-contracts: cannot resolve `<node>:<kind>.<service>.<id>`: <reason>``; reading `reason` never fails. `contracts.lookup` is removed. This supersedes ADR-0012 in part, which introduced the pair `contracts.lookup`, returning the claim or a reason, and `contracts.resolve`, returning the claim or failing.

With two functions, a module chose one by whether it handled the reason, and moving between them changed its call and the shape it read. Neither returned the node's configuration, so the agenix-rekey adapter, which reads a referenced node's `age.secrets`, repeated the core's choice between this configuration and the node collection through an internal helper.

## Considered Options

- **Keep both, and add the configuration to `contracts.lookup`.** The adapter would stop repeating the core's choice, but a module would still choose between two functions with one meaning.
- **Return a null claim and configuration with a reason.** A module that reads `claim` without checking `reason` would fail later, as a missing attribute of null, far from the reference. A lazy error names the reference and the reason where the value is read.
- **Expose the node's configuration as a separate function.** It would repeat the reasons a node does not resolve, and a caller that wants both the claim and its node would resolve twice.

## Consequences

- A module that wants the claim reads `(contracts.resolve reference).claim`, and fails with the same message as before when the reference names none. A check reads `reason` from the same result.
- A secret's `sources` keep their shape, and are built through `contracts.resolve`.
- A backend adapter reads what it needs of a referenced node from the result's `config`, so the choice between this configuration and the node collection stays in the core.
