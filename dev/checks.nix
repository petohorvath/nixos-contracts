{
  formatter,
  inputs,
  pkgs,
  system,
}:
let
  rekey = inputs.agenix-rekey.inputs;
  hooks = rekey.pre-commit-hooks.inputs;
  # The sandbox cannot fetch, so every locked input comes from the store.
  overrides = {
    inherit (inputs)
      agenix
      agenix-rekey
      flake-parts
      nix-libnet
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
  overrideFlags = pkgs.lib.concatStringsSep " " (
    pkgs.lib.mapAttrsToList (name: input: "--override-input ${name} ${input}") overrides
  );
in
import ../tests {
  inherit formatter pkgs;
}
// {
  # Run the nix-unit suite from the `tests` output with the selected inputs.
  evaluation = pkgs.runCommand "contracts-evaluation" { nativeBuildInputs = [ pkgs.nix-unit ]; } ''
    export HOME=$(realpath .)
    # NixOS evaluation writes to the store, so use a writable chroot store.
    export NIX_REMOTE=$HOME/storedata
    nix-unit --extra-experimental-features flakes \
      --flake ${inputs.self}#tests.${system} ${overrideFlags}
    touch "$out"
  '';
}
