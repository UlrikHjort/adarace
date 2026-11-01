#!/bin/sh
# AdaRace: a driving simulator in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# The pictures in the README, made from the game itself with the AI at the
# wheel: screenshots in docs/screenshots, small looping GIFs in docs/gifs.
#
#   scripts/make_media.sh              all of them
#   scripts/make_media.sh rally night  just these
#
# A window opens for each; leave it be while it records.  Needs ffmpeg,
# ImageMagick and xwininfo for the menu, and a built game (make game).

set -e
cd "$(dirname "$0")/.."
SHOTS=docs/screenshots
GIFS=docs/gifs
mkdir -p "$SHOTS" "$GIFS"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A quiet home of its own, so your settings, laps and videos are not touched
home_fresh () {
    rm -rf "$WORK/home"
    mkdir -p "$WORK/home/Videos"
}

ALL="$*"
pick () { [ -z "$ALL" ] && return 0; for w in $ALL; do [ "$w" = "$1" ] && return 0; done; return 1; }

# shot NAME FRAME [VAR=value ...]
shot () {
    name=$1; frame=$2; shift 2
    echo "== shot $name"
    home_fresh
    env HOME="$WORK/home" ADARACE_NOWHEEL=1 ADARACE_VOLUME=0 ADARACE_AUTOSTART=1 ADARACE_AUTOPILOT=1 \
        ADARACE_SHOT="$WORK/$name.ppm" ADARACE_SHOT_FRAME="$frame" "$@" \
        timeout 120 ./bin/adarace > "$WORK/$name.log" 2>&1 || true
    convert "$WORK/$name.ppm" -resize 1280x -quality 84 "$SHOTS/$name.jpg"
}

# clip NAME FROM SECONDS [VAR=value ...]   (FPS, WIDTH, COLOURS: lighter GIFs)
clip () {
    name=$1; from=$2; secs=$3; shift 3
    echo "== clip $name"
    home_fresh
    env HOME="$WORK/home" ADARACE_NOWHEEL=1 ADARACE_VOLUME=0 ADARACE_AUTOSTART=1 ADARACE_AUTOPILOT=1 \
        ADARACE_RECORD_AT="$from" ADARACE_RECORD_FOR="$secs" "$@" \
        timeout $((from + secs + 60)) ./bin/adarace > "$WORK/$name.log" 2>&1 || true
    # the picture goes into its file a moment after the game has gone
    mp4=""
    for i in 1 2 3 4 5 6 7 8 9 10; do
        mp4=$(ls "$WORK"/home/Videos/AdaRace/*.mp4 2>/dev/null | head -n 1)
        [ -n "$mp4" ] && break
        sleep 1
    done
    if [ -z "$mp4" ]; then
        echo "   no video:"; tail -n 5 "$WORK/$name.log"; return
    fi
    sleep 1
    ffmpeg -loglevel error -y -i "$mp4" \
        -vf "fps=${FPS:-10},scale=${WIDTH:-420}:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=${COLOURS:-96}:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
        -loop 0 "$GIFS/$name.gif"
    echo "   $GIFS/$name.gif ($(du -k "$GIFS/$name.gif" | cut -f1) kB)"
}

# Scenes: R4 is car 2, Skovvej track 4; light 4 dawn, 5 dusk, 6 night, 2 golden;
# weather 1 rain, 2 fog, 3 snow; season 1 autumn, 2 winter, 3 spring
STAGE="ADARACE_TRACK=4 ADARACE_CAR=2"

pick rally   && clip rally 22 5 $STAGE ADARACE_CAMERA=CHASE
pick night   && clip night 30 5 $STAGE ADARACE_CAMERA=CHASE ADARACE_TIME=6
pick winter  && clip winter 30 5 $STAGE ADARACE_CAMERA=CHASE ADARACE_SEASON=2 ADARACE_WEATHER=3
pick rain    && clip rain 14 5 ADARACE_TRACK=1 ADARACE_CAMERA=COCKPIT ADARACE_WEATHER=1
pick race    && clip race 8 6 ADARACE_MODE=1 ADARACE_TRACK=1 ADARACE_CAR=1 ADARACE_CAMERA=CHASE ADARACE_TIME=2
pick school  && clip school 18 5 ADARACE_MODE=2 ADARACE_LESSON=1 ADARACE_CAMERA=CHASE

pick shots && {
    shot rally-forest 1500 $STAGE ADARACE_CAMERA=CHASE
    shot rally-night 1800 $STAGE ADARACE_CAMERA=CHASE ADARACE_TIME=6
    shot rally-winter 1800 $STAGE ADARACE_CAMERA=CHASE ADARACE_SEASON=2 ADARACE_WEATHER=3
    shot rally-fog 1500 $STAGE ADARACE_CAMERA=CHASE ADARACE_WEATHER=2
    shot rain-cockpit 1000 ADARACE_TRACK=1 ADARACE_CAMERA=COCKPIT ADARACE_WEATHER=1
    shot autumn-dawn 1200 ADARACE_TRACK=2 ADARACE_CAMERA=CHASE ADARACE_SEASON=1 ADARACE_TIME=4
    shot gt3-golden 1300 ADARACE_TRACK=2 ADARACE_CAR=1 ADARACE_CAMERA=TRACKSIDE ADARACE_TIME=2
    shot driving-line 2000 ADARACE_TRACK=2 ADARACE_AID=2 ADARACE_CAMERA=CHASE
    shot lesson-passed 3500 ADARACE_MODE=2 ADARACE_LESSON=0 ADARACE_CAMERA=CHASE
}

pick menu && {
    echo "== shot menu"
    home_fresh
    HOME="$WORK/home" ADARACE_NOWHEEL=1 ADARACE_VOLUME=0 timeout 14 ./bin/adarace > /dev/null 2>&1 &
    sleep 10
    win=$(xwininfo -root -tree | grep '"AdaRace"' | head -n 1 | awk '{print $1}')
    import -window "$win" "$WORK/menu.png"
    wait
    convert "$WORK/menu.png" -resize 1280x -quality 86 "$SHOTS/menu.jpg"
}

du -sh "$SHOTS" "$GIFS"
