/*
  Build `testContext`, the single argument of every nix-unit suite. It
  imports the library and modules from source, with the libnet that
  `flake.nix` passes them, so the unit suites evaluate no flake-parts. Only
  the integration entry point passes the backends' flakes, `self` and the
  `system` its NixOS configurations evaluate for; they are null otherwise.
*/
{
  nix-libnet,
  nixpkgs,
  agenix ? null,
  agenix-rekey ? null,
  preservation ? null,
  self ? null,
  system ? null,
}:
let
  inherit (nixpkgs) lib;
  libnet = nix-libnet.lib;

  # The exports that `flake.nix` assembles.
  exports = {
    lib = import ../lib { inherit lib; };
    modules.generic.default = import ../modules { inherit libnet; };
    nixosModules = import ../nixos { inherit libnet; };
  };
  # The NixOS modules of the adapters' backends.
  backends = {
    preservation = preservation.nixosModules.default;
    agenix = agenix.nixosModules.default;
    agenix-rekey = agenix-rekey.nixosModules.default;
  };
  # What the helpers and fixtures evaluate with.
  evaluationArgs = {
    inherit
      backends
      exports
      lib
      nixpkgs
      system
      ;
  };
in
{
  inherit lib self;
  contractsLib = exports.lib;
  helpers = import ./helpers evaluationArgs;
  fixtures = import ./fixtures evaluationArgs;
}
