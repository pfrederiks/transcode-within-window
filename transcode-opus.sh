#!/usr/bin/env bash
#
# transcode-av1.sh
# Recursively transcodes mp4/wmv/avi files to AV1 (SVT-AV1) + Opus in MKV.
# Skips files that are:
#   - already HEVC or AV1
#   - below MIN_BITRATE_KBPS (not worth re-encoding)
# Probing happens lazily, per file, just before encoding.
# Only runs between START_HOUR:START_MIN and END_HOUR:END_MIN local time.
# Resumes across days until all matching files are converted.

set -uo pipefail

# ---------- Configuration ----------
SOURCE_DIR="${1:-.}"
START_HOUR=10
START_MIN=30
END_HOUR=16
END_MIN=0

CRF=30
PRESET=6
AUDIO_BITRATE="128k"
MIN_BITRATE_KBPS=1500
LOG_FILE="${SOURCE_DIR%/}/transcode.log"
DELETE_ORIGINAL=false
# -----------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

get_video_codec() {
    ffprobe -v error -select_streams v:0 \
        -show_entries stream=codec_name \
        -of default=nokey=1:noprint_wrappers=1 \
        "$1" 2>/dev/null
}

get_video_bitrate_kbps() {
    local input="$1"
    local br
    br=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=bit_rate \
        -of default=nokey=1:noprint_wrappers=1 \
        "$input" 2>/dev/null)

    if [[ -n "$br" && "$br" != "N/A" && "$br" -gt 0 ]] 2>/dev/null; then
        echo $(( br / 1000 ))
        return
    fi

    local duration size
    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=nokey=1:noprint_wrappers=1 "$input" 2>/dev/null)
    size=$(stat -c%s "$input" 2>/dev/null)

    if [[ -n "$duration" && -n "$size" ]]; then
        awk -v s="$size" -v d="$duration" \
            'BEGIN { if (d > 0) printf "%d\n", (s * 8 / d) / 1000; else print 0 }'
    else
        echo 0
    fi
}

in_window() {
    local now_h now_m now_total start_total end_total
    now_h=$(date +%H)
    now_m=$(date +%M)
    now_total=$((10#$now_h * 60 + 10#$now_m))
    start_total=$((START_HOUR * 60 + START_MIN))
    end_total=$((END_HOUR * 60 + END_MIN))
    [[ $now_total -ge $start_total && $now_total -lt $end_total ]]
}

sleep_until_window() {
    local target_epoch now_epoch
    now_epoch=$(date +%s)
    target_epoch=$(date -d "today ${START_HOUR}:$(printf '%02d' $START_MIN)" +%s)
    if (( now_epoch >= target_epoch )); then
        target_epoch=$(date -d "tomorrow ${START_HOUR}:$(printf '%02d' $START_MIN)" +%s)
    fi
    local secs=$(( target_epoch - now_epoch ))
    log "Outside window. Sleeping ${secs}s until $(date -d "@$target_epoch")."
    sleep "$secs"
}

# Probe + skip-decision + encode for one file.
# Returns:
#   0 = handled (encoded or deliberately skipped)
#   1 = encode failed
#   2 = aborted because window closed
process_file() {
    local input="$1"
    local dir base output tmp
    dir=$(dirname "$input")
    base=$(basename "$input")
    output="${dir}/${base%.*}.mkv"
    tmp="${output}.part.mkv"

    if [[ -f "$output" && "$input" != "$output" ]]; then
        log "SKIP (output exists): $output"
        return 0
    fi

    # ---- lazy probe ----
    local codec
    codec=$(get_video_codec "$input")
    case "$codec" in
        hevc|h265) log "SKIP (already HEVC): $input"; return 0 ;;
        av1)       log "SKIP (already AV1): $input";  return 0 ;;
        "")        log "SKIP (unreadable): $input";   return 0 ;;
    esac

    local bitrate
    bitrate=$(get_video_bitrate_kbps "$input")
    if (( bitrate > 0 && bitrate < MIN_BITRATE_KBPS )); then
        log "SKIP (low bitrate ${bitrate}kbps < ${MIN_BITRATE_KBPS}kbps): $input"
        return 0
    fi

    # Re-check the window right before kicking off a long encode
    if ! in_window; then
        return 2
    fi

    log "START: $input  (codec=$codec, ~${bitrate}kbps)"
    ffmpeg -hide_banner -loglevel error -stats -nostdin -y \
        -i "$input" \
        -map 0 -map -0:d \
        -c:v libsvtav1 -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p10le \
        -c:a libopus -b:a "$AUDIO_BITRATE" \
        -c:s copy \
        "$tmp" &
    local pid=$!

    # Monitor the encode and abort cleanly if window closes
    while kill -0 "$pid" 2>/dev/null; do
        if ! in_window; then
            log "Window closed mid-encode. Stopping ffmpeg."
            kill -INT "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            rm -f -- "$tmp"
            return 2
        fi
        sleep 30
    done
    wait "$pid"
    local rc=$?

    if [[ $rc -eq 0 && -s "$tmp" ]]; then
        mv "$tmp" "$output"
        log "DONE: $output"
        if $DELETE_ORIGINAL && [[ "$input" != "$output" ]]; then
            rm -f -- "$input"
            log "REMOVED original: $input"
        fi
        return 0
    else
        log "FAIL ($rc): $input"
        rm -f -- "$tmp"
        return 1
    fi
}

# ---------- Main loop ----------
command -v ffmpeg  >/dev/null || { echo "ffmpeg not found";  exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe not found"; exit 1; }
[[ -d "$SOURCE_DIR" ]] || { echo "Not a directory: $SOURCE_DIR"; exit 1; }

log "===== Starting transcode run on: $SOURCE_DIR ====="
log "Min bitrate threshold: ${MIN_BITRATE_KBPS} kbps"

while :; do
    # Cheap enumeration only — no probing here.
    # Skip anything that already has a matching .mkv next to it.
    mapfile -d '' CANDIDATES < <(
        find "$SOURCE_DIR" -type f \
            \( -iname '*.mp4' -o -iname '*.wmv' -o -iname '*.avi' \) \
            -print0
    )

    REMAINING=()
    for f in "${CANDIDATES[@]}"; do
        out="${f%.*}.mkv"
        [[ -f "$out" ]] || REMAINING+=("$f")
    done

    if [[ ${#REMAINING[@]} -eq 0 ]]; then
        log "No candidate files left. Exiting."
        exit 0
    fi

    log "${#REMAINING[@]} candidate file(s) to evaluate."

    progressed=false
    for file in "${REMAINING[@]}"; do
        if ! in_window; then
            log "Window closed. Pausing work."
            break
        fi

        process_file "$file"
        rc=$?

        if [[ $rc -eq 2 ]]; then
            # Window closed during this file
            break
        fi
        progressed=true
    done

    if ! in_window; then
        sleep_until_window
    elif ! $progressed; then
        # Inside the window but nothing got handled — avoid a hot loop.
        log "No progress this pass; sleeping 60s before re-scan."
        sleep 60
    fi
done
