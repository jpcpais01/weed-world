#!/usr/bin/env python3
"""Adds secondary-motion bones to the Meshy Keling rig and skins foliage to them.

The Meshy "smart rig" only has a body skeleton, so the leafy crown, the
dandelion stalks and the basket on the back would move rigidly.
This script appends small bone chains (driven at runtime by
SpringBoneSimulator3D) and blends the surrounding vertices onto them with
smooth falloffs, keeping the 4-influence limit of the mobile skinning path.

usage: python3 tools/rig_keling.py keling_source.glb keling.glb
"""
import json, struct, sys
import numpy as np

HEAD, CHEST = "Head", "Chest"

# Meshy exports anonymous bone names; give them humanoid ones. Bone_001 sits
# between the hips and the legs, Bone_036/041/046 (and mirrored) are palm bones.
RENAME = {
    "Bone_000": "Hips", "Bone_001": "Pelvis", "Bone_004": "Spine", "Bone_003": "Chest",
    "Bone_002": "UpperChest", "Bone_017": "Neck", "Bone_016": "Head", "Bone_015": "HeadTop",
    "Bone_014": "LeftUpperLeg", "Bone_013": "LeftLowerLeg", "Bone_012": "LeftFoot", "Bone_011": "LeftToes", "Bone_010": "LeftToesEnd",
    "Bone_009": "RightUpperLeg", "Bone_008": "RightLowerLeg", "Bone_007": "RightFoot", "Bone_006": "RightToes", "Bone_005": "RightToesEnd",
}
for side, base in (("Left", 18), ("Right", 23)):
    b = lambda i: "Bone_%03d" % i
    if side == "Left":
        arm = [22, 21, 20, 19, 18]
        thumb, index, middle, ring = [31, 30, 29, 28], [41, 40, 39, 38, 37], [46, 45, 44, 43, 42], [36, 35, 34, 33, 32]
    else:
        arm = [27, 26, 25, 24, 23]
        thumb, index, middle, ring = [50, 49, 48, 47], [65, 64, 63, 62, 61], [60, 59, 58, 57, 56], [55, 54, 53, 52, 51]
    for n, i in zip(["Shoulder", "UpperArm", "LowerArm", "Hand", "Palm"], arm):
        RENAME[b(i)] = side + n
    for n, i in zip(["ThumbMetacarpal", "ThumbProximal", "ThumbDistal", "ThumbTip"], thumb):
        RENAME[b(i)] = side + n
    for finger, chain in (("Index", index), ("Middle", middle), ("Ring", ring)):
        for n, i in zip(["Metacarpal", "Proximal", "Intermediate", "Distal", "Tip"], chain):
            RENAME[b(i)] = side + finger + n

