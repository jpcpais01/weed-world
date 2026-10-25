#!/usr/bin/env python3
"""Rebuilds João's Meshy water dragon so its whole body can swim.

Meshy's rig only reaches the head and the front legs (and tangles them), and
a serpent's body is never well served by a chain of bones anyway: it should
follow its head through the air, every bit of it passing through the same
places the head went. So the dragon is "unbent" instead:

  * a spine is laid through the body, from a point just ahead of the snout,
    down the S of the body (the model curls in its own side plane), to the
    tip of the tail (CTRL, refined against the mesh's own cross sections),
  * every vertex is given the spot along that spine it belongs to and its
    offset from it, measured in the spine's frame. Where the body bends
    tightly (the U of the neck) a vertex is near two parts of the spine at
    once; those take their spot from their neighbours on the mesh instead,
    so the fins and the mane in the bend never tear away,
  * the mesh is written out straightened: snout at the origin looking down
    +Z, tail down -Z, +Y up, +X the dragon's left. -Z is the distance along
    the spine, X/Y are the offset from it.

At runtime water_dragon.gdshader lays the straight dragon along any curve
(DragonBreath flies the head and the body follows its trail), so the rig is
the flight path itself.

It also writes water_dragon.json: the body length and girth along it (for
the drips, the mist and the bounds), and where the mouth and eyes are.

usage: python3 tools/dragon_asset.py
  reads  art_source/dragon/water_dragon_meshy.glb
  writes assets/fx/dragon/water_dragon.glb (+ water_dragon.json)
  debug: --debug <dir> also writes side views of the spine and the result
"""
import io, json, os, struct, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rig_keling import read_glb, write_glb, accessor_array, add_accessor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art_source/dragon/water_dragon_meshy.glb")
OUT = os.path.join(ROOT, "assets/fx/dragon")

# The spine in the model's side plane, as (z, y), tail tip to snout. The
# whole dragon lies in the x = 0 plane (mirror symmetric), so the spine does.
CTRL = [(-2.56, 0.79), (-2.048, 0.804), (-1.676, 0.767), (-1.304, 0.693), (-0.931, 0.6), (-0.559, 0.544),
        (-0.186, 0.562), (0.186, 0.674), (0.559, 0.786), (0.931, 0.76), (1.304, 0.6), (1.601, 0.432),
        (1.825, 0.451), (1.918, 0.655), (1.918, 0.916), (1.944, 1.121), (2.086, 1.214), (2.309, 1.214),
        (2.577, 1.177)]
AHEAD = 0.42          # the spine starts this far ahead of the snout (whiskers reach forward)
BEHIND = 0.05         # and runs on past the tail tip
STEP = 0.01           # spine sampling (m)
TEX = 1024


