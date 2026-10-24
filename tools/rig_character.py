#!/usr/bin/env python3
"""Rebuilds a Meshy-rigged creature onto the Keling skeleton.

Meshy's "smart rig" invents a different skeleton for every creature: the
four new Kelings came back with four layouts (Lavender has no head bone at all,
Sunflower's forearm folds back on itself, Lavender's elbow sits on the wrist,
Toadstool's whole torso is one bone, finger counts go from four to five) and
skin weights that bleed across the body. Every animation, pose modifier and
prop in the game is written against the original Keling's bone names, so this
tool throws the Meshy skeleton away and builds the Keling's one in its place,
fitted to the new body:

  * joints are placed from the Meshy joints that are right, and set by hand
    where they are wrong or missing (see CHARACTERS),
  * skin weights are rebuilt from scratch: limbs are told apart from the body
    by connected mesh pieces and Meshy's limb weights, then weighted along
    the new bones with short blends at each joint; each twig finger follows
    its own chain (a fifth finger rides on the ring finger); the face moves
    rigidly with the head above a soft seam under the moustache; every small
    loose card (leaf, petal) moves as one piece so it never stretches,
  * the topper (sunflower, lavender spikes, toadstools, blossom twigs) gets
    spring-bone chains, driven at runtime by SpringBoneSimulator3D,
  * a "Root" bone at the feet carries root motion, like the original.

It also writes <id>_body.json next to the model: the trunk profile the
animation retargeter keeps the arms out of, plus the landmarks (mouth,
shoulders, work spot...) the rolling and smoking choreography is fitted to,
and the spring chains for the controller.

usage: python3 tools/rig_character.py <id> [<id>...]   (or "all")
  reads  art_source/characters/<id>_meshy.glb
  writes assets/characters/<id>/<id>.glb (+ textures, + <id>_body.json)
"""
import io, json, os, struct, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rig_keling import read_glb, q2m, m2q, local_mat, basis_y_along, accessor_array, seg_dist, components, smoothstep

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The original Keling's landmarks (skeleton space), which the rolling and
# smoking choreography was authored against. Each character lists its own.
KELING_LANDMARKS = {
    "mouth": [0.0, 0.835, 0.455],
    "work": [0.0, 0.725, 0.62],
    "shoulder_l": [0.289, 0.774, 0.149],
    "shoulder_r": [-0.282, 0.774, 0.149],
    "pouch_l": [0.27, 0.53, 0.34],
    "pouch_r": [-0.27, 0.53, 0.34],
}

