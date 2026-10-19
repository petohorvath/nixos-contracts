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
in
{
  options.contracts.adapters.agenixRekey = {
    secretsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The directory holding provided secrets as `<service>-<id>.age`.
        Evaluation fails when a provided secret needs it and it is null.
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
      {
        inherit (secret) group mode owner;
      }
      // (
        if secret.provenance ? generated then
          { generator.script = secret.provenance.generated; }
        else
          {
            rekeyFile =
              cfg.rekeyFiles.${name} or (
                if cfg.secretsDir != null then
                  cfg.secretsDir + "/${name}.age"
                else
                  throw "nixos-contracts: provided secret `${name}` needs `contracts.adapters.agenixRekey.secretsDir` or an entry in its `rekeyFiles`."
              );
          }
      )
    ) config.contracts.claimSets.secrets;

    contracts.secrets.location =
      name: config.age.secrets.${name}.path or "${config.age.secretsDir}/${name}";
  };
}