def catmull(pts, per=24):
    p = np.array(pts, float)
    p = np.vstack([2 * p[0] - p[1], p, 2 * p[-1] - p[-2]])
    out = []
    for i in range(1, len(p) - 2):
        a, b, c, d = p[i - 1], p[i], p[i + 1], p[i + 2]
        for t in np.linspace(0, 1, per, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3))
    out.append(p[-2])
    return np.array(out)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def resample(line, step):
    seg = np.linalg.norm(np.diff(line, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    ss = np.arange(0, s[-1], step)
    return np.stack([np.interp(ss, s, line[:, k]) for k in range(line.shape[1])], 1)


def smooth(line, k=6, n=3):
    for _ in range(n):
        q = line.copy()
        for i in range(1, len(line) - 1):
            lo, hi = max(0, i - k), min(len(line), i + k + 1)
            q[i] = line[lo:hi].mean(0)
        line = q
    return line


def frames(line):
    """Per spine point (snout -> tail): forward F (towards the snout) and up N, in (z, y)."""
    d = np.gradient(line, axis=0)
    f = -d / np.linalg.norm(d, axis=1, keepdims=True)
    n = np.stack([-f[:, 1], f[:, 0]], 1)        # F rotated +90 deg: F=+z -> N=+y
    return f, n


def build_spine(P):
    """Snout -> tail polyline in (z, y), STEP apart, refined against the mesh."""
    line = resample(catmull(CTRL)[::-1], STEP)
    zy = P[:, [2, 1]]
    ax = np.abs(P[:, 0])
    for _ in range(3):
        f, n = frames(line)
        fixed = line.copy()
        for i in range(0, len(line)):
            rel = zy - line[i]
            along = rel @ f[i]
            side = rel @ n[i]
            # The trunk's flanks: off the midline (fins and the mane are thin
            # plates on it) but not out on the legs or whiskers.
            m = (np.abs(along) < 0.03) & (ax > 0.035) & (ax < 0.15) & (np.abs(side) < 0.4)
            if m.sum() < 12:
                continue
            lo, hi = np.percentile(side[m], [4, 96])
            # Only a nudge (the legs and the head's whiskers sway the flanks),
            # and none in the head, which follows the hand-laid line.
            k = np.clip(0.5 * (lo + hi), -0.04, 0.04) * 0.5 * smoothstep(0.8, 1.1, i * STEP)
            fixed[i] = line[i] + n[i] * k
        line = resample(smooth(fixed, 10, 2), STEP)
    # Lead in ahead of the snout and run on past the tail tip.
    f, _ = frames(line)
    head = [line[0] + f[0] * AHEAD * k for k in np.linspace(1, 0, int(AHEAD / STEP), endpoint=False)]
    tail = [line[-1] - f[-1] * BEHIND * k for k in np.linspace(0, 1, int(BEHIND / STEP) + 1)[1:]]
    return np.vstack([head, line, tail])


def weld_adjacency(P, I):
    key = np.round(P * 1e5).astype(np.int64)
    _, uid = np.unique(key, axis=0, return_inverse=True)
    uid = uid.reshape(-1)
    e = np.concatenate([I[:, [0, 1]], I[:, [1, 2]], I[:, [2, 0]]])
    e = uid[e]
    e = e[e[:, 0] != e[:, 1]]
    e = np.unique(np.sort(e, 1), axis=0)
    return uid, e


def assign(P, I, line):
    """Spine parameter (distance from the spine start) for every vertex."""
    zy = P[:, [2, 1]]
    s_line = np.arange(len(line)) * STEP
    d2 = ((zy[:, None, :] - line[None, :, :]) ** 2).sum(2)      # vertices x spine
    k = d2.argmin(1)
    best = np.sqrt(d2[np.arange(len(P)), k])
    # Ambiguous: another stretch of spine (over 0.25 m along it) nearly as close.
    far = np.abs(s_line[None, :] - s_line[k][:, None]) > 0.25
    alt = np.sqrt(np.where(far, d2, np.inf).min(1))
    amb = alt < best * 1.35 + 0.03
    s = s_line[k].astype(float)
    uid, edges = weld_adjacency(P, I)
    nu = uid.max() + 1
    su = np.zeros(nu); cnt = np.zeros(nu)
    np.add.at(su, uid[~amb], s[~amb]); np.add.at(cnt, uid[~amb], 1)
    fixed = cnt > 0
    su[fixed] /= cnt[fixed]
    # Unfixed ones start from their nearest guess and relax to the average of
    # their neighbours (a harmonic fill).
    guess = np.zeros(nu); gc = np.zeros(nu)
    np.add.at(guess, uid, s); np.add.at(gc, uid, 1)
    su[~fixed] = guess[~fixed] / gc[~fixed]
    deg = np.zeros(nu)
    np.add.at(deg, edges[:, 0], 1); np.add.at(deg, edges[:, 1], 1)
    for _ in range(1500):
        acc = np.zeros(nu)
        np.add.at(acc, edges[:, 0], su[edges[:, 1]]); np.add.at(acc, edges[:, 1], su[edges[:, 0]])
        upd = acc / np.maximum(deg, 1)
        su = np.where(fixed | (deg == 0), su, upd)
    return su[uid], amb


def straighten(P, N, s, line):
    f, n = frames(line)
    k = np.clip(np.round(s / STEP).astype(int), 0, len(line) - 1)
    c = line[k]
    rel = P[:, [2, 1]] - c
    t = (rel * f[k]).sum(1)
    d = (rel * n[k]).sum(1)
    S = np.stack([P[:, 0], d, -(s - t)], 1)
    nz = N[:, 2] * f[k][:, 0] + N[:, 1] * f[k][:, 1]
    ny = N[:, 2] * n[k][:, 0] + N[:, 1] * n[k][:, 1]
    NS = np.stack([N[:, 0], ny, nz], 1)
    NS /= np.linalg.norm(NS, axis=1, keepdims=True)
    return S, NS


def image_bytes(j, b, tex_index, size, mode, fmt):
    img = j["images"][j["textures"][tex_index]["source"]]
    bv = j["bufferViews"][img["bufferView"]]
    o = bv.get("byteOffset", 0)
    im = Image.open(io.BytesIO(bytes(b[o:o + bv["byteLength"]]))).convert(mode).resize((size, size), Image.LANCZOS)
    out = io.BytesIO()
    if fmt == "png":
        im.save(out, "PNG", optimize=True)
    else:
        im.save(out, "JPEG", quality=90)
    return out.getvalue()


def profile(S, n=48):
    """Girth along the body: the trunk's radius at n points from snout to tail."""
    L = -S[:, 2].min()
    out = []
    r = np.sqrt(S[:, 0] ** 2 + S[:, 1] ** 2)
    for i in range(n):
        z0 = -L * i / (n - 1)
        m = (np.abs(S[:, 2] - z0) < L / n) & (np.abs(S[:, 0]) > 0.035)
        out.append(round(float(np.percentile(np.abs(S[m, 0]), 92)) if m.sum() > 8 else 0.02, 4))
    return L, out


def main():
    debug = sys.argv[sys.argv.index("--debug") + 1] if "--debug" in sys.argv else None
    j, b = read_glb(SRC)
    pr = j["meshes"][0]["primitives"][0]
    at = pr["attributes"]
    P = accessor_array(j, b, at["POSITION"])[0].astype(float)
    N = accessor_array(j, b, at["NORMAL"])[0].astype(float)
    UV = accessor_array(j, b, at["TEXCOORD_0"])[0].astype(np.float32)
    I = accessor_array(j, b, pr["indices"])[0].reshape(-1, 3).astype(np.uint32)
    line = build_spine(P)
    s, amb = assign(P, I, line)
    S, NS = straighten(P, N, s, line)
    L, girth = profile(S)
    print("spine %.2f m, %d vertices (%d in tight bends, filled from neighbours), body %.2f m" % (
        len(line) * STEP, len(P), amb.sum(), L))

    # Landmarks (in the straight frame): the mouth and the eyes, found as the
    # front-most head points at their height.
    head = S[:, 2] > -0.75
    snout_z = S[head & (np.abs(S[:, 0]) < 0.03), 2].max()
    meta = {
        "length": round(float(L), 4),
        "girth": girth,
        "snout_z": round(float(snout_z), 4),
        "mouth": [0.0, round(float(np.median(S[head & (np.abs(S[:, 0]) < 0.03) & (S[:, 2] > snout_z - 0.06), 1])), 4), round(float(snout_z - 0.03), 4)],
        "min": S.min(0).round(4).tolist(), "max": S.max(0).round(4).tolist(),
    }

    # A fresh glTF: one plain mesh (no skin), albedo + normal map.
    nj = {"asset": {"version": "2.0", "generator": "weed-world dragon_asset.py"},
          "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "WaterDragon", "mesh": 0}],
          "meshes": [], "accessors": [], "bufferViews": [], "buffers": [{"byteLength": 0}],
          "materials": [{"name": "WaterDragon", "doubleSided": False,
                         "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.15},
                         "normalTexture": {"index": 1}}],
          "textures": [{"source": 0, "sampler": 0}, {"source": 1, "sampler": 0}],
          "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
          "images": []}
    nb = bytearray()
    a_pos = add_accessor(nj, nb, S.astype(np.float32), 5126, "VEC3", True, 34962)
    a_nrm = add_accessor(nj, nb, NS.astype(np.float32), 5126, "VEC3", False, 34962)
    a_uv = add_accessor(nj, nb, UV, 5126, "VEC2", False, 34962)
    a_idx = add_accessor(nj, nb, I.reshape(-1), 5125, "SCALAR", False, 34963)
    nj["meshes"].append({"name": "WaterDragon", "primitives": [
        {"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv}, "indices": a_idx, "material": 0}]})
    albedo_tex = j["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    normal_tex = j["materials"][0]["normalTexture"]["index"]
    for data, mime in [(image_bytes(j, b, albedo_tex, TEX, "RGB", "jpg"), "image/jpeg"),
                       (image_bytes(j, b, normal_tex, TEX, "RGB", "png"), "image/png")]:
        while len(nb) % 4:
            nb.append(0)
        nj["bufferViews"].append({"buffer": 0, "byteOffset": len(nb), "byteLength": len(data)})
        nb += data
        nj["images"].append({"bufferView": len(nj["bufferViews"]) - 1, "mimeType": mime})
    os.makedirs(OUT, exist_ok=True)
    write_glb(os.path.join(OUT, "water_dragon.glb"), nj, nb)
    with open(os.path.join(OUT, "water_dragon.json"), "w") as fh:
        json.dump(meta, fh, indent=1)
    print("wrote", os.path.join(OUT, "water_dragon.glb"), meta["length"], meta["mouth"])

    if debug:
        os.makedirs(debug, exist_ok=True)
        side_view(P, line, amb, os.path.join(debug, "spine.png"))
        side_view(S, None, amb, os.path.join(debug, "straight.png"))


def side_view(P, line, amb, path):
    from PIL import ImageDraw
    W = 1600
    z, y = P[:, 2], P[:, 1]
    lo = np.array([z.min(), y.min()]); sc = (W - 20) / (z.max() - z.min())
    H = int((y.max() - y.min()) * sc) + 20
    im = Image.new("RGB", (W, H), (30, 30, 34)); d = ImageDraw.Draw(im)
    X = ((z - lo[0]) * sc + 10).astype(int); Y = (H - 10 - (y - lo[1]) * sc).astype(int)
    for xx, yy, a in zip(X, Y, amb):
        im.putpixel((min(xx, W - 1), min(max(yy, 0), H - 1)), (255, 120, 60) if a else (150, 210, 230))
    if line is not None:
        pts = [((zz - lo[0]) * sc + 10, H - 10 - (yy - lo[1]) * sc) for zz, yy in line]
        d.line(pts, fill=(255, 40, 40), width=2)
    im.save(path)


if __name__ == "__main__":
    main()
