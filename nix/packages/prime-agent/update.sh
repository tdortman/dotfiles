#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash curl gnused jq nix nodejs git

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
path="$repo_root/nix/packages/prime-agent"
hashes="$path/hashes.json"

if [[ ! -f "$hashes" ]]; then
  echo "error: hashes file not found: $hashes" >&2
  exit 1
fi

release_json="$(curl -fsSL "https://api.github.com/repos/PrimeIntellect-ai/prime-agent/releases/latest")"
new_version="$(echo "$release_json" | jq -r '.tag_name' | sed 's/^v//')"

if [[ -z "$new_version" ]]; then
  echo "error: could not extract version from GitHub API" >&2
  exit 1
fi

old_version="$(jq -r '.version' "$hashes")"

if [[ -z "$old_version" || "$old_version" == "null" ]]; then
  echo "error: could not extract current version from $hashes" >&2
  exit 1
fi

if [[ "$old_version" == "$new_version" ]]; then
  echo "prime-agent is already up to date at $old_version"
  exit 0
fi

echo "Updating prime-agent: $old_version -> $new_version"

url="https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${new_version}/prime-agent-${new_version}.tgz"

source_hash="$(nix store prefetch-file "$url" 2>&1 | sed -nE "s/.*\(hash '([^']+)'\).*/\1/p")"
if [[ -z "$source_hash" ]]; then
  echo "error: failed to prefetch $url" >&2
  exit 1
fi

echo "Regenerating package-lock.json from the release tarball..."
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
curl -fsSL "$url" -o "$tmpdir/prime-agent.tgz"
tar -xzf "$tmpdir/prime-agent.tgz" -C "$tmpdir" --strip-components=1
(
  cd "$tmpdir"
  npm install --package-lock-only --ignore-scripts --no-audit --no-fund
)
cp "$tmpdir/package-lock.json" "$path/package-lock.json"

# Dummy npmDepsHash: build the package and replace it with the hash reported
# by the failed fetch, which also validates the derivation.
jq --arg v "$new_version" --arg h "$source_hash" \
  '.version = $v | .sourceHash = $h | .npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="' \
  "$hashes" > "$tmpdir/hashes.json"
mv "$tmpdir/hashes.json" "$hashes"

echo "Calculating npm dependencies hash..."
cd "$repo_root"
build_output="$(nix build .#prime-agent --no-link 2>&1 || true)"
npm_deps_hash="$(echo "$build_output" | sed -nE 's/.*got:? (sha256-[A-Za-z0-9+/=]+).*/\1/p' | head -n1)"

if [[ -z "$npm_deps_hash" ]]; then
  echo "error: failed to extract npmDepsHash from build output" >&2
  echo "$build_output" >&2
  exit 1
fi

jq --arg h "$npm_deps_hash" '.npmDepsHash = $h' "$hashes" > "$tmpdir/hashes.json"
mv "$tmpdir/hashes.json" "$hashes"

echo "Updated prime-agent: $old_version -> $new_version"
echo "  sourceHash: $source_hash"
echo "  npmDepsHash: $npm_deps_hash"
