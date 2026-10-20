/*
  Install every secret with agenix-rekey, owned and readable as its claim
  says. Where a value comes from, a generator, an encrypted file or the
  dependencies of either, is set on `age.secrets.<service>-<id>` itself.
  Requires the agenix and agenix-rekey NixOS modules;
  `nixosModules.agenix-rekey` also imports `nixosModules.default`.
*/
{ config, lib, ... }:
let
  secrets = config.contracts.claimSets.secrets;
in
{
  config = {
    age.secrets = lib.mapAttrs (_: secret: { inherit (secret) group mode owner; }) secrets;

    # Reads the final file, which agenix-rekey defaults from its
    # `generatedSecretsDir` or `secretsDir`.
    contracts.assertions = lib.mapAttrsToList (name: _: {
      assertion = config.age.secrets.${name}.rekeyFile != null;
      message = "secret `${name}` has no encrypted file: set its `age.secrets.${name}.rekeyFile`, or agenix-rekey's `age.rekey.generatedSecretsDir` when it has a generator and `age.rekey.secretsDir` when it has none.";
    }) secrets;

    # Claims of disabled contracts have no `age.secrets` entry, so they take
    # agenix's default path, which an entry keeps unless a host overrides it.
    contracts.secrets.location =
      name: config.age.secrets.${name}.path or "${config.age.secretsDir}/${name}";
  };
}
