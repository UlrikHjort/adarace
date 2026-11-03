#!/usr/bin/env python3
# AdaRace: a driving simulator in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# A real race circuit from OpenStreetMap: its one-way raceway pieces chained
# end to start round the lap, the heights from SRTM (NASA, public domain)
# through the Open Topo Data service, and the road's own width.  The road file
# it writes is made from OpenStreetMap data, so it is under the ODbL and says
# so.  Give it a name of your own: circuit names are trademarks.
#
#   scripts/osm_raceway.py --osm a.osm b.osm --first "Hatzenbach" \
#       --start "Döttinger Höhe" --name "Hexenwald Ring" --out tracks/11-hexenwald.track
#
# The map comes from the OpenStreetMap API in tiles (api/0.6/map?bbox=...,
# each under 50 000 nodes).  Heights are fetched once and kept in --heights.

import argparse, json, math, os, sys, time, urllib.request
import xml.etree.ElementTree as ET

SIDE_ROADS = ("Boxengasse", "pit", "Pit", "Variante", "Rallycross", "Anbindung")

def load(files):
    nodes, ways = {}, {}
    for f in files:
        for _, el in ET.iterparse(f, events=("end",)):
            if el.tag == "node":
                nodes[el.get("id")] = (float(el.get("lat")), float(el.get("lon")))
            elif el.tag == "way":
                tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
                if tags.get("highway") == "raceway" and tags.get("area") != "yes":
                    ways[el.get("id")] = ([n.get("ref") for n in el.findall("nd")], tags)
                el.clear()
    return nodes, ways

def chain(ways, first, avoid):
    """The lap: from the piece named first, on to the piece that starts where
    this one ends, until back at the first"""
    start = next(w for w, (r, t) in ways.items() if t.get("name") == first)
    seq, cur = [start], start
    while True:
        end = ways[cur][0][-1]
        nxt = [w for w, (r, t) in ways.items()
               if r[0] == end and w not in seq[1:]
               and not any(a in t.get("name", "") for a in avoid)]
        if start in nxt:
            return seq
        if not nxt or len(seq) > 500:
            sys.exit("the lap does not close after " + ways[cur][1].get("name", cur))
        cur = nxt[0]
        seq.append(cur)

def heights(points, cache):
    """Metres above the sea at each (lat, lon), from SRTM at 30 m"""
    known = json.load(open(cache)) if os.path.exists(cache) else {}
    want = [p for p in points if "%.5f,%.5f" % p not in known]
    for i in range(0, len(want), 100):
        batch = want[i:i + 100]
        url = ("https://api.opentopodata.org/v1/srtm30m?locations="
               + "|".join("%.5f,%.5f" % p for p in batch))
        req = urllib.request.Request(url, headers={"User-Agent": "AdaRace-track-builder"})
        reply = json.load(urllib.request.urlopen(req, timeout=60))
        for p, r in zip(batch, reply["results"]):
            known["%.5f,%.5f" % p] = r["elevation"]
        json.dump(known, open(cache, "w"))
        time.sleep(1.1)   # the service asks for one call a second
    return [known["%.5f,%.5f" % p] for p in points]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--osm", nargs="+", required=True)
    ap.add_argument("--first", required=True, help="name of a piece of the lap")
    ap.add_argument("--start", required=True, help="the piece the line is in the middle of")
    ap.add_argument("--name", required=True)
    ap.add_argument("--note", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--heights", default="heights.json")
    ap.add_argument("--every", type=float, default=12.0, help="metres between points")
    ap.add_argument("--bank", nargs="*", default=[], help="piece=degrees, e.g. Karussell=-12")
    a = ap.parse_args()

    nodes, ways = load(a.osm)
    seq = chain(ways, a.first, SIDE_ROADS)
    # Start in the middle of the start piece
    k = next(i for i, w in enumerate(seq) if ways[w][1].get("name") == a.start)
    seq = seq[k:] + seq[:k]
    bank = {b.split("=")[0]: float(b.split("=")[1]) for b in a.bank}

    # The line through the nodes, each with the road's width and banking
    line = []
    for w in seq:
        refs, tags = ways[w]
        try:
            width = float(tags.get("width", "9").split()[0])
        except ValueError:
            width = 9.0
        for r in refs[(1 if line else 0):]:
            line.append((nodes[r], min(6.0, max(3.5, width / 2.0)), bank.get(tags.get("name", ""), 0.0)))
    lat0, lon0 = line[0][0]
    kx, ky = 111320.0 * math.cos(math.radians(lat0)), 110540.0
    xy = [((lo - lon0) * kx, -(la - lat0) * ky) for (la, lo), _, _ in line]
    # Begin halfway along the start piece
    first_len = len(ways[seq[0]][0])
    half = first_len // 2
    xy = xy[half:-1] + xy[:half]
    line = line[half:-1] + line[:half]

    # Evenly spaced points along it
    out, carry = [], 0.0
    for i in range(len(xy)):
        (x0, z0), (x1, z1) = xy[i], xy[(i + 1) % len(xy)]
        seg = math.hypot(x1 - x0, z1 - z0)
        t = carry
        while t < seg:
            f = t / seg
            out.append((x0 + (x1 - x0) * f, z0 + (z1 - z0) * f, line[i][1], line[i][2]))
            t += a.every
        carry = t - seg
    total = len(out) * a.every

    # Heights: SRTM every few points, smoothed over 150 m (it sees the treetops)
    step = max(1, int(40.0 / a.every))
    probe = [(lat0 - z / ky, lon0 + x / kx) for x, z, _, _ in out[::step]]
    raw = heights(probe, a.heights)
    n = len(raw)
    reach = max(1, int(75.0 / (a.every * step)))
    smooth = [sum(raw[(i + j) % n] for j in range(-reach, reach + 1)) / (2 * reach + 1) for i in range(n)]
    low = min(smooth)
    ys = []
    for i in range(len(out)):
        f = i / step
        j = int(f) % n
        ys.append(smooth[j] + (smooth[(j + 1) % n] - smooth[j]) * (f - int(f)) - low + 5.0)

    with open(a.out, "w") as f:
        f.write("# An AdaRace road.  One setting a line, then the points it runs through, closed\n"
                "# back to the first: x  z  height  half-width  banking (metres, degrees; banking\n"
                "# is positive when the right side is lower).  See \"Your own roads\" in the README.\n")
        f.write("#\n# Made by scripts/osm_raceway.py from OpenStreetMap data,\n"
                "# (c) OpenStreetMap contributors, under the Open Database Licence (ODbL),\n"
                "# https://www.openstreetmap.org/copyright.  This file is therefore under the\n"
                "# ODbL too.  Heights from SRTM (NASA), in the public domain.\n")
        f.write("name %s\nkind circuit\nsetting forest\n" % a.name)
        if a.note:
            f.write("# %s\n" % a.note)
        f.write("points\n")
        for (x, z, hw, b), y in zip(out, ys):
            f.write("%9.1f %9.1f %7.1f %5.1f %5.1f\n" % (x, z, y, hw, b))
    print("%s: %.0f m, %d points, %.0f m of climb" % (a.out, total, len(out), max(ys) - min(ys)))

main()
