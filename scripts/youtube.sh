#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_FILE="${1:-"$ROOT_DIR/channels/youtube.txt"}"
OUTPUT_FILE="${2:-"$ROOT_DIR/youtube.m3u8"}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "#EXTM3U" > "$OUTPUT_FILE"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
MAX_JOBS="${YOUTUBE_MAX_WORKERS:-4}"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Arquivo de canais do YouTube nao encontrado: $INPUT_FILE" >&2
  exit 0
fi

COOKIES_FILE="${YT_COOKIES_FILE:-${YOUTUBE_COOKIES_FILE:-}}"

YT_DLP_BASE=(
  yt-dlp
  --progress
  --no-warnings
  --retries 3
  --socket-timeout 15
  --ignore-errors
  --extractor-args "youtube:player_client=android_embedded"
)

if [[ -n "$COOKIES_FILE" && -f "$COOKIES_FILE" ]]; then
  echo "Usando cookies do arquivo $COOKIES_FILE"
  YT_DLP_BASE+=(--cookies "$COOKIES_FILE")
else
  echo "Sem cookies; videos que exigem login podem falhar"
fi

echo "Lendo canais de $INPUT_FILE..."

process_channel() {
  local channel="$1"
  local tmp_file="$2"

  echo "Canal: $channel"

  # Normaliza em URL de canal
  local base_url
  if [[ "$channel" =~ ^https?:// ]]; then
    base_url="$channel"
  elif [[ "$channel" =~ ^@ ]]; then
    base_url="https://www.youtube.com/$channel"
  else
    base_url="https://www.youtube.com/channel/$channel"
  fi

  local playlist_url="${base_url%/}/streams"
  echo "  Buscando lives em $playlist_url"

  mapfile -t video_ids < <(timeout 120s "${YT_DLP_BASE[@]}" --flat-playlist --dump-json --match-filter "live_status=is_live" "$playlist_url" | jq -r 'select(.id != null) | .id' || true)

  if [[ ${#video_ids[@]} -eq 0 ]]; then
    echo "  Nenhuma live encontrada para $channel" >&2
    return
  else
    echo "  Lives encontradas para $channel --> ${#video_ids[@]}"
  fi

  local channel_name
  channel_name="$(timeout 60s "${YT_DLP_BASE[@]}" --dump-json "$base_url" | jq -r '.channel // .uploader // empty' || true)"
  if [[ -z "$channel_name" ]]; then
    channel_name="$channel"
  fi

  {
    echo ""
    echo "# -------- Canal: $channel_name --------"
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

      echo "#EXTINF:-1 tvg-id=\"$channel_name\" group-title=\"YouTube - $channel_name\",$title"
      echo "$m3u8_url"
    done
  } > "$tmp_file"
}

pids=()
job_count=0
channel_idx=0

while IFS= read -r channel || [[ -n "${channel:-}" ]]; do
  channel="$(echo "$channel" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$channel" || "$channel" == \#* ]] && continue

  channel_idx=$((channel_idx + 1))
  tmp_file="$TMP_DIR/${channel_idx}.m3u8"

  process_channel "$channel" "$tmp_file" &
  pids+=("$!")
  job_count=$((job_count + 1))

  if (( job_count >= MAX_JOBS )); then
    wait -n || true
    job_count=$((job_count - 1))
  fi
done < "$INPUT_FILE"

wait || true

for part in "$TMP_DIR"/*.m3u8; do
  [[ -s "$part" ]] && cat "$part" >> "$OUTPUT_FILE"
done
