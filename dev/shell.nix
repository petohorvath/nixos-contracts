{
  actionlint,
  deadnix,
  formatter,
  git,
  mkShellNoCC,
  nil,
  nix,
  nixfmt,
  prettier,
  shfmt,
  statix,
}:
mkShellNoCC {
  packages = [
    nix
    nil
    nixfmt
    statix
    deadnix
    git
    shfmt
    prettier
    actionlint
    formatter
  ];
}
