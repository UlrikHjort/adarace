#!/bin/sh
# AdaRace: a driving simulator in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# The prebuilt download: dist/adarace-<version>-linux-x86_64.tar.gz with the
# game, the Ada libraries that are not usually installed (GtkAda and the GNAT
# runtime), the shaders, the roads and a launcher.  Needs a built game
# (make game).  The release workflow runs this when a version is tagged.

set -eu
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*Number : constant String := "\(.*\)";/\1/p' src/version.ads)
NAME=adarace-$VERSION-linux-x86_64
OUT=dist/$NAME
rm -rf "$OUT" "dist/$NAME.tar.gz"
mkdir -p "$OUT/bin" "$OUT/lib" "$OUT/scripts"

cp bin/adarace "$OUT/bin/"
ldd bin/adarace | awk '/libgtkada|libgnat|libgnarl/ {print $1, $3}' | sort -u |
while read -r SONAME FILE; do
    cp -L "$FILE" "$OUT/lib/$SONAME"
done

cp -r shaders tracks "$OUT/"
cp LICENSE README.md "$OUT/"
cp scripts/make_voice.sh "$OUT/scripts/"

cat > "$OUT/adarace" <<'LAUNCH'
#!/bin/sh
# Start AdaRace (the Ada libraries it brings are in lib/)
D=$(cd "$(dirname "$0")" && pwd)
cd "$D" || exit 1
scripts/make_voice.sh
LD_LIBRARY_PATH="$D/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" exec "$D/bin/adarace" "$@"
LAUNCH
chmod +x "$OUT/adarace"

cat > "$OUT/README-FIRST.txt" <<TXT
AdaRace $VERSION for Linux (x86_64): a driving simulator in Ada

It needs GTK 3, libepoxy, PulseAudio's library, and a graphics card with
OpenGL 4.5. On Debian, Ubuntu and Mint:

    sudo apt install libgtk-3-0 libepoxy0 libpulse0

Then start it with ./adarace. A Logitech G29 works if plugged in, and the
keyboard always does. For the co-driver's voice, install ffmpeg and espeak-ng
or Piper; without them the arrows on the screen still do the job.
TXT

(cd dist && tar czf "$NAME.tar.gz" "$NAME")
rm -rf "$OUT"
echo "dist/$NAME.tar.gz ($(du -h "dist/$NAME.tar.gz" | cut -f1))"
