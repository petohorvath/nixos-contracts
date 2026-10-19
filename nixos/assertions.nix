# Forwards the failed contract checks to NixOS assertions.
{ config, ... }:
{
  assertions = map (message: {
    assertion = false;
    inherit message;
  }) config.contracts.failures;
}
