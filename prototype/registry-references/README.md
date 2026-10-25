# PROTOTYPE: references through nixos-registry instead of inboxes

Throwaway. It answers one question: can nixos-registry carry the references of nixos-contracts claims between nodes, so receivers build every cross-node relation themselves, with no `sendTo`, no inbox and no nixos-cross-config?

## Run

```bash
nix eval --impure --json --expr 'import ./prototype/registry-references { }'
nix eval --impure --json --expr 'import ./prototype/registry-references { scenario = "typo-node"; }'
```

Scenarios: `default`, `typo-node`, `wrong-kind` and `disabled-receiver`. The output shows the proxy's upstreams, vhosts and htpasswd, the store's copies and auths, and every node's contract failures and failed NixOS assertions.

## Setup

Four NixOS nodes, evaluated with `lib.nixosSystem` on this flake's locked Nixpkgs, with agenix, agenix-rekey and this repository's `agenix-rekey` and `systemd-credentials` adapters. nixos-registry is the revision nixos-config locks, `28965e3`, called through `mkRegistry`.

| Node      | Runs                                      |
| --------- | ----------------------------------------- |
| `logs`    | loki, alloy, telegraf                     |
| `metrics` | alloy, grafana, telegraf                  |
| `store`   | influxdb, telegraf, writing to itself     |
| `proxy`   | nginx, alloy, shipping its logs to itself |

[schema.nix](schema.nix) is the shared schema: node addresses, service instances with exports whose `bind` is a `referenceTo "binds"` and whose `vhost` holds the proxy settings, Loki `clients`, and stores keyed by name with `writers` and `readers`. Contributed references are keyed by the claim's `name`.

[modules.nix](modules.nix) holds the service modules. Each one contributes its own claims' `ref`, and the receivers build everything else:

- nginx builds upstreams from the registry's exports, with the port from `contracts.resolve` and the address from the registry. It also builds each vhost from its typed settings, and holds an htpasswd claim per basic-auth instance, `derived.from` the instance's clients.
- influxdb holds one `copied` claim per contributed token and provisions one auth per token, reading the bucket from the store and the permission from the role.

## Verdict

Yes. `default` evaluates with no contract failures and no failed NixOS assertions:

- The proxy's htpasswd depends on four clients' entries on three nodes, its own included. Its users, rebuilt the way agenix-rekey's `generate` builds a generator's `deps`, equal the user names the clients authenticate with, which are their claims' `name`s (`usersMatchClients = true`).
- The store holds four copies, its own telegraf's included. Each is owned `root:influxdb2` with mode `0440` and reads its sender's encrypted file. The store provisions four auths: read-write for writers, read-only for grafana.
- Upstreams are `10.0.0.2:3100` and `10.0.0.4:8086`, and the vhosts carry each backend's settings.
- No relation recursed.

Failure modes:

| Scenario            | Result                                                                                                                                            |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `typo-node`         | The receiver's contract check fails: ``it references `metrix:secrets.telegraf.system-metrics-token`: node `metrix` is not in `contracts.nodes`.`` |
| `wrong-kind`        | The registry fails at the contribution: ``services.loki.main.clients.wrong.kind' is not of type `value "secrets"`…``, naming node `metrics`.      |
| `disabled-receiver` | Silent: the store holds no copies, and no node fails. Inboxes reported this on the sender.                                                        |

Gaps found:

- The receiver chooses each copy's id. Ids allow no `_`, so joining a reference with `-` is ambiguous in principle (`a-b` + `c` against `a` + `b-c`).
- A schema keyed through another collection would make a sender read the combined data to choose its key, which recurses, so stores are keyed by name rather than nested under their influxdb instance. This follows from nixos-registry's documented rules; the prototype does not exercise it.
- A disabled or missing receiver goes unreported.
