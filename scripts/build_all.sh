#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="${1:-"$ROOT_DIR/all.m3u8"}"

echo "#EXTM3U" > "$OUTPUT_FILE"

for file in "$ROOT_DIR/youtube.m3u8" "$ROOT_DIR/kick.m3u8" "$ROOT_DIR/twitch.m3u8"; do
  if [[ -f "$file" ]]; then
    # pula a primeira linha (#EXTM3U)
    tail -n +2 "$file" >> "$OUTPUT_FILE"
  fi
Done
