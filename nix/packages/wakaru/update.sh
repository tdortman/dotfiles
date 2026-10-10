#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils curl jq nix git nix-update

# The platform binary is published on the npm registry rather than as a GitHub
# release, so the version comes from the registry and nix-update only has to
# rewrite the URL and the hash.
#
# REA verifies its Wakaru integration against one release at a time, so a bump
# past that version may need a matching REA update for the feature to work.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# nix-update evaluates this store-path flake with read-only nix-instantiate.
nix eval --impure --expr "(builtins.getFlake $(nix flake metadata --json | jq .path)).outPath" >/dev/null

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
exec nix-update --flake wakaru --override-filename "$path" --version "$new_version" "$@"
