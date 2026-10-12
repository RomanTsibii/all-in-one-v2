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
# Номер береться з папки videos, а не з нуля на кожен запуск:
#   вже є 01, 02, 03 — наступний файл буде 04.
#   якщо кілька файлів випадково мають один номер, вони
#   перенумеровуються за часом: старіший лишається меншим номером.
#
# Те саме з командного рядка — посилання, потім назва в лапках:
#   bash download.sh "https://media.kwigacdn.com/..../seg-1-v1-a1.ts" "Антицелюлітний комплекс"
#
# Рядки з консолі браузера теж підходять (їх друкує track-videos.js):
#   download "https://media.kwigacdn.com/..../video.m3u8"
#
# Після скачування файл перепаковується у звичайний MP4 (faststart),
# щоб Telegram відкривав його як відео, а не як документ.
# Для цього потрібен ffmpeg: sudo apt install ffmpeg
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

video_label() {
  local src="$1"
  local playlist="$2"
  local title="${3:-}"
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

  printf '%s\n' "$label"
}

label_of() {
  local base="${1%.mp4}"
  if [[ "$base" =~ ^[0-9]+[[:space:]]+-[[:space:]](.+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi
  printf '%s\n' "$base"
}

number_of() {
  local base="$1"
  if [[ "$base" =~ ^([0-9]+)[[:space:]]+-[[:space:]] ]]; then
    printf '%s\n' "$((10#${BASH_REMATCH[1]}))"
    return
  fi
  printf '0\n'
}

format_number() {
  local n="$1"
  if (( n > 99 )); then
    printf '%d\n' "$n"
  else
    printf '%02d\n' "$n"
  fi
}

find_by_label() {
  local want="$1"
  local f base
  local restore=0
  shopt -q nullglob || restore=1
  shopt -s nullglob
  for f in "$OUT_DIR"/*.mp4; do
    base="$(basename "$f")"
    [[ "$base" == .* ]] && continue
    if [[ "$(label_of "$base")" == "$want" ]]; then
      printf '%s\n' "$f"
      (( restore == 1 )) && shopt -u nullglob
      return 0
    fi
  done
  (( restore == 1 )) && shopt -u nullglob
  return 1
}

next_serial() {
  local max=0 count=0 f base num
  local restore=0
  shopt -q nullglob || restore=1
  shopt -s nullglob
  for f in "$OUT_DIR"/*.mp4; do
    base="$(basename "$f")"
    [[ "$base" == .* ]] && continue
    count=$((count + 1))
    num="$(number_of "$base")"
    (( num > max )) && max=$num
  done
  (( restore == 1 )) && shopt -u nullglob
  if (( count > max )); then
    printf '%s\n' "$((count + 1))"
  else
    printf '%s\n' "$((max + 1))"
  fi
}

renumber_existing() {
  mkdir -p "$OUT_DIR"
  local -a files=()
  local restore=0
  shopt -q nullglob || restore=1
  shopt -s nullglob
  local f
  for f in "$OUT_DIR"/*.mp4; do
    [[ "$(basename "$f")" == .* ]] && continue
    files+=("$f")
  done
  (( restore == 1 )) && shopt -u nullglob
  (( ${#files[@]} == 0 )) && return 0

  local -A seen=()
  local dup=0 num
  for f in "${files[@]}"; do
    num="$(number_of "$(basename "$f")")"
    if [[ -n "${seen[$num]+x}" ]]; then
      dup=1
      break
    fi
    seen[$num]=1
  done
  (( dup == 0 )) && return 0

  local -a ordered=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && ordered+=("${line#*|}")
  done < <(
    for f in "${files[@]}"; do
      stat -c '%Y|%n' "$f"
    done | sort -n
  )

  local -a labels=() oldnames=() temps=()
  local i=0 tmp
  for f in "${ordered[@]}"; do
    oldnames+=("$(basename "$f")")
    labels+=("$(label_of "$(basename "$f")")")
    tmp="$OUT_DIR/.renumber-$(printf '%04d' "$i").mp4"
    mv -- "$f" "$tmp"
    temps+=("$tmp")
    i=$((i + 1))
  done

  local n=1 dest label
  for i in "${!temps[@]}"; do
    label="${labels[$i]}"
    dest="$OUT_DIR/$(format_number "$n") - ${label}.mp4"
    if [[ -e "$dest" ]]; then
      dest="$OUT_DIR/$(format_number "$n") - ${label}_$n.mp4"
    fi
    mv -- "${temps[$i]}" "$dest"
    if [[ "${oldnames[$i]}" != "$(basename "$dest")" ]]; then
      echo "Перенумеровую: ${oldnames[$i]} -> $(basename "$dest")"
    fi
    n=$((n + 1))
  done
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

  local -a ffmpeg_args=()
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg_args+=(--hls-prefer-ffmpeg --remux-video mp4)
  fi

  "${cmd[@]}" \
    --no-playlist \
    --retries 10 \
    --fragment-retries 10 \
    --referer "$REF" \
    --add-header "Origin:${ORIGIN}" \
    --user-agent "$UA" \
    --merge-output-format mp4 \
    "${ffmpeg_args[@]}" \
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
    -movflags +faststart \
    "$dest"
}

is_playable_mp4() {
  local f="$1"
  local kind
  command -v ffprobe >/dev/null 2>&1 || return 1
  kind="$(ffprobe -v error -show_entries format=format_name -of default=nw=1:nk=1 "$f" 2>/dev/null || true)"
  [[ "$kind" == *mp4* || "$kind" == *mov* ]] || return 1
  head -c 2097152 "$f" | grep -a -q moov
}

to_telegram_mp4() {
  local src="$1"
  local tmp
  [[ -f "$src" ]] || return 0
  if ! command -v ffmpeg >/dev/null 2>&1; then
    if (( FFMPEG_WARNED == 0 )); then
      FFMPEG_WARNED=1
      echo "Telegram покаже це як файл, поки немає ffmpeg."
      echo "Поставте його і запустіть скрипт ще раз: sudo apt install ffmpeg"
    fi
    return 0
  fi
  if is_playable_mp4 "$src"; then
    return 0
  fi

  echo "Пакую для Telegram: $(basename "$src")"
  tmp="${src}.telegram.mp4"
  if ! ffmpeg -y -hide_banner -loglevel error \
      -i "$src" \
      -map 0:v:0 -map "0:a:0?" \
      -c copy -bsf:a aac_adtstoasc \
      -movflags +faststart \
      "$tmp"; then
    rm -f "$tmp"
    if ! ffmpeg -y -hide_banner -loglevel error \
        -i "$src" \
        -map 0:v:0 -map "0:a:0?" \
        -c copy \
        -movflags +faststart \
        "$tmp"; then
      rm -f "$tmp"
      echo "Не вдалося перепакувати: $(basename "$src")"
      return 1
    fi
  fi
  mv -f -- "$tmp" "$src"
}

fix_existing_videos() {
  local f
  local restore=0
  mkdir -p "$OUT_DIR"
  shopt -q nullglob || restore=1
  shopt -s nullglob
  for f in "$OUT_DIR"/*.mp4; do
    [[ "$(basename "$f")" == .* ]] && continue
    to_telegram_mp4 "$f" || true
  done
  (( restore == 1 )) && shopt -u nullglob
  return 0
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

  local label existing
  label="$(video_label "$src" "$playlist" "$title")"
  mkdir -p "$OUT_DIR"
  if existing="$(find_by_label "$label")"; then
    echo "Вже скачано, пропускаю: $existing"
    return 2
  fi

  name="$(format_number "$number") - ${label}.mp4"
  dest="$OUT_DIR/$name"

  if [[ -e "$dest" ]]; then
    echo "Вже скачано, пропускаю: $dest"
    return 2
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

  to_telegram_mp4 "$dest" || true
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

  if [[ "$line" =~ ^download[[:space:]]+\"([^\"]+)\"([[:space:]]+\"([^\"]*)\")?[[:space:]]*$ ]]; then
    add_entry "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]:-}"
    return 0
  fi

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

FFMPEG_WARNED=0
renumber_existing
fix_existing_videos
serial="$(next_serial)"

failed=0
for (( i = 0; i < ${#URLS[@]}; i++ )); do
  status=0
  download_one "${URLS[$i]}" "$serial" "${TITLES[$i]}" || status=$?
  if (( status == 0 )); then
    serial=$((serial + 1))
  elif (( status != 2 )); then
    failed=1
  fi
  echo
done

exit "$failed"

# LINKS
# Вставляйте нові посилання нижче, по одному на рядок.
# Назва — у наступних лапках. Рядки з # ігноруються.
# Номер файлу продовжує вже існуючі відео в папці videos.
# Можна вставити рядок з консолі браузера як є:
# download "https://media.kwigacdn.com/key=YQ2dz-s9b34Ox91hUmaMGQ,end=1792437084/media=hlsA/cabinet-6056/h9sSI1SPNKKf/anticeliulitnii_kompleks_1080p.mp4.m3u8"
# Або посилання і назву в лапках:
# https://media.kwigacdn.com/.../seg-2-v1-a1.ts "Антицелюлітний комплекс"
