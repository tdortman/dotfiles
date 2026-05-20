#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash bun curl gnused jq nix git

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
path="$repo_root/nix/packages/oh-my-pi/default.nix"

if [[ ! -f "$path" ]]; then
    echo "error: package file not found: $path" >&2
    exit 1
fi

release_json="$(curl -fsSL "https://api.github.com/repos/can1357/oh-my-pi/releases/latest")"
new_version="$(echo "$release_json" | jq -r '.tag_name' | sed 's/^v//')"

if [[ -z "$new_version" || "$new_version" == "null" ]]; then
    echo "error: could not extract version from GitHub API" >&2
    exit 1
fi

old_version="$({
    sed -nE 's/^[[:space:]]*version = "([^"]+)";$/\1/p' "$path" | head -n1
})"

if [[ -z "$old_version" ]]; then
    echo "error: could not extract current version from $path" >&2
    exit 1
fi

if [[ "$old_version" == "$new_version" ]]; then
    echo "oh-my-pi is already up to date at $old_version"
    exit 0
fi

echo "Updating oh-my-pi: $old_version -> $new_version"

source_url="https://github.com/can1357/oh-my-pi/archive/refs/tags/v${new_version}.tar.gz"
source_hash="$({
    nix store prefetch-file --json --unpack "$source_url" | jq -r '.hash'
})"

if [[ -z "$source_hash" || "$source_hash" == "null" ]]; then
    echo "error: failed to prefetch source tarball" >&2
    exit 1
fi

backup="$(mktemp)"
cp "$path" "$backup"

tmpdir="$(mktemp -d)"

cleanup() {
    cp "$backup" "$path"
    rm -f "$backup"
    rm -rf "$tmpdir"
}

trap cleanup EXIT

sed -i -E "s|^([[:space:]]*version = \")[^\"]+(\";)$|\1${new_version}\2|" "$path"
sed -i -E "/src = fetchFromGitHub \{/,/^[[:space:]]*\};$/ s|^([[:space:]]*hash = \")[^\"]+(\";)$|\1${source_hash}\2|" "$path"

tarball="$tmpdir/source.tar.gz"
src_dir="$tmpdir/src"
out_dir="$tmpdir/out"

curl -fsSL "$source_url" -o "$tarball"
mkdir -p "$src_dir" "$out_dir"
tar -xzf "$tarball" -C "$src_dir" --strip-components=1

(
    cd "$src_dir"
    export HOME="$tmpdir/home"
    export BUN_INSTALL_CACHE_DIR="$tmpdir/bun-cache"
    mkdir -p "$HOME" "$BUN_INSTALL_CACHE_DIR"

    bun install \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress

    find . -type d -name node_modules -exec cp -R --parents {} "$out_dir" \;
)

node_modules_hash="$(nix hash path "$out_dir")"

sed -i -E "/nodeModules = stdenv.mkDerivation \{/,/^[[:space:]]*\};$/ s|^([[:space:]]*outputHash = \")[^\"]+(\";)$|\1${node_modules_hash}\2|" "$path"

rm -f "$backup"
rm -rf "$tmpdir"
trap - EXIT

echo "Updated oh-my-pi: $old_version -> $new_version"
echo "  source: $source_hash"
echo "  nodeModules: $node_modules_hash"
