/*
  Resolve a contract's identity to the account its files are owned by. A static
  identity without a group takes its user's like-named primary group. A
  dynamic identity has no account at activation time, so it yields no user and
  at most its shared group.
*/
identity:
if identity ? static then
  {
    inherit (identity.static) user;
    group = if identity.static.group != null then identity.static.group else identity.static.user;
  }
else
  {
    user = null;
    group = identity.dynamic.sharedGroup;
  }
