/*
  Deliver every secret of a dynamic-identity service into its unit with
  `LoadCredential=`, so the dynamic user reads it under
  `/run/credentials/<unit>/<service>-<id>`. Loads from the location a
  credentials backend adapter sets, so import one beside it.
*/
{ config, lib, ... }:
let
  inherit (config.contracts) services;
  inherit (config.contracts.secrets) location;

  unitOf = secret: services.${secret.service}.identity.dynamic.unit;
  serviceNameOf = unit: lib.removeSuffix ".service" unit;

  delivered = lib.filter (secret: services.${secret.service}.identity ? dynamic) (
    lib.attrValues config.contracts.claimSets.secrets
  );

  units = lib.unique (map unitOf delivered);

  # The delivery itself defines the unit's entry, so a mistyped unit still
  # exists in `systemd.services`; only its missing `DynamicUser` shows the
  # mistake.
  unitAssertion = unit: {
    assertion =
      lib.hasSuffix ".service" unit
      && (config.systemd.services.${serviceNameOf unit}.serviceConfig.DynamicUser or false);
    message = "nixos-contracts: dynamic identity unit `${unit}` is not a service with `DynamicUser` in `systemd.services`.";
  };
in
{
  config = {
    contracts.secrets.delivery = { unit, name }: "/run/credentials/${unit}/${name}";

    systemd.services = lib.mkIf (location != null) (
      lib.mkMerge (
        map (secret: {
          ${serviceNameOf (unitOf secret)}.serviceConfig.LoadCredential = [
            "${secret.name}:${location secret.name}"
          ];
        }) delivered
      )
    );

    contracts.assertions = [
      {
        assertion = delivered == [ ] || location != null;
        message = "nixos-contracts: delivering secrets needs a credentials backend adapter that sets `contracts.secrets.location`.";
      }
    ]
    ++ map unitAssertion units;
  };
}
