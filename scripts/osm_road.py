#!/usr/bin/env python3
# AdaRace: a driving simulator in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# A street circuit from OpenStreetMap: the shortest way by road through a list
# of points (closed back to the first), with the real buildings beside it as
# blocks of their size and height, and the river as water.  The road file it
# writes is made from OpenStreetMap data, so it is under the ODbL, and says so.
#
#   scripts/osm_road.py --osm paris.osm --name "Paris" \
#       --via 48.8656,2.3212 48.8738,2.2950 ... --out tracks/08-boulevard.track

import argparse, heapq, math, sys
import xml.etree.ElementTree as ET

DRIVE = {"motorway": 9, "trunk": 9, "primary": 8, "secondary": 7, "tertiary": 6.5,
         "unclassified": 5.5, "residential": 5.5,
         "motorway_link": 5, "trunk_link": 5, "primary_link": 5, "secondary_link": 5}

def load(files):
    nodes, ways, buildings, river = {}, [], [], []
    for f in files:
        for _, el in ET.iterparse(f, events=("end",)):
            if el.tag == "node":
                nodes[el.get("id")] = (float(el.get("lat")), float(el.get("lon")))
            elif el.tag == "way":
                tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
                refs = [n.get("ref") for n in el.findall("nd")]
                h = tags.get("highway")
                if h in DRIVE and tags.get("area") != "yes" and tags.get("tunnel") not in ("yes",):
                    lanes = tags.get("lanes", "")
                    width = DRIVE[h]
                    if lanes.isdigit():
                        width = max(width, min(12.0, 1.7 * int(lanes)))
                    ways.append((refs, width, tags.get("name", "")))
                elif "building" in tags:
                    buildings.append((refs, tags))
                elif tags.get("waterway") == "river":
                    river.append(refs)
                el.clear()
            elif el.tag == "relation":
                el.clear()
    return nodes, ways, buildings, river

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--osm", nargs="+", required=True)
    ap.add_argument("--via", nargs="+", required=True, help="lat,lon ...")
    ap.add_argument("--name", required=True)
    ap.add_argument("--note", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--reach", type=float, default=110.0, help="metres of buildings either side")
    a = ap.parse_args()

    nodes, ways, buildings, river = load(a.osm)
    via = [tuple(map(float, v.split(","))) for v in a.via]
    lat0, lon0 = via[0]
    kx = 111320.0 * math.cos(math.radians(lat0))
    ky = 110540.0
    def xz(ll):
        # x to the east, z to the south: the game's axes
        return ((ll[1] - lon0) * kx, -(ll[0] - lat0) * ky)

    # The road graph
    graph, width_of = {}, {}
    for refs, width, name in ways:
        for p, q in zip(refs, refs[1:]):
            if p in nodes and q in nodes:
                a_, b_ = xz(nodes[p]), xz(nodes[q])
                d = math.dist(a_, b_)
                graph.setdefault(p, []).append((q, d))
                graph.setdefault(q, []).append((p, d))
                width_of[p] = max(width_of.get(p, 0), width)
                width_of[q] = max(width_of.get(q, 0), width)

    def nearest(ll):
        p = xz(ll)
        return min(graph, key=lambda n: math.dist(xz(nodes[n]), p))

    used = set()
    def route(s, t):
        # Dijkstra; a road already driven costs much more, so the loop does not double back
        dist, prev, q = {s: 0.0}, {}, [(0.0, s)]
        while q:
            d, n = heapq.heappop(q)
            if n == t:
                break
            if d > dist.get(n, 1e18):
                continue
            for m, w in graph[n]:
                cost = w * (8.0 if (n, m) in used or (m, n) in used else 1.0)
                if d + cost < dist.get(m, 1e18):
                    dist[m], prev[m] = d + cost, n
                    heapq.heappush(q, (d + cost, m))
        if t not in prev and s != t:
            sys.exit("no road between %s and %s" % (s, t))
        path = [t]
        while path[-1] != s:
            path.append(prev[path[-1]])
        path.reverse()
        for p, r in zip(path, path[1:]):
            used.add((p, r))
        return path

    stops = [nearest(v) for v in via]
    path = []
    for s, t in zip(stops, stops[1:] + stops[:1]):
        leg = route(s, t)
        path += leg if not path else leg[1:]
    if path[-1] == path[0]:
        path.pop()

    # Even spacing, about every 20 m, carrying the width along
    pts = [(*xz(nodes[n]), width_of.get(n, 6.0)) for n in path]
    out, carry = [pts[0]], 0.0
    for (x0, z0, w0), (x1, z1, w1) in zip(pts, pts[1:] + pts[:1]):
        d = math.hypot(x1 - x0, z1 - z0)
        t = 20.0 - carry
        while t < d:
            f = t / d
            out.append((x0 + (x1 - x0) * f, z0 + (z1 - z0) * f, w0 + (w1 - w0) * f))
            t += 20.0
        carry = d - (t - 20.0)
    # Street corners are square; a car cannot take them so. Cut the corners
    # (Chaikin, three times over), then space the points evenly again
    for _ in range(3):
        cut = []
        for p, q in zip(out, out[1:] + out[:1]):
            cut.append(tuple(0.75 * u + 0.25 * v for u, v in zip(p, q)))
            cut.append(tuple(0.25 * u + 0.75 * v for u, v in zip(p, q)))
        out = cut
    out = out[::4]
    length = sum(math.dist(p[:2], q[:2]) for p, q in zip(out, out[1:] + out[:1]))

    def near_route(p, reach):
        return min(math.dist(p, q[:2]) for q in out) < reach

    # Buildings near it: each footprint as its smallest rectangle
    blocks = []
    for refs, tags in buildings:
        poly = [xz(nodes[r]) for r in refs if r in nodes]
        if len(poly) < 4:
            continue
        cx = sum(p[0] for p in poly) / len(poly)
        cz = sum(p[1] for p in poly) / len(poly)
        if not near_route((cx, cz), a.reach):
            continue
        best = None
        for p, q in zip(poly, poly[1:]):
            ex, ez = q[0] - p[0], q[1] - p[1]
            L = math.hypot(ex, ez)
            if L < 1.0:
                continue
            ux, uz = ex / L, ez / L
            us = [ (pp[0] - cx) * ux + (pp[1] - cz) * uz for pp in poly ]
            vs = [ -(pp[0] - cx) * uz + (pp[1] - cz) * ux for pp in poly ]
            area = (max(us) - min(us)) * (max(vs) - min(vs))
            if best is None or area < best[0]:
                mu, mv = (max(us) + min(us)) / 2, (max(vs) + min(vs)) / 2
                best = (area, cx + mu * ux - mv * uz, cz + mu * uz + mv * ux, ux, uz,
                        max(us) - min(us), max(vs) - min(vs))
        if best is None or best[5] < 4 or best[6] < 4:
            continue
        h = tags.get("height", "").replace("m", "").strip()
        lv = tags.get("building:levels", "")
        try:
            height = float(h)
        except ValueError:
            height = float(lv) * 3.2 + 2.0 if lv.replace(".", "").isdigit() else 20.0
        blocks.append((best[1], best[2], best[3], best[4], best[5], best[6], min(60.0, height)))

    # The river: circles along its middle, kept off the road
    water = []
    for refs in river:
        line = [xz(nodes[r]) for r in refs if r in nodes]
        for p, q in zip(line, line[1:]):
            d = math.dist(p, q)
            for k in range(int(d // 40) + 1):
                f = k * 40 / d if d else 0
                c = (p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f)
                gap = min(math.dist(c, r[:2]) - r[2] for r in out)
                if 25 < gap < 600 and all(math.dist(c, w[:2]) > 50 for w in water):
                    water.append((c[0], c[1], min(70.0, gap - 14.0)))

    with open(a.out, "w") as f:
        f.write("# An AdaRace road, made by scripts/osm_road.py from OpenStreetMap data.\n")
        f.write("# Map data (c) OpenStreetMap contributors, under the Open Database Licence\n")
        f.write("# (ODbL 1.0): https://www.openstreetmap.org/copyright\n")
        f.write("name %s\nkind circuit\nsetting city\n" % a.name)
        if a.note:
            f.write("# %s\n" % a.note)
        for w in water:
            f.write("water %.0f %.0f %.0f\n" % w)
        for b in blocks:
            f.write("block %.1f %.1f %.4f %.4f %.1f %.1f %.1f\n" % b)
        f.write("points\n")
        for x, z, w in out:
            f.write("%9.1f %9.1f %6.1f %5.1f %4.1f\n" % (x, z, 35.0, min(12.0, max(5.0, w)), 0.0))
    print("%s: %.0f m, %d points, %d buildings, %d pieces of river"
          % (a.out, length, len(out), len(blocks), len(water)))

main()
