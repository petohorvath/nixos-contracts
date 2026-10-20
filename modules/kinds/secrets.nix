# The arguments of `mkClaimKind` for secrets: what a service needs to read at
# runtime and must keep private.
{ lib }:
{
  name = "secrets";
  description = ''
    Runtime secrets the service needs, by secret id. A secret says what
    the service reads and who may read it, never where its value comes
    from or how a backend stores or installs it.
  '';

  settings = {
    location = lib.mkOption {
      type = lib.types.nullOr (lib.types.functionTo lib.types.str);
      default = null;
      description = ''
        Where the secret backend installs a secret, as a function of
        its `<service>-<id>` name. It must answer for any claim name,
        including claims of disabled contracts, which the backend does not
        install. Set by a backend adapter; null when none is imported.
      '';
    };
    delivery = lib.mkOption {
      type = lib.types.nullOr (lib.types.functionTo lib.types.str);
      default = null;
      description = ''
        Where a dynamic identity's unit reads a delivered secret, as a
        function of `{ unit, name }`. Set by a delivery adapter; null when
        none is imported.
      '';
    };
  };

  # A dynamic identity's user exists only while its unit runs, so it reads
  # a secret the backend installs only through its shared group. An
  # undelivered claim has a path only when a backend installs it.
  check =
    { identity, claim }:
    if
      identity.unit != null && !claim.delivered && claim.path != null && claim.group != identity.group
    then
      "its dynamic identity cannot read it; import a delivery adapter such as `nixosModules.systemd-credentials`, or give the identity a `sharedGroup` and the secret that group"
    else
      null;

  claim =
    { identity, config, ... }:
    { claimName, ... }:
    let
      inherit (config.contracts.secrets) delivery location;
      inherit (identity) unit;
      delivered = unit != null && delivery != null;
    in
    {
      options = {
        mode = lib.mkOption {
          type = lib.types.str;
          default = "0440";
          description = "The mode of the installed secret.";
        };
        owner = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = ''
            The owner of the installed secret. The default `root` lets the
            service read the secret through its group but not change it.
          '';
        };
        group = lib.mkOption {
          type = lib.types.str;
          default = lib.defaultTo "root" identity.group;
          defaultText = lib.literalMD "the identity's group, or `root` when it has none";
          description = "The group of the installed secret.";
        };
        unit = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          default = unit;
          defaultText = lib.literalMD "the dynamic identity's unit, or null";
          description = ''
            The unit a dynamic identity's secret is delivered to, or null
            for a static identity.
          '';
        };
        delivered = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          default = delivered;
          defaultText = lib.literalMD "whether the identity is dynamic and a delivery adapter is imported";
          description = ''
            Whether the secret is delivered into the dynamic identity's
            unit, rather than read where the backend installs it.
          '';
        };
        path = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          default =
            if delivered then
              delivery {
                inherit unit;
                name = claimName;
              }
            else if location != null then
              location claimName
            else
              null;
          defaultText = lib.literalMD "the location set by the adapters";
          description = ''
            Where the daemon reads the secret: the delivered credential for
            a dynamic identity when a delivery adapter is imported, else the
            backend's location, or null without adapters.
          '';
        };
      };
    };
}
