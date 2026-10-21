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
in
{
  name = "secrets";
  description = ''
    Runtime secrets the service needs, by secret id. A secret says what
    the service reads, who may read it and whether the service makes its
    own value, never how a backend stores, shares or installs it.
  '';

  settings = {
    location = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      default =
        name:
        throw "nixos-contracts: secret `${name}` has no location: import a secret backend adapter such as `nixosModules.agenix-rekey`, which sets `contracts.secrets.location`";
      defaultText = lib.literalMD "a function that fails, naming the missing backend adapter";
      description = ''
        Where the secret backend installs a secret, as a function of
        its `<service>-<id>` name. It must answer for any claim name,
        including claims of disabled contracts, which the backend does not
        install. Set by a backend adapter; without one, reading a secret's
        location fails.
      '';
    };
    generators = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = ''
        The generators a secret's `generate` may name, such as `alnum`.
        Set by a backend adapter to the generators its backend provides;
        null when none is imported, which leaves `generate` unchecked.
      '';
      example = [
        "alnum"
        "hex"
      ];
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

  check =
    {
      identity,
      claim,
      settings,
    }:
    let
      inherit (settings) generators;
    in
    # A dynamic identity's user exists only while its unit runs, so it reads
    # a secret the backend installs only through its shared group.
    if identity.unit != null && !claim.delivered && claim.group != identity.group then
      "its dynamic identity cannot read it; import a delivery adapter such as `nixosModules.systemd-credentials`, or give the identity a `sharedGroup` and the secret that group"
    else if
      claim.generate != null && generators != null && !builtins.elem claim.generate generators
    then
      "no adapter provides its generator `${claim.generate}`; name one of `contracts.secrets.generators`"
    else if claim.generate == null && builtins.length claim.from > 1 then
      "it references several secrets but has no `generate`; a copy references one"
    else
      null;

  claim =
    { identity, config, ... }:
    { claimName, ... }:
    let
      inherit (config.contracts.secrets) delivery location;
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
            `{ node; name; }` for a secret another configuration holds.
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
              delivery {
                inherit unit;
                name = claimName;
              }
            else
              location claimName;
          defaultText = lib.literalMD "the location set by the adapters";
          description = ''
            Where the daemon reads the secret: the delivered credential for
            a dynamic identity when a delivery adapter is imported, else the
            backend's location. Reading it without a backend adapter fails.
          '';
        };
      };
    };
}
