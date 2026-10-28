---
status: accepted
---

# Address a claim by an absolute reference

A reference names one claim by its node, kind, service and id, `{ node; kind; service; id; }`, and always names its node, so it means the same claim on every node that reads it. Every claim holds its own reference, a read-only `ref`, built from the configuration's node identity at `contracts.node` ([ADR-0010](0010-require-a-node-identity.md)). A reference without a node would mean the claim on the node that resolves it, so a sender's reference carried to a receiver would name the receiver's claim of that name.

## Considered Options

- **A relative reference, checked.** In nixos-config every node runs telegraf, the influxdb node included, so a copy of that node's own telegraf token would pass every check: the receiver's claim of the same name is a valid claim, and no check can tell the two meanings apart.
- **An opaque handle**, a read-only field a backend adapter sets on every secret and a module passes on. It keeps node names out of contracts, but needs a field and a backend rule more, cannot be checked before the backend uses it, does not serialise, and `lib.mkDefaultContract` would recurse into it.
- **Always writing `kind`.** It repeats what a typed field implies, and a reference without a kind cannot say what it names, so a reference of the wrong kind would fail only as a missing claim. A helper such as `lib.mkReference` shortens a reference built in code, but does not replace a typed field defaulting the kind.
- **Depending on nixos-cross-config** for the node identity and node collection. The generic module evaluates under a bare `lib.evalModules`, nixos-cross-config is a NixOS module, and how a reference travels between nodes is the fleet's choice ([ADR-0013](0013-leave-carrying-a-reference-between-nodes-to-the-fleet.md)).

## Consequences

- `lib.types.reference` is the type of a reference of any kind, and `lib.types.referenceTo <kind>` the type of a reference of one kind, whose `kind` defaults to it and accepts no other, so a reference written by hand in a typed field is `{ node; service; id; }`. `lib.mkReference` builds one in code.
- A sender passes its claim's `ref` rather than building a reference from a node identity the library does not know. A `ref` reads no claim set, so contributing it to another node adds no evaluation cycle.
- A reference of the wrong kind, or with a name that breaks its rule, fails as a type error where it is written ([ADR-0009](0009-name-a-claim-by-node-kind-service-and-id.md)).
- A module that reads another node's claim of any kind, such as a backend's bind, resolves a reference rather than reading that node's contracts, where a typo fails as a missing attribute.
- A reference that names `contracts.node` resolves in the configuration itself, so a copy within one configuration references the claim's own `ref`.
- References become part of other configurations, so renaming a service or a claim fails the references to it.
