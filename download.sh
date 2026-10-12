#!/usr/bin/env bash
# Скачування відео з Kwiga CDN.
#
# Як користуватись:
#   1. Вставте посилання в самий кінець цього файлу (під рядком # LINKS).
#      Назву пишіть у наступних лапках. Без лапок ім'я береться з посилання.
#        https://..../seg-1-v1-a1.ts "Антицелюлітний комплекс"
#        https://..../next.m3u8 "Урок 2"
#   2. Запустіть:
#        bash download.sh
#
# Файли отримують номер за порядком рядків:
#   videos/01 - Антицелюлітний комплекс.mp4
#   videos/02 - Урок 2.mp4
#
# Те саме з командного рядка — посилання, потім назва в лапках:
#   bash download.sh "https://media.kwigacdn.com/..../seg-1-v1-a1.ts" "Антицелюлітний комплекс"
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

auto_stem() {
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

  sanitize_title "$base"
}

sanitize_title() {
  local t="$1"
  t="${t//$'\r'/}"
  t="${t//$'\n'/ }"
  t="${t//\// - }"
  t="${t//\\/ - }"
  t="${t//:/ -}"
  t="${t//\*/}"
  t="${t//\?/}"
  t="${t//\"/}"
  t="${t//\'/}"
  t="${t//</}"
  t="${t//>/}"
  t="${t//|/ - }"
  while [[ "$t" == *"  "* ]]; do
    t="${t//  / }"
  done
  t="${t#"${t%%[![:space:].]*}"}"
  t="${t%"${t##*[![:space:].]}"}"
  printf '%s\n' "$t"
}

file_name() {
  local src="$1"
  local playlist="$2"
  local number="$3"
  local title="$4"
  local label=""

  if [[ -n "$title" ]]; then
    label="$(sanitize_title "$title")"
  fi
  if [[ -z "$label" ]]; then
    label="$(auto_stem "$src" "$playlist")"
  fi
  if [[ -z "$label" ]]; then
    label="video"
  fi

  printf '%s - %s.mp4\n' "$number" "$label"
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
  local number="$2"
  local title="${3:-}"
  local playlist dest name

  playlist="$(to_playlist "$src")"
  if [[ "$playlist" != *.m3u8 ]]; then
    echo "Пропускаю, це не m3u8 і не сегмент .ts:"
    echo "  $src"
    return 1
  fi

  name="$(file_name "$src" "$playlist" "$number" "$title")"
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

URLS=()
TITLES=()

add_entry() {
  local url="$1"
  local title="${2:-}"
  url="${url#"${url%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"
  [[ -z "$url" || "$url" == \#* ]] && return 0
  URLS+=("$url")
  TITLES+=("$title")
}

split_line() {
  local line="$1"
  local url rest title
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" || "$line" == \#* ]] && return 0

  url="${line%%[[:space:]]*}"
  title=""
  if [[ "$line" != "$url" ]]; then
    rest="${line#"$url"}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    rest="${rest%"${rest##*[![:space:]]}"}"
    if [[ ${#rest} -ge 2 && ( "$rest" == \"*\" || "$rest" == \'*\' ) ]]; then
      title="${rest:1:$((${#rest} - 2))}"
    else
      title="$rest"
    fi
  fi
  add_entry "$url" "$title"
}

args=("$@")
i=0
while (( i < ${#args[@]} )); do
  url="${args[$i]}"
  title=""
  next=$((i + 1))
  if (( next < ${#args[@]} )); then
    nxt="${args[$next]}"
    if [[ "$nxt" != http://* && "$nxt" != https://* ]]; then
      title="$nxt"
      i=$next
    fi
  fi
  add_entry "$url" "$title"
  i=$((i + 1))
done

while IFS= read -r line || [[ -n "$line" ]]; do
  split_line "$line"
done < <(awk 'BEGIN{p=0} /^# LINKS[[:space:]]*$/{p=1; next} p{print}' "$ROOT/download.sh")

if [[ "${#URLS[@]}" -eq 0 ]]; then
  echo "Немає посилань."
  echo "Вставте URL у кінець файлу download.sh під рядком # LINKS."
  echo "Назву додайте в наступних лапках:"
  echo "  https://media.kwigacdn.com/.../seg-1-v1-a1.ts \"Назва уроку\""
  echo "І запустіть:"
  echo "  bash download.sh"
  exit 1
fi

width=2
if (( ${#URLS[@]} > 99 )); then
  width=3
fi

failed=0
for (( i = 0; i < ${#URLS[@]}; i++ )); do
  printf -v number "%0${width}d" "$((i + 1))"
  download_one "${URLS[$i]}" "$number" "${TITLES[$i]}" || failed=1
  echo
done

exit "$failed"

# LINKS
# Вставляйте нові посилання нижче, по одному на рядок.
# Назва — у наступних лапках. Рядки з # ігноруються.
# Номер файлу — це порядок рядка: 01, 02, 03...
# https://media.kwigacdn.com/key=YQ2dz-s9b34Ox91hUmaMGQ,end=1792437084/media=hlsA/cabinet-6056/h9sSI1SPNKKf/anticeliulitnii_kompleks_1080p.mp4/seg-2-v1-a1.ts?timestamp=1791833838892 "Антицелюлітний комплекс"
