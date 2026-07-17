import bpy
import math
import os
from mathutils import Vector


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLEND_PATH = os.path.join(ROOT, "assets", "blender", "M2_DesertAssetSlice.blend")
OUTPUT_PATH = os.path.join(ROOT, "assets", "M2_DCC_PREVIEW.png")


def point_camera(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def main():
    bpy.ops.wm.open_mainfile(filepath=BLEND_PATH)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = OUTPUT_PATH
    scene.render.film_transparent = False
    scene.world.color = (0.055, 0.055, 0.055)
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 1.25

    for obj in scene.objects:
        if obj.type == "MESH":
            obj.hide_render = not obj.name.endswith("_LOD0")

    positions = {
        "WindBoulder_LOD0": (-19.0, 0.0, 0.0),
        "LayeredMesa_LOD0": (4.0, 0.0, 0.0),
        "DryShrubBranches_LOD0": (23.0, 0.0, 0.0),
        "DryShrubFoliage_LOD0": (23.0, 0.0, 0.0),
    }
    for name, location in positions.items():
        scene.objects[name].location = location

    bpy.ops.mesh.primitive_plane_add(size=100.0, location=(0.0, 0.0, -0.05))
    ground = bpy.context.object
    ground.name = "PreviewGround"
    ground_material = bpy.data.materials.new("PreviewSand")
    ground_material.diffuse_color = (0.20, 0.07, 0.02, 1.0)
    ground_material.roughness = 0.9
    ground.data.materials.append(ground_material)

    bpy.ops.object.light_add(type="AREA", location=(-18.0, -18.0, 28.0))
    key = bpy.context.object
    key.data.energy = 1800
    key.data.color = (1.0, 0.47, 0.22)
    key.data.shape = "DISK"
    key.data.size = 12.0
    point_camera(key, (0.0, 0.0, 3.0))

    bpy.ops.object.light_add(type="AREA", location=(20.0, 5.0, 18.0))
    fill = bpy.context.object
    fill.data.energy = 900
    fill.data.color = (0.30, 0.48, 1.0)
    fill.data.size = 15.0
    point_camera(fill, (5.0, 0.0, 4.0))

    bpy.ops.object.camera_add(location=(28.0, -70.0, 27.0))
    camera = bpy.context.object
    point_camera(camera, (2.0, 0.0, 4.2))
    camera.data.lens = 48
    scene.camera = camera

    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
