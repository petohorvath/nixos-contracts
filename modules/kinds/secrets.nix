# Secrets: what a service needs to read at runtime and must keep private.
{ lib, ... }:
{
  imports = [
    (import ../../lib/mk-claim-kind.nix {
      name = "secrets";
      description = ''
        Runtime secrets the service needs, by secret id. A secret says what
        the service needs and where its value comes from, never how a backend
        stores or installs it.
      '';

      settings = {
        location = lib.mkOption {
          type = lib.types.nullOr (lib.types.functionTo lib.types.str);
          default = null;
          description = ''
            Where the secret backend installs a secret, as a function of
            its `<service>-<id>` name. Set by a backend adapter; null when
            none is imported.
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

      ownership =
        { identity, claim }:
        {
          owner = lib.defaultTo "root" claim.owner;
          group = lib.defaultTo (lib.defaultTo "root" identity.group) claim.group;
        };

      claim =
        {
          service,
          contract,
          config,
        }:
        { lib, name, ... }:
        let
          inherit (config.contracts.secrets) delivery location;
          inherit (import ../../lib/resolve-identity.nix contract.identity) unit;
          claimName = import ../../lib/claim-name.nix service name;
        in
        {
          options = {
            provenance = lib.mkOption {
              type = lib.types.attrTag {
                provided = lib.mkOption {
                  type = lib.types.submodule { };
                  description = "The value is authored by a person.";
                };
                generated = lib.mkOption {
                  type = lib.types.str;
                  description = ''
                    The value is produced by the named generator, which the
                    backend resolves.
                  '';
                  example = "alnum";
                };
              };
              description = ''
                Where the value comes from: exactly one of `provided` or
                `generated`.
              '';
            };
            mode = lib.mkOption {
              type = lib.types.str;
              default = "0440";
              description = "The mode of the installed secret.";
            };
            owner = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                The owner; null keeps root, so the service reads the secret
                through its group but cannot change it.
              '';
            };
            group = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                The group; null takes the identity's group, or root when it has
                none.
              '';
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
            path = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              readOnly = true;
              default =
                if unit != null && delivery != null then
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
    })
  ];
}
