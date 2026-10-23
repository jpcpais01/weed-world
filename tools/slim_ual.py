#!/usr/bin/env python3
"""Builds a slim animation GLB from Quaternius' Universal Animation Library (CC0).

Keeps the mannequin skeleton + mesh and only the clips the game uses, merging
clips from UAL1 and UAL2 (both share an identical skeleton).

Turn clips are taken from the root-motion (_RM) exports so their yaw survives.

usage: python3 tools/slim_ual.py UAL1.glb UAL2.glb UAL1_RM.glb UAL2_RM.glb art_source/ual_keling_clips.glb
"""
import json, struct, sys

UAL1_CLIPS = [
    "Idle_Loop", "Idle_LookAround_Loop", "Walk_Loop", "Jog_Fwd_Loop",
    "Jog_Fwd_LeanL_Loop", "Jog_Fwd_LeanR_Loop", "Sprint_Loop", "Sprint_Exit",
    "Jump_Start", "Jump_Loop", "Jump_Land",
    "Dance_Loop", "Celebration", "GroundSit_Enter", "GroundSit_Idle_Loop",
    "GroundSit_Exit",
]
UAL2_CLIPS = ["Idle_FoldArms_Loop", "Surprise", "Yes"]
UAL1_RM_CLIPS = ["Turn90_L", "Turn90_R"]
UAL2_RM_CLIPS = ["Turn180_L", "Turn180_R"]


def read_glb(path):
    d = open(path, "rb").read()
    assert d[:4] == b"glTF"
    jl = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", d[off:off + 4])[0]
    return j, d[off + 8:off + 8 + bl]


class Writer:
    def __init__(self):
        self.buf = bytearray()
        self.views, self.accessors = [], []

    def add_accessor(self, src_j, src_bin, ai):
        a = dict(src_j["accessors"][ai])
        bv = src_j["bufferViews"][a["bufferView"]]
        start = bv.get("byteOffset", 0)
        data = src_bin[start:start + bv["byteLength"]]
        while len(self.buf) % 4:
            self.buf.append(0)
        nv = {"buffer": 0, "byteOffset": len(self.buf), "byteLength": len(data)}
        if "byteStride" in bv:
            nv["byteStride"] = bv["byteStride"]
        if "target" in bv:
            nv["target"] = bv["target"]
        self.buf += data
        self.views.append(nv)
        a["bufferView"] = len(self.views) - 1
        self.accessors.append(a)
        return len(self.accessors) - 1


def main(ual1, ual2, ual1_rm, ual2_rm, out):
    j1, b1 = read_glb(ual1)
    j2, b2 = read_glb(ual2)
    w = Writer()
    out_j = {k: v for k, v in j1.items() if k not in ("accessors", "bufferViews", "buffers", "animations")}
    out_j["meshes"] = json.loads(json.dumps(j1["meshes"]))
    for m in out_j["meshes"]:
        for p in m["primitives"]:
            p["attributes"] = {k: w.add_accessor(j1, b1, v) for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = w.add_accessor(j1, b1, p["indices"])
            p.pop("targets", None)
    out_j["skins"] = json.loads(json.dumps(j1["skins"]))
    for s in out_j["skins"]:
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = w.add_accessor(j1, b1, s["inverseBindMatrices"])

    name_to_node = {n.get("name"): i for i, n in enumerate(j1["nodes"])}
    anims = []

    def take(src_j, src_bin, names):
        by_name = {a["name"]: a for a in src_j["animations"]}
        for nm in names:
            a = by_name[nm]
            samplers = []
            for s in a["samplers"]:
                samplers.append({"input": w.add_accessor(src_j, src_bin, s["input"]),
                                 "output": w.add_accessor(src_j, src_bin, s["output"]),
                                 "interpolation": s.get("interpolation", "LINEAR")})
            chans = []
            for c in a["channels"]:
                node_name = src_j["nodes"][c["target"]["node"]].get("name")
                chans.append({"sampler": c["sampler"],
                              "target": {"node": name_to_node[node_name], "path": c["target"]["path"]}})
            anims.append({"name": nm, "samplers": samplers, "channels": chans})

    take(j1, b1, UAL1_CLIPS)
    take(j2, b2, UAL2_CLIPS)
    take(*read_glb(ual1_rm), UAL1_RM_CLIPS)
    take(*read_glb(ual2_rm), UAL2_RM_CLIPS)
    out_j["animations"] = anims
    out_j["accessors"] = w.accessors
    out_j["bufferViews"] = w.views
    out_j["buffers"] = [{"byteLength": len(w.buf)}]
    out_j["asset"]["extras"] = {"source": "Quaternius Universal Animation Library 1+2 (CC0 1.0)"}
    js = json.dumps(out_j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    while len(w.buf) % 4:
        w.buf.append(0)
    total = 12 + 8 + len(js) + 8 + len(w.buf)
    with open(out, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON")); f.write(js)
        f.write(struct.pack("<I4s", len(w.buf), b"BIN\x00")); f.write(w.buf)
    print(f"wrote {out}: {len(anims)} clips, {total/1e6:.2f} MB")


if __name__ == "__main__":
    main(*sys.argv[1:6])
