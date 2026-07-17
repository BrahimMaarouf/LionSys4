import bpy
import math
import os
import random
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEXTURE_DIR = os.path.join(ROOT, "assets", "textures")
EXPORT_DIR = os.path.join(ROOT, "assets", "export")
STUDIO_EXPORT_DIR = os.path.join(EXPORT_DIR, "studio")
BLEND_DIR = os.path.join(ROOT, "assets", "blender")


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.images):
        pass
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "BLENDER_EEVEE_NEXT"


def save_image(name, pixels, size=256):
    image = bpy.data.images.new(name, width=size, height=size, alpha=True)
    image.pixels = pixels
    path = os.path.join(TEXTURE_DIR, name + ".png")
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    return image


def make_rock_textures():
    size = 256
    base = []
    normal = []
    roughness = []
    for y in range(size):
        for x in range(size):
            nx = x / size
            ny = y / size
            grain = (
                math.sin(nx * 47.0 + math.sin(ny * 13.0)) * 0.035
                + math.sin(ny * 91.0) * 0.018
                + math.sin((nx + ny) * 157.0) * 0.012
            )
            strata = math.sin(ny * math.pi * 24.0) * 0.025
            r = max(0.0, min(1.0, 0.57 + grain + strata))
            g = max(0.0, min(1.0, 0.32 + grain * 0.7 + strata * 0.6))
            b = max(0.0, min(1.0, 0.17 + grain * 0.45))
            base.extend((r, g, b, 1.0))
            normal.extend((0.5 + grain * 1.8, 0.5 + strata * 1.8, 1.0, 1.0))
            rough = max(0.0, min(1.0, 0.78 + grain * 0.8))
            roughness.extend((rough, rough, rough, 1.0))
    return (
        save_image("M2_Rock_BaseColor", base, size),
        save_image("M2_Rock_Normal", normal, size),
        save_image("M2_Rock_Roughness", roughness, size),
    )


def make_shrub_textures():
    size = 256
    rng = random.Random(90210)
    clusters = []
    for _ in range(34):
        clusters.append((
            rng.uniform(0.12, 0.88),
            rng.uniform(0.15, 0.88),
            rng.uniform(0.045, 0.105),
            rng.uniform(0.025, 0.065),
        ))
    base = []
    normal = []
    roughness = []
    for y in range(size):
        for x in range(size):
            u = (x + 0.5) / size
            v = (y + 0.5) / size
            coverage = 0.0
            for cx, cy, rx, ry in clusters:
                d = ((u - cx) / rx) ** 2 + ((v - cy) / ry) ** 2
                if d < 1.0:
                    coverage = max(coverage, 1.0 - d)
            stem = abs(u - 0.5) < 0.018 and v < 0.62
            if coverage > 0.02:
                edge = min(1.0, coverage * 6.0)
                variation = math.sin(u * 83.0 + v * 47.0) * 0.035
                base.extend((0.24 + variation, 0.34 + variation, 0.10, edge))
                normal.extend((0.5, 0.5, 1.0, edge))
                roughness.extend((0.72, 0.72, 0.72, edge))
            elif stem:
                base.extend((0.29, 0.16, 0.07, 1.0))
                normal.extend((0.5, 0.5, 1.0, 1.0))
                roughness.extend((0.82, 0.82, 0.82, 1.0))
            else:
                base.extend((0.0, 0.0, 0.0, 0.0))
                normal.extend((0.5, 0.5, 1.0, 0.0))
                roughness.extend((0.8, 0.8, 0.8, 0.0))
    return (
        save_image("M2_Shrub_BaseColor", base, size),
        save_image("M2_Shrub_Normal", normal, size),
        save_image("M2_Shrub_Roughness", roughness, size),
    )


def pbr_material(name, base_image, normal_image, roughness_image, alpha=False):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    base = nodes.new("ShaderNodeTexImage")
    base.image = base_image
    base.interpolation = "Linear"
    normal_texture = nodes.new("ShaderNodeTexImage")
    normal_texture.image = normal_image
    normal_texture.image.colorspace_settings.name = "Non-Color"
    roughness = nodes.new("ShaderNodeTexImage")
    roughness.image = roughness_image
    roughness.image.colorspace_settings.name = "Non-Color"
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.55
    links.new(base.outputs["Color"], shader.inputs["Base Color"])
    links.new(roughness.outputs["Color"], shader.inputs["Roughness"])
    links.new(normal_texture.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], shader.inputs["Normal"])
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    if alpha:
        links.new(base.outputs["Alpha"], shader.inputs["Alpha"])
        if hasattr(material, "surface_render_method"):
            material.surface_render_method = "DITHERED"
        material.use_transparency_overlap = False
        material.use_backface_culling = False
    return material


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def smart_uv(obj):
    activate(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.025)
    bpy.ops.object.mode_set(mode="OBJECT")


