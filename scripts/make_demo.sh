#!/bin/sh
# AdaRace: a driving simulator in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# A demo video with sound, from the game itself with the AI at the wheel:
# each scene is recorded (picture and sound), given a caption, faded in and
# out, and the lot joined behind a title.  The result: dist/adarace-demo.mp4,
# and dist/adarace-demo-small.mp4 under 10 MB, which GitHub shows on a page.
#
#   scripts/make_demo.sh          the cars
#   scripts/make_demo.sh bike     the motorcycle, ridden for show
#
# A window opens for each scene; leave it be while it records.  Needs ffmpeg,
# a sound server (the sound is taken from the game's own mixer, whatever the
# volume), and a built game with its co-driver's voice (make game voice).

set -e
cd "$(dirname "$0")/.."
WHAT=${1:-cars}
case "$WHAT" in
    cars) OUT=dist/adarace-demo.mp4 ;;
    bike) OUT=dist/adarace-motorcycle.mp4 ;;
    *) echo "scripts/make_demo.sh [cars|bike]"; exit 1 ;;
esac
SMALL=${OUT%.mp4}-small.mp4
mkdir -p dist
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FONT=$(fc-match -f '%{file}' "DejaVu Sans:bold" 2>/dev/null || true)
[ -n "$FONT" ] || { echo "Needs a font (fontconfig)"; exit 1; }
W=1600
H=900
N=0

