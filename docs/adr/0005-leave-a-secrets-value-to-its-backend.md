---
status: superseded in part by ADR-0006 and ADR-0007
---

# Leave a secret's value to its backend

A secret claim says only what its service reads and who may read it: its id, owner, group and mode, and the path and delivery that follow from them. Where the value comes from is set on the backend under the claim name, such as `age.secrets.influxdb-admin-password.generator`. nixos-config shares one value between configurations, such as a telegraf token that the influxdb node also installs, and generates values from other values, such as an htpasswd file built from client passwords on other hosts. agenix-rekey already models both: a value is its encrypted file, a file on several hosts is one value, and a generator's dependencies are other hosts' secrets. This supersedes ADR-0004.

## Considered Options

A nullable `generator` on the claim (ADR-0004) covered a value that one service owns, but had nowhere to say that two claims read one value, or that a value is built from others. Configuration-wide secret values, named by claims and holding the generator and dependencies, could say both. They would add a concept the library only translates to agenix-rekey, its one backend, and the translation fails at dependencies: agenix-rekey finds a dependency's host by the name and encrypted file of the secret there, and a value name gives neither the name nor, for a value one host generates, the file.

## Consequences

A service module that knows its secret is random writes that in its backend's terms, guarded by its contract's `enable`. The agenix-rekey adapter has no settings: agenix-rekey's own `secretsDir`, `generatedSecretsDir` and `rekeyFile` locate the files, and the adapter's check fails for a secret that ends up with no encrypted file.
