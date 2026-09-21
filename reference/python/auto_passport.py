#!/usr/bin/env python3
"""
auto_passport.py  -  fully automatic Indian passport photo pipeline (no human in the loop)

  python3 auto_passport.py <input_dir> <output_dir> [--head-mm 36]

1. SELECT   score every photo in the folder, hard-reject unusable ones, pick the best
2. PROCESS  level the eyes, segment + matte, find crown and chin, crop to spec, white bg
3. VALIDATE re-measure the finished file against the spec and write a pass/fail report

Setup:
  pip install opencv-contrib-python-headless dlib-bin rembg onnxruntime pymatting pillow-heif
  shape_predictor_68_face_landmarks.dat (from the face_recognition_models PyPI sdist) next to chin.py
  rembg downloads isnet-general-use.onnx (~180 MB) on first run
"""
import os, sys, json, math, argparse, time
import numpy as np, cv2
from PIL import Image, ImageOps, ImageDraw
import pillow_heif; pillow_heif.register_heif_opener()
from pymatting import estimate_alpha_cf, estimate_foreground_ml
from rembg import new_session, remove
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from chin import landmarks, refine_chin

# ----------------------------------------------------------------------------- spec
SPEC = dict(
    name='India passport (VFS USA, 2026)',
    size_mm=(35.0, 45.0), px=(630, 810), print_px=(413, 531), dpi=300,
    head_mm_target=36.0,          # 80% of 45 mm: the one value inside every published range
    head_mm_tol=0.75,
    top_gap_mm=(1.5, 4.0), top_gap_target_mm=2.2,
    eye_from_bottom=(0.50, 0.60), # ICAO
    eye_target=0.55,
    max_roll_deg=2.0, max_centre_off=0.02,
    bg_pure_min=0.95, bg_min_val=245,
    file_kb=(10, 250),
    max_cheek_imbalance=0.10,
    min_eye_open=0.20, max_mouth_open=0.12,
    min_sharpness=250.0,          # eye-region Laplacian variance on the 630x810 output
    max_face_whitened=0.005,
    min_shoulder_span=0.60,
    published_ranges={'ICAO Doc 9303 (32-36 mm)': (32.0, 36.0),
                      'India-strict reading (36-38 mm)': (36.0, 38.0)},
)
MM = lambda px, H: SPEC['size_mm'][1] * px / H

# ----------------------------------------------------------------------------- helpers
def load(path):
    im = ImageOps.exif_transpose(Image.open(path)).convert('RGB')
    return cv2.cvtColor(np.array(im), cv2.COLOR_RGB2BGR)

def ear(P, idx):     # eye aspect ratio
    p = P[idx]
    return (np.linalg.norm(p[1]-p[5]) + np.linalg.norm(p[2]-p[4])) / (2*np.linalg.norm(p[0]-p[3]))

def metrics_from_landmarks(bgr, P):
    g = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY).astype(np.float32)
    le, re_ = P[36:42].mean(0), P[42:48].mean(0)
    roll = math.degrees(math.atan2(re_[1]-le[1], re_[0]-le[0]))
    iod = np.linalg.norm(re_-le)
    fw = P[16,0]-P[0,0]
    # yaw from half-face asymmetry: the far side of a turned face is foreshortened.
    # ratio = right half / left half about the nose; invert (1-kt)/(1+kt) with k = jaw depth / half width ~ 1.2
    lw, rw = P[30,0]-P[0,0], P[16,0]-P[30,0]
    q = rw/lw; t = (1-q)/(1+q)/1.2
    yaw = math.degrees(math.atan(t))
    eyes = min(ear(P, list(range(36,42))), ear(P, list(range(42,48))))
    mouth = np.linalg.norm(P[66]-P[62]) / np.linalg.norm(P[64]-P[60])
    # sharpness: face box normalised to 256 px so photos of different resolution compare fairly
    x0,x1 = int(P[0,0]), int(P[16,0]); y0,y1 = int(min(P[19,1],P[24,1])), int(P[8,1])
    roi = cv2.resize(g[y0:y1, x0:x1], (256,256), interpolation=cv2.INTER_AREA)
    sharp = cv2.Laplacian(roi, cv2.CV_32F).var()
    r = max(4, int(0.06*fw))
    cy = int((P[29,1]+P[33,1])/2)
    cl = g[cy-r:cy+r, int(P[2,0]+0.08*fw)-r:int(P[2,0]+0.08*fw)+r].mean()
    cr = g[cy-r:cy+r, int(P[14,0]-0.08*fw)-r:int(P[14,0]-0.08*fw)+r].mean()
    return dict(roll=roll, iod=iod, yaw_deg=yaw, eyes_open=eyes, mouth_open=mouth,
                sharp=float(sharp), cheek_imbalance=float(abs(cl-cr)/max(cl,cr)))

