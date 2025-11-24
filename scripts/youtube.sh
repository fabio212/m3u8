#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_FILE="${1:-"$ROOT_DIR/channels/youtube.txt"}"
OUTPUT_FILE="${2:-"$ROOT_DIR/youtube.m3u8"}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "#EXTM3U" > "$OUTPUT_FILE"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Arquivo de canais do YouTube nao encontrado: $INPUT_FILE" >&2
  exit 0
fi

YT_DLP_BASE=(yt-dlp --progress --no-warnings --retries 3 --socket-timeout 15 --ignore-errors --extractor-args "youtube:player_client=android_embedded")

echo "Lendo canais de $INPUT_FILE..."

while IFS= read -r channel || [[ -n "${channel:-}" ]]; do
  channel="$(echo "$channel" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$channel" || "$channel" == \#* ]] && continue

  echo "Canal: $channel"

  # Normaliza em URL de canal
  if [[ "$channel" =~ ^https?:// ]]; then
    base_url="$channel"
  elif [[ "$channel" =~ ^@ ]]; then
    base_url="https://www.youtube.com/$channel"
  else
    base_url="https://www.youtube.com/channel/$channel"
  fi

  playlist_url="${base_url%/}/streams"
  echo "  Buscando lives em $playlist_url"

  mapfile -t video_ids < <(timeout 120s "${YT_DLP_BASE[@]}" --flat-playlist --dump-json "$playlist_url" | jq -r 'select(.id != null) | .id' || true)

  if [[ ${#video_ids[@]} -eq 0 ]]; then
    echo "  Nenhuma live encontrada para $channel" >&2
    continue
  else
    echo "  Lives encontradas: ${#video_ids[@]}"
  fi

  channel_name="$(timeout 60s "${YT_DLP_BASE[@]}" --dump-json "$base_url" | jq -r '.channel // .uploader // empty' || true)"
  if [[ -z "$channel_name" ]]; then
    channel_name="$channel"
  fi

  echo "" >> "$OUTPUT_FILE"
  echo "# -------- Canal: $channel_name --------" >> "$OUTPUT_FILE"

  for vid in "${video_ids[@]}"; do
    info_json="$(timeout 120s "${YT_DLP_BASE[@]}" -j "https://www.youtube.com/watch?v=${vid}" || true)"
    [[ -z "$info_json" ]] && continue

    live_status="$(jq -r '.live_status // empty' <<<"$info_json")"
    if [[ "$live_status" != "is_live" ]]; then
      continue
    fi

    title="$(jq -r '.title' <<<"$info_json")"

    m3u8_url="$(timeout 120s "${YT_DLP_BASE[@]}" -g -f 'best' "https://www.youtube.com/watch?v=${vid}" | head -n1 || true)"
    [[ -z "$m3u8_url" ]] && continue

    echo "#EXTINF:-1 tvg-id=\"$channel_name\" group-title=\"YouTube - $channel_name\",$title" >> "$OUTPUT_FILE"
    echo "$m3u8_url" >> "$OUTPUT_FILE"
  done

done < "$INPUT_FILE"
