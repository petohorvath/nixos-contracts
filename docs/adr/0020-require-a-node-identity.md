---
status: accepted
---

# Require a node identity

`contracts.node` is required, with no default, in the generic module and in `nixosModules.default`, and the core's checks read it, so a configuration without one fails to evaluate them with an error naming the option. A reference's `node` is a string, and a claim's `name` is never null. This supersedes ADR-0012 in part, which kept `contracts.node` null by default so a configuration that uses no references needed no node identity.

The null node bought one thing: a configuration outside a fleet could skip one line. It cost a second mode everywhere a node is read. A claim's `ref` named a null node and its `name` was null, the lookup had a reason for a null node, messages labelled it `<no node>`, the reference type accepted null alongside a string, and a reference that a claim built before its configuration had a node identity failed only where something resolved it. Every consumer of `ref` or `name` had to handle a value that never names a claim.

## Considered Options

- **Keep the null default.** The second mode stays, and a configuration learns it lacks a node identity only when a reference fails to resolve, far from the cause.
- **Default to the host name in the NixOS module.** A node identity is independent of its host name, and every NixOS configuration that sets no host name is `nixos`, so two forgotten nodes would give the same references and claim names without any error. The generic module has no host name, so the two modules would differ.
- **Require it only when a claim's `ref` or `name` is read.** An unread option fails only when read, so a configuration whose claims nothing references would evaluate without a node identity until a module first reads one. The checks read it instead, so every configuration fails the same way.

## Consequences

- Every configuration that imports a nixos-contracts module sets `contracts.node`, including one outside a fleet, such as with its host name.
- A configuration with a node collection lists itself in it, or the existing check that `contracts.node` is in a non-empty `contracts.nodes` fails.
- A hand-written reference with a null node fails as a type error where it is written, in a field typed `lib.types.reference` or `lib.types.referenceTo`.
