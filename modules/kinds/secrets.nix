# The arguments of `mkClaimKind` for secrets: what a service needs to read at
# runtime and must keep private.
{ lib }:
let
  contractTypes = import ../types.nix { inherit lib; };
  referenceType = contractTypes.referenceTo "secrets";
  # References resolve through the lookup every kind shares; a secret's
  # value adds only its own rules.
  inherit (import ../references.nix)
    backendPathOf
    deliveryPathOf
    lookup
    referenceLabelOf
    ;

  # The references of a `copied` or `derived` value, in order, or none.
  referencesOf =
    value:
    if value ? copied then
      [ value.copied ]
    else if value ? derived then
      value.derived.from
    else
      [ ];

  # Only a provided or generated secret resolves, so two copies referencing
  # each other fail their checks instead of recursing.
  resolves = claim: claim != null && (claim.value ? provided || claim.value ? generated);

  # A `sources` entry: a reference with the claim it resolves to, or a null
  # claim when a check rejects it.
  toSource =
    config: reference:
    let
      inherit (lookup config reference) claim;
    in
    {
      inherit (reference)
        node
        kind
        service
        id
        ;
      claim = if resolves claim then claim else null;
    };

  # Why a reference does not resolve, or null when it does.
  referenceReason =
    config: reference:
    let
      result = lookup config reference;
      references = "it references `${referenceLabelOf reference}`";
    in
    if result.reason != null then
      "${references}: ${result.reason}"
    else if !resolves result.claim then
      "${references}, which is copied or derived itself; reference a provided or generated secret"
    else
      null;

  # `types.unique` turns into `types.uniq`, losing its message, when the
  # module system substitutes the submodules of an option it wraps.
  uniqueWithSubmodules =
    message: type:
    lib.types.unique { inherit message; } type
    // {
      substSubModules = modules: uniqueWithSubmodules message (type.substSubModules modules);
    };

  # A slot holds the data of one adapter, or null when none is imported. A
  # second adapter's definition fails, naming both, rather than merging with
  # the first, so one backend sets both its path and generators.
  mkAdapterSlot =
    {
      message,
      options,
      description,
    }:
    lib.mkOption {
      type = uniqueWithSubmodules message (lib.types.nullOr (lib.types.submodule { inherit options; }));
      default = null;
      inherit description;
    };
