---
status: accepted
---

# Resolve a reference in the core from the node collection

The core resolves a secret's references, from a node collection at `contracts.nodes`, and checks them; a backend adapter reads only the claims they resolve to. This supersedes ADR-0007 in part, which left a node's name opaque to the generic module and gave the collection, the resolution and every check of a reference to the backend adapter. Whether a reference names a known node, a node with nixos-contracts, a secret claim of an enabled contract and a secret without `from` of its own are facts about contracts, not about a backend, so each backend adapter would repeat them, and the agenix-rekey adapter checked a reference and then resolved it again. A reference without a node still names a secret of this configuration, so the core needs no name of its own node.

## Considered Options

Checks in the core with resolution left to the adapter keep one lookup in two places. A node collection in the core with the checks left to the adapter gives later claim kinds a shared collection, but each backend adapter still repeats the checks. Keeping ADR-0007 costs nothing while agenix-rekey is the only backend, but ties the collection to it, and the key-pair kind ADR-0007 foresees, whose public halves other configurations read, would need a collection of its own. References as a feature of `lib.mkClaimKind`, available to every kind, wait for a second kind that has them; the resolver takes a kind's name, so that kind can reuse it.

## Consequences

- `contracts.adapters.agenix-rekey.nodes` becomes `contracts.nodes`, with the same lazy entries, each with its evaluated `config`. The generic module reads only `contracts.claimSets.secrets` of a node, so it still evaluates with a bare `lib.evalModules`.
- A secret carries a read-only `referenced`: for each reference in `from`, the claim it resolves to, or null when a check rejects it. The agenix-rekey adapter maps those claims to their nodes' `age.secrets` entries.
- The checks for an unknown node, a node without nixos-contracts, a name that is no secret claim of an enabled contract, and a secret with `from` of its own move to the secrets kind. The check for a node without the agenix-rekey adapter stays with the adapter, as does the one for a copy of a secret without an encrypted file.
- The constraints of ADR-0007's prototype move with the resolution: the core does not follow a referenced secret that has `from` of its own, and resolves a broken reference to null.
- A `lib.mkClaimKind` check rule receives the top-level `config`, which the secrets kind reads the node collection from, and may return a list of reasons, so each rejected reference of one secret fails its own check.
- The reference type is exported as `lib.types.reference` and used for `from`, so a receiving service's settings that carry a reference into `from` take the same type.
