#!/usr/bin/env bash
# Скачування відео з Kwiga CDN.
#
# Як користуватись:
#   1. Вставте посилання в самий кінець цього файлу (під рядком # LINKS).
#      Підійде і .m3u8, і сегмент .ts на кшталт seg-2-v1-a1.ts.
#   2. Запустіть:
#        bash download.sh
#
# Можна і без редагування файлу — посилання в кінці команди:
#   bash download.sh "https://media.kwigacdn.com/..../seg-2-v1-a1.ts?timestamp=..."
#
# Готові файли лягають у папку videos/ поруч зі скриптом.
# Якщо з'явиться 403, покладіть cookies.txt (формат Netscape) поруч зі скриптом
# і поставте yt-dlp: pip install -U yt-dlp

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$ROOT/videos"
REF="https://verner.kwiga.com/"
ORIGIN="https://verner.kwiga.com"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

to_playlist() {
  local url="$1"
  local clean="${url%%\?*}"
  clean="${clean%/}"

  if [[ "$clean" == *.m3u8 ]]; then
    printf '%s\n' "$clean"
    return
  fi

  # https://media.kwigacdn.com/.../name_1080p.mp4/seg-2-v1-a1.ts
  # -> https://media.kwigacdn.com/.../name_1080p.mp4.m3u8
  if [[ "$clean" =~ ^(https://media\.kwigacdn\.com/.+\.mp4)/seg-[^/]+\.ts$ ]]; then
    printf '%s.m3u8\n' "${BASH_REMATCH[1]}"
    return
  fi

  # https://ip123.media.kwigacdn.com/.../123.mp4/seg-2-v1-a1.ts
  # -> https://ip123.media.kwigacdn.com/.../123.mp4/index.m3u8
  if [[ "$clean" =~ ^(https://[^/]+\.media\.kwigacdn\.com/.+\.mp4)/seg-[^/]+\.ts$ ]]; then
    printf '%s/index.m3u8\n' "${BASH_REMATCH[1]}"
    return
  fi

  printf '%s\n' "$clean"
}

output_name() {
  local src="$1"
  local playlist="$2"
  local base=""

  if [[ "$src" =~ /([^/?]+)\.mp4/ ]]; then
    base="${BASH_REMATCH[1]}"
  elif [[ "$playlist" =~ /([^/]+)\.mp4\.m3u8$ ]]; then
    base="${BASH_REMATCH[1]}"
  else
    base="$(basename "$playlist" .m3u8)"
  fi

  base="${base//[^A-Za-z0-9._-]/_}"
  printf '%s.mp4\n' "$base"
}

run_ytdlp() {
  local playlist="$1"
  local dest="$2"
  local -a cmd cookie_args=()

  if command -v yt-dlp >/dev/null 2>&1; then
    cmd=(yt-dlp)
  elif python3 -c "import yt_dlp" >/dev/null 2>&1; then
    cmd=(python3 -m yt_dlp)
  else
    return 1
  fi

  if [[ -f "$ROOT/cookies.txt" ]]; then
    cookie_args+=(--cookies "$ROOT/cookies.txt")
  fi

  "${cmd[@]}" \
    --no-playlist \
    --retries 10 \
    --fragment-retries 10 \
    --referer "$REF" \
    --add-header "Origin:${ORIGIN}" \
    --user-agent "$UA" \
    --merge-output-format mp4 \
    "${cookie_args[@]}" \
    -o "$dest" \
    "$playlist"
}

run_ffmpeg() {
  local playlist="$1"
  local dest="$2"
  ffmpeg -y -hide_banner \
    -user_agent "$UA" \
    -headers "Referer: ${REF}"$'\r\n'"Origin: ${ORIGIN}"$'\r\n' \
    -i "$playlist" \
    -map 0:v:0 -map 0:a:0 \
    -c copy -bsf:a aac_adtstoasc \
    "$dest"
}

download_one() {
  local src="$1"
  local playlist dest name

  playlist="$(to_playlist "$src")"
  if [[ "$playlist" != *.m3u8 ]]; then
    echo "Пропускаю, це не m3u8 і не сегмент .ts:"
    echo "  $src"
    return 1
  fi

  name="$(output_name "$src" "$playlist")"
  mkdir -p "$OUT_DIR"
  dest="$OUT_DIR/$name"

  if [[ -e "$dest" ]]; then
    echo "Вже скачано, пропускаю: $dest"
    return 0
  fi

  echo "Джерело:  $src"
  echo "Плейлист: $playlist"
  echo "Файл:     $dest"

  if ! run_ytdlp "$playlist" "$dest"; then
    if [[ -f "$ROOT/cookies.txt" ]]; then
      echo "Для cookies.txt потрібен yt-dlp. Ставлю..."
      python3 -m pip install -U yt-dlp
      run_ytdlp "$playlist" "$dest"
    else
      run_ffmpeg "$playlist" "$dest"
    fi
  fi

  echo "Готово: $dest"
}

collect_links() {
  local line
  if [[ "$#" -gt 0 ]]; then
    printf '%s\n' "$@"
  fi
  awk 'BEGIN{p=0} /^# LINKS[[:space:]]*$/{p=1; next} p{print}' "$ROOT/download.sh" \
    | while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        printf '%s\n' "$line"
      done
}

mapfile -t LINKS < <(collect_links "$@")

if [[ "${#LINKS[@]}" -eq 0 ]]; then
  echo "Немає посилань."
  echo "Вставте URL у кінець файлу download.sh під рядком # LINKS і знову запустіть:"
  echo "  bash download.sh"
  echo "Або передайте посилання аргументом:"
  echo "  bash download.sh \"https://media.kwigacdn.com/...\""
  exit 1
fi

failed=0
for link in "${LINKS[@]}"; do
  download_one "$link" || failed=1
  echo
done

exit "$failed"

# LINKS
# Вставляйте нові посилання нижче, по одному на рядок.
# Рядки з # ігноруються. Приклад сегмента 1080p:
# https://media.kwigacdn.com/key=YQ2dz-s9b34Ox91hUmaMGQ,end=1792437084/media=hlsA/cabinet-6056/h9sSI1SPNKKf/anticeliulitnii_kompleks_1080p.mp4/seg-2-v1-a1.ts?timestamp=1791833838892
