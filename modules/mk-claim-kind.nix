/**
  Build a claim kind: a module that adds one kind of claim to every contract,
  folds the claims of enabled contracts into a read-only claim set by service
  and id, and checks that no two claims clash and that each passes the
  kind's check rule. The shipped binds, mounts and secrets are built with
  this function, so a new kind gets the same treatment.

  # Inputs

  An attribute set with:

  `name`
  : The kind's name. It becomes the field `contracts.services.<service>.<name>`,
    the claim set `contracts.claimSets.<name>` and the settings root
    `contracts.kinds.<name>`, and part of every claim's name. It may contain
    only lowercase letters, digits and hyphens, and the contract's own
    fields `enable` and `identity` are reserved.

  `description`
  : Description of the contract field holding this kind's claims.

  `claim`
  : A function of `{ service, identity, config }` returning the submodule of
    one claim. `service` is the contract's name, `identity` the contract's
    identity resolved to `{ user, group, unit }` (`user` null for a dynamic
    identity, `group` null for a dynamic identity without a shared group,
    `unit` null for a static identity) and `config` the configuration's
    top-level `config`. Inside the submodule, the module argument `name` is
    the claim's id. A value that follows from the identity, such as a file
    owner, is an option defaulting to it. The constructor declares four
    read-only options on every claim, `service`, `id`, its claim name
    `name` and its reference `ref`, so a claim type cannot declare options
    with these names. A claim id may contain only lowercase letters, digits,
    hyphens and `_`.

  `clash`
  : Optional. The kind's clash rule: a function of two claim-set entries
    returning null when they can coexist, or a string saying why they clash.

  `check`
  : Optional. The kind's check rule: a function of
    `{ identity, claim, settings, config }`, where `identity` is the same
    resolved identity, `claim` a claim-set entry, `settings` the kind's
    settings at `contracts.kinds.<name>` and `config` the configuration's
    top-level `config`, returning null when the claim is valid, or a string
    or a list of strings saying why it is not. Only claims of enabled
    contracts are checked, and each reason reads
    "nixos-contracts: <kind> claim `<service>.<id>`: <reason>." in
    `contracts.failures`.

  `settings`
  : Optional. Option declarations placed under `contracts.kinds.<name>`.

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
  check ? null,
  settings ? { },
}:
let
  inherit (import ./references.nix) checkName claimLabelOf nameRules;

  # The kind's name, failing when it contains `_` or another character
  # its rule forbids. The reserved-name check below reads it, so a kind
  # fails as it is built.
  kindName = checkName nameRules.kind (kind: "claim kind name `${kind}`") name;

  # A service name or claim id, failing when it breaks its rule, so `_`
  # joins a service and an id into a name no other pair makes.
  checkService = checkName nameRules.service (service: "service name `${service}`");
  checkId =
    service: checkName nameRules.id (id: "${kindName} claim id `${id}` of service `${service}`");

  # A kind's claims sit beside the contract's own fields.
  reservedNames = [
    "enable"
    "identity"
  ];

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
  throw "nixos-contracts: claim kind name `${kindName}` is reserved for the contract's own `${kindName}` field; choose another name"
else
  { config, lib, ... }:
  let
    topConfig = config;

    # The claims of enabled contracts, by service and id. Its keys come from
    # this configuration's contracts alone, and are checked as they are
    # listed, so reading it fails on a service name or id that is not a name.
    claimSet = lib.pipe config.contracts.services [
      (lib.filterAttrs (service: contract: builtins.seq (checkService service) contract.enable))
      (lib.mapAttrs (
        service: contract:
        let
          serviceClaims = contract.${kindName};
        in
        builtins.deepSeq (map (checkId service) (lib.attrNames serviceClaims)) serviceClaims
      ))
      (lib.filterAttrs (_: serviceClaims: serviceClaims != { }))
    ];

    # Each claim of the claim set, with its service's resolved identity.
    claims = lib.concatLists (
      lib.mapAttrsToList (
        service: serviceClaims:
        let
          identity = resolveIdentity config.contracts.services.${service}.identity;
        in
        map (claim: { inherit identity claim; }) (lib.attrValues serviceClaims)
      ) claimSet
    );

    # The claim set's entries, in a list.
    claimSetEntries = map (claimWithIdentity: claimWithIdentity.claim) claims;

    # Every unordered pair of entries, each pair once.
    pairs = lib.concatLists (
      lib.imap0 (
        index: first: map (second: { inherit first second; }) (lib.drop (index + 1) claimSetEntries)
      ) claimSetEntries
    );

    clashAssertions = lib.optionals (clash != null) (
      map (
        pair:
        let
          reason = clash pair.first pair.second;
        in
        {
          assertion = reason == null;
          message = "${kindName} claims `${claimLabelOf pair.first}` and `${claimLabelOf pair.second}` clash: ${toString reason}.";
        }
      ) pairs
    );

    # A check rule returns null, one reason or a list of them; each reason
    # is one failed check.
    toReasons = reasons: if reasons == null then [ ] else lib.toList reasons;

    # The failed checks of one claim, given as `{ identity, claim }`, each
    # naming the claim by its service and id.
    checkAssertionsOf =
      arguments:
      lib.optionals (check != null) (
        lib.pipe
          (
            arguments
            // {
              settings = config.contracts.kinds.${kindName};
              inherit config;
            }
          )
          [
            check
            toReasons
            (map (reason: {
              assertion = false;
              message = "${kindName} claim `${claimLabelOf arguments.claim}`: ${reason}.";
            }))
          ]
      );

    checkAssertions = lib.concatMap checkAssertionsOf claims;
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
                    # Located here, so a claim type declaring one of these
                    # options fails with an error naming this file.
                    (lib.setDefaultModuleLocation ./mk-claim-kind.nix (
                      { name, config, ... }:
                      {
                        options = {
                          service = lib.mkOption {
                            type = lib.types.str;
                            readOnly = true;
                            default = checkService service;
                            defaultText = lib.literalMD "the service's name";
                            description = "The name of the claim's service.";
                          };
                          id = lib.mkOption {
                            type = lib.types.str;
                            readOnly = true;
                            default = checkId service name;
                            defaultText = lib.literalMD "the claim's attribute name";
                            description = "The claim's id within its contract.";
                          };
                          name = lib.mkOption {
                            type = lib.types.str;
                            readOnly = true;
                            default = lib.concatStringsSep "_" [
                              topConfig.contracts.node
                              kindName
                              config.service
                              config.id
                            ];
                            defaultText = lib.literalMD "`<node>_<kind>_<service>_<id>`";
                            description = ''
                              The claim name, `<node>_<kind>_<service>_<id>`,
                              which no other claim of the node collection
                              shares.
                            '';
                          };
                          # Built from the node identity, kind, service
                          # and id alone, so contributing it to another
                          # node reads no claim set.
                          ref = lib.mkOption {
                            type = lib.types.raw;
                            readOnly = true;
                            default = {
                              inherit (topConfig.contracts) node;
                              kind = kindName;
                              inherit service;
                              id = name;
                            };
                            defaultText = lib.literalMD "`{ node; kind; service; id; }`";
                            description = ''
                              The reference to this claim, naming
                              `contracts.node`.
                            '';
                          };
                        };
                      }
                    ))
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
        type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
        readOnly = true;
        default = claimSet;
        defaultText = lib.literalMD "the ${kindName} claims of every enabled contract";
        description = ''
          The ${kindName} claims of every enabled contract, each as its
          contract holds it, by service and id.
        '';
      };

      kinds.${kindName} = settings;
    };

    # Forcing the claim set checks every id, so evaluating the checks fails
    # on an id nothing else reads.
    config.contracts.assertions = builtins.seq claimSet (clashAssertions ++ checkAssertions);
  }