# ----------------------------------------------------------------------------- segmentation / matting
_SESS = None
def segment(bgr):
    global _SESS
    if _SESS is None: _SESS = new_session('isnet-general-use')
    m = remove(Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)), session=_SESS,
               only_mask=True, post_process_mask=False)
    return np.array(m).astype(np.float32)/255

def matte(bgr, m, P, work=2600):
    H, W = m.shape; S = max(H, W)/3088
    sc = min(1.0, work/max(H, W))
    ims = cv2.resize(bgr, None, fx=sc, fy=sc, interpolation=cv2.INTER_AREA); hs, ws = ims.shape[:2]
    hard = (cv2.resize(m, (ws, hs)) > 0.5).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(hard)
    if n > 1: hard = (lab == 1+np.argmax(st[1:, cv2.CC_STAT_AREA])).astype(np.uint8)
    hard = cv2.morphologyEx(hard, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(9,9)))
    hard = cv2.morphologyEx(hard, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(5,5)))
    ff = np.zeros((hs+2, ws+2), np.uint8); inv = (1-hard).copy()
    cv2.floodFill(inv, ff, (0,0), 2); hard = np.where(inv == 2, 0, 1).astype(np.uint8)   # fill holes
    dist = np.where(hard == 1, cv2.distanceTransform(hard, cv2.DIST_L2, 5),
                               cv2.distanceTransform(1-hard, cv2.DIST_L2, 5))
    brow = min(P[19,1], P[24,1]); fh = P[8,1]-brow
    yy = np.arange(hs, dtype=np.float32)[:, None]
    t = np.clip((yy - brow*sc)/(0.35*fh*sc), 0, 1); t = t*t*(3-2*t)
    bw = (1-t)*18*S + t*5*S                                                # wide in hair, narrow on skin
    tri = np.full((hs, ws), 0.5); tri[(hard==1)&(dist>bw)] = 1; tri[(hard==0)&(dist>bw)] = 0
    rgb = cv2.cvtColor(ims, cv2.COLOR_BGR2RGB).astype(np.float64)/255
    a = np.clip(estimate_alpha_cf(rgb, tri), 0, 1)
    hsv = cv2.cvtColor(ims, cv2.COLOR_BGR2HSV).astype(np.float32); Sat, V = hsv[...,1]/255, hsv[...,2]/255
    core = cv2.erode(((dist>4)&(tri>=0.5)).astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(5,5)))
    a = np.where((dist <= bw+2)&(core==0)&(Sat<0.18)&(V>0.42), 0.0, a)   # wall residue on the rim only
    a = cv2.GaussianBlur(a.astype(np.float32), (0,0), 0.7)
    a = cv2.resize(a, (W, H), interpolation=cv2.INTER_CUBIC).clip(0,1)
    return cv2.GaussianBlur(np.clip((a-0.12)/0.78, 0, 1), (0,0), max(0.8, 0.8*S))

def find_crown(a, P):
    """Top of the hair mass: first row where the subject spans >= 8% of head width (skips stray strands)."""
    fw = P[16,0]-P[0,0]
    cols = slice(max(0, int(P[0,0]-0.3*fw)), int(P[16,0]+0.3*fw))
    span = (a[:, cols] > 0.5).sum(axis=1)
    rows = np.where(span >= 0.08*fw)[0]
    return int(rows[0])

