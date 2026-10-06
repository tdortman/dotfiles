#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git jq nix nix-update

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# nix-update evaluates this store-path flake with read-only nix-instantiate.
nix eval --impure --expr "(builtins.getFlake $(nix flake metadata --json | jq .path)).outPath" >/dev/null
exec nix-update --flake vx --override-filename nix/packages/vx/default.nix "$@"
