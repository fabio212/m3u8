#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_FILE="${1:-"$ROOT_DIR/channels/twitch.txt"}"
OUTPUT_FILE="${2:-"$ROOT_DIR/twitch.m3u8"}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "#EXTM3U" > "$OUTPUT_FILE"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Arquivo de canais da Twitch não encontrado: $INPUT_FILE" >&2
  exit 0
fi

BASE_URL="https://as.luminous.dev/live"

while IFS= read -r channel || [[ -n "${channel:-}" ]]; do
  channel="$(echo "$channel" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$channel" || "$channel" == \#* ]] && continue

  name="$channel"
  m3u8_url="$BASE_URL/${name}?allow_source=true&allow_audio_only=false&fast_bread=true"

  echo "#EXTINF:-1 tvg-id=\"twitch-$name\" group-title=\"Twitch\",Twitch: $name" >> "$OUTPUT_FILE"
  echo "$m3u8_url" >> "$OUTPUT_FILE"

done < "$INPUT_FILE"
