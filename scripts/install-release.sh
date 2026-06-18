#!/usr/bin/env sh
set -eu

repo="${MEGA_WALLET_CLI_REPO:-megaeth-labs/wallet-cli}"
asset_prefix="${MEGA_WALLET_CLI_ASSET_PREFIX:-mega-wallet-cli}"
prefix="${MEGA_WALLET_CLI_PREFIX:-$HOME/.local}"
install_root="${MEGA_WALLET_CLI_HOME:-$HOME/.mega/wallet-cli}"
bin_dir="${MEGA_WALLET_CLI_BIN_DIR:-$prefix/bin}"
version="${MEGA_WALLET_CLI_VERSION:-}"
with_skill=1
skill_agent="${MEGA_WALLET_CLI_SKILL_AGENT:-all}"
force_skill=1
dry_run=0
required_node_major=22

usage() {
  cat <<'USAGE'
Usage: install-release.sh [options]

Install the latest MegaETH MOSS CLI from GitHub Releases.

Options:
  --version VERSION       Release tag to install (default: latest release)
  --repo OWNER/REPO       GitHub repo to fetch from (default: megaeth-labs/wallet-cli)
  --prefix DIR            Prefix used when --bin-dir is omitted (default: ~/.local)
  --bin-dir DIR           Directory for the mega wrapper (default: <prefix>/bin)
  --install-root DIR      Versioned install root (default: ~/.mega/wallet-cli)
  --no-skill              Skip installing the bundled agent skill
  --skill-agent AGENT     Skill target: codex, claude, or all (default: all)
  --no-force-skill        Do not replace an existing installed skill
  --dry-run               Print actions without writing files
  -h, --help              Show this help

Examples:
  curl -fsSL https://account.megaeth.com/install | sh
  curl -fsSL https://account.megaeth.com/install | sh -- --version v0.1.0
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      ;;
    --version)
      version="${2:?missing value for --version}"
      shift 2
      ;;
    --repo)
      repo="${2:?missing value for --repo}"
      shift 2
      ;;
    --prefix)
      prefix="${2:?missing value for --prefix}"
      bin_dir="${MEGA_WALLET_CLI_BIN_DIR:-$prefix/bin}"
      shift 2
      ;;
    --bin-dir)
      bin_dir="${2:?missing value for --bin-dir}"
      shift 2
      ;;
    --install-root)
      install_root="${2:?missing value for --install-root}"
      shift 2
      ;;
    --no-skill)
      with_skill=0
      shift
      ;;
    --skill-agent)
      skill_agent="${2:?missing value for --skill-agent}"
      shift 2
      ;;
    --no-force-skill)
      force_skill=0
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$repo" in
  */*) ;;
  *)
    echo "--repo must be OWNER/REPO" >&2
    exit 2
    ;;
esac

case "$skill_agent" in
  codex|claude|all) ;;
  *)
    echo "--skill-agent must be codex, claude, or all" >&2
    exit 2
    ;;
esac

info() {
  printf 'info: %s\n' "$1"
}

warn() {
  printf 'warn: %s\n' "$1" >&2
}

error() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || error "missing required command: $1"
}

github_api_get() {
  url="$1"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" "$url"
  else
    curl -fsSL "$url"
  fi
}

download() {
  url="$1"
  output="$2"

  if [ "$dry_run" -eq 1 ]; then
    echo "would download: $url -> $output"
    return
  fi

  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fL -H "Authorization: Bearer $GITHUB_TOKEN" "$url" -o "$output"
  else
    curl -fL "$url" -o "$output"
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

latest_version() {
  github_api_get "https://api.github.com/repos/$repo/releases/latest" |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
    head -n 1
}

check_prerequisites() {
  need curl
  need tar
  need node
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    error "missing required command: sha256sum or shasum"
  fi

  node_major="$(node -p 'Number(process.versions.node.split(".")[0])')"
  if [ "$node_major" -lt "$required_node_major" ]; then
    error "Node.js >= $required_node_major is required, but you have Node.js $(node -v 2>/dev/null || echo unknown).

To install Node.js 22:
 • Using nvm: nvm install 22
 • Using apt: curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs"
  fi
}

path_contains() {
  case ":$PATH:" in
    *":$1:"*) return 0 ;;
    *) return 1 ;;
  esac
}

wrapper_is_owned() {
  wrapper="$1"
  [ -f "$wrapper" ] && grep -Fq "$install_root/current/dist/" "$wrapper"
}

remove_legacy_wallet_wrapper() {
  target="$bin_dir/wallet"

  if [ "$dry_run" -eq 1 ]; then
    echo "would remove legacy wallet wrapper if repo-owned: $target"
    return
  fi

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    return
  fi

  if wrapper_is_owned "$target"; then
    rm -f "$target"
  else
    warn "skip non-owned legacy wallet wrapper: $target"
  fi
}

write_wrapper() {
  target="$bin_dir/mega"

  if [ "$dry_run" -eq 1 ]; then
    echo "would write wrapper: $target -> $install_root/current/dist/index.js"
    return
  fi

  mkdir -p "$bin_dir"
  {
    printf '#!/usr/bin/env sh\n'
    printf 'exec node "%s/current/dist/index.js" "$@"\n' "$install_root"
  } >"$target"
  chmod 0755 "$target"
}

install_skill() {
  dest="$1"

  if [ "$with_skill" -ne 1 ]; then
    return
  fi

  if [ "$dry_run" -eq 1 ]; then
    echo "would install bundled skill for agent target: $skill_agent"
    return
  fi

  if [ ! -f "$dest/scripts/install-skill.sh" ]; then
    warn "release does not include scripts/install-skill.sh; skipping skill install"
    return
  fi

  need bash
  if [ "$force_skill" -eq 1 ]; then
    bash "$dest/scripts/install-skill.sh" --agent "$skill_agent" --force
  else
    bash "$dest/scripts/install-skill.sh" --agent "$skill_agent"
  fi
}

if [ "$dry_run" -ne 1 ]; then
  check_prerequisites
fi

if [ -z "$version" ]; then
  if [ "$dry_run" -eq 1 ]; then
    version="latest"
  else
    info "Resolving latest release for $repo"
    version="$(latest_version)"
  fi
fi

[ -n "$version" ] || error "could not resolve release version"
case "$version" in
  */*|"")
    error "invalid release version: $version"
    ;;
