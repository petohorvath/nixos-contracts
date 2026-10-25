---
status: superseded in part by ADR-0007, ADR-0013 and ADR-0015
---

# Mark a secret the service generates

A secret claim names its generator in a nullable `generate` field, such as `generate = "alnum"`, and a backend adapter turns it into the backend's generator. This supersedes ADR-0005 in part. Whether a service makes its own value is a fact the service module knows, while sharing a value or deriving it from others relates configurations, which a contract never names. ADR-0005 left both to the backend, so a service module with a generated secret wrote `age.secrets.<claim name>.generator` itself, typed the claim name by hand and failed to evaluate without agenix. With `generate`, a service module writes no backend option. The fleet layer still writes everything that relates configurations on the backend entry, under the claim's `name`. A generator script set on that entry overrides `generate`, while its dependencies keep it; only `generate = null` on the claim removes the generator, so whether the service makes its value stays stated in one place. The vocabulary of generator names is `contracts.secrets.generators`, set by a backend adapter, so a check catches a misspelt name at evaluation, and no check runs without a backend.

## Considered Options

A tag holding `provided = { }` or `generated = <name>` (ADR-0004's rejected `provenance`) needed `lib.mkForce` to switch, and an empty attribute set to say "provided". A helper that returns the backend entry of a claim fixed the hand-typed name, but still tied the service module to one backend. A generator described by its output, such as a length and a character set, has no counterpart for a generator like `dhparams`, so `generate` names one of the backend's generators instead.

## Consequences

The secret cases that relate configurations remain backend entries written by the fleet layer, as in ADR-0005:

- **Derived values**, such as an htpasswd file built from client passwords: the claim may say `generate = "basic-auth"`, but the dependencies are set on the backend entry.
- **Copies on another configuration**, such as a telegraf token installed on the influxdb node: not a claim on either configuration.
- **Key pairs**, such as WireGuard or SSH host keys, whose public half other configurations read: these need a claim kind of their own.
- **One value read by two claims of one configuration**: two claims with `generate` get two values, so the backend entry of one names the other's encrypted file.

`generate` names the backend's generators, so a configuration that changes its backend may need to rename them. The check rule of `lib.mkClaimKind` also receives the kind's `settings`, so the secrets check reads `contracts.secrets.generators`. The check rule receives only the kind's own settings, not the whole configuration, so a check stays free of options outside `contracts`. The claim type still receives the whole configuration, which this decision leaves unchanged.
