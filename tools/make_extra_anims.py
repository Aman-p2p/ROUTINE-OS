#!/usr/bin/env python3
"""Author extra animations (thwip / point / stretch / think / cheer) for Spiderman-Pet characters.

Uses the same cutout-rig idea as the repo's scripts/build_articulated_assets.py (rotate separate limb layers
around their joints) but adds NEW poses. Output goes to <out>/<character>/<anim>/frame_XX.png plus extras.json
(fps, loop and the web-shooting hand position per frame). bake_pets.py then folds them into the pets folder.

Usage: python make_extra_anims.py <path-to>/Spiderman-Pet-main <out dir> [character ids...]
"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

SIZE = (512, 512)
SPIDER2 = {
 'head':      {'pivot': [252, 238], 'polygon': [[150, 40], [355, 40], [355, 240], [300, 250], [205, 250], [150, 238]]},
 'torso':     {'pivot': [262, 300], 'polygon': [[205, 240], [300, 240], [320, 292], [302, 346], [222, 352], [204, 300]]},
 'arm_left':  {'pivot': [214, 262], 'polygon': [[152, 255], [218, 248], [228, 285], [208, 332], [188, 338], [156, 322], [150, 296]]},
 'arm_right': {'pivot': [298, 262], 'polygon': [[288, 246], [332, 262], [338, 330], [334, 376], [312, 394], [294, 382], [298, 332], [286, 290]]},
 'leg_left':  {'pivot': [226, 346], 'polygon': [[198, 334], [264, 346], [260, 402], [240, 432], [228, 470], [228, 496], [160, 496], [188, 456], [200, 420]]},
 'leg_right': {'pivot': [282, 350], 'polygon': [[246, 344], [306, 338], [320, 400], [332, 440], [330, 496], [282, 496], [284, 446], [262, 410]]},
}
ORDER = ['leg_left', 'leg_right', 'arm_left', 'torso', 'arm_right', 'head']
ORDER_FRONT = ['leg_left', 'leg_right', 'torso', 'head', 'arm_left', 'arm_right']   # arms raised beside the big head must be drawn in front of it
FRONT = ('stretch', 'think', 'cheer')

def layer(source, polygon):
    mask = Image.new('L', SIZE)
    ImageDraw.Draw(mask).polygon([tuple(p) for p in polygon], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(.5))
    out = source.copy()
    out.putalpha(ImageChops.multiply(source.getchannel('A'), mask))
    return out

def transform(image, pivot, angle=0.0, dx=0.0, dy=0.0):
    if abs(angle) < 1e-4 and abs(dx) < 1e-4 and abs(dy) < 1e-4:
        return image
    t = math.radians(angle); c, s = math.cos(t), math.sin(t); px, py = pivot
    a, b, d, e = c, s, -s, c
    return image.transform(SIZE, Image.Transform.AFFINE,
        (a, b, px - a * (px + dx) - b * (py + dy), d, e, py - d * (px + dx) - e * (py + dy)),
        resample=Image.Resampling.BILINEAR)

def smooth(x):
    x = max(0.0, min(1.0, x)); return x * x * (3 - 2 * x)

def envelope(i, n, up, hold, down):
    """0..1 envelope: ramp up over `up` frames, hold, ramp down over `down` frames."""
    if i < up: return smooth(i / float(up))
    if i < up + hold: return 1.0
    return smooth(1.0 - (i - up - hold) / float(max(1, down)))

# ---- pose definitions: return (arms{}, legs{}, head_angle, body_y) --------------------------------------
def pose_thwip(i, n):
    e = envelope(i, n, 5, 7, 6); flick = math.sin(i * 1.3) * 3 * e
    return ({'arm_right': -88 * e + flick}, {'leg_left': 7 * e, 'leg_right': -7 * e}, -5 * e, 2.5 * e)
def pose_point(i, n):
    e = envelope(i, n, 4, 7, 5)
    return ({'arm_right': -64 * e + math.sin(i * .9) * 2 * e}, {}, -3 * e, 0)
def pose_stretch(i, n):
    e = envelope(i, n, 9, 15, 11); sway = math.sin(i * .35) * 3 * e
    return ({'arm_right': -168 * e + sway, 'arm_left': 168 * e - sway}, {'leg_left': 3 * e, 'leg_right': -3 * e}, -8 * e, -4 * e)
def pose_think(i, n):
    s = math.sin(2 * math.pi * i / n)
    return ({'arm_right': -148 + 9 * s}, {}, 5 + 2 * s, 0)
def pose_cheer(i, n):
    s = math.sin(2 * math.pi * i / (n / 2.0)); e = envelope(i, n, 3, 18, 3)
    return ({'arm_right': (-132 - 26 * s) * e, 'arm_left': (132 + 26 * s) * e}, {'leg_left': 9 * s * e, 'leg_right': -9 * s * e}, 6 * s * e, -11 * abs(s) * e)

EXTRAS = {  # name: (frames, fps, loop, pose function, web hand?)
    'thwip': (18, 18, False, pose_thwip, True),
    'point': (16, 16, False, pose_point, True),
    'stretch': (36, 12, False, pose_stretch, False),
    'think': (24, 10, True, pose_think, False),
    'cheer': (24, 16, False, pose_cheer, False),
}

def hand_tip(arm_img, pivot):
    """Farthest opaque point of the arm from its shoulder joint (the hand)."""
    a = arm_img.getchannel('A').point(lambda v: 255 if v > 128 else 0)
    px, py = pivot; best = None; bd = -1.0; w, h = a.size; data = a.load()
    pts = []
    for y in range(0, h):
        for x in range(0, w):
            if data[x, y]:
                d = (x - px) ** 2 + (y - py) ** 2
                pts.append((d, x, y))
    if not pts: return [px, py]
    pts.sort(reverse=True); top = pts[:25]
    return [sum(p[1] for p in top) / len(top), sum(p[2] for p in top) / len(top)]

def build(repo, out, cid):
    root = os.path.join(repo, 'characters', cid)
    src = Image.open(os.path.join(root, 'sprites', 'idle.png')).convert('RGBA')
    if cid == 'spider_2': rig = SPIDER2
    else:
        rp = os.path.join(root, 'rig', 'rig.json')
        if not os.path.exists(rp): return None
        rig = {k: v for k, v in json.load(open(rp)).items() if isinstance(v, dict)}
    parts = {n: layer(src, d['polygon']) for n, d in rig.items()}
    odir = os.path.join(out, cid); os.makedirs(odir, exist_ok=True)
    meta = {}
    for name, (n, fps, loop, fn, web) in EXTRAS.items():
        adir = os.path.join(odir, name); os.makedirs(adir, exist_ok=True)
        hands = []
        for i in range(n):
            arms, legs, head, by = fn(i, n)
            frame = Image.new('RGBA', SIZE); arm_img = None
            for part in (ORDER_FRONT if name in FRONT else ORDER):
                if part not in parts: continue
                ang = legs.get(part, arms.get(part, head if part == 'head' else 0.0))
                moved = transform(parts[part], rig[part]['pivot'], angle=ang, dy=by)
                if part == 'arm_right': arm_img = moved
                frame.alpha_composite(moved)
            if web and arm_img is not None:
                hx, hy = hand_tip(arm_img, [rig['arm_right']['pivot'][0], rig['arm_right']['pivot'][1] + by])
                hands.append([36 + hx * 440 / 512.0, 52 + hy * 440 / 512.0])   # same placement as the repo's rig clips
            frame = frame.resize((440, 440), Image.Resampling.LANCZOS)
            outimg = Image.new('RGBA', SIZE); outimg.alpha_composite(frame, (36, 52))
            outimg.save(os.path.join(adir, 'frame_%02d.png' % i))
        meta[name] = {'n': n, 'fps': fps, 'loop': loop}
        if hands: meta[name]['hands'] = hands
    json.dump(meta, open(os.path.join(odir, 'extras.json'), 'w'))
    return meta

if __name__ == '__main__':
    repo, out = sys.argv[1], sys.argv[2]
    ids = sys.argv[3:] or ['spider_2', 'tom_holland', 'miles_morales']
    for cid in ids:
        m = build(repo, out, cid)
        print(cid, 'extras:', ', '.join(m) if m else 'no rig')
