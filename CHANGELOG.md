# Changelog

## Unreleased

### Added

- Contracts at `contracts.services.<service>`, each with an `enable` and a required static or dynamic `identity`.
- Claim kinds `binds`, `mounts` and `secrets`, whose mount and secret owners and groups default from the service's identity, and whose secrets name the generator of a value the service makes on its own in `generate` and leave the rest of their values to the backend, with read-only claim sets at `contracts.claimSets.<kind>` and clash checks in `contracts.assertions`. A further check fails when a dynamic identity cannot read its secrets, whether or not a backend is imported, and one when a secret's `generate` names a generator no backend adapter provides. A secret's `path` and `contracts.secrets.location` are never null: without a secret backend adapter, reading a `path` or serialising `contracts.claimSets.secrets` fails with an error naming the missing adapter, so import one, or set `contracts.secrets.location`, first.
- `contracts.mounts.classes`, the `contracts.secrets.location` and `contracts.secrets.delivery` rules for adapters, and the `contracts.secrets.generators` vocabulary they set.
- `lib.mkClaimKind`, for defining further claim kinds with their own clash and check rules, whose check rule reads the configuration's settings, and `lib.mkDefaultContract`, for contracts a host can override field by field.
- Checks in `contracts.assertions`, written without the library's prefix, and the read-only `contracts.failures`, the prefixed messages of the failed ones.
- `nixosModules.default`, which forwards the failed checks to NixOS `assertions`, and `modules.generic.default` for any module class.
- Examples for a static-identity service (influxdb2), a dynamic-identity service (alloy) and a project-defined claim kind, evaluated by the checks.
- Adapters `nixosModules.preservation` (mounts into `preservation.preserveAt` by class root), `nixosModules.agenix-rekey` (secrets into `age.secrets` with their owner, group, mode and generator, the rest of a value set on the same entry, `contracts.secrets.generators` from `age.generators`, and a check for a secret without an encrypted file), and `nixosModules.systemd-credentials` (a dynamic identity's secrets into its unit's `LoadCredential=`).
