#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash curl git gnused jq nix

# The suite is five GitHub release tarballs, so the version comes from the
# `releases/latest` redirect and the hash is taken by prefetching the tarball
# itself (the downloads are not behind the rate-limited API).
#
# nix-update is not used: for its release-notes URL it re-evaluates the flake
# from a store-path copy, which under Lix intermittently dies with
# "path ... is not valid" after it has already rewritten the version, leaving
# the package with a stale hash.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

status=0
for app_file in nix/packages/artcraft/*/default.nix; do
  [[ -f "$app_file" ]] || continue
  app=$(basename "$(dirname "$app_file")")

  old_version=$(sed -nE 's/^  version = "([^"]+)";$/\1/p' "$app_file")
  if [[ -z "$old_version" ]]; then
    echo "error: cannot read the version from $app_file" >&2
    status=1
    continue
  fi

  echo "==> Updating $app..."

  release=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/storytold/$app/releases/latest") || {
    echo "    FAILED: $app (cannot resolve the newest release)"
    status=1
    continue
  }
  new_version=${release##*/}
  new_version=${new_version#v}

  if [[ "$new_version" == "$old_version" ]]; then
    echo "    already up to date at $old_version"
    continue
  fi

  url="https://github.com/storytold/$app/releases/download/v$new_version/$app-$new_version-linux-x86_64.tar.gz"
  new_hash=$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash) || {
    echo "    FAILED: $app (cannot prefetch $url)"
    status=1
    continue
  }

  sed -i -E "s|^(  version = \")[^\"]+(\";)$|\1${new_version}\2|" "$app_file"
  sed -i -E "s|^(    hash = \")[^\"]+(\";)$|\1${new_hash}\2|" "$app_file"
  echo "    $old_version -> $new_version"
done

exit $status
