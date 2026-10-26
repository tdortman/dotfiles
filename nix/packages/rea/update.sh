#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils curl gnused jq nix git

# REA ships a built dist/ in its npm tarball, so the CLI has three inputs to
# move together: the registry tarball, the lockfile from the matching git tag,
# and the npm dependency hash. nix-update cannot drive the third, so the script
# bumps the first two and lets the build report the new dep hash.
#
# REA also admits several analysis tools only at the release it audited. The
# release's own dist/ modules name those releases, so pins.json is regenerated
# from them on every run, even when REA itself is unchanged.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
path="nix/packages/rea/default.nix"
pins_path="nix/packages/rea/pins.json"
registry="https://registry.npmjs.org/rea-agents"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

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
else
  echo "Updating rea: $old_version -> $new_version"

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
  # recorded hash is stale and the build reports its replacement. If it does
  # not, the closure is unchanged and the existing hash stands.
  build_output="$(nix build .#rea.cli --no-link 2>&1 || true)"
  deps_hash="$(sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=]+).*/\1/p' <<<"$build_output" | tail -1)"
  if [[ -n "$deps_hash" ]]; then
    sed -i -E "s|^(  depsHash = \")[^\"]+(\";)$|\1${deps_hash}\2|" "$path"
    echo "  deps hash: $deps_hash"
  else
    echo "  npm dependencies unchanged"
  fi
fi

cli="$(nix build .#rea.cli --no-link --print-out-paths)"
package="$cli/lib/node_modules/rea-agents"
node="$(nix build .#rea.nodejs --no-link --print-out-paths)/bin/node"

# Node runs the release's own modules, so a renamed export fails here instead
# of silently dropping a pin.
"$node" --input-type=module - "$package/dist" >"$work/requirements.json" <<'EOF'
const dist = process.argv[2];
const load = (module) => import(`${dist}/${module}`);
const { JADX_RELEASE } = await load("android/JadxRelease.js");
const { WABT_VERSION } = await load("wasm/WabtRelease.js");
const { WAKARU_RELEASE } = await load("javascript/recovery/WakaruRelease.js");
const { FIRMWARE_TOOL_REQUIREMENTS } = await load("contracts/firmware/firmwareToolRequirements.js");
const { SUPPORTED_GHIDRA_VERSION } = await load("ghidra/GhidraReleasePolicy.js");
const { MITMPROXY_CAPTURE_PROVIDER_IDENTITY } = await load("browser/history/CaptureRelease.js");
const required = (value, name) => {
  if (typeof value !== "string" || value === "") throw new Error(`REA no longer exports ${name}`);
  return value;
};
const escape = (version) => version.replaceAll(".", "\\.");
const line = ({ major, minor }) => `${major}\\.${minor}\\..*`;
const [ghidraMajor, ghidraMinor] = required(SUPPORTED_GHIDRA_VERSION, "SUPPORTED_GHIDRA_VERSION").split(".");
console.log(JSON.stringify({
  jadx: { version: required(JADX_RELEASE.version, "JADX_RELEASE"), url: JADX_RELEASE.url, sha256: JADX_RELEASE.sha256 },
  wabt: required(WABT_VERSION, "WABT_VERSION"),
  wakaru: required(WAKARU_RELEASE.version, "WAKARU_RELEASE"),
  nixpkgs: {
    binwalk: line(FIRMWARE_TOOL_REQUIREMENTS.binwalk),
    ghidra: line({ major: ghidraMajor, minor: ghidraMinor }),
    mitmproxy: escape(required(MITMPROXY_CAPTURE_PROVIDER_IDENTITY.version, "MITMPROXY_CAPTURE_PROVIDER_IDENTITY")),
    unblob: line(FIRMWARE_TOOL_REQUIREMENTS.unblob),
  },
}));
EOF

# The sigrok admission is a version-banner regex rather than an export.
sigrok_version="$(grep -ohE '\^sigrok-cli [0-9]+\\\.[0-9]+\\\.[0-9]+' "$package/dist/signals/SigrokRecordingProvider.js" | head -1 | sed -E 's/^\^sigrok-cli //; s/\\//g')"
[[ -n "$sigrok_version" ]] || {
  echo "error: could not find the sigrok-cli version REA admits" >&2
  exit 1
}

node_version="$("$node" --version)"
node_range="$(jq -r .engines.node "$package/package.json")"
"$node" -e 'process.exit(require(process.argv[1]).satisfies(process.argv[2], process.argv[3]) ? 0 : 1)' \
  "$package/node_modules/semver" "$node_version" "$node_range" || {
  echo "error: nodejs $node_version does not satisfy REA's engines range $node_range" >&2
  exit 1
}

# Unchanged URLs keep their recorded hash; new ones are fetched once.
pin() {
  local name="$1" version="$2" url="$3" hash
  hash="$(jq -r --arg name "$name" --arg url "$url" \
    '.build[$name] | select(.url == $url) | .hash' "$pins_path")"
  if [[ -z "$hash" ]]; then
    hash="$(nix store prefetch-file --json "$url" | jq -r .hash)"
    echo "  pinned $name $version" >&2
  fi
  jq -n --arg version "$version" --arg url "$url" --arg hash "$hash" \
    '{ version: $version, url: $url, hash: $hash }'
}

jadx_version="$(jq -r .jadx.version "$work/requirements.json")"
jadx_url="$(jq -r .jadx.url "$work/requirements.json")"
wabt_version="$(jq -r .wabt "$work/requirements.json")"
wakaru_version="$(jq -r .wakaru "$work/requirements.json")"

jadx_pin="$(pin jadx-headless-mcp "$jadx_version" "$jadx_url")"
# REA identifies the jar by digest, so a re-uploaded asset must not slip in.
jadx_expected="$(nix hash convert --hash-algo sha256 --to sri "$(jq -r .jadx.sha256 "$work/requirements.json")")"
[[ "$(jq -r .hash <<<"$jadx_pin")" == "$jadx_expected" ]] || {
  echo "error: $jadx_url does not match the digest REA audited ($jadx_expected)" >&2
  exit 1
}

jq -n \
  --argjson jadx "$jadx_pin" \
  --argjson sigrok "$(pin sigrok-cli "$sigrok_version" "https://sigrok.org/download/source/sigrok-cli/sigrok-cli-$sigrok_version.tar.gz")" \
  --argjson wabt "$(pin wabt "$wabt_version" "https://github.com/WebAssembly/wabt/releases/download/$wabt_version/wabt-$wabt_version.tar.xz")" \
  --argjson wakaru "$(pin wakaru "$wakaru_version" "https://registry.npmjs.org/@wakaru/cli-linux-x64/-/cli-linux-x64-$wakaru_version.tgz")" \
  --slurpfile requirements "$work/requirements.json" \
  '{
    build: { "jadx-headless-mcp": $jadx, "sigrok-cli": $sigrok, wabt: $wabt, wakaru: $wakaru },
    nixpkgs: $requirements[0].nixpkgs
  }' >"$work/pins.json"
mv "$work/pins.json" "$pins_path"

nix build .#rea --no-link
echo "rea $(sed -nE 's/^  version = "([^"]+)";$/\1/p' "$path") pins: jadx-headless-mcp $jadx_version, sigrok-cli $sigrok_version, wabt $wabt_version, wakaru $wakaru_version"