# Joints are given in the Meshy model's own coordinates (metres, +Z forward,
# +X the creature's left) as a Meshy bone name, a point, or
# ["lerp", a, b, t]. Arms: Shoulder (collarbone), UpperArm, LowerArm, Hand.
# Fingers: Meshy chains base to tip; "Pinky" is skinned onto the ring finger.
CHARACTERS = {
    "blossom": {
        "name": "Blossom",
        "scale": 0.92,
        "torso": {"Hips": "Bone_000", "Pelvis": [0.0, 0.36, -0.01], "Spine": "Bone_003", "Chest": "Bone_002",
                  "UpperChest": [0.0, 0.76, 0.017], "Neck": [0.0, 0.86, 0.02], "Head": [0.0, 1.04, 0.03], "HeadTop": [0.0, 1.42, 0.0]},
        "head_seam": [0.8, 0.93], "neck_band": [0.68, 0.84],
        "arms": {
            "Left": {"joints": ["Bone_019", "Bone_018", "Bone_017", "Bone_016"],
                     "fingers": {"Thumb": ["Bone_042", "Bone_041", "Bone_040"], "Index": ["Bone_048", "Bone_047", "Bone_046"],
                                 "Middle": ["Bone_045", "Bone_044", "Bone_043"], "Ring": ["Bone_051", "Bone_050", "Bone_049"],
                                 "Pinky": ["Bone_039", "Bone_038", "Bone_037"]}},
            "Right": {"joints": ["Bone_024", "Bone_023", "Bone_022", "Bone_021"],
                      "fingers": {"Thumb": ["Bone_057", "Bone_056", "Bone_055"], "Index": ["Bone_060", "Bone_059", "Bone_058"],
                                  "Middle": ["Bone_063", "Bone_062", "Bone_061"], "Ring": ["Bone_066", "Bone_065", "Bone_064"],
                                  "Pinky": ["Bone_054", "Bone_053", "Bone_052"]}},
        },
        "legs": {"Left": ["Bone_011", "Bone_010", "Bone_009", "Bone_008"], "Right": ["Bone_007", "Bone_006", "Bone_005", "Bone_004"]},
        "mouth": [0.0, 0.965, 0.35],
        # Spring chains: name, joints (root to tip), skin radius.
        "springs": [
            ["Twig_L", [[0.15, 1.36, 0.02], [0.25, 1.5, 0.03], [0.37, 1.67, 0.05]], 0.07],
            ["Twig_R", [[-0.15, 1.39, 0.0], [-0.2, 1.53, -0.02], [-0.29, 1.68, -0.11]], 0.07],
        ],
        "spring_min_y": 1.3,
    },
    "sunflower": {
        "name": "Sunflower",
        "scale": 0.95,
        "torso": {"Hips": "Bone_000", "Pelvis": "Bone_001", "Spine": "Bone_004", "Chest": [0.0, 0.68, 0.02],
                  "UpperChest": [0.0, 0.78, 0.03], "Neck": [0.0, 0.85, 0.03], "Head": [0.0, 0.97, 0.03], "HeadTop": [0.0, 1.3, -0.03]},
        "head_seam": [0.66, 0.77], "neck_band": [0.58, 0.72],
        "arms": {
            # Meshy's Bone_018 doubles back from the elbow towards the body; it is dropped.
            "Left": {"joints": [[0.12, 0.9, -0.03], "Bone_020", "Bone_019", "Bone_029"],
                     "fingers": {"Thumb": ["Bone_032", "Bone_031", "Bone_030"], "Index": ["Bone_045", "Bone_044", "Bone_043", "Bone_042"],
                                 "Middle": ["Bone_053", "Bone_052", "Bone_051", "Bone_050"], "Ring": ["Bone_049", "Bone_048", "Bone_047", "Bone_046"],
                                 "Pinky": ["Bone_041", "Bone_040", "Bone_039", "Bone_038"]}},
            "Right": {"joints": [[-0.12, 0.9, -0.03], "Bone_025", "Bone_024", "Bone_034"],
                      "fingers": {"Thumb": ["Bone_037", "Bone_036", "Bone_035"], "Index": ["Bone_061", "Bone_060", "Bone_059", "Bone_058"],
                                  "Middle": ["Bone_069", "Bone_068", "Bone_067", "Bone_066"], "Ring": ["Bone_065", "Bone_064", "Bone_063", "Bone_062"],
                                  "Pinky": ["Bone_057", "Bone_056", "Bone_055", "Bone_054"]}},
        },
        "legs": {"Left": ["Bone_014", "Bone_013", "Bone_012", "Bone_011"], "Right": ["Bone_009", "Bone_008", "Bone_007", "Bone_006"]},
        "mouth": [0.0, 0.825, 0.36],
        "springs": [
            ["Sunflower", [[0.07, 1.36, 0.0], [0.11, 1.5, 0.03], [0.17, 1.67, 0.08]], 0.12],
            ["Daisy_L", [[-0.2, 1.3, 0.0], [-0.25, 1.36, -0.01], [-0.28, 1.41, -0.02]], 0.06],
            ["Daisy_B", [[-0.03, 1.36, -0.08], [-0.04, 1.43, -0.11], [-0.05, 1.5, -0.14]], 0.06],
        ],
        "spring_min_y": 1.28,
    },
    "lavender": {
        "name": "Lavender",
        "scale": 1.0,
        # Meshy gave this one no neck or head bones at all.
        "torso": {"Hips": "Bone_000", "Pelvis": "Bone_001", "Spine": "Bone_003", "Chest": [0.0, 0.6, -0.02],
                  "UpperChest": [0.0, 0.68, -0.03], "Neck": [0.0, 0.75, -0.03], "Head": [0.0, 0.88, -0.02], "HeadTop": [0.0, 1.25, -0.02]},
        "head_seam": [0.6, 0.75], "neck_band": [0.52, 0.68],
        "arms": {
            # Meshy put the elbow almost on the wrist; it goes back to mid-arm.
            "Left": {"joints": [[0.12, 0.74, -0.037], [0.28, 0.765, -0.037], ["lerp", [0.28, 0.765, -0.037], "Bone_015", 0.55], "Bone_015"],
                     "fingers": {"Thumb": ["Bone_037", "Bone_036", "Bone_035", "Bone_034"], "Index": ["Bone_045", "Bone_044", "Bone_043", "Bone_042"],
                                 "Middle": ["Bone_049", "Bone_048", "Bone_047", "Bone_046"], "Ring": ["Bone_041", "Bone_040", "Bone_039", "Bone_038"]}},
            "Right": {"joints": [[-0.12, 0.74, -0.037], [-0.28, 0.765, -0.037], ["lerp", [-0.28, 0.765, -0.037], "Bone_012", 0.55], "Bone_012"],
                      "fingers": {"Thumb": ["Bone_021", "Bone_020", "Bone_019", "Bone_018"], "Index": ["Bone_029", "Bone_028", "Bone_027", "Bone_026"],
                                  "Middle": ["Bone_033", "Bone_032", "Bone_031", "Bone_030"], "Ring": ["Bone_025", "Bone_024", "Bone_023", "Bone_022"]}},
        },
        "legs": {"Left": ["Bone_007", "Bone_006", "Bone_005", "Bone_004"], "Right": ["Bone_011", "Bone_010", "Bone_009", "Bone_008"]},
        "mouth": [0.0, 0.79, 0.35],
        "springs": [
            ["Spike_L", [[-0.11, 1.28, 0.0], [-0.13, 1.47, 0.01], [-0.15, 1.68, 0.03]], 0.09],
            ["Spike_C", [[0.0, 1.3, -0.02], [0.02, 1.5, 0.0], [0.04, 1.7, 0.03]], 0.09],
            ["Spike_R", [[0.11, 1.28, -0.02], [0.13, 1.45, -0.02], [0.14, 1.6, 0.0]], 0.09],
        ],
        "spring_min_y": 1.25,
    },
    "toadstool": {
        "name": "Toadstool",
        "scale": 0.86,
        # Meshy's torso is a single bone from the hips to the face.
        "torso": {"Hips": "Bone_000", "Pelvis": [0.0, 0.45, -0.04], "Spine": [0.0, 0.55, -0.04], "Chest": [0.0, 0.72, -0.05],
                  "UpperChest": [0.0, 0.87, -0.06], "Neck": [0.0, 0.95, -0.06], "Head": [0.0, 1.12, -0.04], "HeadTop": [0.0, 1.46, -0.05]},
        "head_seam": [0.84, 0.95], "neck_band": [0.74, 0.88],
        "arms": {
            "Left": {"joints": ["Bone_030", "Bone_029", "Bone_028", "Bone_027"],
                     "fingers": {"Thumb": ["Bone_054", "Bone_053", "Bone_052", "Bone_051"], "Index": ["Bone_058", "Bone_057", "Bone_056", "Bone_055"],
                                 "Middle": ["Bone_062", "Bone_061", "Bone_060", "Bone_059"], "Ring": ["Bone_050", "Bone_049", "Bone_048"]}},
            "Right": {"joints": ["Bone_035", "Bone_034", "Bone_033", "Bone_032"],
                      "fingers": {"Thumb": ["Bone_069", "Bone_068", "Bone_067", "Bone_066"], "Index": ["Bone_077", "Bone_076", "Bone_075", "Bone_074"],
                                  "Middle": ["Bone_073", "Bone_072", "Bone_071", "Bone_070"], "Ring": ["Bone_065", "Bone_064", "Bone_063"]}},
        },
        # Root feet: the front toe is the Keling's toe, side and back toes ride the foot.
        "legs": {"Left": ["Bone_009", "Bone_008", "Bone_007", "Bone_019"], "Right": ["Bone_005", "Bone_004", "Bone_003", "Bone_015"]},
        "mouth": [0.0, 1.06, 0.37],
        "springs": [
            ["Shroom_Big", [[0.12, 1.5, -0.02], [0.14, 1.6, -0.01], [0.15, 1.71, 0.0]], 0.11],
            ["Shroom_R", [[0.19, 1.44, 0.03], [0.22, 1.51, 0.05], [0.24, 1.57, 0.07]], 0.06],
            ["Shroom_L", [[-0.17, 1.5, 0.1], [-0.19, 1.58, 0.12], [-0.2, 1.65, 0.14]], 0.06],
        ],
        "spring_min_y": 1.42,
    },
}

