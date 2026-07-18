"""Builds M7TextureCarrier.glb — a 3-quad GLB whose only purpose is to ferry
the M7 PBR texture sets through Roblox Studio's 3D Importer (the project's
proven upload path). After import, the uploaded ColorMap/NormalMap/RoughnessMap
asset IDs are harvested from the imported SurfaceAppearances and the carrier
model is deleted. The carrier meshes are never used in the world.

Run:  python3 pipeline/textures/build_m7_texture_carrier.py
"""

import os
import struct

import numpy as np
from PIL import Image
from pygltflib import (
    GLTF2, Accessor, Asset, Buffer, BufferView, Image as GltfImage, Material,
    Mesh, Node, NormalMaterialTexture, PbrMetallicRoughness, Primitive, Sampler,
    Scene, Texture, TextureInfo,
)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEXTURE_DIR = os.path.join(ROOT, "assets", "textures")
EXPORT_PATH = os.path.join(ROOT, "assets", "export", "M7TextureCarrier.glb")

SETS = [
    ("M7RockCarrier", "M7_Rock", "OPAQUE"),
    ("M7ShrubCarrier", "M7_Shrub", "BLEND"),
    ("M7BarkCarrier", "M7_Bark", "OPAQUE"),
]

ARRAY_UINT8 = 5121  # noqa: unused reference sizes below
FLOAT = 5126
USHORT = 5123
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963


def pack_metallic_roughness(prefix):
    """glTF wants roughness in the G channel (metallic in B). Our roughness
    PNGs are grayscale; repack into a proper metallicRoughness image."""
    rough = Image.open(os.path.join(TEXTURE_DIR, prefix + "_Roughness.png")).convert("L")
    size = rough.size
    arr = np.zeros((size[1], size[0], 3), dtype=np.uint8)
    arr[:, :, 1] = np.asarray(rough)  # roughness -> G
    arr[:, :, 2] = 0                  # metallic -> B (non-metal)
    out_path = os.path.join(TEXTURE_DIR, prefix + "_MetallicRoughness.png")
    Image.fromarray(arr, "RGB").save(out_path)
    return out_path


def main():
    blob = b""
    buffer_views = []
    accessors = []
    images = []
    textures = []
    materials = []
    meshes = []
    nodes = []

    def add_view(data, target=None):
        nonlocal blob
        offset = len(blob)
        blob += data
        while len(blob) % 4:
            blob += b"\x00"
        buffer_views.append(BufferView(
            buffer=0, byteOffset=offset, byteLength=len(data),
            target=target,
        ))
        return len(buffer_views) - 1

    def add_image(path):
        with open(path, "rb") as handle:
            view = add_view(handle.read())
        images.append(GltfImage(bufferView=view, mimeType="image/png",
                                name=os.path.splitext(os.path.basename(path))[0]))
        textures.append(Texture(source=len(images) - 1, sampler=0))
        return len(textures) - 1

    # one flat quad, reused by all three primitives
    positions = np.array([
        [-1, 0, -1], [1, 0, -1], [1, 0, 1], [-1, 0, 1],
    ], dtype=np.float32)
    normals = np.array([[0, 1, 0]] * 4, dtype=np.float32)
    uvs = np.array([[0, 0], [1, 0], [1, 1], [0, 1]], dtype=np.float32)
    indices = np.array([0, 2, 1, 0, 3, 2], dtype=np.uint16)

    pos_view = add_view(positions.tobytes(), ARRAY_BUFFER)
    accessors.append(Accessor(bufferView=pos_view, componentType=FLOAT, count=4,
                              type="VEC3", max=positions.max(axis=0).tolist(),
                              min=positions.min(axis=0).tolist()))
    pos_acc = len(accessors) - 1
    norm_view = add_view(normals.tobytes(), ARRAY_BUFFER)
    accessors.append(Accessor(bufferView=norm_view, componentType=FLOAT, count=4, type="VEC3"))
    norm_acc = len(accessors) - 1
    uv_view = add_view(uvs.tobytes(), ARRAY_BUFFER)
    accessors.append(Accessor(bufferView=uv_view, componentType=FLOAT, count=4, type="VEC2"))
    uv_acc = len(accessors) - 1
    idx_view = add_view(indices.tobytes(), ELEMENT_ARRAY_BUFFER)
    accessors.append(Accessor(bufferView=idx_view, componentType=USHORT, count=6, type="SCALAR"))
    idx_acc = len(accessors) - 1

    for index, (node_name, prefix, alpha_mode) in enumerate(SETS):
        base = add_image(os.path.join(TEXTURE_DIR, prefix + "_BaseColor.png"))
        mr = add_image(pack_metallic_roughness(prefix))
        normal = add_image(os.path.join(TEXTURE_DIR, prefix + "_Normal.png"))
        materials.append(Material(
            name=prefix + "Mat",
            pbrMetallicRoughness=PbrMetallicRoughness(
                baseColorTexture=TextureInfo(index=base),
                metallicRoughnessTexture=TextureInfo(index=mr),
                metallicFactor=0.0,
            ),
            normalTexture=NormalMaterialTexture(index=normal),
            alphaMode=alpha_mode,
            doubleSided=True,
        ))
        meshes.append(Mesh(name=node_name + "Mesh", primitives=[Primitive(
            attributes={"POSITION": pos_acc, "NORMAL": norm_acc, "TEXCOORD_0": uv_acc},
            indices=idx_acc, material=len(materials) - 1,
        )]))
        nodes.append(Node(name=node_name, mesh=len(meshes) - 1,
                          translation=[index * 3.0, 0.0, 0.0]))

    gltf = GLTF2(
        asset=Asset(version="2.0", generator="WorldEngine M7 texture carrier"),
        scene=0,
        scenes=[Scene(nodes=list(range(len(nodes))))],
        nodes=nodes,
        meshes=meshes,
        materials=materials,
        textures=textures,
        images=images,
        samplers=[Sampler(magFilter=9729, minFilter=9987, wrapS=10497, wrapT=10497)],
        accessors=accessors,
        bufferViews=buffer_views,
        buffers=[Buffer(byteLength=len(blob))],
    )
    gltf.set_binary_blob(blob)
    os.makedirs(os.path.dirname(EXPORT_PATH), exist_ok=True)
    gltf.save_binary(EXPORT_PATH)
    print("wrote", EXPORT_PATH, os.path.getsize(EXPORT_PATH), "bytes")


if __name__ == "__main__":
    main()
