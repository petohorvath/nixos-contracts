{
  git,
  mkShellNoCC,
  nil,
  nix,
  nix-unit,
  statix,
  treefmtShell,
}:
mkShellNoCC {
  inputsFrom = [ treefmtShell ];
  packages = [
    nix
    nix-unit
    git
    nil
    statix
  ];
}
