#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_FILE="${1:-"$ROOT_DIR/channels/twitch.txt"}"
OUTPUT_FILE="${2:-"$ROOT_DIR/twitch.m3u8"}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "#EXTM3U" > "$OUTPUT_FILE"
TMP_DIR="$(mktemp -d)"
MAX_JOBS="${TWITCH_MAX_WORKERS:-6}"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Arquivo de canais da Twitch nao encontrado: $INPUT_FILE" >&2
  exit 0
fi

BASE_URL="https://as.luminous.dev/live"

process_channel() {
  local channel="$1"
  local tmp_file="$2"

  echo "Canal Twitch: $channel"

  local name="$channel"
  local m3u8_url="$BASE_URL/${name}?allow_source=true&allow_audio_only=false&fast_bread=true"

  {
    echo "#EXTINF:-1 tvg-id=\"twitch-$name\" group-title=\"Twitch\",Twitch: $name"
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
