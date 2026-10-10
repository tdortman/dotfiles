#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils curl jq nix git unzip

# Updates both release assets (Ghidra extension zip and bridge wheel) from the
# newest GitHub release whose extension is stamped for the Ghidra version
# nixpkgs ships. nix-update cannot drive this package: it has two fetchurl
# artifacts, and the release to use is not simply the latest one.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
path="$repo_root/nix/packages/ghidra-mcp/default.nix"
flake_ref="${NH_FLAKE:-$repo_root}"
api="https://api.github.com/repos/bethington/ghidra-mcp"

old_version="$(sed -nE 's/^  version = "([^"]+)";$/\1/p' "$path")"
[[ -n "$old_version" ]] || {
  echo "error: could not extract version from $path" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The extension only loads in the Ghidra version it was built against, so the
# release we want is the newest one stamped for this flake's Ghidra.
ghidra_version="$(
  nix eval --raw --impure --expr "
    let
      flake = builtins.getFlake (toString $flake_ref);
    in
    flake.inputs.nixpkgs.legacyPackages.x86_64-linux.ghidra.version
  " 2>/dev/null || true
)"

if [[ -z "$ghidra_version" ]]; then
  echo "error: cannot evaluate PKGS.ghidra for $flake_ref" >&2
  exit 1
fi

echo "Installed Ghidra: $ghidra_version"

releases="$(curl -fsSL "$api/releases?per_page=30")"

pick=""
mapfile -t candidates < <(jq -c '.[] | select(.prerelease | not)' <<<"$releases")
for rel in "${candidates[@]}"; do
  tag="$(jq -r .tag_name <<<"$rel")"
  zip_url="$(jq -r '.assets[] | select(.name | endswith(".zip")) | .browser_download_url' <<<"$rel")"
  wheel_url="$(jq -r '.assets[] | select(.name | endswith("-py3-none-any.whl")) | .browser_download_url' <<<"$rel")"
  [[ -n "$zip_url" && -n "$wheel_url" ]] || continue

  curl -fsSL -o "$work/ext.zip" "$zip_url"
  stamped="$(unzip -p "$work/ext.zip" GhidraMCP/extension.properties | sed -nE 's/^version=//p')"
  if [[ "$stamped" != "$ghidra_version" ]]; then
    echo "skipping $tag: extension is stamped for Ghidra $stamped" >&2
    continue
  fi

  pick="$rel"
  break
done

if [[ -z "$pick" ]]; then
  echo "error: no release has an extension for Ghidra $ghidra_version" >&2
  exit 1
fi

new_version="$(jq -r .tag_name <<<"$pick")"
new_version="${new_version#v}"

if [[ "$new_version" == "$old_version" ]]; then
  echo "ghidra-mcp is already up to date at $old_version"
  exit 0
fi

echo "Updating ghidra-mcp: $old_version -> $new_version"

asset_url() {
  jq -r --arg n "$1" '.assets[] | select(.name == $n) | .browser_download_url' <<<"$pick"
}

fetch_verified() {
  local name="$1" out="$2" url digest got
  url="$(asset_url "$name")"
  [[ -n "$url" ]] || {
    echo "error: release $new_version has no asset $name" >&2
    exit 1
  }
  curl -fsSL -o "$out" "$url"

  digest="$(jq -r --arg n "$name" '.assets[] | select(.name == $n) | .digest // ""' <<<"$pick")"
  if [[ -n "$digest" ]]; then
    got="sha256:$(sha256sum "$out" | cut -d' ' -f1)"
    [[ "$got" == "$digest" ]] || {
      echo "error: $name does not match the published digest ($got != $digest)" >&2
      exit 1
    }
  fi
}

fetch_verified "GhidraMCP-$new_version.zip" "$work/ext.zip"
fetch_verified "ghidra_mcp_bridge-$new_version-py3-none-any.whl" "$work/bridge.whl"

extension_hash="$(nix hash file --type sha256 --sri "$work/ext.zip")"
bridge_hash="$(nix hash file --type sha256 --sri "$work/bridge.whl")"

sed -i -E "s|^(  version = \")[^\"]+(\";)$|\1${new_version}\2|" "$path"
sed -i -E "s|^(  extensionHash = \")[^\"]+(\";)$|\1${extension_hash}\2|" "$path"
sed -i -E "s|^(  bridgeHash = \")[^\"]+(\";)$|\1${bridge_hash}\2|" "$path"

echo "Updated ghidra-mcp: $old_version -> $new_version"