# ----------------------------------------------------------------------------- render
def render(bgr, a, box, size, sharp):
    xa, ya, xb, yb = [int(round(v)) for v in box]
    H, W = a.shape
    pad = [max(0,-ya), max(0,yb-H), max(0,-xa), max(0,xb-W)]
    if any(pad):
        bgr = cv2.copyMakeBorder(bgr, pad[0], pad[1], pad[2], pad[3], cv2.BORDER_CONSTANT, value=(255,255,255))
        a   = cv2.copyMakeBorder(a,   pad[0], pad[1], pad[2], pad[3], cv2.BORDER_CONSTANT, value=0)
        xa += pad[2]; xb += pad[2]; ya += pad[0]; yb += pad[0]
    rgb = cv2.cvtColor(bgr[ya:yb, xa:xb], cv2.COLOR_BGR2RGB).astype(np.float64)/255
    al = a[ya:yb, xa:xb].astype(np.float64); al = np.where(al<0.03, 0, np.where(al>0.97, 1, al))
    fg = estimate_foreground_ml(rgb, al)
    o = np.clip(fg*al[...,None] + (1-al[...,None]), 0, 1); o[al==0] = 1
    out = cv2.resize(cv2.cvtColor((o*255).astype(np.uint8), cv2.COLOR_RGB2BGR), size, interpolation=cv2.INTER_AREA)
    ao = cv2.resize(al.astype(np.float32), size, interpolation=cv2.INTER_AREA)
    def us(b, r, am):
        hi = b.astype(np.float32) - cv2.GaussianBlur(b, (0,0), r).astype(np.float32); hi[np.abs(hi)<2] = 0
        return np.clip(b.astype(np.float32) + am*hi, 0, 255).astype(np.uint8)
    s = us(us(out, sharp[0], sharp[1]), sharp[2], sharp[3])
    s = np.where((ao > 0.02)[...,None], s, 255).astype(np.uint8)
    edge = (ao > 0.02)&(ao < 0.98); s[edge] = out[edge]
    return s, ao

# ----------------------------------------------------------------------------- validate
def validate(path, face_ref=None):
    img = load(path); H, W = img.shape[:2]; A = img.astype(int)
    kb = os.path.getsize(path)/1024
    P = landmarks(img); res = {}
    def chk(key, ok, val, rule): res[key] = dict(ok=bool(ok), value=val, rule=rule)
    chk('dimensions', (W,H) == SPEC['px'], f'{W}x{H}', f"{SPEC['px'][0]}x{SPEC['px'][1]}")
    chk('file_size_kb', SPEC['file_kb'][0] <= kb <= SPEC['file_kb'][1], round(kb,1), f"{SPEC['file_kb'][0]}-{SPEC['file_kb'][1]} KB")
    if P is None:
        chk('face_detected', False, 'none', 'one face'); return res
    chk('face_detected', True, 'yes', 'one face')
    white = (A.min(axis=2) >= 250).astype(np.uint8)
    n, lab = cv2.connectedComponents(white); bg = lab == lab[0,0]
    pure = float((A[bg] == 255).all(axis=1).mean()); mn = int(A[bg].min())
    chk('background_white', pure >= SPEC['bg_pure_min'] and mn >= SPEC['bg_min_val'],
        f'{100*pure:.1f}% pure, min {mn}', f">={100*SPEC['bg_pure_min']:.0f}% pure 255, min >={SPEC['bg_min_val']}")
    sub = (~bg).astype(np.float32)
    crown = find_crown(sub, P); chin = refine_chin(img, P)
    head = MM(chin-crown, H)
    tgt, tol = SPEC['head_mm_target'], SPEC['head_mm_tol']
    chk('head_height_mm', abs(head-tgt) <= tol, round(head,2), f'{tgt} +/- {tol} mm (crown to chin)')
    gap = MM(crown, H)
    chk('top_gap_mm', SPEC['top_gap_mm'][0] <= gap <= SPEC['top_gap_mm'][1], round(gap,2), f"{SPEC['top_gap_mm'][0]}-{SPEC['top_gap_mm'][1]} mm")
    le, re_ = P[36:42].mean(0), P[42:48].mean(0)
    eb = (H - (le[1]+re_[1])/2)/H
    chk('eye_line_from_bottom', SPEC['eye_from_bottom'][0] <= eb <= SPEC['eye_from_bottom'][1], f'{100*eb:.1f}%', '50-60%')
    m = metrics_from_landmarks(img, P)
    chk('head_roll_deg', abs(m['roll']) <= SPEC['max_roll_deg'], round(m['roll'],2), f"<= {SPEC['max_roll_deg']} deg")
    off = abs((le[0]+re_[0])/2 - W/2)/W
    chk('centred', off <= SPEC['max_centre_off'], f'{100*off:.2f}% off', f"<= {100*SPEC['max_centre_off']:.0f}% of width")
    chk('head_yaw_deg', abs(m['yaw_deg']) <= 5.0, round(m['yaw_deg'],1), '<= 5 deg (ISO/IEC 19794-5); estimate +/- 2 deg')
    chk('eyes_open', m['eyes_open'] >= SPEC['min_eye_open'], round(m['eyes_open'],3), f">= {SPEC['min_eye_open']}")
    chk('mouth_closed', m['mouth_open'] <= SPEC['max_mouth_open'], round(m['mouth_open'],3), f"<= {SPEC['max_mouth_open']}")
    chk('even_lighting', m['cheek_imbalance'] <= SPEC['max_cheek_imbalance'], f"{100*m['cheek_imbalance']:.1f}%", f"<= {100*SPEC['max_cheek_imbalance']:.0f}% cheek difference")
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    ex, ey = (le+re_)/2; iod = np.linalg.norm(re_-le)
    sh = cv2.Laplacian(g[int(ey-0.35*iod):int(ey+0.35*iod), int(ex-0.95*iod):int(ex+0.95*iod)], cv2.CV_64F).var()
    chk('sharpness', sh >= SPEC['min_sharpness'], round(float(sh),1), f">= {SPEC['min_sharpness']}")
    # face integrity: nothing inside the face oval may have been turned white
    hull = cv2.convexHull(P[np.r_[0:17, 26:16:-1]].astype(np.int32))
    fm = np.zeros((H,W), np.uint8); cv2.fillConvexPoly(fm, hull, 1)
    fm = cv2.erode(fm, cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(15,15)))
    whit = float(((A.min(axis=2) >= 235) & (fm == 1)).sum() / max(1, fm.sum()))
    chk('face_not_whitened', whit <= SPEC['max_face_whitened'], f'{100*whit:.2f}% of face', f"<= {100*SPEC['max_face_whitened']:.1f}%")
    row = np.where(sub[H-1] > 0)[0]
    span = (row.max()-row.min())/W if len(row) else 0
    chk('shoulders_visible', span >= SPEC['min_shoulder_span'], f'{100*span:.0f}% of width at bottom', f">= {100*SPEC['min_shoulder_span']:.0f}%")
    res['_published_ranges'] = {k: (lo <= head <= hi) for k, (lo, hi) in SPEC['published_ranges'].items()}
    return res

