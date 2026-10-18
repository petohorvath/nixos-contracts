{
  config,
  inputs,
  lib,
  ...
}:
{
  flake.tests = lib.genAttrs config.systems (
    system: import ../tests/evaluation.nix { inherit inputs system; }
  );

  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      formatter = pkgs.callPackage ./formatter.nix { };
      devShells.default = pkgs.callPackage ./shell.nix {
        inherit (config) formatter;
      };
      checks = import ./checks.nix {
        inherit inputs pkgs system;
        inherit (config) formatter;
      };
    };
}
