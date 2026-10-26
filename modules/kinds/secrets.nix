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
        The delivery of a dynamic identity's secrets into its unit. Set by
        a delivery adapter, such as `nixosModules.systemd-credentials`;
        null when none is imported. A node does not set it.
      '';
      options.path = lib.mkOption {
        type = lib.types.functionTo lib.types.str;
        description = ''
          Where a unit reads a delivered secret, as a function of
          `{ unit, service, id }`, where `service` and `id` are the
          secret's.
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
      inherit (settings) backend;
      generator = claim.value.generated or claim.value.derived.generator or null;
      # A dynamic identity's user exists only while its unit runs, so it
      # reads a secret the backend installs only through its shared group.
      claimReason =
        if identity.unit != null && !claim.delivered && claim.group != identity.group then
          "its dynamic identity cannot read it; import a delivery adapter such as `nixosModules.systemd-credentials`, or give the identity a `sharedGroup` and the secret that group"
        else if generator != null && backend != null && !builtins.elem generator backend.generators then
          "the secret backend provides no generator `${generator}`"
          +
            lib.optionalString (backend.generators != [ ])
              "; name one of ${lib.concatMapStringsSep ", " (name: "`${name}`") backend.generators}"
        else
          null;
    in
    lib.filter (reason: reason != null) (
      [ claimReason ] ++ map (referenceReason config) (referencesOf claim.value)
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
          type = lib.types.str;
          readOnly = true;
          default =
            if delivered then
              delivery.path {
                inherit unit;
                inherit (config) service id;
              }
            else
              backendPathOf backend config;
          defaultText = lib.literalMD "the path set by the delivery or backend adapter";
          description = ''
            Where the daemon reads the secret: the delivered credential for
            a dynamic identity when a delivery adapter is imported, else
            where the backend installs it, each as its slot's `path` answers
            for the secret's service and id. Reading it without a backend
            adapter fails.
          '';
        };
      };
    };
}
