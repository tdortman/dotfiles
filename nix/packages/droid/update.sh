#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash curl gnused nix git

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
path="$repo_root/nix/packages/droid/default.nix"

if [[ ! -f "$path" ]]; then
  echo "error: package file not found: $path" >&2
  exit 1
fi

install_script="$(curl -fsSL "https://app.factory.ai/cli")"
new_version="$(
  printf '%s\n' "$install_script" \
    | sed -nE 's/^VER="([^"]+)"$/\1/p' \
    | head -n1
)"

if [[ -z "$new_version" ]]; then
  echo "error: could not extract version from install script" >&2
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
  echo "droid is already up to date at $old_version"
  exit 0
fi

echo "Updating droid: $old_version -> $new_version"

base_url="https://downloads.factory.ai/factory-cli/releases/$new_version"

get_hash() {
  local checksum_url="$1"
  local hex_hash

  hex_hash="$(curl -fsSL "$checksum_url" | tr -d '\r\n')"

  if [[ -z "$hex_hash" ]]; then
    echo "error: empty checksum from $checksum_url" >&2
    exit 1
  fi

  nix hash convert --hash-algo sha256 --to sri "$hex_hash" | tr -d '\r\n'
}

update_hash() {
  local system="$1"
  local hash="$2"
  sed -i -E "s|^([[:space:]]*\"$system\" = \").*(\";)$|\1$hash\2|" "$path"
}

x86_64_linux_hash="$(get_hash "$base_url/linux/x64/droid.sha256")"
aarch64_linux_hash="$(get_hash "$base_url/linux/arm64/droid.sha256")"
x86_64_darwin_hash="$(get_hash "$base_url/darwin/x64/droid.sha256")"
aarch64_darwin_hash="$(get_hash "$base_url/darwin/arm64/droid.sha256")"

sed -i -E "s|^([[:space:]]*version = \").*(\";)$|\1$new_version\2|" "$path"

update_hash "x86_64-linux" "$x86_64_linux_hash"
update_hash "aarch64-linux" "$aarch64_linux_hash"
update_hash "x86_64-darwin" "$x86_64_darwin_hash"
update_hash "aarch64-darwin" "$aarch64_darwin_hash"

echo "Updated droid: $old_version -> $new_version"
echo "  x86_64-linux: $x86_64_linux_hash"
echo "  aarch64-linux: $aarch64_linux_hash"
echo "  x86_64-darwin: $x86_64_darwin_hash"
echo "  aarch64-darwin: $aarch64_darwin_hash"