def make_rock(name, dimensions, seed, subdivisions=4, material=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    rng = random.Random(seed)
    phases = [rng.uniform(0, math.pi * 2) for _ in range(6)]
    width, depth, height = dimensions
    for vertex in obj.data.vertices:
        direction = vertex.co.normalized()
        x, y, z = direction.x, direction.y, direction.z
        broad = (
            math.sin(x * 4.7 + phases[0])
            + math.sin(y * 5.9 + phases[1])
            + math.sin(z * 6.3 + phases[2])
        ) / 3.0
        detail = (
            math.sin((x + y) * 13.0 + phases[3])
            + math.sin((y + z) * 17.0 + phases[4])
            + math.sin((z + x) * 19.0 + phases[5])
        ) / 3.0
        displacement = 1.0 + broad * 0.13 + detail * 0.045
        vertex.co.x = x * width * 0.5 * displacement
        vertex.co.y = y * depth * 0.5 * displacement
        vertex.co.z = max(0.0, (z + 1.0) * height * 0.5 * (1.0 + broad * 0.08))
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    smart_uv(obj)
    if material:
        obj.data.materials.append(material)
    obj["pivot_convention"] = "GROUND_CENTER"
    obj["unit_convention"] = "1_BU_1_STUD"
    return obj


def join_objects(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    return objects[0]


def duplicate_lod(source, name, ratio):
    lod = source.copy()
    lod.data = source.data.copy()
    bpy.context.collection.objects.link(lod)
    lod.name = name
    activate(lod)
    modifier = lod.modifiers.new("DeterministicDecimate", "DECIMATE")
    modifier.ratio = ratio
    modifier.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    lod["lod_ratio"] = ratio
    return lod


def collision_proxy(source, name, ratio=0.04):
    proxy = duplicate_lod(source, name, ratio)
    proxy.data.materials.clear()
    proxy.display_type = "WIRE"
    proxy.hide_render = True
    proxy["roblox_role"] = "COLLISION"
    return proxy


def ground_mesh(obj):
    """Move mesh vertices only so the lowest point is exactly Z=0."""
    minimum_z = min(vertex.co.z for vertex in obj.data.vertices)
    for vertex in obj.data.vertices:
        vertex.co.z -= minimum_z


def make_layered_rock(material):
    layers = []
    specs = [
        ((18.0, 13.5, 3.3), 311, (0.0, 0.0, 0.0)),
        ((15.5, 11.5, 3.0), 419, (0.7, -0.4, 2.65)),
        ((12.5, 9.2, 2.6), 557, (-0.5, 0.35, 5.05)),
    ]
    for index, (dims, seed, location) in enumerate(specs):
        layer = make_rock(f"LayerPart_{index}", dims, seed, subdivisions=3, material=material)
        layer.location = location
        layers.append(layer)
    rock = join_objects(layers, "LayeredMesa_LOD0")
    smart_uv(rock)
    rock["roblox_role"] = "RENDER_LOD0"
    return rock


def make_plane_mesh(name, width, height, angle, material):
    half = width * 0.5
    vertices = [(-half, 0, 0), (half, 0, 0), (half, 0, height), (-half, 0, height)]
    faces = [(0, 1, 2, 3)]
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.uv_layers.new(name="UVMap")
    uv = mesh.uv_layers.active.data
    for loop, coordinate in zip(uv, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop.uv = coordinate
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.rotation_euler[2] = angle
    obj.data.materials.append(material)
    return obj


def make_branch(start, end, radius, name, material):
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    midpoint = (start_v + end_v) * 0.5
    bpy.ops.mesh.primitive_cone_add(
        vertices=8,
        radius1=radius,
        radius2=radius * 0.55,
        depth=direction.length,
        location=midpoint,
    )
    branch = bpy.context.object
    branch.name = name
    branch.rotation_mode = "QUATERNION"
    branch.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    branch.rotation_mode = "XYZ"
    branch.data.materials.append(material)
    return branch


def make_shrub(shrub_material, branch_material):
    branches = [
        make_branch((0, 0, 0), (0, 0, 6.2), 0.34, "StemMain", branch_material),
        make_branch((0, 0, 2.0), (2.8, 0.6, 5.5), 0.21, "StemA", branch_material),
        make_branch((0, 0, 2.4), (-2.5, -0.4, 5.2), 0.20, "StemB", branch_material),
        make_branch((0, 0, 3.0), (0.5, 2.4, 5.8), 0.17, "StemC", branch_material),
    ]
    branch_lod0 = join_objects(branches, "DryShrubBranches_LOD0")
    branch_lod0["roblox_role"] = "RENDER_LOD0_BRANCHES"
    cards = [make_plane_mesh(f"Card{i}", 8.5, 7.0, math.radians(i * 30), shrub_material) for i in range(6)]
    foliage_lod0 = join_objects(cards, "DryShrubFoliage_LOD0")
    foliage_lod0["roblox_role"] = "RENDER_LOD0_FOLIAGE"

    lod1_cards = [make_plane_mesh(f"LOD1Card{i}", 8.3, 6.8, math.radians(i * 60), shrub_material) for i in range(3)]
    lod1 = join_objects(lod1_cards, "DryShrub_LOD1")
    lod1["roblox_role"] = "RENDER_LOD1"

    lod2_cards = [make_plane_mesh(f"LOD2Card{i}", 8.0, 6.5, math.radians(i * 90), shrub_material) for i in range(2)]
    lod2 = join_objects(lod2_cards, "DryShrub_LOD2")
    lod2["roblox_role"] = "RENDER_LOD2"

    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=1.45, depth=5.0, location=(0, 0, 2.5))
    collision = bpy.context.object
    collision.name = "DryShrub_COL"
    collision.display_type = "WIRE"
    collision.hide_render = True
    collision["roblox_role"] = "COLLISION"
    return [branch_lod0, foliage_lod0, lod1, lod2, collision]


def export_asset(prefix, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    path = os.path.join(EXPORT_DIR, prefix + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_extras=True,
    )


def export_studio_meshes(objects):
    os.makedirs(STUDIO_EXPORT_DIR, exist_ok=True)
    for obj in objects:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_scene.gltf(
            filepath=os.path.join(STUDIO_EXPORT_DIR, obj.name + ".glb"),
            export_format="GLB",
            use_selection=True,
            export_apply=True,
            export_yup=True,
            export_materials="NONE",
            export_extras=True,
        )


def main():
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    os.makedirs(EXPORT_DIR, exist_ok=True)
    os.makedirs(STUDIO_EXPORT_DIR, exist_ok=True)
    os.makedirs(BLEND_DIR, exist_ok=True)
    for filename in os.listdir(STUDIO_EXPORT_DIR):
        if filename.lower().endswith(".glb"):
            os.remove(os.path.join(STUDIO_EXPORT_DIR, filename))
    reset_scene()

    rock_images = make_rock_textures()
    shrub_images = make_shrub_textures()
    rock_material = pbr_material("M2_Sandstone_PBR", *rock_images)
    shrub_material = pbr_material("M2_DryShrub_AlphaPBR", *shrub_images, alpha=True)
    branch_material = bpy.data.materials.new("M2_DryBranch")
    branch_material.diffuse_color = (0.23, 0.11, 0.045, 1.0)
    branch_material.roughness = 0.88

    boulder0 = make_rock("WindBoulder_LOD0", (16.0, 13.0, 10.5), 1701, subdivisions=4, material=rock_material)
    boulder0["roblox_role"] = "RENDER_LOD0"
    boulder1 = duplicate_lod(boulder0, "WindBoulder_LOD1", 0.42)
    boulder1["roblox_role"] = "RENDER_LOD1"
    boulder2 = duplicate_lod(boulder0, "WindBoulder_LOD2", 0.14)
    boulder2["roblox_role"] = "RENDER_LOD2"
    boulder_col = collision_proxy(boulder0, "WindBoulder_COL")

    layered0 = make_layered_rock(rock_material)
    layered1 = duplicate_lod(layered0, "LayeredMesa_LOD1", 0.42)
    layered1["roblox_role"] = "RENDER_LOD1"
    layered2 = duplicate_lod(layered0, "LayeredMesa_LOD2", 0.14)
    layered2["roblox_role"] = "RENDER_LOD2"
    layered_col = collision_proxy(layered0, "LayeredMesa_COL")

    shrub_objects = make_shrub(shrub_material, branch_material)

    # Bake every object's world-space transform into its mesh. This preserves the
    # authored shape while putting every export origin at the ground-center (0,0,0).
    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH":
            activate(obj)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            ground_mesh(obj)

    export_asset("WindBoulder", [boulder0, boulder1, boulder2, boulder_col])
    export_asset("LayeredMesa", [layered0, layered1, layered2, layered_col])
    export_asset("DryShrub", shrub_objects)
    export_studio_meshes([
        boulder0, boulder1, boulder2, boulder_col,
        layered0, layered1, layered2, layered_col,
        *shrub_objects,
    ])

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_DIR, "M2_DesertAssetSlice.blend"))


if __name__ == "__main__":
    main()
