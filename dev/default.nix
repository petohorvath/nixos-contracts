{ inputs, ... }:
{
  imports = [ inputs.nix-unit.modules.flake.default ];

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
        inherit pkgs;
        inherit (config) formatter;
      };
      nix-unit =
        let
          rekey = inputs.agenix-rekey.inputs;
          hooks = rekey.pre-commit-hooks.inputs;
        in
        {
          package = pkgs.nix-unit;
          # The sandbox cannot fetch, so every locked input comes from the
          # store, agenix-rekey's own inputs included.
          inputs = {
            inherit (inputs)
              agenix
              agenix-rekey
              flake-parts
              nix-libnet
              nix-unit
              nixpkgs
              preservation
              ;
            "agenix-rekey/devshell" = rekey.devshell;
            "agenix-rekey/flake-compat" = rekey.flake-compat;
            "agenix-rekey/pre-commit-hooks" = rekey.pre-commit-hooks;
            "agenix-rekey/pre-commit-hooks/flake-compat" = hooks.flake-compat;
            "agenix-rekey/pre-commit-hooks/gitignore" = hooks.gitignore;
            "agenix-rekey/treefmt-nix" = rekey.treefmt-nix;
          };
          enableSystemAgnostic = false;
          tests = {
            unit = import ../tests/unit { inherit (inputs) nix-libnet nixpkgs; };
            integration = import ../tests/integration {
              inherit (inputs)
                agenix
                agenix-rekey
                nix-libnet
                nixpkgs
                preservation
                self
                ;
              inherit system;
            };
          };
        };
    };
}
