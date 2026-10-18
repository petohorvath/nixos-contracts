# A claim kind for databases a service owns, built with the same constructor
# as the shipped kinds. Two services cannot own the same database.
{ mkClaimKind }:
mkClaimKind {
  name = "databases";
  description = "Databases the service owns, by database id.";

  # The owning role is the service's user, or the service's name for a
  # dynamic identity, which has no account.
  ownership =
    { identity, claim }:
    {
      owner = if identity.user != null then identity.user else claim.role;
      group = null;
    };

  clash =
    first: second: if first.database == second.database then "both own `${first.database}`" else null;

  claim =
    { service, ... }:
    { lib, name, ... }:
    {
      options = {
        database = lib.mkOption {
          type = lib.types.str;
          default = if name == "main" then service else "${service}_${name}";
          description = "The database name.";
        };
        role = lib.mkOption {
          type = lib.types.str;
          default = service;
          description = "The role owning the database for a dynamic identity.";
        };
      };
    };
}
