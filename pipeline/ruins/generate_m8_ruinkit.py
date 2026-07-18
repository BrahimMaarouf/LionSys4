"""M8 modular ruin kit — math-authored meshes and textures, no DCC required.

Generates the socket-grammar ruin pieces as deterministic geometry and packs
them into assets/export/M8RuinKit.glb for upload through Roblox Studio's 3D
Importer (the project's proven path). Each piece node contains a render mesh
(PIECE_LOD0) and a simplified collision proxy (PIECE_COL). A stone texture set
(M8_Stone_*) is generated alongside and referenced by every render mesh.

Pieces (sizes in studs, ground pivot at node origin):
  WallSegment   8.0 x 6.0 x 1.2   weathered block wall, jagged top
  WallDoorway   8.0 x 6.0 x 1.2   wall with 3.0 x 4.5 opening
  WallBroken    8.0 x ~3.2 x 1.2  collapsed half wall, strongly jagged
  CornerPost    1.6 x 6.2 x 1.6   corner pier
  Pillar        1.8 dia x 5.6     tapered column
  PillarBroken  1.8 dia x ~2.8    snapped column stump
  RubblePile    ~6 x 1.8 x ~6     scattered block heap
  FloorSlab     4.0 x 0.4 x 4.0   cracked paving slab

Run:  python3 pipeline/ruins/generate_m8_ruinkit.py
"""

import math
import os
import sys

import numpy as np
from PIL import Image
from pygltflib import (
    GLTF2, Accessor, Asset, Buffer, BufferView, Image as GltfImage, Material,
    Mesh, Node, NormalMaterialTexture, PbrMetallicRoughness, Primitive, Sampler,
    Scene, Texture, TextureInfo,
)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEXTURE_DIR = os.path.join(ROOT, "assets", "textures")
EXPORT_PATH = os.path.join(ROOT, "assets", "export", "M8RuinKit.glb")

sys.path.insert(0, os.path.join(ROOT, "pipeline", "textures"))
from generate_m7_textures import clamp01, fbm, height_to_normal, save_rgba, _hash01  # noqa: E402

FLOAT = 5126
USHORT = 5123
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963


# ------------------------------------------------------------ stone texture

def make_stone_set(size=256):
    """Sandstone block courses with recessed mortar, matching the desert palette."""
    course_h = 1.0 / 6.0
    base, height, rough = [], [], []
    for y in range(size):
        for x in range(size):
            u, v = (x + 0.5) / size, (y + 0.5) / size
            course = int(v / course_h)
            offset = 0.5 * (course % 2)
            block_w = 1.0 / 3.0
            bu = (u + offset * block_w) % block_w / block_w
            bv = (v % course_h) / course_h
            mortar = 1.0 if (bu < 0.045 or bu > 0.955 or bv < 0.07 or bv > 0.93) else 0.0
            block_id = course * 7 + int((u + offset * block_w) / block_w)
            tint = _hash01(block_id, 3, 800) * 0.16 - 0.08
            grain = fbm(u, v, 810, octaves=4, base_freq=9) - 0.5
            chip = clamp01((fbm(u, v, 811, octaves=3, base_freq=6) - 0.66) * 3.0)
            tone = clamp01(0.55 + tint + grain * 0.18 - mortar * 0.24 - chip * 0.2)
            r = clamp01(tone * (0.92 + tint))
            g = clamp01(tone * 0.78)
            b = clamp01(tone * 0.58)
            base.append((int(r * 255), int(g * 255), int(b * 255), 255))
            height.append(clamp01(0.55 + grain * 0.3 - mortar * 0.5 - chip * 0.4))
            rv = clamp01(0.78 + grain * 0.2 + mortar * 0.1)
            rough.append((int(rv * 255),) * 3 + (255,))
    save_rgba("M8_Stone_BaseColor", base, size)
    save_rgba("M8_Stone_Normal", height_to_normal(height, size, 2.4), size)
    save_rgba("M8_Stone_Roughness", rough, size)


# ------------------------------------------------------------ mesh helpers