esac

asset="$asset_prefix-$version.tar.gz"
base_url="https://github.com/$repo/releases/download/$version"
archive_url="$base_url/$asset"
checksum_url="$base_url/$asset.sha256"

if [ "$dry_run" -eq 1 ]; then
  echo "would install release: $repo@$version"
  echo "would use asset: $archive_url"
  echo "would use checksum: $checksum_url"
  echo "would install root: $install_root"
  echo "would install wrapper dir: $bin_dir"
  write_wrapper
  remove_legacy_wallet_wrapper
  install_skill "$install_root/releases/$version"
  exit 0
fi

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t mega-wallet-cli)"
trap 'rm -rf "$tmp_dir"' EXIT

archive_path="$tmp_dir/$asset"
checksum_path="$tmp_dir/$asset.sha256"

info "Downloading $asset"
download "$archive_url" "$archive_path"
download "$checksum_url" "$checksum_path"

expected_checksum="$(awk '{print $1}' "$checksum_path" | head -n 1)"
actual_checksum="$(sha256_file "$archive_path")"
[ "$expected_checksum" = "$actual_checksum" ] || error "checksum mismatch for $asset"
info "Checksum verified"

tar -xzf "$archive_path" -C "$tmp_dir"
extracted_dir="$tmp_dir/$asset_prefix-$version"
if [ ! -f "$extracted_dir/dist/index.js" ]; then
  dist_entry="$(find "$tmp_dir" -type f -path '*/dist/index.js' | head -n 1)"
  [ -n "$dist_entry" ] || error "release archive is missing dist/index.js"
  extracted_dir="$(dirname "$(dirname "$dist_entry")")"
fi

release_root="$install_root/releases"
release_dir="$release_root/$version"
staging_dir="$release_root/.tmp-$version-$$"

mkdir -p "$release_root"
rm -rf "$staging_dir"
cp -R "$extracted_dir" "$staging_dir"
rm -rf "$release_dir"
mv "$staging_dir" "$release_dir"

if [ -L "$install_root/current" ] || [ -f "$install_root/current" ]; then
  rm -f "$install_root/current"
elif [ -d "$install_root/current" ]; then
  rm -rf "$install_root/current"
fi
ln -s "$release_dir" "$install_root/current"

write_wrapper
remove_legacy_wallet_wrapper
install_skill "$release_dir"

info "Installed MegaETH MOSS CLI $version"
info "  release: $release_dir"
info "  mega:    $bin_dir/mega"
if ! path_contains "$bin_dir"; then
  warn "add $bin_dir to PATH to run mega moss commands without an absolute path"
fi
