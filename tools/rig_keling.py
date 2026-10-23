#!/usr/bin/env python3
"""Turns the Meshy Keling export into the game-ready, skinned Keling.

The Meshy "smart rig" gives a body skeleton with automatic skin weights that
bleed far too wide for this round little creature: the arms pull on the face,
beard and the whole side of the torso, the legs drag the belly, and the head
is spread over three bones. This script:

  * names the bones,
  * removes the basket from the back and the white dandelion puffs from the
    crown, and grows procedural yellow flowers in their place,
  * re-skins the body: arms and legs only move their own geometry (with a
    short blend at the joint), the head moves as one rigid piece above a soft
    beard seam, and each twig finger follows its own bone chain,
  * appends spring-bone chains for the leafy crown and its flower stalks
    (driven at runtime by SpringBoneSimulator3D), skinned to foliage only,
  * adds a "Root" bone at the feet for root motion,

keeping the 4-influence limit of the mobile skinning path.

usage: python3 tools/rig_keling.py art_source/keling_meshy_source.glb assets/characters/keling/keling.glb
"""
import io, json, struct, sys
import numpy as np
from PIL import Image

HEAD, CHEST = "Head", "Chest"

# Meshy exports anonymous bone names; give them humanoid ones. Bone_001 sits
# between the hips and the legs, Bone_018/023 are palm bones.
RENAME = {
    "Bone_000": "Hips", "Bone_001": "Pelvis", "Bone_004": "Spine", "Bone_003": "Chest",
    "Bone_002": "UpperChest", "Bone_017": "Neck", "Bone_016": "Head", "Bone_015": "HeadTop",
    "Bone_014": "LeftUpperLeg", "Bone_013": "LeftLowerLeg", "Bone_012": "LeftFoot", "Bone_011": "LeftToes", "Bone_010": "LeftToesEnd",
    "Bone_009": "RightUpperLeg", "Bone_008": "RightLowerLeg", "Bone_007": "RightFoot", "Bone_006": "RightToes", "Bone_005": "RightToesEnd",
}
FINGERS = {}  # side -> {finger: [bone names, base to tip]}
for side in ("Left", "Right"):
    b = lambda i: "Bone_%03d" % i
    if side == "Left":
        arm = [22, 21, 20, 19, 18]
        thumb, index, middle, ring = [31, 30, 29, 28], [41, 40, 39, 38, 37], [46, 45, 44, 43, 42], [36, 35, 34, 33, 32]
    else:
        arm = [27, 26, 25, 24, 23]
        thumb, index, middle, ring = [50, 49, 48, 47], [65, 64, 63, 62, 61], [60, 59, 58, 57, 56], [55, 54, 53, 52, 51]
    for n, i in zip(["Shoulder", "UpperArm", "LowerArm", "Hand", "Palm"], arm):
        RENAME[b(i)] = side + n
    FINGERS[side] = {}
    for n, i in zip(["ThumbMetacarpal", "ThumbProximal", "ThumbDistal", "ThumbTip"], thumb):
        RENAME[b(i)] = side + n
    FINGERS[side]["Thumb"] = [side + n for n in ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal", "ThumbTip"]]
    for finger, chain in (("Index", index), ("Middle", middle), ("Ring", ring)):
        names = []
        for n, i in zip(["Metacarpal", "Proximal", "Intermediate", "Distal", "Tip"], chain):
            RENAME[b(i)] = side + finger + n
            names.append(side + finger + n)
        FINGERS[side][finger] = names[1:]  # the metacarpal stays inside the palm

ARM_CHAIN = ["Shoulder", "UpperArm", "LowerArm", "Hand", "Palm", "Thumb", "Index", "Middle", "Ring"]
LEG_CHAIN = ["UpperLeg", "LowerLeg", "Foot", "Toes"]
TORSO = ["Hips", "Pelvis", "Spine", "Chest", "UpperChest"]

# name, parent, joints (world space, metres). The last point is the virtual tip.
CHAINS = [
    ("Crown_FrontR", HEAD, [(-0.10, 1.25, 0.15), (-0.14, 1.40, 0.30), (-0.17, 1.55, 0.46)]),
    ("Crown_FrontC", HEAD, [(0.02, 1.25, 0.15), (0.03, 1.37, 0.27), (0.04, 1.48, 0.40)]),
    ("Crown_FrontL", HEAD, [(0.15, 1.25, 0.15), (0.25, 1.37, 0.27), (0.33, 1.48, 0.38)]),
    ("Crown_Top", HEAD, [(0.05, 1.28, 0.05), (0.10, 1.46, 0.10), (0.17, 1.68, 0.12)]),
    ("Crown_BackL", HEAD, [(0.12, 1.25, -0.08), (0.18, 1.42, -0.12), (0.22, 1.58, -0.16)]),
    ("Crown_SideR", HEAD, [(-0.20, 1.25, 0.05), (-0.30, 1.38, 0.06), (-0.40, 1.48, 0.07)]),
]

# Head seam: below HEAD_SEAM[0] the body, above HEAD_SEAM[1] the rigid head.
HEAD_SEAM = (0.90, 1.00)
NECK_BAND = (0.82, 0.93)
HEAD_CENTER = np.array([0.0, 1.15, 0.05])


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def read_glb(path):
    d = open(path, "rb").read()
    jl = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", d[off:off + 4])[0]
    return j, bytearray(d[off + 8:off + 8 + bl])


def write_glb(path, j, b):
    while len(b) % 4:
        b.append(0)
    j["buffers"][0]["byteLength"] = len(b)
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(b)))
        f.write(struct.pack("<I4s", len(js), b"JSON")); f.write(js)
        f.write(struct.pack("<I4s", len(b), b"BIN\x00")); f.write(bytes(b))


