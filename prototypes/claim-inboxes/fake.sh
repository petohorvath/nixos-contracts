#!/usr/bin/env bash
# PROTOTYPE: create the empty encrypted and rekeyed files the main scenario
# names, so every node evaluates to its system derivation.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
nix eval --json -f "$here" fleet.roles --apply builtins.attrNames | jq -r '.[]' | while read -r node; do
  mkdir -p "$here/fake/rekeyed/$node"
done
for kind in encrypted rekeyed; do
  nix eval --json -f "$here" "fakePaths.$kind" | jq -r '.[]' | while read -r path; do
    case "$path" in /*) continue ;; esac
    mkdir -p "$here/fake/$(dirname "$path")"
    touch "$here/fake/$path"
  done
done
