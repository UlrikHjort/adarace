#!/bin/sh
# AdaRace: a driving simulator in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Is everything needed to build AdaRace here?  Says what is missing and how to
# get it; exit status 1 if something needed is.  `make` runs this first.

MISSING=""
have () { command -v "$1" > /dev/null 2>&1; }

have gnatmake || MISSING="$MISSING gnat"
have gprbuild || MISSING="$MISSING gprbuild"

GTKADA=no
if have gnatls; then
    for D in $(echo "${GPR_PROJECT_PATH:-}" | tr ':' ' ') \
             $(gnatls -v 2> /dev/null | sed -n '/Project Search Path/,/^$/p' | tail -n +2); do
        [ -f "$D/gtkada.gpr" ] && GTKADA=yes
    done
fi
[ "$GTKADA" = yes ] || MISSING="$MISSING gtkada"

if have pkg-config; then
    pkg-config --exists gtk+-3.0 || MISSING="$MISSING gtk3"
    pkg-config --exists epoxy || MISSING="$MISSING epoxy"
    pkg-config --exists libpulse-simple || MISSING="$MISSING pulse"
else
    MISSING="$MISSING pkg-config"
fi

[ -z "$MISSING" ] && exit 0

echo "AdaRace cannot be built yet. Missing:$MISSING"
echo
echo "  Debian, Ubuntu, Mint: sudo apt install gnat gprbuild libgtkada-dev libgtk-3-dev libepoxy-dev libpulse-dev pkg-config"
echo "      (the GtkAda package is called libgtkada20-dev or similar on some releases)"
echo "  Fedora:   sudo dnf install gcc-gnat gprbuild gtkada-devel gtk3-devel libepoxy-devel pulseaudio-libs-devel pkgconf"
echo "  Arch:     sudo pacman -S gcc-ada gprbuild gtk3 libepoxy libpulse pkgconf, and gtkada from the AUR"
echo "  openSUSE: sudo zypper install gcc-ada gprbuild gtkada-devel gtk3-devel libepoxy-devel libpulse-devel pkg-config"
exit 1
