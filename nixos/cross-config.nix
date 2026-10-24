/*
  Take the node identity and the node collection from nixos-cross-config, so a fleet states them once. Reads
  only options nixos-cross-config's own module declares, so it needs no
  flake input; import it beside that module.
*/
{ config, lib, ... }:
{
  contracts = {
    node = lib.mkDefault config.crossConfig.name;
    nodes = lib.mkDefault config.crossConfig.nodeConfigurations;
  };
}
