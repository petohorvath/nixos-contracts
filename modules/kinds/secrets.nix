# The arguments of `mkClaimKind` for secrets: what a service needs to read at
# runtime and must keep private.
{ lib }:
let
  referenceType = (import ../types.nix { inherit lib; }).referenceTo "secrets";
  # References resolve through the lookup every kind shares; `from` adds
  # only its own rules.
  inherit (import ../references.nix) labelOf lookup;

  # PROTOTYPE: a secret's value is exactly one of these tags.
  valueOf = claim: builtins.head (builtins.attrNames claim.value);
  referencesOf =
    value:
    if value ? copy then
      [ value.copy ]
    else if value ? derive then
      value.derive.from
    else
      [ ];
  generatorOf =
    value:
    if value ? generate then
      value.generate
    else if value ? derive then
      value.derive.generator
    else
      null;

  # Only a provided or generated secret resolves as a source, so two copies
  # referencing each other fail their checks instead of recursing.
  resolves =
    claim:
    claim != null
    && builtins.elem (valueOf claim) [
      "provided"
      "generate"
    ];

  # A `sources` entry: a reference with the claim it resolves to, or a
  # null claim when a check rejects it.
  toReferenced =
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
      references = "it references `${labelOf reference}`";
    in
    if result.reason != null then
      "${references}: ${result.reason}"
    else if !resolves result.claim then
      "${references}, which is a copy or derived itself; reference a provided or generated secret"
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
  # the first, so one backend sets both its location and generators.
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
        leaves `generate` unchecked and fails reading a secret's location.
        A node does not set it.
      '';
      options = {
        location = lib.mkOption {
          type = lib.types.functionTo lib.types.str;
          description = ''
            Where the backend installs a secret, as a function of its
            `<service>-<id>` name. It must answer for any claim name,
            including claims of disabled contracts, which the backend does
            not install.
          '';
        };
        generators = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "The generators a secret's `generate` may name, such as `alnum`.";
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
          `{ unit, name }`.
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
      # A dynamic identity's user exists only while its unit runs, so it
      # reads a secret the backend installs only through its shared group.
      claimReason =
        if identity.unit != null && !claim.delivered && claim.group != identity.group then
          "its dynamic identity cannot read it; import a delivery adapter such as `nixosModules.systemd-credentials`, or give the identity a `sharedGroup` and the secret that group"
        else if generator != null && backend != null && !builtins.elem generator backend.generators then
          "the secret backend provides no generator `${generator}`"
          +
            lib.optionalString (backend.generators != [ ])
              "; name one of ${lib.concatMapStringsSep ", " (generator: "`${generator}`") backend.generators}"
        else
          null;
      generator = generatorOf claim.value;
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
    { address, config, ... }:
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
        # PROTOTYPE: exactly one tag. `provided` when a person or another
        # party supplies the value.
        value = lib.mkOption {
          type = lib.types.attrTag {
            provided = lib.mkOption {
              type = lib.types.submodule { };
              description = "A person or another party provides the value.";
            };
            generate = lib.mkOption {
              type = lib.types.str;
              description = "The generator that makes the value, such as `alnum`.";
            };
            copy = lib.mkOption {
              type = referenceType;
              description = "The provided or generated secret this one copies.";
            };
            derive = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  generator = lib.mkOption {
                    type = lib.types.str;
                    description = "The generator that makes the value from `from`.";
                  };
                  from = lib.mkOption {
                    type = lib.types.listOf referenceType;
                    description = "The secrets the value is made from.";
                  };
                };
              };
              description = "A value a generator makes from other secrets.";
            };
          };
          default.provided = { };
          description = "Where the secret's value comes from: exactly one tag.";
        };
        sources = lib.mkOption {
          type = lib.types.listOf lib.types.raw;
          readOnly = true;
          default = map (toReferenced topConfig) (referencesOf config.value);
          defaultText = lib.literalMD "each reference of `value` with the claim it resolves to";
          description = ''
            Each reference of a copy or a derived value as
            `{ node; kind; service; id; claim; }`, `claim` null when a check
            rejects the reference.
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
                inherit unit address;
              }
            else if backend == null then
              throw "nixos-contracts: secret `${lib.concatStringsSep "." address}` has no location: import a secret backend adapter such as `nixosModules.agenix-rekey`, which sets `contracts.kinds.secrets.backend`"
            else
              backend.location address;
          defaultText = lib.literalMD "the path set by the delivery or backend adapter";
          description = ''
            Where the daemon reads the secret: the delivered credential for
            a dynamic identity when a delivery adapter is imported, else the
            backend's location. Reading it without a backend adapter fails.
          '';
        };
      };
    };
}
