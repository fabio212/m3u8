#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_FILE="${1:-"$ROOT_DIR/channels/kick.txt"}"
OUTPUT_FILE="${2:-"$ROOT_DIR/kick.m3u8"}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "#EXTM3U" > "$OUTPUT_FILE"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Arquivo de canais da Kick não encontrado: $INPUT_FILE" >&2
  exit 0
fi

while IFS= read -r channel || [[ -n "${channel:-}" ]]; do
  channel="$(echo "$channel" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$channel" || "$channel" == \#* ]] && continue

  # Normaliza em URL de canal Kick
  if [[ "$channel" =~ ^https?:// ]]; then
    url="$channel"
    name="${channel##*/}"
  else
    url="https://kick.com/$channel"
    name="$channel"
  fi

  info_json="$(yt-dlp -j "$url" 2>/dev/null || true)"
  [[ -z "$info_json" ]] && continue

  is_live="$(jq -r '.is_live // .live_status // empty' <<<"$info_json")"
  if [[ "$is_live" != "true" && "$is_live" != "is_live" ]]; then
    echo "Canal Kick offline: $channel" >&2
    continue
  fi

  title="$(jq -r '.title // .fulltitle // "Kick live"' <<<"$info_json")"
  m3u8_url="$(yt-dlp -g -f 'best' "$url" 2>/dev/null | head -n1 || true)"
  [[ -z "$m3u8_url" ]] && continue

  echo "#EXTINF:-1 tvg-id=\"kick-$name\" group-title=\"Kick\",$title" >> "$OUTPUT_FILE"
  echo "$m3u8_url" >> "$OUTPUT_FILE"

done < "$INPUT_FILE"
