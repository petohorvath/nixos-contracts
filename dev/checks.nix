# statix, which treefmt cannot run correctly, and the repository's static
# guards; nix-unit's module adds the `nix-unit` check and treefmt-nix's
# module the `treefmt` check.
{ pkgs }:
{
  lint =
    pkgs.runCommand "contracts-lint"
      {
        src = ../.;
        nativeBuildInputs = [ pkgs.statix ];
      }
      ''
        cd "$src"
        statix check .
        # A shipped adapter receives the public library, so a parent path,
        # which leads out of its directory, reaches an internal helper. `...`
        # is fine.
        parentPath='(^|[^.])\.\.([^.]|$)'
        if grep -rHnE --include='*.nix' "$parentPath" nixos/adapters; then
          echo "lint: a shipped adapter names a parent path;" \
            "use the contractsLib it receives." >&2
          exit 1
        fi
        touch "$out"
      '';
}
