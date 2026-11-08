#!/usr/bin/env python3
"""Bake Spiderman-Pet character animations into sprite strips for RIO LIFE OS.

Usage:  python bake_pets.py <path-to>/Spiderman-Pet-main/characters <output pets folder> [--extras <dir>] [character ids...]
        (--extras = output folder of make_extra_anims.py: adds thwip / point / stretch / think / cheer)
Needs:  pip install pillow
Result: <out>/<id>/<anim>.png (one horizontal strip per animation) + <out>/<id>/pet.json
"""
import json, os, sys
from PIL import Image

TARGET_H = 172          # on-screen height of a standing character, in pixels
PAD = 6

def bake(chars_dir, out_dir, cid, extras_dir=None):
    root = os.path.join(chars_dir, cid)
    man = json.load(open(os.path.join(root, 'animation_manifest.json')))
    canvas = man.get('canvas', [512, 512])
    anchor = man.get('anchor') or [canvas[0] // 2, canvas[1] - 24]
    anims = man['animations']
    ex = {}
    if extras_dir and os.path.exists(os.path.join(extras_dir, cid, 'extras.json')):
        ex = json.load(open(os.path.join(extras_dir, cid, 'extras.json')))
    def frame_path(name, i):
        if name in ex: return os.path.join(extras_dir, cid, name, 'frame_%02d.png' % i)
        return os.path.join(root, anims[name]['frames'][i])
    names = list(anims.keys()) + [n for n in ex if n not in anims]
    counts = {n: (ex[n]['n'] if n in ex else len(anims[n]['frames'])) for n in names}
    # union bounding box over every frame so all frames share one crop (no jitter)
    ux0, uy0, ux1, uy1 = 10**6, 10**6, -1, -1
    idle0 = Image.open(os.path.join(root, anims['idle']['frames'][0])).convert('RGBA').getbbox()
    stand_h = idle0[3] - idle0[1]
    for n in names:
        for i in range(counts[n]):
            im = Image.open(frame_path(n, i)).convert('RGBA')
            bb = im.getbbox()
            if not bb: continue
            ux0 = min(ux0, bb[0]); uy0 = min(uy0, bb[1]); ux1 = max(ux1, bb[2]); uy1 = max(uy1, bb[3])
    ux0 = max(0, ux0 - PAD); uy0 = max(0, uy0 - PAD); ux1 = min(canvas[0], ux1 + PAD); uy1 = min(canvas[1], uy1 + PAD)
    sc = TARGET_H / float(stand_h)
    fw = int(round((ux1 - ux0) * sc)); fh = int(round((uy1 - uy0) * sc))
    ax = (anchor[0] - ux0) * sc; ay = (anchor[1] - uy0) * sc
    odir = os.path.join(out_dir, cid); os.makedirs(odir, exist_ok=True)
    meta = {'name': cid, 'fw': fw, 'fh': fh, 'ax': round(ax, 1), 'ay': round(ay, 1), 'anims': {}}
    for n in names:
        cnt = counts[n]
        strip = Image.new('RGBA', (fw * cnt, fh), (0, 0, 0, 0))
        for i in range(cnt):
            im = Image.open(frame_path(n, i)).convert('RGBA').crop((ux0, uy0, ux1, uy1))
            im = im.resize((fw, fh), Image.LANCZOS)
            strip.paste(im, (i * fw, 0))
        strip.save(os.path.join(odir, n + '.png'), optimize=True)
        if n in ex:
            e = ex[n]; meta['anims'][n] = {'n': cnt, 'fps': e['fps'], 'loop': bool(e['loop'])}
            if 'hands' in e:   # hand position per frame in baked-frame pixels (used for the web-shot teleport)
                meta['anims'][n]['hands'] = [[round((h[0] - ux0) * sc, 1), round((h[1] - uy0) * sc, 1)] for h in e['hands']]
        else:
            a = anims[n]; meta['anims'][n] = {'n': cnt, 'fps': a.get('fps', 12), 'loop': bool(a.get('loop', True))}
    json.dump(meta, open(os.path.join(odir, 'pet.json'), 'w'), separators=(',', ':'))
    return meta

if __name__ == '__main__':
    args = sys.argv[1:]
    extras_dir = None
    if '--extras' in args:
        k = args.index('--extras'); extras_dir = args[k + 1]; del args[k:k + 2]
    chars_dir, out_dir = args[0], args[1]
    ids = args[2:] or [d for d in sorted(os.listdir(chars_dir)) if os.path.isdir(os.path.join(chars_dir, d))]
    for cid in ids:
        m = bake(chars_dir, out_dir, cid, extras_dir)
        print(cid, m['fw'], 'x', m['fh'], len(m['anims']), 'animations')
