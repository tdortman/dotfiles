#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash curl git gnused jq nix nix-update

# The release is a single AppImage, so the version comes from the
# `releases/latest` redirect and nix-update takes the hash by building the
# derivation's src.
#
# nix-update's own version bump resolves the release-notes URL first, which
# re-evaluates the flake after the version has been rewritten. That eval needs
# the store copy of the tree, and nix-update's nix-instantiate cannot create it,
# so the eval dies with "path ... did not exist in the store during evaluation"
# and leaves the package with a stale hash. Write the version here and let
# nix-update update only the hash.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

path=nix/packages/shiru/default.nix

old_version=$(sed -nE 's/^  version = "([^"]+)";$/\1/p' "$path")
if [[ -z "$old_version" ]]; then
  echo "error: cannot read the version from $path" >&2
  exit 1
fi

release=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/RockinChaos/Shiru/releases/latest")
new_version=${release##*/}
new_version=${new_version#v}

if [[ "$new_version" == "$old_version" ]]; then
  echo "shiru is already up to date at $old_version"
  exit 0
fi

echo "Updating shiru: $old_version -> $new_version"

sed -i -E "s|^(  version = \")[^\"]+(\";)$|\1${new_version}\2|" "$path"

# Materialise the store copy of the tree that nix-update's nix-instantiate eval
# reads; it runs after the version is written because that is the tree the eval
# evaluates.
nix eval --impure --expr "(builtins.getFlake $(nix flake metadata --json | jq .path)).outPath" >/dev/null

exec nix-update --flake shiru --override-filename "$path" --version skip "$@"
