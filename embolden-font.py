#!/usr/bin/env python3
# Usage: embolden-font.py SRC.ttf DST.ttf STRENGTH STYLE WEIGHT
#   ./embolden-font.py ProggyVector-Regular.ttf out/ProggyVector-Regular.ttf 18 Regular 400
#   ./embolden-font.py ProggyVector-Regular.ttf out/ProggyVector-Bold.ttf    56 Bold    700
# Needs python-fonttools. STRENGTH is in font units (ProggyVector is 1024 upem).

# Port of FreeType's FT_Outline_EmboldenXY, applied to glyf outlines.
# Grows ink by `strength` font units total per axis. X growth is symmetric so
# monospace cells stay centered; Y keeps the baseline and grows upward.
import math, sys
from fontTools.ttLib import TTFont

def embolden_contour(pts, xs, ys, tt_orient):
    n = len(pts)
    if n < 2: return pts
    xs /= 2; ys /= 2
    out_pts = [list(p) for p in pts]
    # unit vectors and lengths of each edge i -> i+1, skipping zero-length edges
    def edge(a, b):
        dx, dy = b[0]-a[0], b[1]-a[1]; l = math.hypot(dx, dy)
        return (dx/l, dy/l, l) if l else None
    for i in range(n):
        # incoming: nearest distinct previous point; outgoing: nearest distinct next
        p = pts[i]
        j = (i-1) % n
        while pts[j] == p and j != i: j = (j-1) % n
        k = (i+1) % n
        while pts[k] == p and k != i: k = (k+1) % n
        ein, eout = edge(pts[j], p), edge(p, pts[k])
        if not ein or not eout: continue
        ix, iy, lin = ein; ox, oy, lout = eout
        d = ix*ox + iy*oy
        if d <= -0.375:  # sharp reversal, same threshold as FreeType (-0x6000)
            sx = sy = 0.0
        else:
            d += 1.0
            sx, sy = iy + oy, ix + ox
            if tt_orient: sx = -sx
            else: sy = -sy
            q = ox*iy - oy*ix
            if tt_orient: q = -q
            l = min(lin, lout)
            sx = sx*xs/d if xs*q <= l*d else sx*l/q
            sy = sy*ys/d if ys*q <= l*d else sy*l/q
        out_pts[i][0] = p[0] + sx
        out_pts[i][1] = p[1] + ys + sy
    return out_pts

def run(src, dst, strength, style, weight, ystrength=None):
    ystrength = strength if ystrength is None else ystrength
    f = TTFont(src)
    glyf, hmtx = f['glyf'], f['hmtx']
    for name in f.getGlyphOrder():
        g = glyf[name]
        if g.isComposite() or g.numberOfContours <= 0: continue
        coords, ends, flags = g.getCoordinates(glyf)
        coords = list(coords)
        area = 0.0; start = 0
        for e in ends:
            c = coords[start:e+1]
            area += sum(c[m][0]*c[(m+1)%len(c)][1] - c[(m+1)%len(c)][0]*c[m][1] for m in range(len(c)))
            start = e+1
        tt = area < 0  # clockwise outer contours = TrueType orientation
        new = []; start = 0
        for e in ends:
            new += embolden_contour(coords[start:e+1], strength, ystrength, tt)
            start = e+1
        g.coordinates = type(g.coordinates)([(round(x), round(y)) for x, y in new])
        g.recalcBounds(glyf)
        adv, _ = hmtx[name]; hmtx[name] = (adv, g.xMin)
    os2, head, nm = f['OS/2'], f['head'], f['name']
    os2.usWeightClass = weight
    bold = style == 'Bold'
    os2.fsSelection = (os2.fsSelection & ~0b1100001) | (0b100000 if bold else 0b1000000)
    head.macStyle = (head.macStyle & ~1) | (1 if bold else 0)
    ver = f"Version 1.1.7; neutrino +{strength}"
    for rec in list(nm.names):
        if rec.nameID == 2: nm.setName(style, 2, rec.platformID, rec.platEncID, rec.langID)
        if rec.nameID == 3: nm.setName(f"ProggyVector-{style};{ver}", 3, rec.platformID, rec.platEncID, rec.langID)
        if rec.nameID == 4: nm.setName(f"ProggyVector {style}" if bold else "ProggyVector", 4, rec.platformID, rec.platEncID, rec.langID)
        if rec.nameID == 5: nm.setName(ver, 5, rec.platformID, rec.platEncID, rec.langID)
        if rec.nameID == 6: nm.setName(f"ProggyVector-{style}", 6, rec.platformID, rec.platEncID, rec.langID)
    f['hhea'].recalc(f)
    f.save(dst)

if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], int(sys.argv[5]))
