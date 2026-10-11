#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git jq nix nix-update

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

status=0
for app_file in nix/packages/artcraft/*/default.nix; do
  [[ -e "$app_file" ]] || continue
  app=$(basename "$(dirname "$app_file")")
  echo "==> Updating $app..."
  # nix-update evaluates this store-path flake with read-only nix-instantiate,
  # so refresh it after every edit the previous iteration made.
  nix eval --impure --expr "(builtins.getFlake $(nix flake metadata --json | jq .path)).outPath" >/dev/null
  if ! nix-update --flake "$app" \
    --override-filename "$app_file" \
    --use-github-releases "$@"; then
    echo "    FAILED: $app"
    status=1
  fi
done

exit $status