class MeshBuilder:
    def __init__(self):
        self.positions = []
        self.normals = []
        self.uvs = []
        self.indices = []

    def quad(self, a, b, c, d, normal, uv_scale=(1.0, 1.0), uv_offset=(0.0, 0.0)):
        """Adds quad a-b-c-d (counter-clockwise when viewed from outside)."""
        start = len(self.positions)
        au, av = uv_offset
        su, sv = uv_scale
        self.positions += [a, b, c, d]
        self.normals += [normal] * 4
        self.uvs += [(au, av), (au + su, av), (au + su, av + sv), (au, av + sv)]
        self.indices += [start, start + 2, start + 1, start, start + 3, start + 2]

    def box(self, center, size, seed=0, top_jag=0.0, jag_segments=6, uv_density=0.14):
        """Axis-aligned box; optional jagged top edge (displaces top face down)."""
        cx, cy, cz = center
        sx, sy, sz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
        us = (size[0] * uv_density, size[1] * uv_density)
        vs = (size[2] * uv_density, size[1] * uv_density)
        hs = (size[0] * uv_density, size[2] * uv_density)

        if top_jag <= 0.0:
            x0, x1 = cx - sx, cx + sx
            y0, y1 = cy - sy, cy + sy
            z0, z1 = cz - sz, cz + sz
            self.quad((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (0, 0, 1), us)
            self.quad((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (0, 0, -1), us)
            self.quad((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (1, 0, 0), vs)
            self.quad((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (-1, 0, 0), vs)
            self.quad((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0), (0, 1, 0), hs)
            self.quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (0, -1, 0), hs)
            return

        # jagged: build side walls as vertical strips with varying top height
        x0, x1 = cx - sx, cx + sx
        y0 = cy - sy
        z0, z1 = cz - sz, cz + sz
        tops = []
        for i in range(jag_segments + 1):
            t = i / jag_segments
            drop = (_hash01(seed, i, 71) * 0.85 + 0.15) * top_jag
            tops.append(cy + sy - drop)
        step = size[0] / jag_segments
        for i in range(jag_segments):
            xa, xb = x0 + i * step, x0 + (i + 1) * step
            ya, yb = tops[i], tops[i + 1]
            un = (step * uv_density, size[1] * uv_density)
            self.quad((xa, y0, z1), (xb, y0, z1), (xb, yb, z1), (xa, ya, z1), (0, 0, 1), un, (i * 0.17 % 1.0, 0))
            self.quad((xb, y0, z0), (xa, y0, z0), (xa, ya, z0), (xb, yb, z0), (0, 0, -1), un, (i * 0.23 % 1.0, 0))
            # sloped top strip
            self.quad((xa, ya, z1), (xb, yb, z1), (xb, yb, z0), (xa, ya, z0), (0, 1, 0),
                      (step * uv_density, size[2] * uv_density), (i * 0.31 % 1.0, 0))
        self.quad((x1, y0, z1), (x1, y0, z0), (x1, tops[-1], z0), (x1, tops[-1], z1), (1, 0, 0), vs)
        self.quad((x0, y0, z0), (x0, y0, z1), (x0, tops[0], z1), (x0, tops[0], z0), (-1, 0, 0), vs)
        self.quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (0, -1, 0), hs)

    def cylinder(self, center, radius_bottom, radius_top, height_, segments=10, seed=0, uv_density=0.14):
        cx, cy, cz = center
        top_ring, bottom_ring = [], []
        for i in range(segments):
            angle = i / segments * math.tau
            wobble = 1.0 + (_hash01(seed, i, 91) - 0.5) * 0.12
            bx = cx + math.cos(angle) * radius_bottom * wobble
            bz = cz + math.sin(angle) * radius_bottom * wobble
            tx = cx + math.cos(angle) * radius_top * wobble
            tz = cz + math.sin(angle) * radius_top * wobble
            bottom_ring.append((bx, cy, bz))
            top_ring.append((tx, cy + height_, tz))
        for i in range(segments):
            j = (i + 1) % segments
            angle = (i + 0.5) / segments * math.tau
            normal = (math.cos(angle), 0.0, math.sin(angle))
            self.quad(bottom_ring[i], bottom_ring[j], top_ring[j], top_ring[i], normal,
                      (0.8 / segments * math.tau * radius_bottom, height_ * uv_density),
                      (i / segments, 0))
        # cap top
        start = len(self.positions)
        self.positions.append((cx, cy + height_, cz))
        self.normals.append((0, 1, 0))
        self.uvs.append((0.5, 0.5))
        for i in range(segments):
            j = (i + 1) % segments
            a = len(self.positions)
            self.positions += [top_ring[i], top_ring[j]]
            self.normals += [(0, 1, 0)] * 2
            self.uvs += [(0.3, 0.3), (0.7, 0.3)]
            self.indices += [start, a + 1, a]

    def arrays(self):
        return (np.array(self.positions, dtype=np.float32),
                np.array(self.normals, dtype=np.float32),
                np.array(self.uvs, dtype=np.float32),
                np.array(self.indices, dtype=np.uint16))


# ------------------------------------------------------------ piece builders

def build_wall_segment():
    b = MeshBuilder()
    b.box((0, 3.0, 0), (8.0, 6.0, 1.2), seed=11, top_jag=1.1, jag_segments=7)
    c = MeshBuilder()
    c.box((0, 2.8, 0), (8.0, 5.6, 1.3))
    return b, c


def build_wall_doorway():
    b = MeshBuilder()
    op_w, op_h = 3.0, 4.5
    side = (8.0 - op_w) / 2.0
    b.box((-(op_w / 2 + side / 2), 3.0, 0), (side, 6.0, 1.2), seed=21, top_jag=0.9, jag_segments=4)
    b.box(((op_w / 2 + side / 2), 3.0, 0), (side, 6.0, 1.2), seed=22, top_jag=0.9, jag_segments=4)
    b.box((0, op_h + (6.0 - op_h) / 2, 0), (op_w + 0.02, 6.0 - op_h, 1.2), seed=23, top_jag=0.7, jag_segments=4)
    c = MeshBuilder()
    c.box((-(op_w / 2 + side / 2), 2.8, 0), (side, 5.6, 1.3))
    c.box(((op_w / 2 + side / 2), 2.8, 0), (side, 5.6, 1.3))
    c.box((0, op_h + (6.0 - op_h) / 2, 0), (op_w, 6.0 - op_h, 1.3))
    return b, c


def build_wall_broken():
    b = MeshBuilder()
    b.box((0, 1.7, 0), (8.0, 3.4, 1.2), seed=31, top_jag=2.0, jag_segments=8)
    c = MeshBuilder()
    c.box((0, 1.3, 0), (8.0, 2.6, 1.3))
    return b, c


def build_corner_post():
    b = MeshBuilder()
    b.box((0, 3.1, 0), (1.6, 6.2, 1.6), seed=41, top_jag=0.7, jag_segments=3)
    c = MeshBuilder()
    c.box((0, 3.0, 0), (1.7, 6.0, 1.7))
    return b, c


def build_pillar():
    b = MeshBuilder()
    b.cylinder((0, 0, 0), 0.95, 0.78, 5.6, segments=10, seed=51)
    b.box((0, 0.25, 0), (2.2, 0.5, 2.2))  # plinth
    c = MeshBuilder()
    c.cylinder((0, 0, 0), 1.0, 0.85, 5.6, segments=6, seed=52)
    return b, c


def build_pillar_broken():
    b = MeshBuilder()
    b.cylinder((0, 0, 0), 0.95, 0.9, 2.6, segments=10, seed=61)
    b.box((0, 2.75, 0), (1.9, 0.5, 1.9), seed=62, top_jag=0.45, jag_segments=4)
    b.box((0, 0.25, 0), (2.2, 0.5, 2.2))
    c = MeshBuilder()
    c.cylinder((0, 0, 0), 1.0, 0.95, 2.9, segments=6, seed=63)
    return b, c


def build_rubble_pile():
    b = MeshBuilder()
    for i in range(9):
        angle = _hash01(70, i, 1) * math.tau
        dist = _hash01(70, i, 2) * 2.2
        px, pz = math.cos(angle) * dist, math.sin(angle) * dist
        w = 0.8 + _hash01(70, i, 3) * 1.4
        h = 0.5 + _hash01(70, i, 4) * 1.0
        d = 0.8 + _hash01(70, i, 5) * 1.4
        b.box((px, h / 2 * (0.65 + 0.35 * _hash01(70, i, 6)), pz), (w, h, d), seed=71 + i, top_jag=0.25, jag_segments=2)
    c = MeshBuilder()
    c.box((0, 0.8, 0), (5.6, 1.6, 5.6))
    return b, c


def build_floor_slab():
    b = MeshBuilder()
    for gx in range(2):
        for gz in range(2):
            px = -1.0 + gx * 2.0
            pz = -1.0 + gz * 2.0
            tilt = (_hash01(80, gx * 2 + gz, 1) - 0.5) * 0.12
            b.box((px, 0.2 + tilt, pz), (1.9, 0.4, 1.9), seed=81 + gx * 2 + gz, top_jag=0.08, jag_segments=2)
    c = MeshBuilder()
    c.box((0, 0.2, 0), (4.0, 0.5, 4.0))
    return b, c


PIECES = [
    ("WallSegment", build_wall_segment),
    ("WallDoorway", build_wall_doorway),
    ("WallBroken", build_wall_broken),
    ("CornerPost", build_corner_post),
    ("Pillar", build_pillar),
    ("PillarBroken", build_pillar_broken),
    ("RubblePile", build_rubble_pile),
    ("FloorSlab", build_floor_slab),
]


# ------------------------------------------------------------ glb assembly

def main():
    make_stone_set()

    blob = b""
    views, accessors, images, textures, materials, meshes, nodes = [], [], [], [], [], [], []

    def add_view(data, target=None):
        nonlocal blob
        offset = len(blob)
        blob += data
        while len(blob) % 4:
            blob += b"\x00"
        views.append(BufferView(buffer=0, byteOffset=offset, byteLength=len(data), target=target))
        return len(views) - 1

    def add_image(path):
        with open(path, "rb") as handle:
            view = add_view(handle.read())
        images.append(GltfImage(bufferView=view, mimeType="image/png",
                                name=os.path.splitext(os.path.basename(path))[0]))
        textures.append(Texture(source=len(images) - 1, sampler=0))
        return len(textures) - 1

    def add_mesh(name, builder, material_index):
        positions, normals, uvs, indices = builder.arrays()
        pv = add_view(positions.tobytes(), ARRAY_BUFFER)
        accessors.append(Accessor(bufferView=pv, componentType=FLOAT, count=len(positions), type="VEC3",
                                  max=positions.max(axis=0).tolist(), min=positions.min(axis=0).tolist()))
        pa = len(accessors) - 1
        nv = add_view(normals.tobytes(), ARRAY_BUFFER)
        accessors.append(Accessor(bufferView=nv, componentType=FLOAT, count=len(normals), type="VEC3"))
        na = len(accessors) - 1
        uv = add_view(uvs.tobytes(), ARRAY_BUFFER)
        accessors.append(Accessor(bufferView=uv, componentType=FLOAT, count=len(uvs), type="VEC2"))
        ua = len(accessors) - 1
        iv = add_view(indices.tobytes(), ELEMENT_ARRAY_BUFFER)
        accessors.append(Accessor(bufferView=iv, componentType=USHORT, count=len(indices), type="SCALAR"))
        ia = len(accessors) - 1
        meshes.append(Mesh(name=name, primitives=[Primitive(
            attributes={"POSITION": pa, "NORMAL": na, "TEXCOORD_0": ua},
            indices=ia, material=material_index)]))
        return len(meshes) - 1

    # metallicRoughness packing for the stone set
    rough_img = Image.open(os.path.join(TEXTURE_DIR, "M8_Stone_Roughness.png")).convert("L")
    mr = np.zeros((rough_img.size[1], rough_img.size[0], 3), dtype=np.uint8)
    mr[:, :, 1] = np.asarray(rough_img)
    mr_path = os.path.join(TEXTURE_DIR, "M8_Stone_MetallicRoughness.png")
    Image.fromarray(mr, "RGB").save(mr_path)

    base_ti = add_image(os.path.join(TEXTURE_DIR, "M8_Stone_BaseColor.png"))
    mr_ti = add_image(mr_path)
    nrm_ti = add_image(os.path.join(TEXTURE_DIR, "M8_Stone_Normal.png"))
    materials.append(Material(
        name="M8StoneMat",
        pbrMetallicRoughness=PbrMetallicRoughness(
            baseColorTexture=TextureInfo(index=base_ti),
            metallicRoughnessTexture=TextureInfo(index=mr_ti),
            metallicFactor=0.0),
        normalTexture=NormalMaterialTexture(index=nrm_ti),
        alphaMode="OPAQUE", doubleSided=False))
    materials.append(Material(name="M8CollisionMat",
                              pbrMetallicRoughness=PbrMetallicRoughness(metallicFactor=0.0),
                              alphaMode="OPAQUE", doubleSided=False))

    for index, (name, build) in enumerate(PIECES):
        render, collision = build()
        rm = add_mesh(name + "_LOD0Mesh", render, 0)
        cm = add_mesh(name + "_COLMesh", collision, 1)
        rn = Node(name=name + "_LOD0", mesh=rm)
        cn = Node(name=name + "_COL", mesh=cm)
        nodes.append(rn)
        nodes.append(cn)
        nodes.append(Node(name=name, children=[len(nodes) - 2, len(nodes) - 1],
                          translation=[index * 12.0, 0.0, 0.0]))

    root_children = [i for i, node in enumerate(nodes) if node.name in dict(PIECES)]
    gltf = GLTF2(
        asset=Asset(version="2.0", generator="WorldEngine M8 ruin kit"),
        scene=0, scenes=[Scene(nodes=root_children)], nodes=nodes, meshes=meshes,
        materials=materials, textures=textures, images=images,
        samplers=[Sampler(magFilter=9729, minFilter=9987, wrapS=10497, wrapT=10497)],
        accessors=accessors, bufferViews=views,
        buffers=[Buffer(byteLength=len(blob))])
    gltf.set_binary_blob(blob)
    os.makedirs(os.path.dirname(EXPORT_PATH), exist_ok=True)
    gltf.save_binary(EXPORT_PATH)
    total_tris = sum(len(m.primitives) for m in meshes)
    print("wrote", EXPORT_PATH, os.path.getsize(EXPORT_PATH), "bytes,", len(PIECES), "pieces", total_tris)


if __name__ == "__main__":
    main()
