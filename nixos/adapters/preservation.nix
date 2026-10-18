# Persist every mount with preservation, under the root mapped to its class.
# Requires the preservation NixOS module; the flake's
# `nixosModules.preservation` also imports the contracts module.
{ config, lib, ... }:
let
  cfg = config.contracts.adapters.preservation;
  inherit (config.contracts) claimSets mounts;

  entryOf =
    mount:
    {
      inherit (mount) group mode;
      user = mount.owner;
    }
    // (if mount.kind == "file" then { file = mount.path; } else { directory = mount.path; });
in
{
  options.contracts.adapters.preservation.roots = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = ''
      The preservation root of each mount class: a key of
      `preservation.preserveAt`, such as `/persist/state`. Every class in
      `contracts.mounts.classes` needs one.
    '';
    example = {
      state = "/persist/state";
      cache = "/persist/cache";
    };
  };

  config = {
    preservation.preserveAt = lib.mkMerge (
      lib.mapAttrsToList (
        _: mount:
        lib.mkIf (cfg.roots ? ${mount.class}) {
          ${cfg.roots.${mount.class}} =
            if mount.kind == "file" then
              { files = [ (entryOf mount) ]; }
            else
              { directories = [ (entryOf mount) ]; };
        }
      ) claimSets.mounts
    );

    contracts.assertions = map (class: {
      assertion = cfg.roots ? ${class};
      message = "nixos-contracts: mount class `${class}` has no preservation root in `contracts.adapters.preservation.roots`.";
    }) mounts.classes;
  };
}
