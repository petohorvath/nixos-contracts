---
status: accepted
---

# Put the kind into a claim's name

A claim's `name` joins its node identity, kind, service and id with `_`, `<node>_<kind>_<service>_<id>`, such as `beta-influxdb_secrets_influxdb_admin-token`. A kind's name may contain only lowercase letters, digits and hyphens, so the first three `_` of a claim name end the node, the kind and the service. This supersedes ADR-0014 and ADR-0017 in part, which joined only the node identity, service and id.

A claim set is nested by kind, so no two claims of one kind share a service and id, but one service may hold claims of two kinds with one id, such as `mounts.data` and `secrets.data`. Both got the name `<node>_<service>_data`, so a name was unique only within its kind, while the glossary's claim name names a claim across the node collection. With the kind, a claim's `name` is unique in the node collection and determines its `ref`.

The kind costs length, not correctness. Every use of a name today stays within one kind: a copy's id and an htpasswd user name are both of secrets. Neither is typed by hand: a receiver joins a reference's fields into a copy's id, and a client reads its claim's `name`.

## Considered Options

- **Keep the name and say it is unique within a kind.** The names stay short. However, the glossary's claim name would need a caveat, a key built across kinds would need the whole `ref`, and the name would not determine the claim it names.
- **Check that no service holds one id in two kinds.** The name stays short and becomes unique. However, the check rejects contracts that are natural, such as a service's `data` mount beside its `data` secret, only to protect the name.

## Consequences

- A copy's id, which joins a reference's fields into the sent claim's name, joins `node`, `kind`, `service` and `id`, so a copy is installed under a name such as `influxdb_metrics_secrets_telegraf_token`.
- An htpasswd user name that takes its client's `name` gains the kind, such as `beta-grafana_secrets_grafana_loki-password`, so each client takes its new user name.
- Backend names stay `<service>_<id>`: an adapter installs claims of one kind, so its entries need no kind.
- A kind whose name contains `_` or an uppercase letter fails as it is built, naming the kind and the allowed characters.