# ----------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(); ap.add_argument('inp'); ap.add_argument('out')
    ap.add_argument('--head-mm', type=float, default=SPEC['head_mm_target'])
    args = ap.parse_args(); SPEC['head_mm_target'] = args.head_mm
    os.makedirs(args.out, exist_ok=True); t0 = time.time()
    files = sorted(f for f in os.listdir(args.inp) if f.lower().endswith(('.heic','.jpg','.jpeg','.png')))
    log = []

    # ---------- 1. SELECT
    cands = []
    for f in files:
        img = load(os.path.join(args.inp, f)); H, W = img.shape[:2]
        P = landmarks(img); rec = dict(file=f, size=f'{W}x{H}')
        if P is None: rec.update(reject='no face found'); cands.append(rec); continue
        m = metrics_from_landmarks(img, P); rec.update({k: round(v, 3) for k, v in m.items()})
        # head height in px estimated from landmarks, before any segmentation
        # (calibrated on IMG_0012 / IMG_0013: crown-to-chin = 1.64 x brow-to-chin)
        chin = refine_chin(img, P); brow = min(P[19,1], P[24,1])
        est_head = (chin-brow)*1.64
        need = SPEC['px'][1]*SPEC['head_mm_target']/SPEC['size_mm'][1]
        rec['est_head_px'] = int(est_head); rec['scale'] = round(est_head/need, 2)
        reasons = []
        if m['sharp'] < 100: reasons.append(f"blurry (sharpness {m['sharp']:.0f}, need >= 100)")
        if m['eyes_open'] < SPEC['min_eye_open']: reasons.append('eyes closed')
        if m['mouth_open'] > SPEC['max_mouth_open']: reasons.append('mouth open')
        if abs(m['yaw_deg']) > 8: reasons.append(f"head turned {m['yaw_deg']:+.1f} deg")
        if m['cheek_imbalance'] > SPEC['max_cheek_imbalance']:
            reasons.append(f"uneven lighting ({100*m['cheek_imbalance']:.1f}% cheek difference) - processing can't fix this")
        if abs(m['roll']) > 10: reasons.append(f"head tilted {m['roll']:.1f} deg")
        if est_head < need: reasons.append(f'too small/far: face would need {need/est_head:.2f}x upscaling')
        Hc = est_head/(SPEC['head_mm_target']/SPEC['size_mm'][1]); Wc = Hc*7/9
        cx = (P[36:48,0]).mean()
        if cx-Wc/2 < -0.02*Wc or cx+Wc/2 > W+0.02*Wc or chin + 0.25*Hc > H: reasons.append('not enough room around head/shoulders in frame')
        if reasons: rec['reject'] = '; '.join(reasons)
        # score (higher = better): sharpness dominates, then lighting, frontality, level
        rec['score'] = round(
            0.35*min(1, m['sharp']/300) +
            0.25*max(0, 1-m['cheek_imbalance']/0.10) +
            0.25*max(0, 1-abs(m['yaw_deg'])/8) +
            0.10*max(0, 1-abs(m['roll'])/10) +
            0.05*min(1, rec['scale']/2.5), 3)
        cands.append(rec)
    ok = [c for c in cands if 'reject' not in c]
    ranked = sorted(ok, key=lambda c: -c['score']) + [c for c in cands if 'reject' in c]
    if not ok:
        json.dump(dict(status='NO USABLE PHOTO', candidates=ranked), open(os.path.join(args.out,'report.json'),'w'), indent=2)
        write_md(args.out, ranked, None, None, None, time.time()-t0); print('No usable photo; see report.md'); return
    best = ok and max(ok, key=lambda c: c['score'])

    # ---------- 2. PROCESS
    img = load(os.path.join(args.inp, best['file'])); H, W = img.shape[:2]
    P = landmarks(img)
    le, re_ = P[36:42].mean(0), P[42:48].mean(0)
    th = math.degrees(math.atan2(re_[1]-le[1], re_[0]-le[0]))
    M = cv2.getRotationMatrix2D(tuple(((le+re_)/2).tolist()), th, 1.0)
    img = cv2.warpAffine(img, M, (W, H), flags=cv2.INTER_LANCZOS4, borderMode=cv2.BORDER_REPLICATE)
    P = landmarks(img)
    m = segment(img); a = matte(img, m, P)
    crown = find_crown(a, P); chin = refine_chin(img, P)
    le, re_ = P[36:42].mean(0), P[42:48].mean(0); eye_y = (le[1]+re_[1])/2; cx = (le[0]+re_[0])/2
    hf = SPEC['head_mm_target']/SPEC['size_mm'][1]
    Hc = (chin-crown)/hf; Wc = Hc*SPEC['size_mm'][0]/SPEC['size_mm'][1]
    # aim for a comfortable top gap; only move off it if the eye line would leave its 50-60% band
    r = (eye_y-crown)/(chin-crown)
    topf = SPEC['top_gap_target_mm']/SPEC['size_mm'][1]
    eb = 1 - topf - r*hf
    e_lo, e_hi = SPEC['eye_from_bottom']
    if eb < e_lo+0.01: topf = 1 - (e_lo+0.01) - r*hf
    if eb > e_hi-0.01: topf = 1 - (e_hi-0.01) - r*hf
    lo, hi = [v/SPEC['size_mm'][1] for v in SPEC['top_gap_mm']]
    topf = min(max(topf, lo+0.004), hi-0.004)
    top = crown - topf*Hc
    box = (cx-Wc/2, top, cx+Wc/2, top+Hc)
    # background: how far was the real wall from white? (light cleanup vs full replacement)
    bgmask = cv2.resize((a < 0.02).astype(np.uint8), None, fx=0.25, fy=0.25) > 0
    small = cv2.resize(img, None, fx=0.25, fy=0.25)
    ya, yb, xa, xb = [int(max(0, v*0.25)) for v in (box[1], box[3], box[0], box[2])]
    region = small[ya:yb, xa:xb][bgmask[ya:yb, xa:xb]]
    bg_dist = float(255 - region.mean()) if region.size else 0.0
    bg_std = float(region.std()) if region.size else 0.0
    bg_mode = 'light cleanup (wall was already near-white)' if bg_dist < 25 and bg_std < 12 else 'full background replacement'

    dig, _ = render(img, a, box, SPEC['px'], (1.3,0.28,0.8,0.32))
    prn, _ = render(img, a, box, SPEC['print_px'], (1.1,0.20,0.7,0.22))
    up = os.path.join(args.out, 'upload_630x810.jpg')
    Image.fromarray(cv2.cvtColor(dig, cv2.COLOR_BGR2RGB)).save(up, dpi=(300,300), quality=96, subsampling=0)
    q = 96
    while os.path.getsize(up)/1024 > SPEC['file_kb'][1] and q > 70:
        q -= 4; Image.fromarray(cv2.cvtColor(dig, cv2.COLOR_BGR2RGB)).save(up, dpi=(300,300), quality=q, subsampling=0)
    sheet = np.full((1800,1200,3), 255, np.uint8); TW, TH = SPEC['print_px']; gx, gy = 60, 40
    x0 = (1200-(2*TW+gx))//2; y0 = (1800-(3*TH+2*gy))//2
    for rr in range(3):
        for c in range(2):
            x = x0+c*(TW+gx); y = y0+rr*(TH+gy)
            sheet[y:y+TH, x:x+TW] = prn; cv2.rectangle(sheet, (x-1,y-1), (x+TW,y+TH), (205,205,205), 1)
    sh = Image.fromarray(cv2.cvtColor(sheet, cv2.COLOR_BGR2RGB)); d = ImageDraw.Draw(sh)
    d.text((20,14), f"35 x 45 mm, head {SPEC['head_mm_target']} mm - print 4x6 in at 100%, no scaling - cut on grey lines", fill=(120,120,120))
    sh.save(os.path.join(args.out, 'print_4x6.jpg'), dpi=(300,300), quality=96, subsampling=0)

    # ---------- 3. VALIDATE
    val = validate(up)
    proc = dict(source=best['file'], rotation_deg=round(th,2), crown_px=crown, chin_px=int(chin),
                head_px=int(chin-crown), crop_px=f'{int(Wc)}x{int(Hc)}',
                resample=f"{Wc/SPEC['px'][0]:.2f}x {'downscale' if Wc >= SPEC['px'][0] else 'UPSCALE'}",
                background=bg_mode, bg_distance_from_white=round(bg_dist,1))
    allok = all(v['ok'] for k, v in val.items() if not k.startswith('_'))
    json.dump(dict(status='PASS' if allok else 'FAIL', spec=SPEC, processing=proc, checks=val, candidates=ranked),
              open(os.path.join(args.out,'report.json'),'w'), indent=2, default=str)
    write_md(args.out, ranked, best, proc, val, time.time()-t0)
    print(open(os.path.join(args.out,'report.md')).read())

