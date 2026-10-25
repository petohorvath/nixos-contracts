---
status: proposed
---

# Carry claims between nodes through inboxes

A claim names the inboxes it is sent to in `sendTo`, a list of references, and an inbox is a claim of its own kind: a service's hold on a place where claims of one kind arrive from any node, the node itself included. An inbox says which kind it takes, `secrets` by default, and in `copy` whether the receiving service holds a copy of each secret it receives and with which settings, such as its group. It shows what arrived as a read-only `received`, `<node>.<service>.<id>` of `{ ref; claim; copy; }`, and as `refs`, the received references in order. The core carries every send through the node collection, so no node writes another node's options. Copies sit in `contracts.copySets.<kind>`, beside the claim sets and keyed by their location (ADR-0014), and an adapter installs both. An opt-in `contracts.checkSends` evaluates each node a second time with every inbox empty and fails, naming the claim, when what a node sends depends on what it received.

nixos-config carries each relation between nodes through its own nixos-cross-config contribution: a sending node writes the receiving node's `age.secrets` entries, nginx upstreams or influxdb authorisations in the receiver's terms, so a change to the receiving service breaks every sender without an error, and what arrives escapes the receiving contract's types, checks and ownership. With inboxes, a sender states only where its claim goes, and the receiver states what it accepts and builds its configuration from what arrived, with a typo in an inbox, a claim of the wrong kind and a disabled receiver reported as checks. A copy is a secret claim of the receiving service, typed by the secrets kind, so it takes its owner from the receiver's identity and a misspelt setting fails at its definition. This contradicts ADR-0012, which left how a reference travels between nodes to the consumer; proposed reconsideration: the core already holds the node collection (ADR-0011, ADR-0012), so carrying references through it adds no dependency, and nixos-cross-config stays for options outside contracts. It supersedes ADR-0003 in part, whose constructor now gives every claim `sendTo` and `location`, and ADR-0006 in part, which left a copy on another node to backend entries.

## Considered Options

- **A relation constructor with offers and incoming views.** Each relation is a value of its own rather than a claim, so nothing reuses the kinds' checks, and a send that depends on what arrived recurses with no message.
- **`sendTo` naming the receiving claim, whose `from` merges what arrives.** The sender writes into a claim the receiver owns, and a cycle again recurses with no message.
- **Channels with a transport port, with nixos-cross-config, the node collection and static data as adapters.** Only the node collection carried sends in practice, so the seam stayed hypothetical, and its check rejected any send that read another node, even one that would not recurse.
- **Copies in the claim sets.** A claim set's keys would depend on other nodes' claim sets, which recurses; copies keep a layer of their own.

## Consequences

- A sender names the receiver's node, service and inbox. A fleet registry may carry inbox references, so service modules do not spell them out.
- While a node collects what it sends, its inboxes are empty, so a send that depends on what arrived recurses without `contracts.checkSends` and fails with a message with it. Each node evaluates twice with the check; on six nodes of the prototype, evaluation took a third more time.
- Only secrets inboxes hold copies; an inbox of another kind sets `copy = null` and the receiver reads `received`. A copy of a copy fails its check.
- A prototype on the `prototype/claim-inboxes` branch, commit `c64870d`, evaluated six NixOS nodes, a guest inside its host included, to complete systems with and without the check: telegraf tokens copied to influxdb, binds sent to telegraf and to an nginx upstream, an htpasswd derived from four clients' passwords, and a guest's SSH host key copied to its host. The derivations matched in both modes.
