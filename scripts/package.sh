#!/usr/bin/env bash
# Builds dist/<name>_<version>.zip with a top-level <name>_<version>/ folder, as Factorio expects.
# Only the files the game loads are packaged; tests, scripts, and docs stay out of the zip.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$root/info.json" ]] || { echo "expected $root/info.json" >&2; exit 2; }
name="$(jq -r .name "$root/info.json")"
version="$(jq -r .version "$root/info.json")"
folder="${name}_${version}"
out="$root/dist"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir "$stage/$folder"
for item in info.json changelog.txt thumbnail.png control.lua data.lua settings.lua locale migrations script graphics THIRD_PARTY_LICENSES.md; do
  [[ -e "$root/$item" ]] && cp -R "$root/$item" "$stage/$folder/"
done
mkdir -p "$out"
rm -f "$out/$folder.zip"
(cd "$stage" && zip -rq "$out/$folder.zip" "$folder" -x '*.DS_Store')
echo "$out/$folder.zip"
