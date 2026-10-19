/*
  Install every secret with agenix-rekey. A provided secret's encrypted file
  is `<secretsDir>/<service>-<id>.age` unless `rekeyFiles` names another; a
  generated one names its agenix-rekey generator. Requires the agenix and
  agenix-rekey NixOS modules; `nixosModules.agenix-rekey` also imports
  `nixosModules.default`.
*/
{ config, lib, ... }:
let
  cfg = config.contracts.adapters.agenixRekey;
  secrets = config.contracts.claimSets.secrets;

  # The encrypted file of a provided secret, or null when none is known.
  rekeyFileOrNull =
    name:
    cfg.rekeyFiles.${name}
      or (if cfg.secretsDir != null then cfg.secretsDir + "/${name}.age" else null);
in
{
  options.contracts.adapters.agenixRekey = {
    secretsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The directory holding provided secrets as `<service>-<id>.age`.
        A check fails when a provided secret needs it and it is null.
      '';
    };
    rekeyFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = ''
        Encrypted files of provided secrets that do not follow the
        `secretsDir` convention, by `<service>-<id>` name.
      '';
    };
  };

  config = {
    age.secrets = lib.mapAttrs (
      name: secret:
      let
        rekeyFile = rekeyFileOrNull name;
      in
      {
        inherit (secret) group mode owner;
      }
      // (
        if secret.provenance ? generated then
          { generator.script = secret.provenance.generated; }
        else
          lib.optionalAttrs (rekeyFile != null) { inherit rekeyFile; }
      )
    ) secrets;

    contracts.assertions = lib.mapAttrsToList (name: _: {
      assertion = rekeyFileOrNull name != null;
      message = "provided secret `${name}` needs `contracts.adapters.agenixRekey.secretsDir` or an entry in its `rekeyFiles`.";
    }) (lib.filterAttrs (_: secret: secret.provenance ? provided) secrets);

    # Claims of disabled contracts have no `age.secrets` entry, so they take
    # agenix's default path, which an entry keeps unless a host overrides it.
    contracts.secrets.location =
      name: config.age.secrets.${name}.path or "${config.age.secretsDir}/${name}";
  };
}
