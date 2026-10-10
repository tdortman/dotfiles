#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils curl jq nix git

# REA ships a built dist/ in its npm tarball, so this package has three inputs
# to move together: the registry tarball, the lockfile from the matching git
# tag, and the npm dependency hash. nix-update cannot drive the third, so the
# script bumps the first two and lets the build report the new dep hash.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
path="$repo_root/nix/packages/rea/default.nix"
registry="https://registry.npmjs.org/rea-agents"

old_version="$(sed -nE 's/^  version = "([^"]+)";$/\1/p' "$path")"
[[ -n "$old_version" ]] || {
  echo "error: could not extract version from $path" >&2
  exit 1
}

release="$(curl -fsSL "$registry/latest")"
new_version="$(jq -r .version <<<"$release")"
tarball_url="$(jq -r .dist.tarball <<<"$release")"

if [[ "$new_version" == "$old_version" ]]; then
  echo "rea is already up to date at $old_version"
  exit 0
fi

echo "Updating rea: $old_version -> $new_version"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -fsSL -o "$work/rea-agents.tgz" "$tarball_url"
lock_url="https://raw.githubusercontent.com/morluto/rea/rea-agents-$new_version/package-lock.json"
if ! curl -fsSL -o "$work/package-lock.json" "$lock_url"; then
  echo "error: $lock_url is not available yet; the git tag may lag the npm release" >&2
  exit 1
fi

tarball_hash="$(nix hash file --type sha256 --sri "$work/rea-agents.tgz")"
lock_hash="$(nix hash file --type sha256 --sri "$work/package-lock.json")"

sed -i -E "s|^(  version = \")[^\"]+(\";)$|\1${new_version}\2|" "$path"
sed -i -E "s|^(  tarballHash = \")[^\"]+(\";)$|\1${tarball_hash}\2|" "$path"
sed -i -E "s|^(  lockHash = \")[^\"]+(\";)$|\1${lock_hash}\2|" "$path"

# A new release usually moves the dependency closure, in which case the
# recorded hash is stale and the build reports its replacement. If it does not,
# the closure is unchanged and the existing hash stands.
build_output="$(nix build .#rea --no-link 2>&1 || true)"
deps_hash="$(sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=]+).*/\1/p' <<<"$build_output" | tail -1)"
if [[ -z "$deps_hash" ]]; then
  if nix build .#rea --no-link 2>/dev/null; then
    echo "  npm dependencies unchanged"
  else
    echo "error: build did not report a new npm dependency hash" >&2
    echo "$build_output" >&2
    exit 1
  fi
else
  sed -i -E "s|^(  depsHash = \")[^\"]+(\";)$|\1${deps_hash}\2|" "$path"
  nix build .#rea --no-link
  echo "  deps hash: $deps_hash"
fi

echo "Updated rea: $old_version -> $new_version"
