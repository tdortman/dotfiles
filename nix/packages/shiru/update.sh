#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash curl gnused jq nix git

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
path="$repo_root/nix/packages/shiru/default.nix"

if [[ ! -f "$path" ]]; then
  echo "error: package file not found: $path" >&2
  exit 1
fi

release_json="$(curl -fsSL "https://api.github.com/repos/RockinChaos/Shiru/releases/latest")"
new_version="$(echo "$release_json" | jq -r '.tag_name' | sed 's/^v//')"

if [[ -z "$new_version" ]]; then
  echo "error: could not extract version from GitHub API" >&2
  exit 1
fi

old_version="$(
  sed -nE 's/^[[:space:]]*version = "([^"]+)";$/\1/p' "$path" \
    | head -n1
)"

if [[ -z "$old_version" ]]; then
  echo "error: could not extract current version from $path" >&2
  exit 1
fi

if [[ "$old_version" == "$new_version" ]]; then
  echo "shiru is already up to date at $old_version"
  exit 0
fi

echo "Updating shiru: $old_version -> $new_version"

url="https://github.com/RockinChaos/Shiru/releases/download/v${new_version}/linux-Shiru-v${new_version}.AppImage"

hash="$(nix store prefetch-file "$url" 2>&1 | sed -nE "s/.*\(hash '([^']+)'\).*/\1/p")"
if [[ -z "$hash" ]]; then
  echo "error: failed to prefetch $url" >&2
  exit 1
fi

# Update version
sed -i -E "s|^(  version = \")[^\"]+(\";)$|\1${new_version}\2|" "$path"

# Update sha256
sed -i -E "s|^([[:space:]]*sha256 = \")[^\"]+(\";)$|\1${hash}\2|" "$path"

echo "Updated shiru: $old_version -> $new_version"
echo "  sha256: $hash"
