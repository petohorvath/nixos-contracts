# Changelog

## Unreleased

### Added

- Contracts at `contracts.services.<service>`, each with an `enable` and a required static or dynamic `identity`.
- Claim kinds `binds`, `mounts` and `secrets`, whose mount and secret owners and groups default from the service's identity, and whose secrets name the generator of a value the service makes on its own in `generate` and leave the rest of their values to the backend, with read-only claim sets at `contracts.claimSets.<kind>` and clash checks in `contracts.assertions`. A further check fails when a dynamic identity cannot read its secrets, whether or not a backend is imported, and one when a secret's `generate` names a generator no backend adapter provides. A secret's `path` and `contracts.secrets.location` are never null: without a secret backend adapter, reading a `path` or serialising `contracts.claimSets.secrets` fails with an error naming the missing adapter, so import one, or set `contracts.secrets.location`, first.
- `contracts.mounts.classes`, the `contracts.secrets.location` and `contracts.secrets.delivery` rules for adapters, and the `contracts.secrets.generators` vocabulary they set.
- `lib.mkClaimKind`, for defining further claim kinds with their own clash and check rules, whose check rule reads the kind's settings, and `lib.mkDefaultContract`, for contracts a node can override field by field, including claims held under `lib.mkIf` or `lib.mkMerge`.
- Checks in `contracts.assertions`, written without the library's prefix, and the read-only `contracts.failures`, the prefixed messages of the failed ones.
- `nixosModules.default`, which forwards the failed checks to NixOS `assertions`, and `modules.generic.default` for any module class.
- Examples for a static-identity service (influxdb2), a dynamic-identity service (alloy) and a project-defined claim kind, evaluated by the checks.
- Adapters `nixosModules.preservation` (mounts into `preservation.preserveAt` by class root), `nixosModules.agenix-rekey` (secrets into `age.secrets` with their owner, group, mode and generator, the rest of a value set on the same entry, `contracts.secrets.generators` from `age.generators`, and a check for a secret without an encrypted file), and `nixosModules.systemd-credentials` (a dynamic identity's secrets into its unit's `LoadCredential=`).
- A secret's `from`, a list of references to the secrets its value comes from, each a claim name or `{ node; name; }` for a secret another configuration holds. Without `generate` the secret is a copy; with it, the generator makes the value from the referenced secrets. The agenix-rekey adapter resolves references from its new `contracts.adapters.agenix-rekey.nodes` setting into the copy's `rekeyFile` and the generator's `dependencies`, with checks for an unknown node, a name that is no secret claim of an enabled contract, a referenced secret with `from` of its own, a referenced node without the agenix-rekey adapter, and several references without `generate`. An example shares one token between two nodes.

### Migration

- A service module that names a secret's generator on the backend, as in `age.secrets.<service>-<id>.generator.script = "alnum";`, names it on the claim instead: `secrets.<id>.generate = "alnum";`.
- A configuration that copies another configuration's secret by writing `age.secrets.<name>.rekeyFile` and the receiver's group, mode and installed path on the sender's side declares a copy on the receiving service instead, as `secrets.<id>.from = [ { node = "<sender>"; name = "<service>-<id>"; } ]`, and gives the agenix-rekey adapter its nodes at `contracts.adapters.agenix-rekey.nodes`. A generator's dependencies set on `age.secrets.<name>.generator.dependencies` move to the claim's `from` the same way.
- A `lib.mkClaimKind` check rule receives `settings` beside `identity` and `claim`, so a rule written as `{ identity, claim }:` must accept it, for example as `{ identity, claim, ... }:`.
