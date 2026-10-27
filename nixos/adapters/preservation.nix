# Persist every mount with preservation, under the root mapped to its class.
# Requires the preservation NixOS module; `nixosModules.preservation` also
# imports `nixosModules.default`.
{ config, lib, ... }:
let
  cfg = config.contracts.adapters.preservation;
  inherit (import ../../lib { inherit lib; }) claimsOf;
  mounts = claimsOf config.contracts.claimSets.mounts;

  preserveEntry =
    mount:
    let
      isFile = mount.type == "file";
    in
    {
      ${if isFile then "files" else "directories"} = [
        {
          ${if isFile then "file" else "directory"} = mount.path;
          inherit (mount) group mode;
          user = mount.owner;
        }
      ];
    };
in
{
  options.contracts.adapters.preservation.roots = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = ''
      The preservation root of each mount class: a key of
      `preservation.preserveAt`, such as `/persist/state`. Every class a
      mount uses needs one.
    '';
    example = {
      state = "/persist/state";
      cache = "/persist/cache";
    };
  };

  config = {
    preservation.preserveAt = lib.mkMerge (
      map (
        mount:
        lib.mkIf (cfg.roots ? ${mount.class}) {
          ${cfg.roots.${mount.class}} = preserveEntry mount;
        }
      ) mounts
    );

    contracts.assertions = map (class: {
      assertion = cfg.roots ? ${class};
      message = "mount class `${class}` has no preservation root in `contracts.adapters.preservation.roots`.";
    }) (lib.unique (map (mount: mount.class) mounts));
  };
}
