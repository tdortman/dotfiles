#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils curl jq nix git nix-update

# The jar is a GitHub release asset, which nix-update cannot discover on its
# own, so the newest non-prerelease tag comes from the API and nix-update
# rewrites the URL version and the hash.
#
# REA expects a specific jar name, printed as the last line of this script.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# nix-update evaluates this store-path flake with read-only nix-instantiate.
nix eval --impure --expr "(builtins.getFlake $(nix flake metadata --json | jq .path)).outPath" >/dev/null

path="nix/packages/jadx-headless-mcp/default.nix"
repo="1013503897/jadx-headless-mcp"

old_version="$(sed -nE 's/^  version = "([^"]+)";$/\1/p' "$path")"
[[ -n "$old_version" ]] || {
  echo "error: could not extract version from $path" >&2
  exit 1
}

release="$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=20")"
new_version="$(jq -r '[.[] | select(.prerelease | not)][0].tag_name' <<<"$release" | sed 's/^v//')"
[[ -n "$new_version" && "$new_version" != "null" ]] || {
  echo "error: could not determine the newest release of $repo" >&2
  exit 1
}

if [[ "$new_version" == "$old_version" ]]; then
  echo "jadx-headless-mcp is already up to date at $old_version"
  exit 0
fi

echo "Updating jadx-headless-mcp: $old_version -> $new_version"
nix-update --flake jadx-headless-mcp --override-filename "$path" --version "$new_version" "$@"

echo "check that REA's documentation still names jadx-headless-mcp-$new_version-all.jar"
