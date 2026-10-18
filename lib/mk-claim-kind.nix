/**
  Build a claim kind: a module that adds one kind of claim to every contract,
  folds the claims of enabled contracts into a read-only claim set, and checks
  that no two claims clash. The shipped binds, mounts and secrets are built
  with this function, so a new kind gets the same treatment.

  # Inputs

  An attribute set with:

  `name`
  : The kind's name. It becomes the field `contracts.services.<service>.<name>`,
    the claim set `contracts.claimSets.<name>` and the settings root
    `contracts.<name>`. `services`, `claimSets`, `assertions` and `adapters` are
    reserved.

  `description`
  : Description of the contract field holding this kind's claims.

  `claim`
  : A function of `{ service, contract, config }` returning the submodule of
    one claim. `service` is the contract's name, `contract` its evaluated value
    and `config` the configuration's top-level `config`. Inside the submodule,
    `name` is the claim's id.

  `ownership`
  : Optional. A function of `{ identity, claim }` returning the claim's final
    `{ owner, group }`, where `identity` is the contract's identity resolved to
    `{ user, group }` (both null when it has no account). Omit it for kinds
    without files, such as binds.

  `conflict`
  : Optional. A function of two claim-set entries returning null when they can
    coexist, or a string saying why they clash. Two claims with the same
    `<service>-<id>` name always clash.

  `settings`
  : Optional. Option declarations placed under `contracts.<name>`.

  # Output

  A module for any module class.

  # Example

  ```nix
  mkClaimKind {
    name = "databases";
    description = "Databases the service owns.";
    claim = { ... }: { lib, ... }: {
      options.engine = lib.mkOption { type = lib.types.str; };
    };
  }
  ```
*/
{
  name,
  description,
  claim,
  ownership ? null,
  conflict ? null,
  settings ? { },
}:
let
  kindName = name;
  reservedNames = [
    "adapters"
    "assertions"
    "claimSets"
    "services"
  ];
  resolveIdentity = import ./resolve-identity.nix;
in
if builtins.elem kindName reservedNames then
  throw "nixos-contracts: claim kind name `${kindName}` is reserved"
else
  { config, lib, ... }:
  let
    topConfig = config;

    mkEntry =
      service: contract: id: value:
      value
      // {
        inherit service id;
        name = "${service}-${id}";
      }
      // lib.optionalAttrs (ownership != null) (ownership {
        identity = resolveIdentity contract.identity;
        claim = value;
      });

    entries = lib.pipe config.contracts.services [
      (lib.filterAttrs (_: contract: contract.enable))
      (lib.mapAttrsToList (
        service: contract: lib.mapAttrsToList (mkEntry service contract) contract.${kindName}
      ))
      lib.concatLists
    ];

    nameAssertions = lib.pipe entries [
      (lib.groupBy (entry: entry.name))
      (lib.mapAttrsToList (
        artifact: group: {
          assertion = builtins.length group == 1;
          message = "nixos-contracts: ${kindName} claims ${
            lib.concatMapStringsSep " and " (entry: "`${entry.id}` of `${entry.service}`") group
          } share the name `${artifact}`.";
        }
      ))
    ];

    # Every unordered pair of entries, each pair once.
    pairs = lib.concatLists (
      lib.imap0 (
        index: first: map (second: { inherit first second; }) (lib.drop (index + 1) entries)
      ) entries
    );

    conflictAssertions = lib.optionals (conflict != null) (
      map (
        pair:
        let
          reason = conflict pair.first pair.second;
        in
        {
          assertion = reason == null;
          message = "nixos-contracts: ${kindName} claims `${pair.first.name}` and `${pair.second.name}` clash: ${toString reason}.";
        }
      ) pairs
    );
  in
  {
    options.contracts = {
      services = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, config, ... }:
            {
              options.${kindName} = lib.mkOption {
                type = lib.types.attrsOf (
                  lib.types.submodule (claim {
                    service = name;
                    contract = config;
                    config = topConfig;
                  })
                );
                default = { };
                inherit description;
              };
            }
          )
        );
      };

      claimSets.${kindName} = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        readOnly = true;
        default = lib.listToAttrs (map (entry: lib.nameValuePair entry.name entry) entries);
        defaultText = lib.literalMD "the ${kindName} claims of every enabled contract";
        description = ''
          The ${kindName} claims of every enabled contract, keyed by
          `<service>-<id>`, each carrying its service, id and name and, for a
          kind with files, its final owner and group.
        '';
      };

      ${kindName} = settings;
    };

    config.contracts.assertions = nameAssertions ++ conflictAssertions;
  }
