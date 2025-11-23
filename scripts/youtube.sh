#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_FILE="${1:-"$ROOT_DIR/channels/youtube.txt"}"
OUTPUT_FILE="${2:-"$ROOT_DIR/youtube.m3u8"}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "#EXTM3U" > "$OUTPUT_FILE"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Arquivo de canais do YouTube não encontrado: $INPUT_FILE" >&2
  exit 0
fi

while IFS= read -r channel || [[ -n "${channel:-}" ]]; do
  channel="$(echo "$channel" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$channel" || "$channel" == \#* ]] && continue

  # Normaliza em URL de canal
  if [[ "$channel" =~ ^https?:// ]]; then
    base_url="$channel"
  elif [[ "$channel" =~ ^@ ]]; then
    base_url="https://www.youtube.com/$channel"
  else
    base_url="https://www.youtube.com/channel/$channel"
  fi

  playlist_url="${base_url%/}/streams"

  # Lista vídeos da aba "streams" do canal
  mapfile -t video_ids < <(yt-dlp --flat-playlist --dump-json "$playlist_url" 2>/dev/null | jq -r 'select(.id != null) | .id' || true)

  if [[ ${#video_ids[@]} -eq 0 ]]; then
    echo "Nenhuma live encontrada para $channel" >&2
    continue
  fi

  # Nome amigável do canal
  channel_name="$(yt-dlp --dump-json "$base_url" 2>/dev/null | jq -r '.channel // .uploader // empty' || true)"
  if [[ -z "$channel_name" ]]; then
    channel_name="$channel"
  fi

  echo "" >> "$OUTPUT_FILE"
  echo "# -------- Canal: $channel_name --------" >> "$OUTPUT_FILE"

  for vid in "${video_ids[@]}"; do
    info_json="$(yt-dlp -j "https://www.youtube.com/watch?v=${vid}" 2>/dev/null || true)"
    [[ -z "$info_json" ]] && continue

    live_status="$(jq -r '.live_status // empty' <<<"$info_json")"
    if [[ "$live_status" != "is_live" ]]; then
      # Ignora VODs / estreias / agendados
      continue
    fi

    title="$(jq -r '.title' <<<"$info_json")"

    # Pega a melhor URL (normalmente um .m3u8 para lives)
    m3u8_url="$(yt-dlp -g -f 'best' "https://www.youtube.com/watch?v=${vid}" 2>/dev/null | head -n1 || true)"
    [[ -z "$m3u8_url" ]] && continue

    echo "#EXTINF:-1 tvg-id=\"$channel_name\" group-title=\"YouTube - $channel_name\",$title" >> "$OUTPUT_FILE"
    echo "$m3u8_url" >> "$OUTPUT_FILE"
  done

done < "$INPUT_FILE"
