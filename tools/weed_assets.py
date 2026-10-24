#!/usr/bin/env python3
"""Turns João's four Meshy exports into the game-ready weed assets.

  * bud: the Meshy bud is a relief on a flat backing plate. The plate is cut
    off and the carved front is mirrored onto the back, so the bud is round
    from every side. The rim is pinned to the mirror plane and the seam
    normals are averaged, so the two halves meet without a crease.
  * three strains of plant: decimated for phones (the game crosses two
    copies at runtime so they read from every side).

Every texture is resized (the plants keep albedo only: their leaves are real
geometry, and a normal map buys nothing at this size on a phone). Metallic
and roughness maps are dropped for a constant leafy roughness.

Simplification uses meshoptimizer's gltfpack (`npm i gltfpack`).

usage: python3 tools/weed_assets.py <dir with the 4 Meshy glbs> assets/weed
  (sources kept in the project files under weed-source/)
"""
import io, json, os, struct, subprocess, sys, tempfile
import numpy as np
from PIL import Image

SOURCES = {
    # out name: (source file prefix, triangle ratio, albedo size, keep normal map)
    "bud": ("Meshy_AI_Enchanted_Bloom_Tree", 0.24, 512, True),
    "plant_ember": ("Meshy_AI_Enchanted_Herb_Bloom", 0.26, 1024, False),
    "plant_starlit": ("Meshy_AI_Starlit_Verdant_Bloom", 0.26, 1024, False),
    "plant_verdant": ("Meshy_AI_Enchanted_Verdant_Spr", 0.26, 1024, False),
}
CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path):
    d = open(path, "rb").read()
    jl = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    b = d[20 + jl + 8:]

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        o = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        n = NC[a["type"]]
        arr = np.frombuffer(b, dtype=CT[a["componentType"]], count=a["count"] * n, offset=o)
        return arr.reshape(a["count"], n) if n > 1 else arr

    pr = j["meshes"][0]["primitives"][0]
    at = pr["attributes"]
    mat = j["materials"][pr["material"]]
    imgs = []
    for im in j["images"]:
        bv = j["bufferViews"][im["bufferView"]]
        o = bv.get("byteOffset", 0)
        imgs.append(b[o:o + bv["byteLength"]])
    tex = lambda t: imgs[j["textures"][t["index"]]["source"]]
    return {
        "pos": acc(at["POSITION"]).astype(np.float64),
        "nrm": acc(at["NORMAL"]).astype(np.float64),
        "uv": acc(at["TEXCOORD_0"]).astype(np.float64),
        "idx": acc(pr["indices"]).astype(np.int64).reshape(-1, 3),
        "base": tex(mat["pbrMetallicRoughness"]["baseColorTexture"]),
        "normal": tex(mat["normalTexture"]) if "normalTexture" in mat else None,
    }


def write_glb(path, pos, nrm, uv, idx, images):
    blobs, views, accs = [], [], []

    def view(data, target=None):
        off = sum(len(x) for x in blobs)
        blobs.append(data + b"\0" * ((4 - len(data) % 4) % 4))
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    def accessor(arr, ctype, typ, target, minmax=False):
        a = {"bufferView": view(arr.tobytes(), target), "componentType": ctype, "count": len(arr), "type": typ}
        if minmax:
            a["min"] = arr.min(0).tolist()
            a["max"] = arr.max(0).tolist()
        accs.append(a)
        return len(accs) - 1

    attrs = {
        "POSITION": accessor(pos.astype(np.float32), 5126, "VEC3", 34962, True),
        "NORMAL": accessor(nrm.astype(np.float32), 5126, "VEC3", 34962),
        "TEXCOORD_0": accessor(uv.astype(np.float32), 5126, "VEC2", 34962),
    }
    ind = accessor(idx.astype(np.uint32).reshape(-1), 5125, "SCALAR", 34963)
    jimgs, texs = [], []
    for data, mime in images:
        jimgs.append({"bufferView": view(data), "mimeType": mime})
        texs.append({"source": len(jimgs) - 1})
    mat = {"name": "Weed", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.8}, "doubleSided": True}
    if len(images) > 1:
        mat["normalTexture"] = {"index": 1}
    j = {
        "asset": {"version": "2.0", "generator": "weed-world tools/weed_assets.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "Mesh"}],
        "meshes": [{"name": "Mesh", "primitives": [{"attributes": attrs, "indices": ind, "material": 0}]}],
        "materials": [mat], "textures": texs, "images": jimgs,
        "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": sum(len(x) for x in blobs)}],
    }
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    binary = b"".join(blobs)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def jpeg(data, size, quality=88):
    im = Image.open(io.BytesIO(data)).convert("RGB").resize((size, size), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, "JPEG", quality=quality, optimize=True)
    return out.getvalue()


def png(data, size):
    im = Image.open(io.BytesIO(data)).convert("RGB").resize((size, size), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, "PNG", optimize=True)
    return out.getvalue()


