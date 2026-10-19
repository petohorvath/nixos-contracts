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
  : A function of `{ service, identity, config }` returning the submodule of
    one claim. `service` is the contract's name, `identity` the contract's
    identity resolved to `{ user, group, unit }` (`user` null for a dynamic
    identity, `group` null for a dynamic identity without a shared group,
    `unit` null for a static identity) and `config` the configuration's
    top-level `config`. Inside the submodule, `name` is the claim's id and the
    module argument `claimName` its `<service>-<id>` claim name.

  `clash`
  : Optional. The kind's clash rule: a function of two claim-set entries
    returning null when they can coexist, or a string saying why they clash.
    Two claims with the same claim name always clash.

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
  clash ? null,
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
  # A claim's claim name, which keys its claim set.
  toClaimName = service: id: "${service}-${id}";

  /*
    Resolve a contract's identity to the account its files are owned by and
    the unit it is allocated for. A static identity without a group takes its
    user's like-named primary group and has no unit. A dynamic identity has no
    account at activation time, so it yields no user, at most its shared
    group, and its unit.
  */
  resolveIdentity =
    identity:
    if identity ? static then
      {
        inherit (identity.static) user;
        group = if identity.static.group != null then identity.static.group else identity.static.user;
        unit = null;
      }
    else
      {
        user = null;
        group = identity.dynamic.sharedGroup;
        inherit (identity.dynamic) unit;
      };
in
if builtins.elem kindName reservedNames then
  throw "nixos-contracts: claim kind name `${kindName}` is reserved"
else
  { config, lib, ... }:
  let
    topConfig = config;

    mkEntry =
      service: id: value:
      value
      // {
        inherit service id;
        name = toClaimName service id;
      };

    entries = lib.pipe config.contracts.services [
      (lib.filterAttrs (_: contract: contract.enable))
      (lib.mapAttrsToList (service: contract: lib.mapAttrsToList (mkEntry service) contract.${kindName}))
      lib.concatLists
    ];

    nameAssertions = lib.pipe entries [
      (lib.groupBy (entry: entry.name))
      (lib.mapAttrsToList (
        name: group: {
          assertion = builtins.length group == 1;
          message = "nixos-contracts: ${kindName} claims ${
            lib.concatMapStringsSep " and " (entry: "`${entry.id}` of `${entry.service}`") group
          } share the name `${name}`.";
        }
      ))
    ];

    # Every unordered pair of entries, each pair once.
    pairs = lib.concatLists (
      lib.imap0 (
        index: first: map (second: { inherit first second; }) (lib.drop (index + 1) entries)
      ) entries
    );

    clashAssertions = lib.optionals (clash != null) (
      map (
        pair:
        let
          reason = clash pair.first pair.second;
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
            let
              service = name;
            in
            {
              options.${kindName} = lib.mkOption {
                type = lib.types.attrsOf (
                  lib.types.submodule [
                    (claim {
                      inherit service;
                      identity = resolveIdentity config.identity;
                      config = topConfig;
                    })
                    (
                      { name, ... }:
                      {
                        _module.args.claimName = toClaimName service name;
                      }
                    )
                  ]
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
          The ${kindName} claims of every enabled contract, keyed by claim
          name, each as its contract holds it plus its service, id and claim
          name.
        '';
      };

      ${kindName} = settings;
    };

    config.contracts.assertions = nameAssertions ++ clashAssertions;
  }
