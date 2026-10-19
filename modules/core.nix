# Declares contracts, their identities and the checks over them, and prefixes
# the messages of the checks that fail.
{ config, lib, ... }:
let
  identityType = lib.types.attrTag {
    static = lib.mkOption {
      type = lib.types.submodule {
        options = {
          user = lib.mkOption {
            type = lib.types.str;
            description = "The account the service effectively runs as.";
          };
          group = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              The service's group; null takes the user's like-named primary
              group.
            '';
          };
        };
      };
      description = "A named account the service runs as.";
    };
    dynamic = lib.mkOption {
      type = lib.types.submodule {
        options = {
          unit = lib.mkOption {
            type = lib.types.str;
            description = ''
              The systemd unit, such as `alloy.service`, whose dynamic user the
              service runs as.
            '';
            example = "alloy.service";
          };
          sharedGroup = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              A static supplementary group the dynamic user shares, or null for
              none.
            '';
          };
        };
      };
      description = "A user systemd allocates for one unit while it runs.";
    };
  };
in
{
  options.contracts = {
    services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              enable = lib.mkEnableOption "the contract of service `${name}`";
              identity = lib.mkOption {
                type = identityType;
                description = ''
                  What the service effectively runs as: exactly one of `static`
                  or `dynamic`. Owners and groups of its files follow from it.
                '';
              };
            };
          }
        )
      );
      default = { };
      description = "The contracts of this configuration's services, by name.";
    };

    assertions = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            assertion = lib.mkOption {
              type = lib.types.bool;
              description = "Whether the checked condition holds.";
            };
            message = lib.mkOption {
              type = lib.types.str;
              description = ''
                The error reported when the condition fails, without the
                library's prefix, which `contracts.failures` adds.
              '';
            };
          };
        }
      );
      default = [ ];
      description = ''
        Checks over all contracts, such as claim clashes. Read the failed
        ones from `contracts.failures`.
      '';
    };

    failures = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = lib.pipe config.contracts.assertions [
        (lib.filter (check: !check.assertion))
        (map (check: "nixos-contracts: ${check.message}"))
      ];
      defaultText = lib.literalMD "the prefixed messages of the failed `contracts.assertions`";
      description = ''
        The messages of the failed checks, each prefixed with
        `nixos-contracts: `. The NixOS module forwards them to `assertions`.
      '';
    };
  };
}