# scene "Caption" FROM SECONDS VAR=value ...
scene () {
    caption=$1; from=$2; secs=$3; shift 3
    N=$((N + 1))
    echo "== $N: $caption"
    rm -rf "$WORK/home"
    mkdir -p "$WORK/home/Videos"
    env HOME="$WORK/home" ADARACE_NOWHEEL=1 ADARACE_VOLUME=0 ADARACE_AUTOSTART=1 ADARACE_AUTOPILOT=1 \
        ADARACE_RECORD_AT="$from" ADARACE_RECORD_FOR="$secs" "$@" \
        timeout $((from + secs + 60)) ./bin/adarace > "$WORK/$N.log" 2>&1 || true
    mp4=""
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        mp4=$(ls "$WORK"/home/Videos/AdaRace/*.mp4 2>/dev/null | head -n 1)
        [ -n "$mp4" ] && break
        sleep 1
    done
    if [ -z "$mp4" ]; then
        echo "   no video:"; tail -n 5 "$WORK/$N.log"; exit 1
    fi
    sleep 1
    printf '%s' "$caption" > "$WORK/$N.txt"
    # The caption slides in a moment after the start; fades at both ends
    d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$mp4")
    end=$(awk "BEGIN { print $d - 0.5 }")
    ffmpeg -loglevel error -y -i "$mp4" -filter_complex "\
[0:v]scale=$W:$H,fps=30,\
drawtext=fontfile=$FONT:textfile=$WORK/$N.txt:fontsize=32:fontcolor=white:x=40:y=h-226:\
box=1:boxcolor=black@0.6:boxborderw=14:\
alpha='min(1,max(0,(t-0.6)*3))*min(1,max(0,($d-0.6-t)*3))',\
fade=t=in:st=0:d=0.5,fade=t=out:st=$end:d=0.5[v];\
[0:a]aresample=48000,afade=t=in:st=0:d=0.4,afade=t=out:st=$end:d=0.5,\
loudnorm=I=-18:TP=-2:LRA=11[a]" -map "[v]" -map "[a]" \
        -c:v libx264 -preset medium -crf 21 -pix_fmt yuv420p -c:a aac -b:a 192k -ar 48000 \
        "$WORK/s$N.mp4"
    echo "file '$WORK/s$N.mp4'" >> "$WORK/list.txt"
}

card () {
    big=$1; small=$2; secs=$3
    end=$(awk "BEGIN { print $secs - 0.6 }")
    N=$((N + 1))
    printf '%s' "$big" > "$WORK/$N.a"
    printf '%s' "$small" > "$WORK/$N.b"
    ffmpeg -loglevel error -y -f lavfi -i "color=c=0x0c0e12:s=${W}x$H:d=$secs:r=30" \
        -f lavfi -i "anullsrc=r=48000:cl=stereo" -t "$secs" -filter_complex "\
[0:v]drawtext=fontfile=$FONT:textfile=$WORK/$N.a:fontsize=96:fontcolor=white:x=(w-tw)/2:y=h/2-110,\
drawtext=fontfile=$FONT:textfile=$WORK/$N.b:fontsize=32:fontcolor=0xff5a3c:x=(w-tw)/2:y=h/2+20,\
fade=t=in:st=0:d=0.6,fade=t=out:st=$end:d=0.6[v]" -map "[v]" -map 1:a \
        -c:v libx264 -preset medium -crf 21 -pix_fmt yuv420p -c:a aac -b:a 192k -ar 48000 \
        "$WORK/s$N.mp4"
    echo "file '$WORK/s$N.mp4'" >> "$WORK/list.txt"
}

: > "$WORK/list.txt"
if [ "$WHAT" = bike ]; then
B="ADARACE_CAR=5 ADARACE_STUNT=1"
card "ADARACE" "The Nordic 1000 R: a motorcycle that leans to turn" 4
# shellcheck disable=SC2086
scene "Up on the back wheel at 190 km/h" 4 8 $B ADARACE_TRACK=1 ADARACE_CAMERA=CHASE ADARACE_ORBIT=75.0
# shellcheck disable=SC2086
scene "Lights out: a pack of riders" 14 10 $B ADARACE_MODE=1 ADARACE_TRACK=1 ADARACE_CAMERA=CHASE
# shellcheck disable=SC2086
scene "Down the speedway on one wheel, in the golden hour" 5 7 $B ADARACE_TRACK=3 ADARACE_CAMERA=CHASE ADARACE_ORBIT=-65.0 ADARACE_TIME=2
# shellcheck disable=SC2086
scene "A stoppie into the hairpin" 48 9 $B ADARACE_TRACK=2 ADARACE_CAMERA=CHASE ADARACE_ORBIT=95.0
# shellcheck disable=SC2086
scene "From the helmet: the horizon leans with the bike" 26 12 $B ADARACE_MODE=1 ADARACE_TRACK=7 ADARACE_CAMERA=COCKPIT ADARACE_TIME=6
# shellcheck disable=SC2086
scene "Knee down at the harbour, at night" 84 9 $B ADARACE_MODE=1 ADARACE_TRACK=7 ADARACE_CAMERA=CHASE_FAR ADARACE_TIME=6
# shellcheck disable=SC2086
scene "And once more, for the camera" 30 7 $B ADARACE_TRACK=1 ADARACE_CAMERA=CHASE ADARACE_ORBIT=-80.0 ADARACE_TIME=4
card "ADARACE" "Ride it with an Xbox controller: make run" 4
else
card "ADARACE" "A driving simulator in Ada, written by Claude Opus 5.5" 4
scene "Rally: a forest stage, the co-driver calling the notes" 18 22 ADARACE_TRACK=4 ADARACE_CAR=2 ADARACE_CAMERA=CHASE
scene "From the cockpit: live gauges, gravel under the floor" 24 12 ADARACE_TRACK=5 ADARACE_CAR=2 ADARACE_CAMERA=COCKPIT
scene "Night, on the headlamps" 40 10 ADARACE_TRACK=4 ADARACE_CAR=2 ADARACE_CAMERA=CHASE ADARACE_TIME=6
scene "Winter, snow falling" 26 10 ADARACE_TRACK=5 ADARACE_CAR=2 ADARACE_CAMERA=CHASE ADARACE_SEASON=2 ADARACE_WEATHER=3
scene "Rain, wipers going" 16 10 ADARACE_TRACK=1 ADARACE_CAR=0 ADARACE_CAMERA=COCKPIT ADARACE_WEATHER=1
scene "A race against the AI: lights out" 5 14 ADARACE_MODE=1 ADARACE_TRACK=1 ADARACE_CAR=1 ADARACE_CAMERA=CHASE ADARACE_TIME=2
scene "Five cars, each its own engine: the Hyper, 540 kW" 14 9 ADARACE_TRACK=2 ADARACE_CAR=4 ADARACE_CAMERA=TRACKSIDE
card "ADARACE" "Ada and GtkAda, physics at 1 kHz, a Logitech G29" 4
fi

ffmpeg -loglevel error -y -f concat -safe 0 -i "$WORK/list.txt" -c copy -movflags +faststart "$OUT"
echo "$OUT ($(du -h "$OUT" | cut -f1), $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" | cut -d. -f1) s)"

# The small one: 720p, the bitrate held down until it is under 10 MB
for CRF in 28 30 32 34; do
    ffmpeg -loglevel error -y -i "$OUT" -vf scale=1280:720 -c:v libx264 -preset slow -crf "$CRF" \
        -maxrate 850k -bufsize 1700k -c:a aac -b:a 96k -movflags +faststart "$SMALL"
    [ "$(stat -c %s "$SMALL")" -lt 10000000 ] && break
done
echo "$SMALL ($(du -h "$SMALL" | cut -f1))"
