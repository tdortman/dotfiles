#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils gnused jq nix git

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
path="$repo_root/nix/packages/vx/default.nix"
fake_hash="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

new_version="$(
  git ls-remote --tags --refs https://github.com/vx-lang/Vx 'v*' \
    | sed -E 's|.*refs/tags/v||' | sort -V | tail -n1
)"
if [[ -z "$new_version" ]]; then
  echo "error: could not list vx-lang/Vx tags" >&2
  exit 1
fi

old_version="$(sed -nE 's/^  version = "([^"]+)";$/\1/p' "$path")"
if [[ -z "$old_version" ]]; then
  echo "error: could not extract current version from $path" >&2
  exit 1
fi

if [[ "$old_version" == "$new_version" ]]; then
  echo "vx is already up to date at $old_version"
  exit 0
fi

echo "Updating vx: $old_version -> $new_version"

src_hash="$(nix flake prefetch --json "github:vx-lang/Vx/v$new_version" | jq -r .hash)"

backup="$(mktemp)"
cp "$path" "$backup"
trap 'cp "$backup" "$path"; rm -f "$backup"' ERR

sed -i -E "s|^(  version = \")[^\"]+(\";)$|\1${new_version}\2|" "$path"
sed -i -E "s|^(    hash = \")[^\"]+(\";)$|\1${src_hash}\2|" "$path"
sed -i -E "s|^(  cargoHash = \")[^\"]+(\";)$|\1${fake_hash}\2|" "$path"

# The vendored crates only have a hash once fetched; build them against a fake one and read it back.
# That build is expected to fail, so only the reported hash decides success.
cargo_hash="$(
  { nix build --no-link "$repo_root#vx.cargoDeps" 2>&1 || true; } \
    | sed -nE 's/^[[:space:]]*got:[[:space:]]*(sha256-[^[:space:]]+).*/\1/p' | head -n1
)"
if [[ -z "$cargo_hash" ]]; then
  echo "error: could not determine cargoHash for $new_version" >&2
  false
fi
sed -i -E "s|^(  cargoHash = \")[^\"]+(\";)$|\1${cargo_hash}\2|" "$path"

trap - ERR
rm -f "$backup"

echo "Updated vx: $old_version -> $new_version"
echo "  hash: $src_hash"
echo "  cargoHash: $cargo_hash"