in
{
  name = "secrets";
  description = ''
    Runtime secrets the service needs, by secret id. A secret says what
    the service reads, who may read it and whether the service makes its
    own value, never how a backend stores, shares or installs it.
  '';

  settings = {
    backend = mkAdapterSlot {
      message = "A configuration imports one secret backend adapter, which sets `backend`.";
      description = ''
        The secret backend: where it installs a secret and which
        generators it provides. Set by a backend adapter, such as
        `nixosModules.agenix-rekey`; null when none is imported, which
        leaves a value's generator unchecked and fails reading a secret's
        `path`. A node does not set it.
      '';
      options = {
        path = lib.mkOption {
          type = lib.types.functionTo lib.types.str;
          description = ''
            Where the backend installs a secret, as a function of its
            `{ service, id }`. It must answer for any service and id,
            including those of claims of disabled contracts, which the
            backend does not install. A backend names its entry for a
            secret `<service>_<id>`, which no other claim of the node
            shares, since no service name contains `_`.
          '';
        };
        generators = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = ''
            The generators a secret's `generated` or `derived` value may
            name, such as `alnum`.
          '';
          example = [
            "alnum"
            "hex"
          ];
        };
      };
    };
    delivery = mkAdapterSlot {
      message = "A configuration imports one delivery adapter, which sets `delivery`.";
      description = ''
        The delivery of secrets into the units they name. Set by a
        delivery adapter, such as `nixosModules.systemd-credentials`; null
        when none is imported, which fails the check of a delivered secret
        and reading its `path`. A node does not set it.
      '';
      options.path = lib.mkOption {
        type = lib.types.functionTo lib.types.str;
        description = ''
          Where a unit reads a delivered secret, as a function of
          `{ unit, service, id }`, the secret's `unit`, service and id.
        '';
      };
    };
  };

  check =
    {
      identity,
      claim,
      settings,
      config,
    }:
    let
      inherit (settings) backend delivery;
      generator = claim.value.generated or claim.value.derived.generator or null;
      deliveryReason =
        if claim.delivered && delivery == null then
          "it is delivered to `${claim.unit}`, but no delivery adapter is imported; import one such as `nixosModules.systemd-credentials`, or set its `unit` to null"
        else
          null;
      # A dynamic identity's user exists only while its unit runs, so it
      # reads a secret delivered to that unit, or one the backend installs
      # through its shared group.
      readReason =
        if identity.unit == null then
          null
        else if claim.delivered && claim.unit != identity.unit then
          "it is delivered to `${claim.unit}`, but its dynamic identity exists only in `${identity.unit}`; deliver it to `${identity.unit}`, or set its `unit` to null"
        else if !claim.delivered && claim.group != identity.group then
          "its dynamic identity cannot read it; deliver it to `${identity.unit}`, or give the identity a `sharedGroup` and the secret that group"
        else
          null;
      generatorReason =
        if generator != null && backend != null && !builtins.elem generator backend.generators then
          "the secret backend provides no generator `${generator}`"
          +
            lib.optionalString (backend.generators != [ ])
              "; name one of ${lib.concatMapStringsSep ", " (name: "`${name}`") backend.generators}"
        else
          null;
    in
    lib.filter (reason: reason != null) (
      [
        deliveryReason
        readReason
        generatorReason
      ]
      ++ map (referenceReason config) (referencesOf claim.value)
    );

  claim =
    { identity, config, ... }:
    let
      # Read before the claim's own `config` shadows the top-level one.
      topConfig = config;
    in
    { config, ... }:
    let
      inherit (topConfig.contracts.kinds.secrets) backend delivery;
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
          default = if config.delivered then "root" else lib.defaultTo "root" identity.group;
          defaultText = lib.literalMD "`root` for a delivered secret, else the identity's group, or `root` when it has none";
          description = ''
            The group of the installed secret. A delivered secret defaults
            to `root`: only the delivery adapter reads the installed file,
            not the other units of the identity's account.
          '';
        };
        value = lib.mkOption {
          type = contractTypes.tag {
            provided = lib.mkOption {
              type = lib.types.submodule { };
              description = ''
                A value a person or another party provides, set on the
                backend.
              '';
            };
            generated = lib.mkOption {
              type = lib.types.str;
              description = ''
                The generator that makes the value, such as `alnum`, when
                the service makes its own value. A backend adapter turns it
                into the backend's generator.
              '';
              example = "alnum";
            };
            copied = lib.mkOption {
              type = referenceType;
              description = ''
                The one secret this secret is a copy of, as a reference
                `{ node; service; id; }`, such as another secret's `ref`.
              '';
            };
            derived = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  generator = lib.mkOption {
                    type = lib.types.str;
                    description = ''
                      The generator that makes the value from the secrets
                      in `from`, such as `basic-auth`.
                    '';
                    example = "basic-auth";
                  };
                  from = lib.mkOption {
                    type = lib.types.listOf referenceType;
                    default = [ ];
                    description = ''
                      The secrets the generator makes the value from, in
                      order, each a reference `{ node; service; id; }`, such
                      as another secret's `ref`.
                    '';
                  };
                };
              };
              description = ''
                A value a generator makes from the secrets it references.
              '';
            };
          };
          default.provided = { };
          description = ''
            Where the secret's value comes from: `provided = { }`, the
            default, when a person or another party provides it,
            `generated = "<generator>"` when the service makes it,
            `copied = <reference>` for a copy of one other secret, or
            `derived = { generator; from; }` when a generator makes it from
            the secrets `from` references. A reference names
            `contracts.node` or a node in `contracts.nodes`, and the core
            resolves it into `sources`. A node switches a module's
            default-priority tag by writing another at normal priority.
          '';
          example.copied = {
            node = "metrics";
            service = "telegraf";
            id = "token";
          };
        };
        sources = lib.mkOption {
          type = lib.types.listOf lib.types.raw;
          readOnly = true;
          default = map (toSource topConfig) (referencesOf config.value);
          defaultText = lib.literalMD "the references of a `copied` or `derived` value, each with the claim it resolves to";
          description = ''
            The references of a `copied` value, or those of a `derived`
            value's `from` in order, each as
            `{ node; kind; service; id; claim; }`, where `claim` is the
            claim-set entry of the secret it names, read from the node
            collection, or null when a check rejects the reference. Empty
            for a `provided` or `generated` value. A backend adapter reads
            the references from it rather than resolving them itself.
          '';
        };
        unit = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = identity.unit;
          defaultText = lib.literalMD "the dynamic identity's unit, or null";
          description = ''
            The unit the secret is delivered to, such as
            `mastodon-init-dirs.service`, or null to read it where the
            backend installs it. The module that hands the secret's `path`
            to the daemon names the unit that reads it. A dynamic identity's
            secret is delivered to the identity's unit or not at all.
          '';
          example = "mastodon-init-dirs.service";
        };
        delivered = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          default = config.unit != null;
          defaultText = lib.literalMD "whether the secret names a unit";
          description = ''
            Whether the secret is delivered to its `unit`, rather than read
            where the backend installs it.
          '';
        };
        backendPath = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = backendPathOf backend config;
          defaultText = lib.literalMD "the path set by the backend adapter";
          description = ''
            Where the backend installs the secret, as the backend slot's
            `path` answers. It equals `path` for an undelivered secret; a
            delivery adapter loads a delivered secret from it. Reading it
            fails without a backend adapter.
          '';
        };
        path = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = if config.delivered then deliveryPathOf delivery config else config.backendPath;
          defaultText = lib.literalMD "the path set by the delivery or backend adapter";
          description = ''
            Where the daemon reads the secret: the credential in its `unit`
            for a delivered secret, else where the backend installs it, each
            as its slot's `path` answers. Reading it fails without the
            delivery adapter a delivered secret needs, or the backend adapter
            every secret needs.
          '';
        };
      };
    };
}
