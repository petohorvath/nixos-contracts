/*
  Resolve a contract's identity to the account its files are owned by and the
  unit it is allocated for. A static identity without a group takes its user's
  like-named primary group and has no unit. A dynamic identity has no account
  at activation time, so it yields no user, at most its shared group, and its
  unit.
*/
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
  }
