#!/usr/bin/env bash
#
# process_audio.sh — Convert one of Mark's archive .m4a recordings into a
# loopable, evenly-leveled, de-popped production .m4a for the app bundle.
#
# Usage:  ./process_audio.sh <source.m4a> <output.m4a>
#
# Pipeline (every step is conservative; none of it erases the cat):
#
#   1. highpass(28 Hz)       — strip non-purr rumble below the fundamental
#                              (our autocorrelation showed all three cats
#                              purr at ~28-29 Hz, so we cut just below that)
#   2. adeclick               — isolate and patch transient pops/clicks
#                              (mic bumps, sheet rustles ARE preserved
#                              because they're broader-spectrum; only
#                              instantaneous spikes are removed)
#   3. dynaudnorm             — dynamic level compensation. Smooths the
#                              swings from us moving the mic closer/farther
#                              without flattening the cat's actual dynamics
#   4. loudnorm               — final loudness normalization to a target
#                              perceived level (-18 LUFS, podcast-ish)
#   5. seamless loop crossfade — last 0.5s fades into a copy of the first
#                              0.5s using an EQUAL-POWER curve (qsin —
#                              quarter-sine). Linear/triangular crossfades
#                              produce a -3dB dip at the midpoint when the
#                              two signals are uncorrelated; qsin keeps the
#                              combined energy constant so the seam is
#                              inaudible even when tail and head have
#                              different content (true for longer purrs).
#   6. AAC encode @ 96kbps    — matches the source format; in-ear quality
#
# Originals in Audio kitty purrs/ are never written to. The processed files
# go to the project root at Purr Machine/Purr[123].m4a — that's where the
# pbxproj has explicit PBXFileReferences. (The inner synchronized folder
# Purr Machine/Purr Machine/ would also auto-include them, producing a
# duplicate-output build error — do NOT put audio there.)

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: $0 <source.m4a> <output.m4a>"
    exit 1
fi

SRC="$1"
OUT="$2"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- 1. Process audio (no loop crossfade yet) into a clean intermediate WAV
INTERMEDIATE="$TMPDIR/processed.wav"

ffmpeg -hide_banner -loglevel error -y -i "$SRC" \
    -af "highpass=f=28, \
         adeclick=window=55:overlap=75:arorder=2:threshold=2:burst=2, \
         dynaudnorm=p=0.85:m=10:s=12:g=15, \
         loudnorm=I=-18:LRA=11:TP=-1.5" \
    -ar 44100 -ac 1 -c:a pcm_s16le \
    "$INTERMEDIATE"

# --- 2. Get the processed duration
DUR=$(ffprobe -v quiet -show_entries format=duration -of csv="p=0" "$INTERMEDIATE")
CROSSFADE=0.5
BODY_END=$(awk -v d="$DUR" -v x="$CROSSFADE" 'BEGIN {printf "%.6f", d - x}')

# --- 3. Create the loop-crossfaded version
#
# Structure: body[0..D-X] || crossfade(tail[D-X..D], head[0..X])
#
# That gives an output of length D whose last X seconds is the audio's
# original tail fading down + the audio's original head fading up. When
# this file is looped, end-of-iteration-N matches start-of-iteration-N+1.

LOOPABLE="$TMPDIR/loopable.wav"

ffmpeg -hide_banner -loglevel error -y \
    -i "$INTERMEDIATE" -i "$INTERMEDIATE" -i "$INTERMEDIATE" \
    -filter_complex "
        [0:a]atrim=0:${BODY_END}[body];
        [1:a]atrim=${BODY_END}:${DUR},asetpts=PTS-STARTPTS[tail];
        [2:a]atrim=0:${CROSSFADE},asetpts=PTS-STARTPTS[head];
        [tail][head]acrossfade=d=${CROSSFADE}:c1=qsin:c2=qsin[xf];
        [body][xf]concat=n=2:v=0:a=1[out]
    " \
    -map "[out]" -ar 44100 -ac 1 -c:a pcm_s16le \
    "$LOOPABLE"

# --- 4. Encode to AAC for the app bundle
ffmpeg -hide_banner -loglevel error -y -i "$LOOPABLE" \
    -c:a aac -b:a 96k -movflags +faststart \
    "$OUT"

# --- 5. Report
SRC_DUR=$(ffprobe -v quiet -show_entries format=duration -of csv="p=0" "$SRC")
SRC_SIZE=$(stat -f%z "$SRC" 2>/dev/null || stat -c%s "$SRC")
OUT_SIZE=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT")
printf "  %-30s  src=%6.2fs %6dKB  →  out=%6.2fs %6dKB\n" \
    "$(basename "$SRC") → $(basename "$OUT")" \
    "$SRC_DUR" "$((SRC_SIZE/1024))" \
    "$DUR" "$((OUT_SIZE/1024))"
