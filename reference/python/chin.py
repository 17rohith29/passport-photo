import dlib, cv2, numpy as np
_det=dlib.get_frontal_face_detector(); _sp=dlib.shape_predictor('shape_predictor_68_face_landmarks.dat')
def landmarks(bgr):
    g=cv2.cvtColor(bgr,cv2.COLOR_BGR2GRAY); s=min(1.0,1000/max(g.shape))
    r=_det(cv2.resize(g,None,fx=s,fy=s),1)
    if not r: return None
    r=max(r,key=lambda b:b.area())
    sh=_sp(g,dlib.rectangle(int(r.left()/s),int(r.top()/s),int(r.right()/s),int(r.bottom()/s)))
    return np.array([(sh.part(i).x,sh.part(i).y) for i in range(68)],float)
def refine_chin(bgr,P,debug=False):
    """Start at landmark 8, walk down the centre strip. Chin bottom = where beard texture
    (bearded) or the jaw edge (clean-shaven) ends and smooth neck skin begins."""
    g=cv2.cvtColor(bgr,cv2.COLOR_BGR2GRAY).astype(np.float32)
    fw=P[16,0]-P[0,0]; cx=P[8,0]; y8=P[8,1]
    face_h=y8-(P[19,1]+P[24,1])/2
    half=int(0.10*fw)
    y0=int(y8-0.05*face_h); y1=int(y8+0.22*face_h)
    strip=g[y0:y1,int(cx-half):int(cx+half)]
    # texture energy per row (beard hair = high frequency)
    lap=np.abs(cv2.Laplacian(cv2.GaussianBlur(strip,(0,0),1.0),cv2.CV_32F))
    tex=cv2.GaussianBlur(lap.mean(axis=1)[:,None],(1,0),sigmaX=0,sigmaY=0.012*face_h).ravel()
    lum=cv2.GaussianBlur(strip.mean(axis=1)[:,None],(1,0),sigmaX=0,sigmaY=0.008*face_h).ravel()
    ref=np.median(tex[:int(0.10*face_h)])                 # beard / chin texture level at landmark 8
    neck=np.median(tex[-int(0.06*face_h):])               # smooth neck level
    thr=neck+0.35*(ref-neck)
    start=int(0.05*face_h)
    below=np.where(tex[start:]<thr)[0]
    y_tex=y0+start+(below[0] if len(below) else len(tex)-start-1)
    # clean-shaven fallback: strongest light->dark edge (chin -> under-chin shadow)
    dl=np.diff(lum); k=np.argmin(dl[start:])+start
    y_edge=y0+k
    bearded = ref > 1.8*neck
    chin = y_tex if bearded else y_edge
    return (chin,dict(y8=y8,y_tex=y_tex,y_edge=y_edge,bearded=bearded,ref=ref,neck=neck)) if debug else chin
