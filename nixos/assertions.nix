# Forwards the contract checks to NixOS assertions.
{ config, ... }:
{
  assertions = map (check: { inherit (check) assertion message; }) config.contracts.assertions;
}
