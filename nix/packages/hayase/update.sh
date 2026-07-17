#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash curl gnused jq git

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_path="$repo_root/nix/packages/hayase/source.json"

if [[ ! -f "$source_path" ]]; then
  echo "error: source metadata file not found: $source_path" >&2
  exit 1
fi

latest_linux="$(curl -fsSL "https://api.hayase.watch/files/latest-linux.yml")"
new_version="$(sed -nE 's/^version: ([^[:space:]]+)$/\1/p' <<< "$latest_linux" | head -n1)"
filename="$(sed -nE 's/^path: (.+)$/\1/p' <<< "$latest_linux" | head -n1)"
upstream_sha512="$(sed -nE 's/^sha512: ([^[:space:]]+)$/\1/p' <<< "$latest_linux" | head -n1)"

if [[ -z "$new_version" || -z "$filename" || -z "$upstream_sha512" ]]; then
  echo "error: invalid Linux release metadata" >&2
  exit 1
fi

if [[ ! "$filename" =~ ^linux-hayase-[0-9]+(\.[0-9]+)*-linux\.AppImage$ ]]; then
  echo "error: unexpected Linux AppImage filename: $filename" >&2
  exit 1
fi

if [[ "$filename" != "linux-hayase-${new_version}-linux.AppImage" ]]; then
  echo "error: Linux release metadata version does not match path" >&2
  exit 1
fi

url="https://api.hayase.watch/files/$filename"
hash="sha512-$upstream_sha512"
old_version="$(jq -r '.version // empty' "$source_path")"
old_url="$(jq -r '.url // empty' "$source_path")"
old_hash="$(jq -r '.hash // empty' "$source_path")"

if [[ -z "$old_version" || -z "$old_url" || -z "$old_hash" ]]; then
  echo "error: invalid source metadata in $source_path" >&2
  exit 1
fi

if [[ "$old_version" == "$new_version" && "$old_url" == "$url" && "$old_hash" == "$hash" ]]; then
  echo "hayase is already up to date at $old_version"
  exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
jq -n \
  --arg version "$new_version" \
  --arg url "$url" \
  --arg hash "$hash" \
  '{version: $version, url: $url, hash: $hash}' > "$tmp"
mv "$tmp" "$source_path"
trap - EXIT

echo "Updated hayase: $old_version -> $new_version"
echo "  source: $url"
echo "  hash: $hash"
