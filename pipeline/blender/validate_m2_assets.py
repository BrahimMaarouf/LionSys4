import bpy
import json
import os
import sys


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSET_DIR = os.path.join(ROOT, "assets", "export")
REPORT_PATH = os.path.join(ROOT, "assets", "M2_DCC_VALIDATION.json")
EXPECTED = {
    "WindBoulder": ["WindBoulder_LOD0", "WindBoulder_LOD1", "WindBoulder_LOD2", "WindBoulder_COL"],
    "LayeredMesa": ["LayeredMesa_LOD0", "LayeredMesa_LOD1", "LayeredMesa_LOD2", "LayeredMesa_COL"],
    "DryShrub": [
        "DryShrubBranches_LOD0",
        "DryShrubFoliage_LOD0",
        "DryShrub_LOD1",
        "DryShrub_LOD2",
        "DryShrub_COL",
    ],
}


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def mesh_bounds(obj):
    vertices = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return {
        "min": [round(min(vertex[i] for vertex in vertices), 4) for i in range(3)],
        "max": [round(max(vertex[i] for vertex in vertices), 4) for i in range(3)],
    }


def validate_asset(asset_name, expected_names):
    reset_scene()
    path = os.path.join(ASSET_DIR, asset_name + ".glb")
    bpy.ops.import_scene.gltf(filepath=path)
    objects = sorted((obj for obj in bpy.context.scene.objects if obj.type == "MESH"), key=lambda obj: obj.name)
    names = [obj.name for obj in objects]
    by_name = {obj.name: obj for obj in objects}
    details = {}
    assertions = {
        "file_exists": os.path.isfile(path),
        "exact_object_names": names == sorted(expected_names),
        "origins_at_zero": all(max(abs(value) for value in obj.location) < 0.0001 for obj in objects),
        "identity_rotation": all(max(abs(value) for value in obj.rotation_euler) < 0.0001 for obj in objects),
        "identity_scale": all(max(abs(value - 1.0) for value in obj.scale) < 0.0001 for obj in objects),
        "ground_contact": True,
        "lod_triangles_descend": True,
        "collision_simpler_than_lod0": True,
        "render_mesh_has_uvs": True,
        "render_mesh_has_material": True,
    }

    for obj in objects:
        bounds = mesh_bounds(obj)
        triangles = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
        details[obj.name] = {
            "triangles": triangles,
            "bounds": bounds,
            "materials": [slot.name for slot in obj.data.materials],
            "uv_layers": len(obj.data.uv_layers),
        }
        if "_LOD" in obj.name:
            assertions["ground_contact"] = assertions["ground_contact"] and abs(bounds["min"][2]) <= 0.001
            assertions["render_mesh_has_uvs"] = assertions["render_mesh_has_uvs"] and len(obj.data.uv_layers) > 0
            assertions["render_mesh_has_material"] = assertions["render_mesh_has_material"] and len(obj.data.materials) > 0

    if all(name in by_name for name in expected_names):
        if asset_name == "DryShrub":
            lod0_count = (
                details["DryShrubBranches_LOD0"]["triangles"]
                + details["DryShrubFoliage_LOD0"]["triangles"]
            )
        else:
            lod0_count = details[f"{asset_name}_LOD0"]["triangles"]
        counts = [lod0_count, details[f"{asset_name}_LOD1"]["triangles"], details[f"{asset_name}_LOD2"]["triangles"]]
        assertions["lod_triangles_descend"] = counts[0] > counts[1] > counts[2]
        assertions["collision_simpler_than_lod0"] = details[f"{asset_name}_COL"]["triangles"] < counts[0]
    else:
        assertions["lod_triangles_descend"] = False
        assertions["collision_simpler_than_lod0"] = False

    return {
        "passed": all(assertions.values()),
        "assertions": assertions,
        "objects": details,
    }


def main():
    report = {
        "blender_version": bpy.app.version_string,
        "unit_convention": "1 Blender unit = 1 Roblox stud",
        "assets": {name: validate_asset(name, expected) for name, expected in EXPECTED.items()},
    }
    report["passed"] = all(asset["passed"] for asset in report["assets"].values())
    with open(REPORT_PATH, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, sort_keys=True)
    print(json.dumps(report, indent=2, sort_keys=True))
    if not report["passed"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