def write_md(out, ranked, best, proc, val, secs):
    L = ['# Passport photo report', '']
    if val:
        allok = all(v['ok'] for k, v in val.items() if not k.startswith('_'))
        L += [f"**Result: {'PASS' if allok else 'FAIL'}** - {SPEC['name']}, {secs:.0f}s, no human input", '']
        L += ['## Checks on the finished file', '', '| check | result | value | rule |', '|---|---|---|---|']
        for k, v in val.items():
            if k.startswith('_'): continue
            L.append(f"| {k} | {'pass' if v['ok'] else '**FAIL**'} | {v['value']} | {v['rule']} |")
        L += ['', 'Head height against the published ranges:']
        for k, ok in val['_published_ranges'].items(): L.append(f"- {k}: {'inside' if ok else 'outside'}")
        L += ['', '## Processing', '']
        for k, v in proc.items(): L.append(f'- {k}: {v}')
    else:
        L += ['**Result: NO USABLE PHOTO**', '']
    L += ['', '## Photo selection', '', '| rank | file | score | sharp | cheek diff | yaw deg | roll | scale | verdict |', '|---|---|---|---|---|---|---|---|---|']
    for i, c in enumerate(ranked, 1):
        v = 'REJECTED: '+c['reject'] if 'reject' in c else ('**chosen**' if best and c['file']==best['file'] else 'ok')
        L.append(f"| {i} | {c['file']} | {c.get('score','-')} | {c.get('sharp','-')} | "
                 f"{('%.1f%%'%(100*c['cheek_imbalance'])) if 'cheek_imbalance' in c else '-'} | "
                 f"{('%+.1f'%c['yaw_deg']) if 'yaw_deg' in c else '-'} | {c.get('roll','-')} | {c.get('scale','-')} | {v} |")
    open(os.path.join(out,'report.md'),'w').write('\n'.join(L)+'\n')

if __name__ == '__main__':
    main()
