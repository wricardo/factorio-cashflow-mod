#!/usr/bin/env bash
# Builds the working tree and installs it for local Factorio manual testing on macOS.
# Usage: npm run install:local
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mods_dir="${FACTORIO_MODS_DIR:-$HOME/Library/Application Support/factorio/mods}"
name="$(jq -r .name "$root/info.json")"
version="$(jq -r .version "$root/info.json")"
archive="$root/dist/${name}_${version}.zip"
mod_list="$mods_dir/mod-list.json"

bash "$root/scripts/package.sh"
[[ -f "$archive" ]] || {
  echo "Package did not produce $archive" >&2
  exit 1
}

mkdir -p "$mods_dir"
if [[ -f "$mod_list" ]]; then
  updated_mod_list="$(mktemp "$mods_dir/mod-list.json.XXXXXX")"
  trap 'rm -f "$updated_mod_list"' EXIT
  jq --arg name "$name" '
    if any((.mods // [])[]; .name == $name) then
      .mods |= map(if .name == $name then .enabled = true else . end)
    else
      .mods = (.mods // []) + [{ name: $name, enabled: true }]
    end
  ' "$mod_list" > "$updated_mod_list"
  mv "$updated_mod_list" "$mod_list"
else
  printf '{"mods":[{"name":"%s","enabled":true}]}\n' "$name" > "$mod_list"
fi

find "$mods_dir" -maxdepth 1 -type f -name "${name}_*.zip" -delete
cp "$archive" "$mods_dir/${name}_${version}.zip"
printf 'Built and installed %s_%s in %s\n' "$name" "$version" "$mods_dir"