ARM_BONES = ["Shoulder", "UpperArm", "LowerArm", "Hand"]
LEG_BONES = ["UpperLeg", "LowerLeg", "Foot", "Toes"]
TORSO = ["Hips", "Spine", "Chest", "UpperChest"]
FINGER_BONES = {"Thumb": ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal", "ThumbTip"],
                "Index": ["IndexMetacarpal", "IndexProximal", "IndexIntermediate", "IndexDistal", "IndexTip"],
                "Middle": ["MiddleMetacarpal", "MiddleProximal", "MiddleIntermediate", "MiddleDistal", "MiddleTip"],
                "Ring": ["RingMetacarpal", "RingProximal", "RingIntermediate", "RingDistal", "RingTip"]}
SMALL_PIECE = 60  # triangles: loose cards this small move as one piece


def write_glb(path, j, b):
    while len(b) % 4:
        b.append(0)
    j["buffers"] = [{"byteLength": len(b)}]
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(b)))
        f.write(struct.pack("<I4s", len(js), b"JSON")); f.write(js)
        f.write(struct.pack("<I4s", len(b), b"BIN\x00")); f.write(bytes(b))


class Builder:
    """A fresh glTF buffer: accessors and views appended as they are made."""

    def __init__(self):
        self.j = {"asset": {"version": "2.0", "generator": "weed-world tools/rig_character.py"},
                  "bufferViews": [], "accessors": []}
        self.b = bytearray()

    def view(self, data, target=None):
        while len(self.b) % 4:
            self.b.append(0)
        off = len(self.b)
        self.b += data
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        self.j["bufferViews"].append(v)
        return len(self.j["bufferViews"]) - 1

    def accessor(self, arr, ctype, atype, minmax=False, target=None):
        acc = {"bufferView": self.view(arr.tobytes(), target), "componentType": ctype, "count": len(arr), "type": atype}
        if minmax:
            acc["min"] = arr.min(0).tolist(); acc["max"] = arr.max(0).tolist()
        self.j["accessors"].append(acc)
        return len(self.j["accessors"]) - 1


