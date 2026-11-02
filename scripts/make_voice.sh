#!/bin/sh
# AdaRace: a driving simulator in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# The co-driver's words, one short clip each, in sounds/codriver (44.1 kHz,
# 16 bit, mono, raw, cut tight and through a helmet intercom).  Not kept in
# git, since a voice comes with its own licence: made on your machine, with
# Piper if it can be found, else espeak-ng.  Without either the game simply
# shows the arrows.  To use your own voice, put clips of the same names there.
#
#   PIPER=/path/to/piper PIPER_VOICE=/path/to/voice.onnx scripts/make_voice.sh

cd "$(dirname "$0")/.."
OUT=sounds/codriver
WORDS="left right one two three four five six long hairpin over crest into finish"
[ -f "$OUT/finish.pcm" ] && [ -z "$FORCE" ] && exit 0
command -v ffmpeg > /dev/null || { echo "No co-driver voice: ffmpeg is needed (sudo apt install ffmpeg)"; exit 0; }

PIPER=${PIPER:-$(command -v piper || echo "$HOME/prg/piper/piper")}
[ -x "$PIPER" ] || PIPER=""
if [ -n "$PIPER" ] && [ -z "$PIPER_VOICE" ]; then
    PIPER_VOICE=$(find "$HOME" -maxdepth 6 -name '*.onnx' -path '*en_*' -not -path '*/.cache/*' 2>/dev/null | head -n 1)
fi
if [ -n "$PIPER" ] && [ -n "$PIPER_VOICE" ]; then
    MAKER=piper
elif command -v espeak-ng > /dev/null; then
    MAKER=espeak
else
    echo "No co-driver voice: neither piper nor espeak-ng found (see \"The co-driver's voice\" in the README)"; exit 0
fi

mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
for w in $WORDS; do
    case $MAKER in
        piper)  echo "$w." | "$PIPER" --model "$PIPER_VOICE" --output_file "$WORK/$w.wav" > /dev/null 2>&1 ;;
        espeak) espeak-ng -v en-gb -s 190 -w "$WORK/$w.wav" "$w" ;;
    esac
    # Quicker than speech, no silence at the ends, and the thin sound of an intercom
    ffmpeg -loglevel error -y -i "$WORK/$w.wav" \
        -af "silenceremove=start_periods=1:start_threshold=-40dB,areverse,silenceremove=start_periods=1:start_threshold=-40dB,areverse,atempo=1.22,highpass=f=280,lowpass=f=3600,acompressor=threshold=-18dB:ratio=4,volume=1.5" \
        -ar 44100 -ac 1 -f s16le "$OUT/$w.pcm"
done
echo "Co-driver's voice made with $MAKER in $OUT"
if [ "$MAKER" = espeak ]; then
    echo "(For a natural voice, install Piper: see \"The co-driver's voice\" in the README.)"
fi
