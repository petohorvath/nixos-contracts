# Helpers that evaluate the library's modules for the suites.
{
  backends,
  exports,
  lib,
  nixpkgs,
  system,
}:
{
  contracts = import ./contracts.nix {
    inherit lib;
    module = exports.modules.generic.default;
  };
  nixos = import ./nixos.nix {
    inherit backends nixpkgs system;
    inherit (exports) nixosModules;
  };
  nodesWith = import ./nodes.nix;
}
