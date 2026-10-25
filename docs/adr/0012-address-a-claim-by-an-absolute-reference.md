---
status: superseded in part by ADR-0013 and ADR-0014
---

# Address a claim by an absolute reference

A reference names one claim by its node, kind, service and id, `{ node; kind; service; id; }`, and always names its node. Every claim holds its own reference, a read-only `ref`, built from the configuration's node identity at `contracts.node`. The core resolves a reference of any kind from the node collection, through `contracts.lookup` and `contracts.resolve`. This supersedes ADR-0007 in part, which let a reference omit its node and named the claim by its claim name, and ADR-0011 in part, which gave the core no name of its own node and resolved references for secrets alone.

A reference without a node meant the claim on the node that resolves it. nixos-cross-config carries a reference from the node that sends it to the node that receives it, so a sender's reference that omitted its node named the receiver's claim of that name. In nixos-config every node runs telegraf, the influxdb node included, so a copy of that node's own `telegraf-metrics-token` passed every check. A sender also built a reference to its own claim by hand, from a node identity the library did not know, and a reference written on the receiving side spelt out the claim name, which joins service and id with a hyphen and so cannot always be split back. Readers of other kinds had no lookup at all: nixos-config's firewall and nginx modules read a backend's binds from other nodes' contracts directly, where a typo fails as a missing attribute.

## Considered Options

- **Keep the relative form and check it.** The receiver's claim of the same name is a valid claim, so no check can tell the two meanings apart.
- **How a reference says its kind.** `lib.types.referenceTo <kind>` defaults `kind` to the kind its field takes and accepts no other, so a reference written by hand is `{ node; service; id; }` and a claim's `ref` of another kind fails as a type error at its definition. Always writing `kind` repeats what the field implies; a helper function shortens it but leaves four required fields on the option; a reference without a kind cannot say what it names, so a reference of the wrong kind fails only as a missing claim.
- **What the lookup indexes.** Claim sets stay keyed by claim name, and the lookup compares the entry's service and id with the reference's. Claim sets nested by service would make the lookup exact, but every adapter would flatten them and the backends still key by claim name, so the name clash check stays either way. Reading a node's contracts instead of its claim set repeats the `enable` filter. A separator that ids cannot contain removes the ambiguity, at the cost of renaming every backend entry and encrypted file a consumer has.
- **Depend on nixos-cross-config.** The generic module evaluates under a bare `lib.evalModules`, nixos-cross-config is a NixOS module, and how a reference travels between nodes is the consumer's choice. Instead, `nixosModules.cross-config` defaults `contracts.node` and `contracts.nodes` from `crossConfig.name` and `crossConfig.nodeConfigurations`, and needs no flake input.

## Consequences

- A configuration whose claims are referenced, even by itself, sets `contracts.node`, such as through `nixosModules.cross-config`; a check fails when a node collection is given and has no node of that name. A configuration without a node collection may still set it, so it references its own claims. Without it, a claim's `ref` names a null node, which every lookup rejects with a reason pointing to `contracts.node`, rather than one that fails to read, so claim sets still serialise in a configuration that uses no references. A null node never resolves as the reading configuration's own.
- A claim's `ref` reads no claim set, so a sender that contributes it to another node adds no evaluation cycle.
- A reference of the wrong kind fails as a type error at its definition. An unknown node, a node without nixos-contracts, an unknown kind and a claim of no enabled contract are reasons `contracts.lookup` returns, which a secret's `from` reports as checks and `contracts.resolve` raises as an error.
- A reference that names `contracts.node` resolves in the configuration itself, so a copy within one configuration references the claim's own `ref`.
- The claim name stays the key of claim sets and backend entries, so encrypted files keep their names, and the name clash check stays.
- `lib.types.reference` requires `kind`; a field that takes one kind uses `lib.types.referenceTo`. Each entry of a secret's `referenced` carries the reference's fields beside the claim it resolves to.
