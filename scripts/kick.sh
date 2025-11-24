#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_FILE="${1:-"$ROOT_DIR/channels/kick.txt"}"
OUTPUT_FILE="${2:-"$ROOT_DIR/kick.m3u8"}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "#EXTM3U" > "$OUTPUT_FILE"
TMP_DIR="$(mktemp -d)"
MAX_JOBS="${KICK_MAX_WORKERS:-4}"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Arquivo de canais da Kick nao encontrado: $INPUT_FILE" >&2
  exit 0
fi

process_channel() {
  local channel="$1"
  local tmp_file="$2"

  echo "Canal Kick: $channel"

  # Normaliza em URL de canal Kick
  local url name
  if [[ "$channel" =~ ^https?:// ]]; then
    url="$channel"
    name="${channel##*/}"
  else
    url="https://kick.com/$channel"
    name="$channel"
  fi

  info_json="$(timeout 60s yt-dlp -j "$url" 2>/dev/null || true)"
  [[ -z "$info_json" ]] && return

  is_live="$(jq -r '.is_live // .live_status // empty' <<<"$info_json")"
  if [[ "$is_live" != "true" && "$is_live" != "is_live" ]]; then
    echo "  Offline: $channel" >&2
    return
  fi

  title="$(jq -r '.title // .fulltitle // "Kick live"' <<<"$info_json")"
  m3u8_url="$(timeout 60s yt-dlp -g -f 'best' "$url" 2>/dev/null | head -n1 || true)"
  [[ -z "$m3u8_url" ]] && return

  {
    echo "#EXTINF:-1 tvg-id=\"kick-$name\" group-title=\"Kick\",$title"
    echo "$m3u8_url"
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
    wait -n
    job_count=$((job_count - 1))
  fi
done < "$INPUT_FILE"

wait

for part in "$TMP_DIR"/*.m3u8; do
  [[ -s "$part" ]] && cat "$part" >> "$OUTPUT_FILE"
done
