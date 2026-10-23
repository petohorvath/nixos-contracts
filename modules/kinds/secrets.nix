# The arguments of `mkClaimKind` for secrets: what a service needs to read at
# runtime and must keep private.
{ lib }:
let
  # A claim name alone references a secret of this configuration.
  referenceType = lib.types.coercedTo lib.types.str (name: { inherit name; }) (
    lib.types.submodule {
      options = {
        node = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            The node holding the secret, or null for this configuration.
          '';
        };
        name = lib.mkOption {
          type = lib.types.str;
          description = "The secret's claim name, `<service>-<id>`.";
        };
      };
    }
  );

  # `types.unique` turns into `types.uniq`, losing its message, when the
  # module system substitutes the submodules of an option it wraps.
  uniqueWithSubmodules =
    message: type:
    lib.types.unique { inherit message; } type
    // {
      substSubModules = modules: uniqueWithSubmodules message (type.substSubModules modules);
    };

  /*
    A slot holds the data of one adapter, or null when none is imported.
    A second adapter's definition fails, naming both, rather than merging
    with the first, so one backend sets both its location and generators.
  */
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
    }:
    let
      inherit (settings) backend;
    in
    # A dynamic identity's user exists only while its unit runs, so it reads
    # a secret the backend installs only through its shared group.
    if identity.unit != null && !claim.delivered && claim.group != identity.group then
      "its dynamic identity cannot read it; import a delivery adapter such as `nixosModules.systemd-credentials`, or give the identity a `sharedGroup` and the secret that group"
    else if
      claim.generate != null && backend != null && !builtins.elem claim.generate backend.generators
    then
      "the secret backend provides no generator `${claim.generate}`"
      +
        lib.optionalString (backend.generators != [ ])
          "; name one of ${lib.concatMapStringsSep ", " (generator: "`${generator}`") backend.generators}"
    else if claim.generate == null && builtins.length claim.from > 1 then
      "it references several secrets but has no `generate`; a copy references one"
    else
      null;

  claim =
    { identity, config, ... }:
    { claimName, ... }:
    let
      inherit (config.contracts.kinds.secrets) backend delivery;
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
        generate = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            The generator that makes the secret's value, such as `alnum`,
            when the service makes its own value; null when a person or
            another party provides it. A backend adapter turns it into the
            backend's generator.
          '';
          example = "alnum";
        };
        from = lib.mkOption {
          type = lib.types.listOf referenceType;
          default = [ ];
          description = ''
            The secrets the value comes from, each a claim name, or
            `{ node; name; }` for a secret another node holds.
            Without `generate`, the secret is a copy of the one secret it
            references; with it, the generator makes the value from the
            secrets it references. A backend adapter resolves them.
          '';
          example = [
            {
              node = "metrics";
              name = "telegraf-token";
            }
          ];
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
                name = claimName;
              }
            else if backend == null then
              throw "nixos-contracts: secret `${claimName}` has no location: import a secret backend adapter such as `nixosModules.agenix-rekey`, which sets `contracts.kinds.secrets.backend`"
            else
              backend.location claimName;
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
