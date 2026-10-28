---
status: accepted
---

# Leave carrying a reference between nodes to the fleet

nixos-contracts carries nothing between nodes: a sending node makes its claim's `ref` available through shared data the fleet already has, such as a nixos-registry field of `lib.types.referenceTo` values, and the receiving node writes its own claims from the references it reads there, a copy of each with `value.copied`, as `lib.copiesOf` does, or one secret `value.generated.from` all of them. In nixos-config, every relation between nodes is discovery, such as a store's URL, which nixos-registry carries; options written on another node, such as a proxy's virtual hosts, which nixos-cross-config carries; or a secret handed to another node. A transport in the library would serve only the third, and all it would carry there is a list of references, which shared data already carries.

## Considered Options

- **Inboxes**, built and prototyped but never released. A claim named the inboxes it was sent to in `sendTo`, an inbox was a claim kind of its own, and the core carried every send through the node collection. Since a claim named its inboxes, a node's sends depended on all of its claim sets. To keep that from recursing, copies were held outside the claim sets, each kind exposed its claim type to the inboxes kind, kinds declared whether they were sendable, and a second evaluation per node, `contracts.checkSends`, named the cycle, at a third more evaluation time.
- **Inboxes with sends declared beside the claims.** It removes the cycle, so copies can join the claim sets and the second evaluation goes, but the core would still hold a transport for one relation shape, with its own vocabulary: inbox, send, received.
- **nixos-cross-config as the carrier.** A contribution is written in the receiver's terms, its group, mode and installed path, so a change to the receiving service breaks every sender without an error, and what arrives escapes the receiving contract's types, checks and ownership. Shared data holds only the sender's own `ref`, and the claims the receiver writes from it are typed and checked like any other.
- **A transport seam with adapters.** In practice there is one carrier per fleet, which it already has.

## Consequences

- A receiver reads a claim of any other kind, such as a backend's bind, through `contracts.resolve`.
- A receiver's claim set may depend on references read from shared data. nixos-registry reads each node's contributions and never its claim sets, so two nodes that hand each other references evaluate without a cycle. A node whose contribution reads what it received still recurses.
- Nothing reports a missing or disabled receiver, since the core does not know who reads a `ref`. A reference to an unknown node or claim fails the receiver's check, and one of another kind fails `lib.types.referenceTo` where it is contributed.
- A receiver gets the references in the order its shared data gives them. Where the order shows in what it builds, such as an htpasswd, it sorts them, for example by claim `name`.
- A fleet sets `contracts.node` and `contracts.nodes` itself, as it does for nixos-registry or nixos-cross-config.
- A prototype on the `prototype/registry-references` branch, commit `727b097`, evaluated four NixOS nodes that contributed their claims' refs to nixos-registry. The receivers built an htpasswd generated from four clients on three nodes, four copies, each with its InfluxDB auth, and nginx upstreams, with ports read through `contracts.resolve`. Nothing recursed. A mistyped node failed the receiver's check, a reference of another kind failed the registry's type, and a disabled receiver went unreported.
