# Checks each copy an inbox holds as a secret claim of its receiving
# service, so a copy its identity can't read, or one of a secret that is
# itself copied or derived, fails as an authored secret would.
{ config, lib, ... }:
let
  inherit (import ./references.nix) copiesOf;
  inherit (config.contracts.internal.kinds) secrets;
in
{
  # A copy's location starts with its receiving service.
  config.contracts.assertions = lib.concatMap (
    copy: secrets.assertions (builtins.head copy.location) copy
  ) (copiesOf config);
}
