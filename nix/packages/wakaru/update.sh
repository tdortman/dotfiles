#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils curl gnused jq nix git nix-update

# The platform binary is published on the npm registry rather than as a GitHub
# release, so the version comes from the registry.
#
# nix-update's own version bump resolves the release-notes URL first, which
# re-evaluates the flake after the version has been rewritten. That eval needs
# the store copy of the tree, and nix-update's nix-instantiate cannot create it,
# so the eval dies with "path ... did not exist in the store during evaluation"
# and leaves the package with a stale hash. Write the version here and let
# nix-update update only the hash.
#
# REA verifies its Wakaru integration against one release at a time, so a bump
# past that version may need a matching REA update for the feature to work.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

path="nix/packages/wakaru/default.nix"
registry="https://registry.npmjs.org/@wakaru/cli-linux-x64"

old_version="$(sed -nE 's/^  version = "([^"]+)";$/\1/p' "$path")"
[[ -n "$old_version" ]] || {
  echo "error: could not extract version from $path" >&2
  exit 1
}

new_version="$(curl -fsSL "$registry/latest" | jq -r .version)"

if [[ "$new_version" == "$old_version" ]]; then
  echo "wakaru is already up to date at $old_version"
  exit 0
fi

echo "Updating wakaru: $old_version -> $new_version"

sed -i -E "s|^(  version = \")[^\"]+(\";)$|\1${new_version}\2|" "$path"

# Materialise the store copy of the tree that nix-update's nix-instantiate eval
# reads; it runs after the version is written because that is the tree the eval
# evaluates.
nix eval --impure --expr "(builtins.getFlake $(nix flake metadata --json | jq .path)).outPath" >/dev/null

exec nix-update --flake wakaru --override-filename "$path" --version skip "$@"