# name, parent, joints (world space, metres). The last point is the virtual tip.
CHAINS = [
    ("Crown_FrontR", HEAD, [(-0.10, 1.25, 0.15), (-0.14, 1.40, 0.30), (-0.17, 1.55, 0.46)]),
    ("Crown_FrontC", HEAD, [(0.02, 1.25, 0.15), (0.03, 1.37, 0.27), (0.04, 1.48, 0.40)]),
    ("Crown_FrontL", HEAD, [(0.15, 1.25, 0.15), (0.25, 1.37, 0.27), (0.33, 1.48, 0.38)]),
    ("Crown_Top", HEAD, [(0.05, 1.28, 0.05), (0.10, 1.46, 0.10), (0.17, 1.68, 0.12)]),
    ("Crown_BackL", HEAD, [(0.12, 1.25, -0.08), (0.18, 1.42, -0.12), (0.22, 1.58, -0.16)]),
    ("Crown_SideR", HEAD, [(-0.20, 1.25, 0.05), (-0.30, 1.38, 0.06), (-0.40, 1.48, 0.07)]),
]
BASKET = ("Basket", CHEST, [(0.15, 0.84, -0.24), (0.22, 0.45, -0.46)])


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


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1), t


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

    prim = j["meshes"][0]["primitives"][0]
    P, _ = accessor_array(j, b, prim["attributes"]["POSITION"])
    J, j_off = accessor_array(j, b, prim["attributes"]["JOINTS_0"])
    W, w_off = accessor_array(j, b, prim["attributes"]["WEIGHTS_0"])
    nv = len(P)
    n_old = len(skin["joints"])

    # Dense weight matrix over (old + new) joints.
    new_bones = []  # (name, parent_node_index, world_matrix)

    def add_chain(name, parent_name, pts, suffixes):
        pts = [np.array(p) for p in pts]
        par = by_name[parent_name] if isinstance(parent_name, str) else parent_name
        ids = []
        for k in range(len(pts) - 1):
            Mw = np.eye(4)
            Mw[:3, :3] = basis_y_along(pts[k + 1] - pts[k])
            Mw[:3, 3] = pts[k]
            nm = name + suffixes[k]
            new_bones.append((nm, par, Mw))
            ids.append(len(new_bones) - 1)
            par = ("new", len(new_bones) - 1)
        return ids, pts

    chain_info = []
    for name, par, pts in CHAINS:
        ids, p = add_chain(name, par, pts, ["_1", "_2"])
        chain_info.append((ids, p))
    basket_ids, basket_pts = add_chain(BASKET[0], BASKET[1], BASKET[2], [""])

    Wd = np.zeros((nv, n_old + len(new_bones)), np.float64)
    np.add.at(Wd, (np.repeat(np.arange(nv), 4), J.reshape(-1).astype(int)), W.reshape(-1))

    def move_to(mask_w, target_cols):
        """Moves mask_w of each vertex's weight onto new joints; target_cols sum to 1."""
        Wd[:, :n_old] *= (1.0 - mask_w)[:, None]
        for col, tw in target_cols:
            Wd[:, n_old + col] += mask_w * tw

    x, y, z = P[:, 0], P[:, 1], P[:, 2]

    # Leafy crown + dandelion stalks.
    crown = smoothstep(1.17, 1.34, y)
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
    cols = []
    for c, (ids, _) in enumerate(chain_info):
        upper = smoothstep(0.3, 0.7, ts[c])
        cols.append((ids[0], ks[c] * (1 - upper)))
        cols.append((ids[1], ks[c] * upper))
    move_to(crown, cols)

    # Basket on the back (offset towards the character's left).
    basket = smoothstep(-0.20, -0.27, z) * smoothstep(0.36, 0.42, y) * smoothstep(0.97, 0.9, y)
    move_to(basket, [(basket_ids[0], np.ones(nv))])

    # Back to 4 influences.
    top = np.argsort(-Wd, axis=1)[:, :4]
    tw = np.take_along_axis(Wd, top, 1)
    tw /= tw.sum(1, keepdims=True)
    J_new = top.astype(np.uint8)
    W_new = tw.astype(np.float32)
    b[j_off:j_off + J_new.nbytes] = J_new.tobytes()
    b[w_off:w_off + W_new.nbytes] = W_new.tobytes()

    # Nodes, skin joints and inverse bind matrices.
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
        skin["joints"].append(idx)
        ibm_list.append(np.linalg.inv(Mw).T.reshape(-1).astype(np.float32))  # column-major

    # A "Root" bone at the feet, parent of the hips, carries extracted root motion.
    hips = by_name["Hips"]
    arm = next(i for i, n in enumerate(nodes) if hips in n.get("children", []))
    nodes.append({"name": "Root", "children": [hips]})
    root_idx = len(nodes) - 1
    nodes[arm]["children"] = [root_idx if c == hips else c for c in nodes[arm]["children"]]
    skin["joints"].append(root_idx)
    ibm_list.append(np.eye(4, dtype=np.float32).reshape(-1))

    ibm_acc = j["accessors"][skin["inverseBindMatrices"]]
    old_ibm, _ = accessor_array(j, b, skin["inverseBindMatrices"])
    all_ibm = np.concatenate([old_ibm, np.array(ibm_list)], 0).astype(np.float32)
    while len(b) % 4:
        b.append(0)
    off = len(b)
    b += all_ibm.tobytes()
    j["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": all_ibm.nbytes})
    ibm_acc = dict(ibm_acc)
    ibm_acc["bufferView"] = len(j["bufferViews"]) - 1
    ibm_acc["count"] = len(all_ibm)
    ibm_acc.pop("byteOffset", None)
    j["accessors"].append(ibm_acc)
    skin["inverseBindMatrices"] = len(j["accessors"]) - 1
    j["buffers"][0]["byteLength"] = len(b)

    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    while len(b) % 4:
        b.append(0)
    total = 12 + 8 + len(js) + 8 + len(b)
    with open(dst, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON")); f.write(js)
        f.write(struct.pack("<I4s", len(b), b"BIN\x00")); f.write(bytes(b))
    for name, m in [("crown", crown), ("basket", basket)]:
        print(f"{name:7s} vertices touched: {(m > 0.01).sum()}")
    print(f"wrote {dst} with {len(new_bones)} extra bones")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
