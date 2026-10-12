#!/usr/bin/env bash
# Робить копії для Telegram у папці video_play поруч із videos.
# Оригінали в videos/ не чіпає. Повну назву файлу зберігає.
# Повторний запуск пропускає те, що вже лежить у video_play.
#
# Запуск з папки, де є videos/:
#   bash video_play.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/videos"
DEST="$ROOT/video_play"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Потрібен ffmpeg: sudo apt install ffmpeg"
  exit 1
fi

if [[ ! -d "$SRC" ]]; then
  echo "Немає папки з відео: $SRC"
  exit 1
fi

if [[ -d "$DEST" ]]; then
  echo "Папка вже є: $DEST"
else
  mkdir -p "$DEST"
  echo "Створив папку: $DEST"
fi

shopt -s nullglob
files=("$SRC"/*.mp4)
shopt -u nullglob

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "У $SRC немає mp4."
  exit 0
fi

packed=0
skipped=0
failed=0

for src in "${files[@]}"; do
  name="$(basename "$src")"
  [[ "$name" == .* ]] && continue
  out="$DEST/$name"

  if [[ -s "$out" ]]; then
    echo "Вже є, пропускаю: $name"
    skipped=$((skipped + 1))
    continue
  fi

  echo "Пакую: $name"
  tmp="$DEST/.part.${name}"
  rm -f "$tmp"

  if ! ffmpeg -y -hide_banner -loglevel error \
      -i "$src" \
      -map 0:v:0 -map 0:a:0 \
      -c copy -bsf:a aac_adtstoasc \
      -movflags +faststart \
      "$tmp"; then
    rm -f "$tmp"
    if ! ffmpeg -y -hide_banner -loglevel error \
        -i "$src" \
        -map 0:v:0 -map 0:a:0 \
        -c copy \
        -movflags +faststart \
        "$tmp"; then
      rm -f "$tmp"
      echo "Не вдалося: $name"
      failed=$((failed + 1))
      continue
    fi
  fi

  mv -f -- "$tmp" "$out"
  packed=$((packed + 1))
  echo "Готово: $out"
done

echo "Нових: $packed, вже були: $skipped, помилок: $failed"
exit "$failed"
