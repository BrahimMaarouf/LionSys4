"""M7 texture-quality pass — math-authored PBR textures, no DCC required.

Generates the improved desert texture sets as deterministic pure functions,
following the project's "painting with math" doctrine. Texture-only upgrades
are signature-safe: WorldEngine golden signatures hash mesh IDs and positions,
never SurfaceAppearance maps, so these can be swapped without rebaselining.

Outputs (assets/textures/):
  M7_Rock_BaseColor.png / M7_Rock_Normal.png / M7_Rock_Roughness.png   (384px)
  M7_Shrub_BaseColor.png / M7_Shrub_Normal.png / M7_Shrub_Roughness.png (256px)
  M7_Bark_BaseColor.png / M7_Bark_Normal.png / M7_Bark_Roughness.png   (256px)

The bark set is new: DryShrub branch meshes UV-map into a region of the M2
shrub atlas that carried no bark texels. Rather than remapping UVs (a mesh
change that would cascade golden rebaselines), branches receive their own
seamless bark set that reads correctly under any UV layout.

Run:  python3 pipeline/textures/generate_m7_textures.py
"""

import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEXTURE_DIR = os.path.join(ROOT, "assets", "textures")


# ---------------------------------------------------------------- utilities

def _hash01(ix, iy, seed):
    h = (ix * 374761393 + iy * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def _fade(t):
    return t * t * t * (t * (t * 6 - 15) + 10)


def value_noise(u, v, freq, seed, tile=1):
    """Seamless (toroidal) value noise on [0,1)^2."""
    fu, fv = u * freq, v * freq
    iu, iv = int(fu), int(fv)
    tu, tv = _fade(fu - iu), _fade(fv - iv)
    period = freq * tile
    a = _hash01(iu % period, iv % period, seed)
    b = _hash01((iu + 1) % period, iv % period, seed)
    c = _hash01(iu % period, (iv + 1) % period, seed)
    d = _hash01((iu + 1) % period, (iv + 1) % period, seed)
    return (a + (b - a) * tu) + ((c + (d - c) * tu) - (a + (b - a) * tu)) * tv


def fbm(u, v, seed, octaves=4, base_freq=4):
    total, amp, norm, freq = 0.0, 1.0, 0.0, base_freq
    for octave in range(octaves):
        total += value_noise(u, v, freq, seed + octave * 101) * amp
        norm += amp
        amp *= 0.5
        freq *= 2
    return total / norm


def clamp01(x):
    return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)


def height_to_normal(height, size, strength=2.2):
    """Sobel-style tangent-space normal map from a height field (seamless)."""
    pixels = []
    for y in range(size):
        for x in range(size):
            hl = height[y * size + (x - 1) % size]
            hr = height[y * size + (x + 1) % size]
            hd = height[((y - 1) % size) * size + x]
            hu = height[((y + 1) % size) * size + x]
            dx = (hl - hr) * strength
            dy = (hd - hu) * strength
            inv = 1.0 / math.sqrt(dx * dx + dy * dy + 1.0)
            pixels.append((
                int(clamp01(dx * inv * 0.5 + 0.5) * 255),
                int(clamp01(dy * inv * 0.5 + 0.5) * 255),
                int(clamp01(inv * 0.5 + 0.5) * 255),
                255,
            ))
    return pixels


def save_rgba(name, pixels, size):
    image = Image.new("RGBA", (size, size))
    image.putdata(pixels)
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    path = os.path.join(TEXTURE_DIR, name + ".png")
    image.save(path)
    print("wrote", path)


# ---------------------------------------------------------------- rock set

def make_rock_set(size=384):
    """Layered desert sandstone: warped strata, grain, cavity shading.

    Addresses the M2 critique of flat saturated orange: wider value range,
    desaturated banding, and darkened cavities give distance readability.
    """
    base, height, rough = [], [], []
    for y in range(size):
        for x in range(size):
            u, v = (x + 0.5) / size, (y + 0.5) / size
            warp = fbm(u, v, 900, octaves=3, base_freq=3) - 0.5
            band_v = v + warp * 0.22
            strata = math.sin(band_v * math.pi * 26.0)
            strata_soft = strata * 0.5 + 0.5
            grain = fbm(u, v, 901, octaves=5, base_freq=8) - 0.5
            cavity = fbm(u, v, 902, octaves=4, base_freq=5)
            cavity_dark = clamp01((cavity - 0.62) * 2.2)

            tone = clamp01(0.52 + strata * 0.07 + grain * 0.22 - cavity_dark * 0.28)
            warm = clamp01(0.55 + strata_soft * 0.12 - cavity_dark * 0.1)
            r = clamp01(tone * (0.86 + warm * 0.28))
            g = clamp01(tone * (0.62 + warm * 0.12))
            b = clamp01(tone * 0.45)
            base.append((int(r * 255), int(g * 255), int(b * 255), 255))
            height.append(clamp01(0.5 + strata * 0.1 + grain * 0.5 - cavity_dark * 0.35))
            rv = clamp01(0.72 + grain * 0.35 + cavity_dark * 0.15)
            rough.append((int(rv * 255),) * 3 + (255,))
    save_rgba("M7_Rock_BaseColor", base, size)
    save_rgba("M7_Rock_Normal", height_to_normal(height, size, 2.6), size)
    save_rgba("M7_Rock_Roughness", rough, size)