def q2m(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def m2q(m):
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        return [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    i = int(np.argmax(np.diag(m)))
    if i == 0:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        return [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    if i == 1:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        return [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
    return [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]


def local_mat(n):
    M = np.eye(4)
    M[:3, :3] = q2m(n.get("rotation", [0, 0, 0, 1])) @ np.diag(n.get("scale", [1, 1, 1]))
    M[:3, 3] = n.get("translation", [0, 0, 0])
    return M


def basis_y_along(direction):
    y = np.asarray(direction, float)
    y /= np.linalg.norm(y)
    ref = np.array([0.0, 0.0, 1.0]) if abs(y[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    x = np.cross(y, ref); x /= np.linalg.norm(x)
    z = np.cross(x, y)
    return np.stack([x, y, z], axis=1)


def accessor_array(j, b, i):
    a = j["accessors"][i]; bv = j["bufferViews"][a["bufferView"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
    dt = {5126: np.float32, 5123: np.uint16, 5121: np.uint8, 5125: np.uint32}[a["componentType"]]
    o = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    return np.frombuffer(bytes(b), dtype=dt, count=a["count"] * n, offset=o).reshape(a["count"], n).copy(), o


def add_accessor(j, b, arr, ctype, atype, minmax=False, target=None):
    while len(b) % 4:
        b.append(0)
    off = len(b)
    b += arr.tobytes()
    bv = {"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes}
    if target:
        bv["target"] = target
    j["bufferViews"].append(bv)
    acc = {"bufferView": len(j["bufferViews"]) - 1, "componentType": ctype, "count": len(arr), "type": atype}
    if ctype == 5121 and atype == "VEC4" and arr.dtype == np.uint8 and minmax == "norm":
        acc["normalized"] = True
    if minmax is True:
        acc["min"] = arr.min(0).tolist(); acc["max"] = arr.max(0).tolist()
    j["accessors"].append(acc)
    return len(j["accessors"]) - 1


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1), t


def components(P, I):
    """Connected pieces of the mesh (vertices welded by position)."""
    key = np.round(P / 1e-5).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    parent = np.arange(weld.max() + 1)

    def find(x):
        r = x
        while parent[r] != r:
            r = parent[r]
        while parent[x] != r:
            parent[x], x = r, parent[x]
        return r
    for t in weld[I]:
        a = find(t[0])
        parent[find(t[1])] = a
        parent[find(t[2])] = a
    roots = np.array([find(x) for x in range(len(parent))])
    return roots[weld[I[:, 0]]]


def triangle_colors(j, b, UV, I):
    """Average albedo of each triangle (texture sampled at corners and centre)."""
    tex = j["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    img = j["images"][j["textures"][tex]["source"]]
    bv = j["bufferViews"][img["bufferView"]]
    data = bytes(b[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])
    alb = np.asarray(Image.open(io.BytesIO(data)).convert("RGB")).astype(np.float32) / 255.0
    H, W, _ = alb.shape

    def samp(uv):
        x = np.clip((uv[:, 0] % 1) * W, 0, W - 1).astype(int)
        y = np.clip((uv[:, 1] % 1) * H, 0, H - 1).astype(int)
        return alb[y, x]
    return (samp(UV[I[:, 0]]) + samp(UV[I[:, 1]]) + samp(UV[I[:, 2]]) + samp(UV[I].mean(1))) / 4


# ---------------------------------------------------------------- flowers --

def flower_mesh(center, normal, radius, seed):
    """A cupped, five-petal buttercup with an orange heart and stamens."""
    rng = np.random.default_rng(seed)
    n = normal / np.linalg.norm(normal)
    ref = np.array([0.0, 1.0, 0.0]) if abs(n[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    u = np.cross(n, ref); u /= np.linalg.norm(u)
    v = np.cross(n, u)
    spin = rng.uniform(0, 2 * np.pi)
    verts, cols, tris = [], [], []

    def add(p, c):
        verts.append(p); cols.append(c)
        return len(verts) - 1

    def at(r, ang, h):
        return center + radius * (r * (np.cos(ang) * u + np.sin(ang) * v) + h * n)

    deep = np.array([0.93, 0.55, 0.05]); mid = np.array([1.0, 0.80, 0.12]); tip = np.array([1.0, 0.93, 0.38])
    petals = 5
    NU, NV = 8, 7  # rings along the petal, columns across it
    for k in range(petals):
        a0 = spin + k * 2 * np.pi / petals + rng.normal(0, 0.06)
        half = 0.78 + rng.normal(0, 0.03)  # half opening angle of the petal (radians)
        cup = 0.75 + rng.normal(0, 0.05)
        idx = []
        for iu in range(NU + 1):
            s = iu / NU
            r = 0.16 + 0.84 * s
            width = (0.3 + 0.7 * s ** 0.6) * np.sqrt(max(0.0, 1.0 - s ** 5))  # narrow claw, broad rounded tip
            row = []
            for iv in range(NV + 1):
                w = (iv / NV - 0.5) * 2
                ang = a0 + w * half * width
                h = cup * s * s + 0.05 * (1 - abs(w)) * s  # cupped up, with a soft midrib
                c = deep * (1 - s) ** 2 + mid * 2 * s * (1 - s) + tip * s * s
                c = c * (0.94 + 0.06 * (1 - abs(w)))
                row.append(add(at(r, ang, h), c))
            idx.append(row)
        for iu in range(NU):
            for iv in range(NV):
                a, bb, c, d = idx[iu][iv], idx[iu][iv + 1], idx[iu + 1][iv + 1], idx[iu + 1][iv]
                tris += [(a, bb, c), (a, c, d)]
    # Heart: a small orange dome.
    heart = np.array([0.85, 0.42, 0.04]); heart_top = np.array([0.98, 0.62, 0.10])
    rings, segs = 3, 10
    top = add(center + radius * 0.16 * n, heart_top)
    prev = None
    for ir in range(1, rings + 1):
        rr = 0.2 * ir / rings
        hh = 0.16 * np.cos(0.5 * np.pi * ir / rings)
        ring = [add(at(rr, spin + s * 2 * np.pi / segs, hh), heart * (0.9 + 0.1 * (1 - ir / rings)) + heart_top * 0.0) for s in range(segs)]
        for s in range(segs):
            s2 = (s + 1) % segs
            if prev is None:
                tris.append((top, ring[s], ring[s2]))
            else:
                tris += [(prev[s], ring[s], ring[s2]), (prev[s], ring[s2], prev[s2])]
        prev = ring
    # Stamens: tiny pale-gold tufts around the heart.
    for s in range(8):
        ang = spin + s * 2 * np.pi / 8 + 0.2
        base = at(0.2, ang, 0.08)
        tipp = at(0.3, ang, 0.32)
        side = radius * 0.025 * (np.cos(ang + np.pi / 2) * u + np.sin(ang + np.pi / 2) * v)
        i0 = add(base - side, heart); i1 = add(base + side, heart); i2 = add(tipp, np.array([1.0, 0.9, 0.45]))
        tris.append((i0, i1, i2))
    return np.array(verts), np.array(cols), np.array(tris)


def vertex_normals(V, T):
    N = np.zeros_like(V)
    fn = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    for k in range(3):
        np.add.at(N, T[:, k], fn)
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
    return N


# ------------------------------------------------------------------- main --

def main(src, dst):
    j, b = read_glb(src)
    nodes = j["nodes"]
    skin = j["skins"][0]
    for n in nodes:
        n["name"] = RENAME.get(n.get("name"), n.get("name"))
    by_name = {n["name"]: i for i, n in enumerate(nodes)}
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    def world(i):
        M = local_mat(nodes[i])
        while i in parent:
            i = parent[i]
            M = local_mat(nodes[i]) @ M
        return M

    def jpos(name):
        return world(by_name[name])[:3, 3]

    prim = j["meshes"][0]["primitives"][0]
    P, _ = accessor_array(j, b, prim["attributes"]["POSITION"])
    UV, _ = accessor_array(j, b, prim["attributes"]["TEXCOORD_0"])
    J, j_off = accessor_array(j, b, prim["attributes"]["JOINTS_0"])
    W, w_off = accessor_array(j, b, prim["attributes"]["WEIGHTS_0"])
    I, i_off = accessor_array(j, b, prim["indices"])
    I = I.reshape(-1, 3).astype(np.int64)
    nv = len(P)
    joints = skin["joints"]
    n_old = len(joints)
    col_of = {nodes[k]["name"]: c for c, k in enumerate(joints)}
    x, y, z = P[:, 0], P[:, 1], P[:, 2]

    # ---- pieces to remove: the basket and the dandelion puffs --------------
    tri_comp = components(P, I)
    tri_col = triangle_colors(j, b, UV, I)
    centroid = P[I].mean(1)
    lum = tri_col.mean(1); sat = tri_col.max(1) - tri_col.min(1)
    white = (lum > 0.62) & (sat < 0.18)
    sizes = np.bincount(tri_comp)
    main_comp = int(np.argmax(sizes))
    remove_tri = np.zeros(len(I), bool)
    puffs = []
    for c in np.unique(tri_comp):
        m = tri_comp == c
        cen = centroid[m].mean(0)
        if c != main_comp and cen[0] > 0.0 and cen[2] < -0.2 and 0.4 < cen[1] < 0.95:
            remove_tri |= m  # basket and the leaves tucked into it
        elif (white[m].mean() > 0.5 and cen[1] > 1.0) or (white[m].sum() >= 4 and cen[1] > 1.55 and m.sum() < 80):
            remove_tri |= m
            vids = np.unique(I[m])
            ext = np.ptp(P[vids], axis=0).max()
            puffs.append((vids, P[vids].mean(0), ext))
    print(f"removing {remove_tri.sum()} triangles (basket + {len(puffs)} dandelion puffs)")

    # Vertices of the main body piece vs. foliage (for the crown springs).
    vert_comp = np.full(nv, -1)
    vert_comp[I.reshape(-1)] = np.repeat(tri_comp, 3)
    vert_col = np.zeros((nv, 3)); cnt = np.zeros(nv)
    for k in range(3):
        np.add.at(vert_col, I[:, k], tri_col); np.add.at(cnt, I[:, k], 1)
    vert_col /= np.maximum(cnt, 1)[:, None]
    is_foliage = (vert_comp != main_comp) & (vert_col[:, 1] > vert_col[:, 2] + 0.05) & (vert_col[:, 1] >= vert_col[:, 0] - 0.02)

    # ---- new bones ----------------------------------------------------------
    new_bones = []  # (name, parent_node_index or ("new", k), world_matrix)

    def add_chain(name, parent_name, pts, suffixes):
        pts = [np.array(p) for p in pts]
        par = by_name[parent_name]
        ids = []
        for k in range(len(pts) - 1):
            Mw = np.eye(4)
            Mw[:3, :3] = basis_y_along(pts[k + 1] - pts[k])
            Mw[:3, 3] = pts[k]
            new_bones.append((name + suffixes[k], par, Mw))
            ids.append(len(new_bones) - 1)
            par = ("new", len(new_bones) - 1)
        return ids, pts

    chain_info = [add_chain(name, par, pts, ["_1", "_2"]) for name, par, pts in CHAINS]

    # ---- skin weights -------------------------------------------------------
    Wd = np.zeros((nv, n_old + len(new_bones)), np.float64)
    np.add.at(Wd, (np.repeat(np.arange(nv), 4), J.reshape(-1).astype(int)), W.reshape(-1))

    def cols(names):
        return [col_of[n] for n in names if n in col_of]

    def chain_cols(side, parts):
        return [col_of[n] for n in col_of if n.startswith(side) and any(n[len(side):].startswith(p) for p in parts)]

    upper_chest = col_of["UpperChest"]

    def torso_fallback(yy):
        """Height-based torso weights for vertices that had none."""
        knots = [("Hips", 0.30), ("Spine", 0.52), ("Chest", 0.70), ("UpperChest", 0.84)]
        out = np.zeros((len(yy), len(knots)))
        hs = np.array([k[1] for k in knots])
        yy = np.clip(yy, hs[0], hs[-1])
        for i in range(len(knots) - 1):
            m = (yy >= hs[i]) & (yy <= hs[i + 1])
            t = (yy[m] - hs[i]) / (hs[i + 1] - hs[i])
            out[m, i] += 1 - t; out[m, i + 1] += t
        return [col_of[k[0]] for k in knots], out

    head_mask = smoothstep(*HEAD_SEAM, y)

    # Arms and legs keep only their own geometry: Meshy marks the limb itself
    # with ~full weight and smears the rest across the body. Everything a limb
    # gives up goes to the core (torso / neck / head), shaped like the vertex's
    # own core weights, or by height where it had none.
    core_cols = cols(TORSO + ["Neck", "Head", "HeadTop"])
    limb_parts = []
    keep_total = np.zeros(nv)
    for side in ("Left", "Right"):
        for parts, lo, hi in ((ARM_CHAIN, 0.80, 0.97), (LEG_CHAIN, 0.55, 0.92)):
            cc = chain_cols(side, parts)
            wl = Wd[:, cc].sum(1)
            keep = smoothstep(lo, hi, wl) * (1 - head_mask)
            shape = np.where(wl[:, None] > 1e-6, Wd[:, cc] / np.maximum(wl, 1e-9)[:, None], 0.0)
            limb_parts.append((cc, keep, shape))
            keep_total += keep
    norm = np.maximum(keep_total, 1.0)
    cw = Wd[:, core_cols]
    cs = cw.sum(1)
    core_shape = np.where(cs[:, None] > 1e-4, cw / np.maximum(cs, 1e-9)[:, None], 0.0)
    fb_cols, fb = torso_fallback(y)
    New = np.zeros_like(Wd)
    core_amount = 1.0 - keep_total / norm
    New[:, core_cols] += core_shape * core_amount[:, None]
    need_fb = cs <= 1e-4
    for k, c in enumerate(fb_cols):
        New[need_fb, c] += fb[need_fb, k] * core_amount[need_fb]
    for cc, keep, shape in limb_parts:
        New[:, cc] += shape * (keep / norm)[:, None]
    Wd[:] = New

    # Fingers: each twig follows its own chain; the rest of the hand is rigid.
    for side in ("Left", "Right"):
        hand_cc = chain_cols(side, ["Hand", "Palm", "Thumb", "Index", "Middle", "Ring"])
        wh = Wd[:, hand_cc].sum(1)
        region = wh > 0.5
        if not region.any():
            continue
        pts_r = P[region]
        best_d = np.full(len(pts_r), np.inf)
        best_w = np.zeros((len(pts_r), Wd.shape[1]))
        member = np.zeros(len(pts_r))
        for finger, names in FINGERS[side].items():
            jp = [jpos(n) for n in names]
            tip_ext = jp[-1] + (jp[-1] - jp[-2]) * 0.8
            chain = jp + [tip_ext]
            dmin = np.full(len(pts_r), np.inf); seg = np.zeros(len(pts_r), int); tseg = np.zeros(len(pts_r))
            for k in range(len(chain) - 1):
                d, t = seg_dist(pts_r, chain[k], chain[k + 1])
                better = d < dmin
                dmin[better] = d[better]; seg[better] = k; tseg[better] = t[better]
            # Past the knuckle (projection onto the first segment) and close to the twig.
            a0, a1 = chain[0], chain[1]
            along = ((pts_r - a0) @ (a1 - a0)) / np.linalg.norm(a1 - a0)
            m = smoothstep(-0.008, 0.012, along) * smoothstep(0.032, 0.018, dmin)
            fw = np.zeros((len(pts_r), Wd.shape[1]))
            bone_cols = [col_of[n] for n in names] + [col_of[names[-1]]]
            for k in range(len(chain) - 1):
                sel = seg == k
                t = tseg[sel]
                # Blend into the next bone over the last 30% of a segment.
                blend = smoothstep(0.7, 1.0, t) * 0.5 if k + 1 < len(chain) - 1 else np.zeros_like(t)
                prevb = smoothstep(0.3, 0.0, t) * 0.5 if k > 0 else np.zeros_like(t)
                fw[sel, bone_cols[k]] += 1 - blend - prevb
                if k + 1 < len(chain) - 1:
                    fw[sel, bone_cols[k + 1]] += blend
                if k > 0:
                    fw[sel, bone_cols[k - 1]] += prevb
            closer = dmin < best_d
            best_d[closer] = dmin[closer]; best_w[closer] = fw[closer]; member[closer] = m[closer]
        rows = np.where(region)[0]
        hand = col_of[side + "Hand"]
        old = Wd[rows].copy()
        hand_part = old[:, hand_cc].sum(1)
        rest = old.copy(); rest[:, hand_cc] = 0.0
        rest[:, hand] = hand_part
        Wd[rows] = member[:, None] * best_w + (1 - member)[:, None] * rest
    # Head: one rigid piece above the beard seam, a soft band through the neck.
    for name in ("HeadTop", "Neck"):
        c = col_of[name]
        tgt = col_of["Head"] if name == "HeadTop" else upper_chest
        Wd[:, tgt] += Wd[:, c]; Wd[:, c] = 0.0
    neck_mask = smoothstep(*NECK_BAND, y) * (1 - head_mask)
    Wd *= (1 - head_mask - neck_mask)[:, None]
    Wd[:, col_of["Head"]] += head_mask
    Wd[:, col_of["Neck"]] += neck_mask

    # Leafy crown + flower stalks: foliage only, never the face.
    front = smoothstep(0.15, 0.30, z)
    crown = smoothstep(1.22 + 0.05 * front, 1.36 + 0.05 * front, y) * is_foliage
    sigma = 0.09
    ks, ts = [], []
    for ids, pts in chain_info:
        d1, t1 = seg_dist(P, pts[0], pts[1])
        d2, t2 = seg_dist(P, pts[1], pts[2])
        d = np.minimum(d1, d2)
        s = np.where(d1 <= d2, 0.5 * t1, 0.5 + 0.5 * t2)
        ks.append(np.exp(-(d / sigma) ** 2) + 1e-4)
        ts.append(s)
    ks = np.array(ks); ks /= ks.sum(0)
    Wd[:, :n_old] *= (1.0 - crown)[:, None]
    for c, (ids, _) in enumerate(chain_info):
        upper = smoothstep(0.3, 0.7, ts[c])
        Wd[:, n_old + ids[0]] += crown * ks[c] * (1 - upper)
        Wd[:, n_old + ids[1]] += crown * ks[c] * upper

    def top4(Wrows):
        top = np.argsort(-Wrows, axis=1)[:, :4]
        tw = np.take_along_axis(Wrows, top, 1)
        tw /= np.maximum(tw.sum(1, keepdims=True), 1e-9)
        return top.astype(np.uint8), tw.astype(np.float32)

    J_new, W_new = top4(Wd)
    b[j_off:j_off + J_new.nbytes] = J_new.tobytes()
    b[w_off:w_off + W_new.nbytes] = W_new.tobytes()

    # ---- drop removed triangles ---------------------------------------------
    kept = I[~remove_tri].astype(np.uint16)
    b[i_off:i_off + kept.nbytes] = kept.tobytes()
    j["accessors"][prim["indices"]]["count"] = int(kept.size)

    # ---- flowers ------------------------------------------------------------
    FV, FC, FT, FW = [], [], [], []
    base = 0
    for k, (vids, cen, ext) in enumerate(sorted(puffs, key=lambda p: tuple(p[1]))):
        big = ext > 0.1
        radius = 0.072 if big else 0.034
        out = cen - HEAD_CENTER; out /= np.linalg.norm(out)
        normal = out + np.array([0.0, 0.8, 0.0]) + np.array([0.0, 0.0, 0.35])
        center = cen - out * radius * 0.35  # sit on the stalk tip
        V, C, T = flower_mesh(center, normal, radius, seed=17 + k)
        avg = Wd[vids].mean(0, keepdims=True)
        FV.append(V); FC.append(C); FT.append(T + base); FW.append(np.repeat(avg, len(V), 0))
        base += len(V)
    FV = np.concatenate(FV).astype(np.float32)
    FC = np.concatenate([np.concatenate(FC), np.ones((len(FV), 1))], 1).astype(np.float32)
    FT = np.concatenate(FT).astype(np.uint16)
    FN = vertex_normals(FV.astype(np.float64), FT.astype(np.int64)).astype(np.float32)
    FJ, FWt = top4(np.concatenate(FW))
    j["materials"].append({"name": "Flower", "doubleSided": True,
                           "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.5}})
    fprim = {
        "attributes": {
            "POSITION": add_accessor(j, b, FV, 5126, "VEC3", True, 34962),
            "NORMAL": add_accessor(j, b, FN, 5126, "VEC3", False, 34962),
            "COLOR_0": add_accessor(j, b, FC, 5126, "VEC4", False, 34962),
            "JOINTS_0": add_accessor(j, b, FJ, 5121, "VEC4", False, 34962),
            "WEIGHTS_0": add_accessor(j, b, FWt, 5126, "VEC4", False, 34962),
        },
        "indices": add_accessor(j, b, FT.reshape(-1), 5123, "SCALAR", False, 34963),
        "material": len(j["materials"]) - 1,
    }
    j["meshes"][0]["primitives"].append(fprim)

    # ---- nodes, skin joints and inverse bind matrices ------------------------
    new_node_index = {}
    ibm_list = []
    for k, (nm, par, Mw) in enumerate(new_bones):
        if isinstance(par, tuple):
            Mp = new_bones[par[1]][2]
            pidx = new_node_index[par[1]]
        else:
            Mp = world(par); pidx = par
        Ml = np.linalg.inv(Mp) @ Mw
        nodes.append({"name": nm, "translation": Ml[:3, 3].tolist(),
                      "rotation": [float(v) for v in m2q(Ml[:3, :3] / np.linalg.norm(Ml[:3, :3], axis=0))]})
        idx = len(nodes) - 1
        nodes[pidx].setdefault("children", []).append(idx)
        new_node_index[k] = idx
        joints.append(idx)
        ibm_list.append(np.linalg.inv(Mw).T.reshape(-1).astype(np.float32))  # column-major

    # A "Root" bone at the feet, parent of the hips, carries extracted root motion.
    hips = by_name["Hips"]
    arm = next(i for i, n in enumerate(nodes) if hips in n.get("children", []))
    nodes.append({"name": "Root", "children": [hips]})
    root_idx = len(nodes) - 1
    nodes[arm]["children"] = [root_idx if c == hips else c for c in nodes[arm]["children"]]
    joints.append(root_idx)
    ibm_list.append(np.eye(4, dtype=np.float32).reshape(-1))

    old_ibm, _ = accessor_array(j, b, skin["inverseBindMatrices"])
    all_ibm = np.concatenate([old_ibm, np.array(ibm_list)], 0).astype(np.float32)
    acc = dict(j["accessors"][skin["inverseBindMatrices"]])
    new_acc = add_accessor(j, b, all_ibm, 5126, "MAT4")
    acc["bufferView"] = j["accessors"][new_acc]["bufferView"]; acc["count"] = len(all_ibm); acc.pop("byteOffset", None)
    j["accessors"][new_acc] = acc
    skin["inverseBindMatrices"] = new_acc

    write_glb(dst, j, b)
    print(f"crown vertices: {(crown > 0.01).sum()}, flowers: {len(puffs)} ({len(FV)} verts)")
    print(f"wrote {dst} with {len(new_bones)} extra bones")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
