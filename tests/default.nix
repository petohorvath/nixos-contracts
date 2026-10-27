# Assemble the root checks that run source tools over the repository.
{ formatter, pkgs }:
let
  sourceDir = pkgs.lib.cleanSource ../.;
  runSourceCheck =
    name: packages: script:
    pkgs.runCommand "contracts-${name}" { nativeBuildInputs = packages; } ''
      cp -R ${sourceDir} source
      chmod -R u+w source
      cd source
      ${script}
      touch "$out"
    '';
in
{
  formatting = runSourceCheck "formatting" [ formatter ] "contracts-fmt --ci";
  lint = runSourceCheck "lint" [ pkgs.statix pkgs.deadnix ] ''
    statix check .
    deadnix --fail .
    # A shipped adapter receives the public library, so a parent path, which
    # leads out of its directory, reaches an internal helper. `...` is fine.
    if grep -rHnE --include='*.nix' '(^|[^.])\.\.([^.]|$)' nixos/adapters; then
      echo "lint: a shipped adapter names a parent path; use the contractsLib it receives." >&2
      exit 1
    fi
  '';
  workflows = runSourceCheck "workflows" [ pkgs.actionlint ] ''
    shopt -s nullglob
    workflows=(.github/workflows/*.yml .github/workflows/*.yaml)
    if (( ''${#workflows[@]} )); then
      actionlint "''${workflows[@]}"
    fi
  '';
}
