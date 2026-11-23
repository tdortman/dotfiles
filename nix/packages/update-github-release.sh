#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils curl git gnugrep gnused nix

# Usage: update-github-release.sh <package> <owner/repo> <attr>=<output>...
#
# Bumps nix/packages/<package>/default.nix to the newest GitHub release of
# <owner/repo> (tagged v<version>), then refreshes every `<attr> = "...";` hash
# from the flake output it pins, in the order given: `hash=src`,
# `vendorHash=goModules`, `cargoHash=cargoDeps`.
#
# The version comes from the `releases/latest` redirect, which is not behind
# the rate-limited API. Each hash is read back from a build against a fake one,
# so it works for any fetcher.
#
# nix-update is not used: after every rewrite it re-evaluates the flake from a
# store path with read-only nix-instantiate, and evaluating this flake copies
# its tree into the store, so that evaluation dies after the version has
# already been rewritten.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

package=$1
repo=$2
shift 2

path=nix/packages/$package/default.nix
fake_hash=sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=

# Replaces the value of the only `<attr> = "...";` line in the package.
set_attr() {
  if [[ $(grep -cE "^[[:space:]]*$1 = \"[^\"]*\";$" "$path") != 1 ]]; then
    echo "error: expected exactly one \`$1 = \"...\";\` line in $path" >&2
    return 1
  fi
  sed -i -E "s|^([[:space:]]*$1 = \")[^\"]*(\";)$|\1$2\2|" "$path"
}

old_version=$(sed -nE 's/^[[:space:]]*version = "([^"]+)";$/\1/p' "$path")

release=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
if [[ "$release" != */releases/tag/v* ]]; then
  echo "error: $repo has no latest release tagged v<version> (got $release)" >&2
  exit 1
fi
new_version=${release##*/v}

if [[ "$new_version" == "$old_version" ]]; then
  echo "$package is already up to date at $old_version"
  exit 0
fi

echo "Updating $package: $old_version -> $new_version"

# A half-updated package pairs the new version with stale hashes, so any failure
# puts the file back.
backup=$(mktemp)
cp "$path" "$backup"
trap 'cp "$backup" "$path"; rm -f "$backup"' EXIT

set_attr version "$new_version"

for spec in "$@"; do
  attr=${spec%%=*}
  output=${spec#*=}

  set_attr "$attr" "$fake_hash"
  # The build is expected to fail on the fake hash; only the hash it reports
  # decides success.
  log=$(nix build --no-link ".#$package.$output" 2>&1 || true)
  hash=$(sed -nE 's/^[[:space:]]*got:[[:space:]]*(sha256-[^[:space:]]+).*/\1/p' <<<"$log" | head -n1)
  if [[ -z "$hash" ]]; then
    echo "$log" >&2
    echo "error: cannot determine $attr from .#$package.$output" >&2
    exit 1
  fi
  set_attr "$attr" "$hash"
  echo "  $attr: $hash"
done

trap - EXIT
rm -f "$backup"
