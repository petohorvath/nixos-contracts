# Declares contracts, their identities, the node collection and the checks over
# them, and prefixes the messages of the checks that fail.
{ config, lib, ... }:
let
  references = import ./references.nix;
  # A string that fails, naming itself, when it is not a name, so a claim
  # name joins the node identity with `_`.
  nodeIdentityType = lib.mkOptionType {
    name = "nodeIdentity";
    description = "string of lowercase letters, digits and hyphens";
    descriptionClass = "noun";
    check = builtins.isString;
    merge =
      loc: defs: references.checkName (node: "node identity `${node}`") (lib.mergeEqualOption loc defs);
  };
  contractTypes = import ./types.nix { inherit lib; };
  identityType = contractTypes.tag {
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

    node = lib.mkOption {
      type = lib.types.nullOr nodeIdentityType;
      default = null;
      description = ''
        This configuration's node identity, its name in the node
        collection, which every claim's `ref` names. While it is null, no
        lookup resolves a claim's `ref`.
      '';
    };

    lookup = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      default = references.lookup config;
      defaultText = lib.literalMD "the lookup of a reference in this configuration or `contracts.nodes`";
      description = ''
        A function of a reference returning `{ claim; reason; }`: the
        claim-set entry it names, or a null claim and why not.
      '';
    };

    resolve = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      default =
        reference:
        let
          result = config.contracts.lookup reference;
        in
        if result.reason == null then
          result.claim
        else
          throw "nixos-contracts: cannot resolve `${references.labelOf reference}`: ${result.reason}";
      defaultText = lib.literalMD "the claim `contracts.lookup` finds, or an error with its reason";
      description = ''
        A function of a reference returning the claim-set entry it names,
        failing with the reason when it names none.
      '';
    };

    nodes = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      description = ''
        The node collection: the nodes a reference may name, each with its
        evaluated `config`, such as nixos-cross-config's node collection.
        A reference naming `contracts.node` resolves in this configuration
        itself.
      '';
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

  # A configuration without a node collection needs none to name itself.
  config.contracts.assertions =
    lib.optional (config.contracts.node != null && config.contracts.nodes != { })
      {
        assertion = config.contracts.nodes ? ${config.contracts.node};
        message = "`contracts.node` is `${config.contracts.node}`, which is not in `contracts.nodes`.";
      };
}
