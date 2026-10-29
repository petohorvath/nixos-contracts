---
status: accepted
---

# Resolve and check a reference in the core

The core resolves a reference of any kind from the node collection at `contracts.nodes` through one function: `contracts.resolve reference` returns `{ claim; config; reason; }`, the claim-set entry, the evaluated configuration of its node and a null reason, or the reason the reference names no claim, in which case reading `claim` or `config` fails with ``nixos-contracts: cannot resolve `<node>:<kind>.<service>.<id>`: <reason>``. A reference's shape is checked first, so a value that is not an attribute set, misses one of `node`, `kind`, `service` and `id` or holds another field fails as soon as it is resolved, naming it; its names come second, so a name that breaks its rule gives a `reason`, like any other reference that names no claim. Whether a reference names a known node, a node with nixos-contracts, a claim of an enabled contract, and a secret its reader may reference ([ADR-0007](0007-say-where-a-secrets-value-comes-from-on-the-secret.md)) are facts about contracts, not about a backend, so a backend adapter reads only the claims references resolve to.

## Considered Options

- **Checks in the core, resolution in the adapter.** The lookup would sit in two places, and an adapter would check a reference and then resolve it again.
- **A node collection in the core, with the checks in the adapter.** Each backend adapter would repeat the checks.
- **A pair of functions: one returning the claim or a reason, one returning the claim or failing.** A module would choose one by whether it handles the reason, and moving between them would change its call and the shape it reads. Without the node's configuration in either, a backend adapter would repeat the core's choice between this configuration and the node collection.
- **A null claim and configuration with a reason.** A module that reads `claim` without checking `reason` would fail later, as a missing attribute of null, far from the reference. A lazy error names the reference and the reason where the value is read.
- **The node's configuration from a separate function.** It would repeat the reasons a node does not resolve, and a caller that wants both the claim and its node would resolve twice.
- **A `reason` for a malformed reference too.** The reason and the lazy error name the reference by its four fields, which a malformed reference lacks, and a label with gaps would name a reference no one wrote.
- **Failing on a name that breaks its rule.** A secret's checks read each reference's `reason` together, so one invalid name would hide the other failed checks instead of being reported among them.
- **Ignoring unknown fields.** A misspelt field, such as `servce` beside a missing `service`, would be reported as the missing field alone, and a value that only resembles a reference would pass.

## Consequences

- Reading `reason` never fails for a reference of the right shape, so a check reads the reason and a module the claim from the same result.
- A reference written as a literal, outside a typed field, gets the checks a typed field applies: a missing `kind` fails naming the reference rather than with Nix's `attribute 'kind' missing`, and a typo such as the service `web_proxy` gets a reason naming the rule rather than "no enabled contract holds it".
- The generic module reads only a node's `contracts.claimSets`, and for `contracts.resolveService` whether a contract is enabled ([ADR-0012](0012-resolve-a-services-claims-beside-a-reference.md)), so it still evaluates with a bare `lib.evalModules`, and references across nodes, in either direction, evaluate without cycles.
- The core resolves each of a secret's references through `contracts.resolve` into a source, `{ reference; reason; }`: the reference as written, and a null reason or the one its check reports ([ADR-0016](0016-hold-a-secrets-sources-on-its-copy-and-its-generator.md)). A source holds neither a claim nor a node's `config`, so a claim set stays serialisable and holds no other node's claims.
- A backend adapter reads what else it needs of a referenced node from the result's `config`, so the choice between this configuration and the node collection stays in the core. A source's `reference` passes to `contracts.resolve` as it is; a caller that passes a value with extra fields removes them first.
- Checks that concern a backend stay with its adapter, such as the agenix-rekey adapter's checks for a referenced node without the adapter and for a copy of a secret without an encrypted file.
- A prototype on the `prototype/secret-references` branch evaluated telegraf tokens copied to an influxdb node, a copy in the opposite direction and an nginx htpasswd generated from four clients' passwords across nixos-cross-config to complete NixOS systems without cycles. It held under three constraints, which the library keeps: the core does not follow a referenced secret's own references, and resolves a broken reference to nothing, so a check reports it; and the agenix-rekey adapter names its entries from its own claim set alone, since an entry whose existence depends on another node's entries recurses.
