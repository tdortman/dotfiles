#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash curl gnused jq nix git

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
path="$repo_root/nix/packages/fluxer/default.nix"

if [[ ! -f "$path" ]]; then
  echo "error: package file not found: $path" >&2
  exit 1
fi

x64_manifest="$(curl -fsSL "https://api.fluxer.app/dl/desktop/stable/linux/x64/manifest.json")"
arm64_manifest="$(curl -fsSL "https://api.fluxer.app/dl/desktop/stable/linux/arm64/manifest.json")"

new_version_x64="$(echo "$x64_manifest" | jq -r '.version')"
new_version_arm64="$(echo "$arm64_manifest" | jq -r '.version')"

if [[ "$new_version_x64" != "$new_version_arm64" ]]; then
  echo "error: version mismatch between x64 ($new_version_x64) and arm64 ($new_version_arm64)" >&2
  exit 1
fi

new_version="$new_version_x64"

old_version="$(
  sed -nE 's/^[[:space:]]*version \? "([^"]+)",$/\1/p' "$path" \
    | head -n1
)"

if [[ -z "$old_version" ]]; then
  echo "error: could not extract current version from $path" >&2
  exit 1
fi

if [[ "$old_version" == "$new_version" ]]; then
  echo "fluxer is already up to date at $old_version"
  exit 0
fi

echo "Updating fluxer: $old_version -> $new_version"

appimage_x64="$(echo "$x64_manifest" | jq -r '.files.appimage')"
appimage_arm64="$(echo "$arm64_manifest" | jq -r '.files.appimage')"

if [[ -z "$appimage_x64" || "$appimage_x64" == "null" ]]; then
  echo "error: no appimage file in x64 manifest" >&2
  exit 1
fi

if [[ -z "$appimage_arm64" || "$appimage_arm64" == "null" ]]; then
  echo "error: no appimage file in arm64 manifest" >&2
  exit 1
fi

url_x64="https://api.fluxer.app/dl/desktop/stable/linux/x64/${appimage_x64}"
url_arm64="https://api.fluxer.app/dl/desktop/stable/linux/arm64/${appimage_arm64}"

get_hash() {
  local url="$1"
  local hash
  hash="$(nix store prefetch-file "$url" 2>&1 | sed -nE "s/.*\(hash '([^']+)'\).*/\1/p")"
  if [[ -z "$hash" ]]; then
    echo "error: failed to prefetch $url" >&2
    exit 1
  fi
  printf '%s' "$hash"
}

x64_hash="$(get_hash "$url_x64")"
arm64_hash="$(get_hash "$url_arm64")"

# Update version
sed -i -E "s|^(  version \? \")[^\"]+(\",)$|\1${new_version}\2|" "$path"

# Update first hash (x86_64-linux)
sed -i -E '/x86_64\.AppImage/{n;s|^([[:space:]]*)hash = "sha256-[^"]+";|\1hash = "'"$x64_hash"'";|}' "$path"

# Update second hash (aarch64-linux)
sed -i -E '/arm64\.AppImage/{n;s|^([[:space:]]*)hash = "sha256-[^"]+";|\1hash = "'"$arm64_hash"'";|}' "$path"

echo "Updated fluxer: $old_version -> $new_version"
echo "  x86_64-linux: $x64_hash"
echo "  aarch64-linux: $arm64_hash"
