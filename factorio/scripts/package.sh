#!/usr/bin/env bash
# Builds dist/<name>_<version>.zip with a top-level <name>_<version>/ folder, as Factorio expects.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mod="${1:?usage: package.sh <mod-directory>}"
source="$root/$mod"
if [[ "$mod" == */* || ! -f "$source/info.json" ]]; then
  echo "expected factorio/<mod-directory>/info.json" >&2
  exit 2
fi
name="$(jq -r .name "$source/info.json")"
version="$(jq -r .version "$source/info.json")"
folder="${name}_${version}"
out="$root/dist"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp -R "$source" "$stage/$folder"
mkdir -p "$out"
rm -f "$out/$folder.zip"
(cd "$stage" && zip -rq "$out/$folder.zip" "$folder" -x '*.DS_Store')
echo "$out/$folder.zip"
