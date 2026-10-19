# The arguments of `mkClaimKind` for mounts: paths whose contents must
# survive, each under a declared class.
{ lib }:
let
  normalize = path: if path == "/" then path else lib.removeSuffix "/" path;
in
{
  name = "mounts";
  description = ''
    Paths whose contents must survive, by mount id. A mount says what must
    survive, never how a backend keeps it.
  '';

  settings.classes = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      The classes of persistent storage mounts may name, such as `state`
      or `cache`. Where each class lives is up to an adapter.
    '';
    example = [
      "state"
      "cache"
    ];
  };

  ownership =
    { identity, claim }:
    let
      owner = lib.defaultTo (lib.defaultTo "root" identity.user) claim.owner;
    in
    {
      inherit owner;
      group = lib.defaultTo (lib.defaultTo owner identity.group) claim.group;
    };

  clash =
    first: second:
    if normalize first.path == normalize second.path then "both persist `${first.path}`" else null;

  claim =
    { config, ... }:
    {
      options = {
        path = lib.mkOption {
          type = lib.types.pathWith {
            absolute = true;
            inStore = false;
          };
          description = "The absolute path whose contents must survive.";
          example = "/var/lib/influxdb2";
        };
        class = lib.mkOption {
          type = lib.types.enum config.contracts.mounts.classes;
          description = ''
            The class of storage the path belongs to, one of
            `contracts.mounts.classes`.
          '';
          example = "state";
        };
        type = lib.mkOption {
          type = lib.types.enum [
            "directory"
            "file"
          ];
          default = "directory";
          description = "Whether the path is a directory or a single file.";
        };
        mode = lib.mkOption {
          type = lib.types.str;
          default = "0700";
          description = "The mode of the directory or file.";
        };
        owner = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            The owner; null takes the identity's user, or root for a dynamic
            identity.
          '';
        };
        group = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            The group; null takes the identity's group, or else the owner.
          '';
        };
      };
    };
}