# ---------------------------------------------------------------- shrub set

def make_shrub_set(size=256):
    """Leaf-cluster alpha atlas, same layout as M2 (leaf clusters + stem strip)
    so existing foliage UVs keep reading correctly — but with richer leaf color
    variation, vein detail, and softer silhouette edges."""
    import random
    rng = random.Random(90210)  # same seed/layout as M2 atlas
    clusters = []
    for _ in range(34):
        clusters.append((
            rng.uniform(0.12, 0.88),
            rng.uniform(0.15, 0.88),
            rng.uniform(0.045, 0.105),
            rng.uniform(0.025, 0.065),
        ))
    base, height, rough = [], [], []
    for y in range(size):
        for x in range(size):
            u, v = (x + 0.5) / size, (y + 0.5) / size
            coverage, cluster_id = 0.0, 0
            for index, (cx, cy, rx, ry) in enumerate(clusters):
                d = ((u - cx) / rx) ** 2 + ((v - cy) / ry) ** 2
                if d < 1.0 and (1.0 - d) > coverage:
                    coverage, cluster_id = 1.0 - d, index
            stem = abs(u - 0.5) < 0.018 and v < 0.62
            if coverage > 0.02:
                edge = clamp01(coverage * 5.0)
                tint = _hash01(cluster_id, 7, 400) * 0.16 - 0.08
                dry = _hash01(cluster_id, 11, 401) * 0.22
                vein = abs(math.sin(u * 210.0 + cluster_id * 17.0)) * 0.05
                detail = fbm(u, v, 903, octaves=3, base_freq=24) - 0.5
                r = clamp01(0.26 + tint + dry * 0.55 + detail * 0.10 + vein)
                g = clamp01(0.38 + tint * 0.6 + dry * 0.28 + detail * 0.12)
                b = clamp01(0.11 + dry * 0.06 + detail * 0.05)
                base.append((int(r * 255), int(g * 255), int(b * 255), int(edge * 255)))
                height.append(clamp01(0.5 + coverage * 0.4 + detail * 0.3))
                rv = clamp01(0.62 + detail * 0.2 + dry * 0.18)
                rough.append((int(rv * 255),) * 3 + (int(edge * 255),))
            elif stem:
                base.append((74, 41, 18, 255))
                height.append(0.55)
                rough.append((209, 209, 209, 255))
            else:
                base.append((0, 0, 0, 0))
                height.append(0.5)
                rough.append((204, 204, 204, 0))
    save_rgba("M7_Shrub_BaseColor", base, size)
    save_rgba("M7_Shrub_Normal", height_to_normal(height, size, 1.6), size)
    save_rgba("M7_Shrub_Roughness", rough, size)


# ---------------------------------------------------------------- bark set

def make_bark_set(size=256):
    """Seamless dry-wood bark: vertical fibers, cracked plates, sun-bleached
    ridges. Fully opaque and tileable so branch meshes read correctly under
    any UV layout — the fix for the M2 shrub-atlas bark gap."""
    base, height, rough = [], [], []
    for y in range(size):
        for x in range(size):
            u, v = (x + 0.5) / size, (y + 0.5) / size
            fiber_warp = fbm(u, v, 904, octaves=3, base_freq=4) - 0.5
            fiber = math.sin((u + fiber_warp * 0.14) * math.pi * 30.0)
            fiber_soft = fiber * 0.5 + 0.5
            crack = fbm(u, v, 905, octaves=4, base_freq=6)
            crack_line = clamp01((crack - 0.58) * 3.2)
            bleach = fbm(u, v, 906, octaves=3, base_freq=3)

            tone = clamp01(0.42 + fiber_soft * 0.16 - crack_line * 0.30 + (bleach - 0.5) * 0.18)
            r = clamp01(tone * (0.95 + bleach * 0.2))
            g = clamp01(tone * (0.72 + bleach * 0.1))
            b = clamp01(tone * 0.52)
            base.append((int(r * 255), int(g * 255), int(b * 255), 255))
            height.append(clamp01(0.5 + fiber * 0.18 - crack_line * 0.45))
            rv = clamp01(0.78 + crack_line * 0.15 - bleach * 0.1)
            rough.append((int(rv * 255),) * 3 + (255,))
    save_rgba("M7_Bark_BaseColor", base, size)
    save_rgba("M7_Bark_Normal", height_to_normal(height, size, 2.4), size)
    save_rgba("M7_Bark_Roughness", rough, size)


if __name__ == "__main__":
    make_rock_set()
    make_shrub_set()
    make_bark_set()
    print("M7 texture pass complete.")
