---
status: accepted
---

# Leave carrying a reference between nodes to the fleet

nixos-contracts carries nothing between nodes. A sending node makes its claim's `ref` available through shared data the fleet already has, such as a nixos-registry field of `lib.types.referenceTo` values. The receiving node then writes its own claims from the references it reads there: a copy of each with `value.copied`, or one secret `value.derived.from` all of them. It reads a claim of any other kind through `contracts.resolve`. This supersedes ADR-0015, which carried claims through inboxes, and returns to ADR-0012's stance that how a reference travels between nodes is the consumer's choice.

In nixos-config, every relation between nodes is one of three shapes:

- discovery, such as a store's URL, which nixos-registry carries
- options written on another node, such as a proxy's virtual hosts, which nixos-cross-config carries
- a credential handed to another node

Inboxes served only the third shape, and all they carried there was a list of references. Because a claim named its inboxes in `sendTo`, a node's sends depended on all of its claim sets. To keep that from recursing, copies were held outside the claim sets, each kind exposed its claim type to the inboxes kind, kinds declared whether they were sendable, and a second evaluation per node (`contracts.checkSends`) was needed to name the cycle. ADR-0015's reason for inboxes still holds without them. A nixos-cross-config contribution is written in the receiver's terms, while shared data holds only the sender's own `ref`, and the claims the receiver writes from it are typed and checked like any other.

## Considered Options

- **Keep inboxes and simplify them.** Declaring sends beside the claims, rather than on them, removes the cycle, so copies can join the claim sets and the second evaluation goes. The core would still hold a transport for one relation shape, with its own vocabulary: inbox, send, received.
- **nixos-cross-config as the carrier.** The sender writes the receiver's options, which ADR-0015 rejected for the reason above.
- **A transport seam with adapters**, as ADR-0015 also rejected. In practice there is one carrier per fleet, which it already has.

## Consequences

- The `inboxes` kind, `sendTo`, `lib.mkClaimKind`'s `sendable`, `contracts.checkSends` and the copies an inbox held all go, and adapters read only claim sets. None of these were released.
- A receiver's claim set may depend on references read from shared data. nixos-registry reads each node's contributions and never its claim sets, so two nodes that hand each other references evaluate without a cycle. A node whose contribution reads what it received still recurses.
- Nothing reports a missing or disabled receiver, since the core does not know who reads a `ref`. A reference to an unknown node or claim fails the receiver's check, and one of another kind fails `lib.types.referenceTo` where it is contributed.
- A receiver gets the references in the order its shared data gives them. Where the order shows in what it builds, such as an htpasswd, it sorts them, for example by claim `name`.
- `nixosModules.cross-config` goes. A fleet sets `contracts.node` and `contracts.nodes` itself, as it does for nixos-registry or nixos-cross-config.
- A prototype on the `prototype/registry-references` branch, commit `727b097`, evaluated four NixOS nodes that contributed their claims' refs to nixos-registry. The receivers built:
  - an htpasswd derived from four clients on three nodes
  - four copies, each with its InfluxDB auth
  - nginx upstreams, with ports read through `contracts.resolve`

  Nothing recursed. A mistyped node failed the receiver's check, a reference of another kind failed the registry's type, and a disabled receiver went unreported.