def main(cid):
    cfg = CHARACTERS[cid]
    src = os.path.join(ROOT, "art_source/characters/%s_meshy.glb" % cid)
    out_dir = os.path.join(ROOT, "assets/characters", cid)
    os.makedirs(out_dir, exist_ok=True)
    j, b = read_glb(src)
    nodes = j["nodes"]
    S = float(cfg.get("scale", 1.0))
    by_name = {n.get("name"): i for i, n in enumerate(nodes)}
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

    def mpos(name):  # Meshy joint, scaled
        return world(by_name[name])[:3, 3] * S

    def pt(spec):
        if isinstance(spec, str):
            return mpos(spec)
        if isinstance(spec, list) and spec and spec[0] == "lerp":
            a, c = pt(spec[1]), pt(spec[2])
            return a + (c - a) * spec[3]
        return np.array(spec, float) * S

    def descendants(name):
        out = [by_name[name]]
        k = 0
        while k < len(out):
            out += nodes[out[k]].get("children", [])
            k += 1
        return out

    prim = j["meshes"][0]["primitives"][0]
    P, _ = accessor_array(j, b, prim["attributes"]["POSITION"])
    P = P.astype(np.float64) * S
    N, _ = accessor_array(j, b, prim["attributes"]["NORMAL"])
    UV, _ = accessor_array(j, b, prim["attributes"]["TEXCOORD_0"])
    MJ, _ = accessor_array(j, b, prim["attributes"]["JOINTS_0"])
    MW, _ = accessor_array(j, b, prim["attributes"]["WEIGHTS_0"])
    I, _ = accessor_array(j, b, prim["indices"])
    I = I.reshape(-1, 3).astype(np.int64)
    nv = len(P)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    skin = j["skins"][0]
    meshy_joints = skin["joints"]
    col_of_node = {k: c for c, k in enumerate(meshy_joints)}

    # Meshy limb weight per vertex, by side.
    Wm = np.zeros((nv, len(meshy_joints)))
    np.add.at(Wm, (np.repeat(np.arange(nv), 4), MJ.reshape(-1).astype(int)), MW.reshape(-1))

    def region_weight(root_names):
        cols = set()
        for r in root_names:
            for nd in descendants(r):
                if nd in col_of_node:
                    cols.add(col_of_node[nd])
        return Wm[:, sorted(cols)].sum(1)

    # ---- the skeleton -------------------------------------------------------
    J = {}  # name -> position
    for k, v in cfg["torso"].items():
        J[k] = pt(v)
    J["Root"] = np.zeros(3)
    knuckles = {}
    finger_chains = {}  # side -> finger -> [joint positions incl. tip]
    for side, arm in cfg["arms"].items():
        for name, spec in zip(ARM_BONES, arm["joints"]):
            J[side + name] = pt(spec)
        finger_chains[side] = {}
        for finger, chain in arm["fingers"].items():
            finger_chains[side][finger] = [mpos(n) for n in chain]
        knuckles[side] = np.mean([finger_chains[side][f][0] for f in ("Index", "Middle", "Ring")], 0)
        J[side + "Palm"] = J[side + "Hand"] + (knuckles[side] - J[side + "Hand"]) * 0.25
    for side, leg in cfg["legs"].items():
        for name, spec in zip(LEG_BONES, leg):
            J[side + name] = pt(spec)

    # Mesh pieces, and which side's arm/leg each vertex belongs to.
    tri_comp = components(P, I)
    comp_ids, comp_tris = np.unique(tri_comp, return_counts=True)
    comp_size = dict(zip(comp_ids, comp_tris))
    vert_comp = np.full(nv, -1)
    vert_comp[I.reshape(-1)] = np.repeat(tri_comp, 3)
    main_comp = int(comp_ids[np.argmax(comp_tris)])

    def limb_membership(raw, lo, hi):
        """Sharpened limb weight; whole pieces that mostly belong go along."""
        keep = smoothstep(lo, hi, raw)
        for c in comp_ids:
            if c == main_comp or comp_size[c] < 40:
                continue
            m = vert_comp == c
            if raw[m].mean() > 0.6:
                keep[m] = 1.0
            elif raw[m].mean() < 0.25:
                keep[m] = 0.0
        return keep

    arm_mem, leg_mem = {}, {}
    for side, arm in cfg["arms"].items():
        root = [n for n in arm["joints"] if isinstance(n, str)]
        roots = [root[0]] + [arm["fingers"]["Thumb"][0]]
        arm_mem[side] = limb_membership(region_weight(roots), 0.6, 0.92)
    for side, leg in cfg["legs"].items():
        leg_mem[side] = limb_membership(region_weight([leg[0]]), 0.55, 0.9)

    # Fingertips: run along the last segment until the twig ends.
    for side in finger_chains:
        hand = J[side + "Hand"]
        region = arm_mem[side] > 0.5
        fdir = knuckles[side] - hand
        fdir /= np.linalg.norm(fdir)
        past = ((P - hand) @ fdir) > 0.0
        HP = P[region & past]
        for finger, ch in finger_chains[side].items():
            d = ch[-1] - ch[-2]
            d /= np.linalg.norm(d)
            rel = HP - ch[-1]
            along = rel @ d
            radial = np.linalg.norm(rel - along[:, None] * d, axis=1)
            near = (along > 0) & (radial < 0.022 * max(S, 0.8))
            ext = float(np.percentile(along[near], 98)) if near.sum() > 5 else 0.012
            ch.append(ch[-1] + d * np.clip(ext, 0.008, 0.06))

    for side, fingers in finger_chains.items():
        palm = J[side + "Palm"]
        th = fingers["Thumb"]
        J[side + "ThumbMetacarpal"], J[side + "ThumbProximal"], J[side + "ThumbDistal"], J[side + "ThumbTip"] = th[0], th[1], th[2], th[-1]
        for f in ("Index", "Middle", "Ring"):
            ch = fingers[f]
            J[side + f + "Metacarpal"] = palm + (ch[0] - palm) * 0.45
            J[side + f + "Proximal"] = ch[0]
            J[side + f + "Intermediate"] = ch[1]
            J[side + f + "Distal"] = ch[2] if len(ch) > 4 else ch[-2]
            J[side + f + "Tip"] = ch[-1]
    for side in cfg["legs"]:
        ankle, toe = J[side + "Foot"], J[side + "Toes"]
        d = toe - ankle
        d[1] = 0.0
        d /= np.linalg.norm(d)
        foot = (leg_mem[side] > 0.5) & (y < toe[1] + 0.05)
        along = (P[foot] - toe) @ d
        J[side + "ToesEnd"] = toe + d * float(np.clip(np.percentile(along, 99), 0.02, 0.12))
        J[side + "ToesEnd"][1] = max(toe[1] * 0.9, 0.012)

    # Hierarchy (the Keling's).
    PARENT = {"Hips": "Root", "Pelvis": "Hips", "Spine": "Pelvis", "Chest": "Spine", "UpperChest": "Chest",
              "Neck": "UpperChest", "Head": "Neck", "HeadTop": "Head"}
    for s in ("Left", "Right"):
        PARENT.update({s + "Shoulder": "UpperChest", s + "UpperArm": s + "Shoulder", s + "LowerArm": s + "UpperArm",
                       s + "Hand": s + "LowerArm", s + "Palm": s + "Hand",
                       s + "UpperLeg": "Pelvis", s + "LowerLeg": s + "UpperLeg", s + "Foot": s + "LowerLeg",
                       s + "Toes": s + "Foot", s + "ToesEnd": s + "Toes"})
        for f, names in FINGER_BONES.items():
            prev = s + "Palm"
            for n in names:
                PARENT[s + n] = prev
                prev = s + n
    springs = []
    for name, pts, radius in cfg["springs"]:
        pts = [np.array(p, float) * S for p in pts]
        J[name + "_1"], J[name + "_2"] = pts[0], pts[1]
        PARENT[name + "_1"] = "Head"
        PARENT[name + "_2"] = name + "_1"
        springs.append((name, pts, radius * S))
    # Main child of each bone (its +Y points there).
    AIM = {"Root": "Hips", "Hips": "Spine", "Pelvis": "Spine", "Spine": "Chest", "Chest": "UpperChest",
           "UpperChest": "Neck", "Neck": "Head", "Head": "HeadTop"}
    for s in ("Left", "Right"):
        AIM.update({s + "Shoulder": s + "UpperArm", s + "UpperArm": s + "LowerArm", s + "LowerArm": s + "Hand",
                    s + "Hand": s + "MiddleProximal", s + "Palm": s + "MiddleProximal",
                    s + "UpperLeg": s + "LowerLeg", s + "LowerLeg": s + "Foot", s + "Foot": s + "Toes", s + "Toes": s + "ToesEnd"})
        for f, names in FINGER_BONES.items():
            for a, c in zip(names[:-1], names[1:]):
                AIM[s + a] = s + c
    for name, pts, _r in springs:
        AIM[name + "_1"] = name + "_2"

    order = ["Root"]
    k = 0
    while k < len(order):
        for c, p in PARENT.items():
            if p == order[k]:
                order.append(c)
        k += 1
    assert set(order) == set(J), set(J) ^ set(order)
    bone_index = {n: i for i, n in enumerate(order)}

    def bone_basis(n):
        if n in AIM:
            d = J[AIM[n]] - J[n]
        elif n.endswith("_2"):
            spr = next(s for s in springs if n == s[0] + "_2")
            d = spr[1][2] - spr[1][1]
        else:
            p = PARENT[n]
            d = J[n] - J[p]
        if np.linalg.norm(d) < 1e-5:
            d = np.array([0.0, 1.0, 0.0])
        return basis_y_along(d)

    Gw = {}
    for n in order:
        M = np.eye(4)
        M[:3, :3] = bone_basis(n) if n != "Root" else np.eye(3)
        M[:3, 3] = J[n]
        Gw[n] = M

    # ---- skin weights -------------------------------------------------------
    nb = len(order)
    W = np.zeros((nv, nb))

    def col(n):
        return bone_index[n]

    def chain_weights(pts, bones, blends, sel):
        """Weights along a joint polyline: nearest segment, eased across joints."""
        Q = P[sel]
        best = np.full(len(Q), np.inf)
        seg = np.zeros(len(Q), int)
        tt = np.zeros(len(Q))
        for k in range(len(pts) - 1):
            d, t = seg_dist(Q, pts[k], pts[k + 1])
            if k == len(pts) - 2:  # the last segment runs on past its end
                ab = pts[k + 1] - pts[k]
                t = ((Q - pts[k]) @ ab) / (ab @ ab)
                t = np.maximum(t, 0.0)
                d = np.linalg.norm(Q - (pts[k] + np.minimum(t, 1.0)[:, None] * ab), axis=1)
            better = d < best - 1e-9
            best[better] = d[better]; seg[better] = k; tt[better] = t[better]
        out = np.zeros((len(Q), nb))
        for k in range(len(pts) - 1):
            m = seg == k
            L = np.linalg.norm(pts[k + 1] - pts[k])
            s = tt[m] * L  # metres along the segment
            w_self = np.ones(m.sum())
            if k > 0:  # blend with the previous bone near this segment's start
                h = blends[k - 1]
                prev = 0.5 * (1 - smoothstep(0.0, h, s))
                out[np.where(m)[0], col(bones[k - 1])] += prev
                w_self -= prev
            if k < len(pts) - 2:  # and with the next near its end
                h = blends[k]
                nxt = 0.5 * smoothstep(L - h, L, s)
                out[np.where(m)[0], col(bones[k + 1])] += nxt
                w_self -= nxt
            out[np.where(m)[0], col(bones[k])] += w_self
        return out

    # Core: by height along the torso, then the neck band and the rigid head.
    hs = [J[n][1] for n in TORSO]
    core = np.zeros((nv, nb))
    yy = np.clip(y, hs[0], hs[-1])
    for i in range(len(TORSO) - 1):
        m = (yy >= hs[i]) & (yy <= hs[i + 1])
        t = smoothstep(hs[i], hs[i + 1], yy[m])
        core[m, col(TORSO[i])] += 1 - t
        core[m, col(TORSO[i + 1])] += t
    head = smoothstep(*cfg["head_seam"], y)
    neck = smoothstep(*cfg["neck_band"], y) * (1 - head)
    core *= (1 - head - neck)[:, None]
    core[:, col("Head")] += head
    core[:, col("Neck")] += neck

    # Arms: shoulder to wrist along the chain; past the wrist each finger its own.
    limb_total = np.zeros(nv)
    for side in cfg["arms"]:
        mem = arm_mem[side]
        sel = mem > 1e-3
        pts = [J[side + n] for n in ARM_BONES] + [knuckles[side]]
        aw = chain_weights(pts, [side + n for n in ARM_BONES], [0.03, 0.04, 0.025], sel)
        # Fingers.
        hand = J[side + "Hand"]
        fdir = (knuckles[side] - hand) / np.linalg.norm(knuckles[side] - hand)
        Q = P[sel]
        past = (Q - hand) @ fdir
        fbest = np.full(len(Q), np.inf)
        fw_best = np.zeros((len(Q), nb))
        fmember = np.zeros(len(Q))
        for finger, ch in finger_chains[side].items():
            target = "Ring" if finger == "Pinky" else finger
            names = FINGER_BONES[target]
            if target == "Thumb":
                pts_f = ch[:3] + [ch[-1]]
                bones_f = [side + n for n in names[:3]]
            else:
                pts_f = [ch[0], ch[1], ch[2] if len(ch) > 4 else ch[-2], ch[-1]]
                bones_f = [side + n for n in names[1:4]]
            # Distance to this finger and position along it.
            dmin = np.full(len(Q), np.inf); segk = np.zeros(len(Q), int); tseg = np.zeros(len(Q))
            for k in range(len(pts_f) - 1):
                d, t = seg_dist(Q, pts_f[k], pts_f[k + 1])
                better = d < dmin
                dmin[better] = d[better]; segk[better] = k; tseg[better] = t[better]
            a0, a1 = pts_f[0], pts_f[1]
            along0 = ((Q - a0) @ (a1 - a0)) / np.linalg.norm(a1 - a0)
            rad = 0.02 * max(S, 0.8)
            m = smoothstep(-0.008, 0.01, along0) * smoothstep(rad * 1.5, rad * 0.8, dmin)
            fw = np.zeros((len(Q), nb))
            for k in range(len(pts_f) - 1):
                s_ = segk == k
                t = tseg[s_]
                nxt = smoothstep(0.75, 1.0, t) * 0.5 if k < len(pts_f) - 2 else np.zeros_like(t)
                prv = smoothstep(0.25, 0.0, t) * 0.5 if k > 0 else np.zeros_like(t)
                fw[s_, col(bones_f[k])] += 1 - nxt - prv
                if k < len(pts_f) - 2:
                    fw[s_, col(bones_f[k + 1])] += nxt
                if k > 0:
                    fw[s_, col(bones_f[k - 1])] += prv
            closer = dmin < fbest
            fbest[closer] = dmin[closer]; fw_best[closer] = fw[closer]; fmember[closer] = m[closer]
        in_hand = smoothstep(-0.01, 0.02, past)
        fm = (fmember * in_hand)[:, None]
        aw = fm * fw_best + (1 - fm) * aw
        W[sel] += aw * mem[sel, None]
        limb_total += mem
    for side in cfg["legs"]:
        mem = leg_mem[side]
        sel = mem > 1e-3
        pts = [J[side + n] for n in LEG_BONES] + [J[side + "ToesEnd"]]
        lw = chain_weights(pts, [side + n for n in LEG_BONES], [0.035, 0.025, 0.015], sel)
        W[sel] += lw * mem[sel, None]
        limb_total += mem
    norm = np.maximum(limb_total, 1.0)
    W /= norm[:, None]
    W += core * np.clip(1 - limb_total / norm, 0, 1)[:, None]

    # Topper springs: loose pieces on top follow their nearest chain.
    small = np.array([comp_size.get(c, 0) for c in vert_comp]) < 400
    loose = (vert_comp != main_comp) & small & (y > cfg["spring_min_y"] * S) & (limb_total < 0.05)
    ks, ts = [], []
    for name, pts, radius in springs:
        d1, t1 = seg_dist(P, pts[0], pts[1])
        d2, t2 = seg_dist(P, pts[1], pts[2])
        d = np.minimum(d1, d2)
        s = np.where(d1 <= d2, 0.5 * t1, 0.5 + 0.5 * t2)
        ks.append(np.exp(-(d / radius) ** 2))
        ts.append(s)
    ks = np.array(ks)
    reach = ks.max(0)
    sp = np.zeros(nv)
    if len(springs):
        sp = loose * smoothstep(0.15, 0.5, reach)
        kn = ks / np.maximum(ks.sum(0), 1e-9)
        W *= (1 - sp)[:, None]
        for c, (name, pts, radius) in enumerate(springs):
            upper = smoothstep(0.3, 0.7, ts[c])
            W[:, col(name + "_1")] += sp * kn[c] * (1 - upper)
            W[:, col(name + "_2")] += sp * kn[c] * upper

    # Small loose cards move as one piece (no stretched leaves).
    for c in comp_ids:
        if c == main_comp or comp_size[c] > SMALL_PIECE:
            continue
        m = vert_comp == c
        W[m] = W[m].mean(0)

    top = np.argsort(-W, axis=1)[:, :4]
    tw = np.take_along_axis(W, top, 1)
    tw /= np.maximum(tw.sum(1, keepdims=True), 1e-9)
    J4 = top.astype(np.uint8)
    W4 = tw.astype(np.float32)
    unweighted = (W.sum(1) < 0.5).sum()

    # ---- body profile and landmarks ------------------------------------------
    limb_any = limb_total
    trunk = (limb_any < 0.15) & (y < J["Head"][1] + 0.3)
    profile = []
    for h in np.arange(J["Hips"][1] * 0.5, J["Head"][1] + 0.1, 0.02):
        m = trunk & (np.abs(y - h) < 0.015)
        if m.sum() < 8:
            continue
        profile.append([round(float(h), 3), round(float(np.percentile(np.abs(x[m]), 95)), 4),
                        round(float(np.percentile(z[m], 97)), 4), round(float(np.percentile(z[m], 3)), 4)])
    prof = np.array(profile)
    for c in (1, 2, 3):
        prof[:, c] = [np.median(prof[max(0, i - 2):i + 3, c]) for i in range(len(prof))]
    prof[:, 3] = np.minimum(prof[:, 3], -0.12)

    def body_at(h):
        k = int(np.clip(np.searchsorted(prof[:, 0], h), 1, len(prof) - 1))
        f = (h - prof[k - 1, 0]) / (prof[k, 0] - prof[k - 1, 0])
        return prof[k - 1] + (prof[k] - prof[k - 1]) * np.clip(f, 0, 1)

    mouth = np.array(cfg["mouth"], float) * S
    arm_len = np.linalg.norm(J["LeftLowerArm"] - J["LeftUpperArm"]) + np.linalg.norm(J["LeftHand"] - J["LeftLowerArm"])
    hand_len = np.linalg.norm(J["LeftMiddleTip"] - J["LeftHand"])
    sh_l, sh_r = J["LeftUpperArm"], J["RightUpperArm"]
    # Work spot: in front of the belly below the mouth, where both pinches meet.
    wy = mouth[1] - 0.11
    wz = max(body_at(wy)[2] + 0.13, mouth[2] + 0.12)
    work = np.array([0.0, wy, wz])
    pinch_reach = arm_len + hand_len * 0.75
    for _ in range(40):
        if max(np.linalg.norm(work - sh_l), np.linalg.norm(work - sh_r)) <= pinch_reach * 0.98:
            break
        work[2] -= 0.01
        work[1] -= 0.003
    py = J["Hips"][1] + 0.2
    pb = body_at(py)
    pouch_l = np.array([pb[1] * 0.85, py, pb[2] * 0.75])
    landmarks = {"mouth": mouth, "work": work, "shoulder_l": sh_l, "shoulder_r": sh_r,
                 "pouch_l": pouch_l, "pouch_r": pouch_l * np.array([-1, 1, 1])}
    keling_leg = 0.146 + 0.087  # original thigh + shin
    leg = np.linalg.norm(J["LeftLowerLeg"] - J["LeftUpperLeg"]) + np.linalg.norm(J["LeftFoot"] - J["LeftLowerLeg"])
    body = {
        "columns": ["y", "half_width", "front_z", "back_z"],
        "rows": np.round(prof, 4).tolist(),
        "landmarks": {k: np.round(v, 4).tolist() for k, v in landmarks.items()},
        # name, tip length, stiffness: the big heavy toppers sway slower.
        "springs": [[name, round(float(np.linalg.norm(pts[2] - pts[1])), 3), 1.1 if r >= 0.1 * S else 1.5] for name, pts, r in springs],
        "height": round(float(P[:, 1].max()), 3),
        "arm_length": round(float(arm_len), 3),
        "leg_length": round(float(leg), 3),
    }
    with open(os.path.join(out_dir, cid + "_body.json"), "w") as fh:
        json.dump(body, fh, indent=1)

    # ---- write the new glTF -------------------------------------------------
    B = Builder()
    gj = B.j
    # Images: re-encode as JPEG files beside the model (Godot extracts them anyway).
    images = []
    for k, im in enumerate(j["images"]):
        bv = j["bufferViews"][im["bufferView"]]
        data = bytes(b[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])
        images.append({"bufferView": B.view(data), "mimeType": im.get("mimeType", "image/jpeg"), "name": im.get("name", "Image_%d" % k)})
    gj["images"] = images
    gj["samplers"] = j.get("samplers", [{}])
    gj["textures"] = j["textures"]
    mat = json.loads(json.dumps(j["materials"][0]))
    mat["name"] = cid.capitalize()
    gj["materials"] = [mat]
    attrs = {
        "POSITION": B.accessor(P.astype(np.float32), 5126, "VEC3", True, 34962),
        "NORMAL": B.accessor(N.astype(np.float32), 5126, "VEC3", False, 34962),
        "TEXCOORD_0": B.accessor(UV.astype(np.float32), 5126, "VEC2", False, 34962),
        "JOINTS_0": B.accessor(J4, 5121, "VEC4", False, 34962),
        "WEIGHTS_0": B.accessor(W4, 5126, "VEC4", False, 34962),
    }
    idx = I.reshape(-1).astype(np.uint16 if nv < 65536 else np.uint32)
    gj["meshes"] = [{"name": cid.capitalize(), "primitives": [{"attributes": attrs, "material": 0,
                     "indices": B.accessor(idx, 5123 if nv < 65536 else 5125, "SCALAR", False, 34963)}]}]
    gnodes = []
    for n in order:
        p = PARENT.get(n)
        Ml = (np.linalg.inv(Gw[p]) @ Gw[n]) if p else Gw[n]
        R = Ml[:3, :3] / np.linalg.norm(Ml[:3, :3], axis=0)
        gnodes.append({"name": n, "translation": [float(v) for v in Ml[:3, 3]], "rotation": [float(v) for v in m2q(R)]})
    for n in order:
        kids = [bone_index[c] for c in order if PARENT.get(c) == n]
        if kids:
            gnodes[bone_index[n]]["children"] = kids
    mesh_node = len(gnodes)
    gnodes.append({"name": cid.capitalize(), "mesh": 0, "skin": 0})
    arm_node = len(gnodes)
    gnodes.append({"name": "SmartRigArmature", "children": [mesh_node, bone_index["Root"]]})
    gj["nodes"] = gnodes
    ibm = np.array([np.linalg.inv(Gw[n]).T.reshape(-1) for n in order], np.float32)
    gj["skins"] = [{"joints": list(range(len(order))), "inverseBindMatrices": B.accessor(ibm, 5126, "MAT4"), "skeleton": bone_index["Root"]}]
    gj["scenes"] = [{"name": "Scene", "nodes": [arm_node]}]
    gj["scene"] = 0
    write_glb(os.path.join(out_dir, cid + ".glb"), gj, B.b)
    print("%s: %d verts, %d tris, %d bones, %d unweighted, %d spring verts, height %.2f, arm %.2f, leg %.2f"
          % (cid, nv, len(I), nb, unweighted, int((sp > 0.01).sum()) if len(springs) else 0, P[:, 1].max(), arm_len, leg))
    print("   landmarks", {k: np.round(v, 3).tolist() for k, v in landmarks.items()})


if __name__ == "__main__":
    ids = sys.argv[1:] or ["all"]
    if ids == ["all"]:
        ids = list(CHARACTERS)
    for cid in ids:
        main(cid)