def weld_ids(pos, tol=1e-5):
    key = np.round(pos / tol).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    return inv.reshape(-1)


def weld(pos, nrm, uv, idx):
    """Merges corners that share a position and a UV (Meshy splits every
    face's normals apart, which leaves the simplifier nothing to collapse),
    averaging their normals."""
    key = np.concatenate([np.round(pos / 1e-5), np.round(uv / 1e-5)], axis=1).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    n = np.zeros((len(first), 3))
    np.add.at(n, inv, nrm)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    tris = inv[idx]
    tris = tris[(tris[:, 0] != tris[:, 1]) & (tris[:, 1] != tris[:, 2]) & (tris[:, 2] != tris[:, 0])]
    return pos[first], n, uv[first], tris


def round_bud(m):
    """Cuts the flat backing plate off the relief and mirrors the front onto
    the back, pinning the rim to the mirror plane so the halves close up."""
    p, n, uv, idx = m["pos"].copy(), m["nrm"].copy(), m["uv"].copy(), m["idx"]
    fn = np.cross(p[idx[:, 1]] - p[idx[:, 0]], p[idx[:, 2]] - p[idx[:, 0]])
    fz = fn[:, 2] / np.maximum(np.linalg.norm(fn, axis=1), 1e-12)
    zmin = p[:, 2].min()
    # The plate: back-facing faces within a sliver of the rear.
    plate = (fz < -0.6) & (p[idx][:, :, 2].max(1) < zmin + 0.012)
    idx = idx[~plate]
    used = np.unique(idx)
    remap = -np.ones(len(p), dtype=np.int64)
    remap[used] = np.arange(len(used))
    p, n, uv, idx = p[used], n[used], uv[used], remap[idx]

    # Mirror plane just behind the carved front.
    w = weld_ids(p)
    e = np.sort(np.concatenate([w[idx[:, [0, 1]]], w[idx[:, [1, 2]]], w[idx[:, [2, 0]]]]), axis=1)
    ue, cnt = np.unique(e, axis=0, return_counts=True)
    rim = np.isin(w, np.unique(ue[cnt == 1]))
    z0 = float(np.median(p[rim, 2]))
    # Pin the rim onto the plane and ease its neighbours, flatten anything behind.
    d = np.full(len(p), np.inf)
    rp = p[rim]
    for i in range(0, len(p), 512):
        blk = p[i:i + 512, None, :] - rp[None, :, :]
        d[i:i + 512] = np.sqrt((blk ** 2).sum(-1)).min(1)
    ease = np.clip(1.0 - d / 0.02, 0.0, 1.0) ** 2
    p[:, 2] = np.maximum(p[:, 2] + (z0 - p[:, 2]) * ease, z0)
    p[rim, 2] = z0
    # Rim normals lie in the plane so both halves shade into each other.
    n[rim, 2] = 0.0
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)

    q = p.copy()
    q[:, 2] = 2.0 * z0 - q[:, 2]
    qn = n.copy()
    qn[:, 2] = -qn[:, 2]
    pos = np.concatenate([p, q])
    nrm = np.concatenate([n, qn])
    uvs = np.concatenate([uv, uv])
    tris = np.concatenate([idx, idx[:, ::-1] + len(p)])
    # Centre the bud on its own middle, stem down.
    lo, hi = pos.min(0), pos.max(0)
    pos -= (lo + hi) * 0.5
    return pos, nrm, uvs, tris


def ground(m):
    """Plants stand on their own root at the origin."""
    p = m["pos"].copy()
    lo, hi = p.min(0), p.max(0)
    p[:, 0] -= (lo[0] + hi[0]) * 0.5
    p[:, 2] -= (lo[2] + hi[2]) * 0.5
    p[:, 1] -= lo[1]
    return p, m["nrm"], m["uv"], m["idx"]


def main():
    src_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    files = os.listdir(src_dir)
    for name, (prefix, ratio, tex_size, keep_normal) in SOURCES.items():
        src = os.path.join(src_dir, next(f for f in files if prefix in f and f.endswith(".glb")))
        m = read_glb(src)
        pos, nrm, uv, idx = round_bud(m) if name == "bud" else ground(m)
        pos, nrm, uv, idx = weld(pos, nrm, uv, idx)
        images = [(jpeg(m["base"], tex_size), "image/jpeg")]
        if keep_normal and m["normal"] is not None:
            images.append((png(m["normal"], tex_size // 2), "image/png"))
        with tempfile.TemporaryDirectory() as tmp:
            raw = os.path.join(tmp, "raw.glb")
            write_glb(raw, pos, nrm, uv, idx, images)
            out = os.path.join(out_dir, name + ".glb")
            subprocess.run(["npx", "--no-install", "gltfpack", "-i", raw, "-o", out, "-noq", "-kn", "-km",
                            "-si", str(ratio), "-se", "0.2"], check=True)
        print(name, "tris", len(idx), "->", read_glb(out)["idx"].shape[0])


if __name__ == "__main__":
    main()
