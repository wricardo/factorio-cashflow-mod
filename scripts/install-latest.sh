#!/usr/bin/env bash
# Usage: curl -fsSL https://raw.githubusercontent.com/wricardo/factorio-cashflow-mod/main/scripts/install-latest.sh | bash
set -euo pipefail

repo="wricardo/factorio-cashflow-mod"
mods_dir="${FACTORIO_MODS_DIR:-$HOME/Library/Application Support/factorio/mods}"
api="https://api.github.com/repos/$repo/releases/latest"

for command in curl unzip; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

release="$(curl -fsSL "$api")"
asset_url="$(printf '%s' "$release" | tr ',' '\n' | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*cashflow-freeplay_[^"]*\.zip\)".*/\1/p' | head -n 1)"
[[ -n "$asset_url" ]] || {
  echo "The latest release has no Cashflow zip asset." >&2
  exit 1
}

archive="$(mktemp -t cashflow-freeplay.XXXXXX.zip)"
trap 'rm -f "$archive"' EXIT
curl -fsSL "$asset_url" -o "$archive"

root="$(unzip -Z1 "$archive" | sed -n '1{s|/.*||;p;}')"
[[ "$root" == cashflow-freeplay_* ]] && unzip -Z1 "$archive" | grep -qx "$root/info.json" || {
  echo "Downloaded release is not a valid Cashflow mod archive." >&2
  exit 1
}

mkdir -p "$mods_dir"
find "$mods_dir" -maxdepth 1 -type f -name 'cashflow-freeplay_*.zip' -delete
cp "$archive" "$mods_dir/${root}.zip"
printf 'Installed %s in %s\nEnable Cashflow in Factorio’s Mods menu, then restart the game.\n' "$root" "$mods_dir"
