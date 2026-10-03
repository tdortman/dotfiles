#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils curl gnused jq nix git sqlite xdg-utils

# Downloads require a build.stencil.so login. The session cookie is read from
# the most recently used Firefox-family profile and only ever passed to curl
# on stdin; it is never written anywhere. Only the tarball enters the store.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
path="$repo_root/nix/packages/tern/default.nix"
site="https://build.stencil.so"
interactive=false
[[ -t 0 && -t 1 ]] && interactive=true

old_version="$(sed -nE 's/^  version = "([^"]+)";$/\1/p' "$path")"
if [[ -z "$old_version" ]]; then
  echo "error: could not extract current version from $path" >&2
  exit 1
fi

# Firefox keeps its cookie database locked, so query a copy on the user-only
# runtime tmpfs.
work="$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}")"
trap 'rm -rf "$work"' EXIT

read_cookie() {
  local db best="" best_seen=0 row
  for db in ~/.librewolf/*/cookies.sqlite ~/.mozilla/firefox/*/cookies.sqlite; do
    [[ -f "$db" ]] || continue
    cp "$db" "$work/cookies.sqlite"
    rm -f "$work/cookies.sqlite-wal"
    [[ -f "$db-wal" ]] && cp "$db-wal" "$work/cookies.sqlite-wal"
    row="$(sqlite3 -separator ' ' "$work/cookies.sqlite" \
      "select lastAccessed, name || '=' || value from moz_cookies
       where host = '.stencil.so' and name = '__Secure-stencil_session'
       order by lastAccessed desc limit 1")"
    rm -f "$work"/cookies.sqlite*
    if [[ -n "$row" && "${row%% *}" -gt "$best_seen" ]]; then
      best_seen="${row%% *}"
      best="${row#* }"
    fi
  done
  printf '%s' "$best"
}

# Prints the newest build, or nothing when the session is missing or expired.
latest_build() {
  [[ -n "$cookie" ]] || return 0
  printf 'Cookie: %s\n' "$cookie" \
    | curl -fsS -H @- -H 'Accept: application/json' "$site/api/products/tern/builds" 2>/dev/null \
    | jq -c '.builds | max_by(.published_at) | {version, file: (.files[]
        | select(.platform == "linux" and .arch == "x86_64" and .kind == "archive"))}' \
    || true
}

cookie="$(read_cookie)"
build="$(latest_build)"

if [[ -z "$build" ]] && $interactive; then
  read -rp "Not logged in to $site. Open it in the browser to log in? [Y/n] " answer
  if [[ "${answer,,}" != n* ]]; then
    xdg-open "$site/tern" >/dev/null 2>&1 &
    read -rp "Press Enter once logged in… "
    cookie="$(read_cookie)"
    build="$(latest_build)"
  fi
fi

if [[ -z "$build" ]]; then
  echo "error: could not list tern builds; log in at $site/tern in LibreWolf or Firefox" >&2
  exit 1
fi

new_version="$(jq -r .version <<<"$build")"
name="$(jq -r .file.name <<<"$build")"
url="$site$(jq -r .file.url <<<"$build")"
sha256="$(jq -r .file.sha256 <<<"$build")"

if [[ "$new_version" == "$old_version" ]]; then
  echo "tern is already up to date at $old_version"
  exit 0
fi

echo "Updating tern: $old_version -> $new_version"

# requireFile looks the source up by this exact name.
printf 'Cookie: %s\n' "$cookie" | curl -fL --progress-bar -H @- -o "$work/$name" "$url"
if [[ "$(sha256sum "$work/$name" | cut -d' ' -f1)" != "$sha256" ]]; then
  echo "error: $name does not match the published sha256" >&2
  exit 1
fi
if [[ "$name" != "Tern-$new_version-linux-x86_64.tar.gz" ]]; then
  echo "error: unexpected file name $name; update the requireFile name in $path" >&2
  exit 1
fi

nix-store --add-fixed sha256 "$work/$name" >/dev/null
hash="$(nix hash file --type sha256 --sri "$work/$name")"

sed -i -E "s|^(  version = \")[^\"]+(\";)$|\1${new_version}\2|" "$path"
sed -i -E "s|^(    hash = \")[^\"]+(\";)$|\1${hash}\2|" "$path"

echo "Updated tern: $old_version -> $new_version"
echo "  hash: $hash"
