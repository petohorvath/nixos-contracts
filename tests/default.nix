# Assemble the root checks that run source tools over the repository.
{ formatter, pkgs }:
let
  sourceDir = pkgs.lib.cleanSource ../.;
  sourceCheck =
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
  formatting = sourceCheck "formatting" [ formatter ] "contracts-fmt --ci";
  lint = sourceCheck "lint" [ pkgs.statix pkgs.deadnix ] ''
    statix check .
    deadnix --fail .
  '';
  workflows = sourceCheck "workflows" [ pkgs.actionlint ] ''
    shopt -s nullglob
    workflows=(.github/workflows/*.yml .github/workflows/*.yaml)
    if (( ''${#workflows[@]} )); then
      actionlint "''${workflows[@]}"
    fi
  '';
}
