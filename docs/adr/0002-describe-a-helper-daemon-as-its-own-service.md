---
status: accepted
---

# Describe a helper daemon as its own service

A contract has no integrations. A helper with its own process, such as a metrics exporter beside chrony, gets its own contract with its own identity and claims, and a configuration that wants to group the two does so in its own modules. In the earlier design an integration was a slice attached to its parent's contract that took the parent's identity. It needed its own enable flag and a separate check against misspelled integration ids, and it was the largest single source of complexity in that design.

## Consequences

An exporter's bind belongs to the exporter's contract, not to the service it observes, and the exporter must state an identity, even one it shares with the parent. Whatever an integration conveyed beyond its claims, such as "this exporter observes chrony", is not part of v0. If needed later, it becomes a claim kind referencing another contract, not a slice nested inside one.
