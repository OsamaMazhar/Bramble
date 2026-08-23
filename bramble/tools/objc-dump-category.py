import sys, struct, mmap, os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'objc-find-selector.py')).read().split("mn = sec('__objc_methname')")[0])
mn_a, mn_sz, mn_fo = sec('__objc_methname')
sr_a, sr_sz, sr_fo = sec('__objc_selrefs')
slot2sel = {}
for i in range(0, sr_sz, 8):
    t = deptr(struct.unpack_from('<Q', data, sr_fo + i)[0])
    if t is not None and mn_a <= t < mn_a + mn_sz:
        slot2sel[sr_a + i] = cstr(t)
def methods(ml):
    out=[]
    if not ml: return out
    hdr = rd(ml,8)
    if not hdr: return out
    ent,cnt = struct.unpack('<II',hdr); rel = bool(ent & 0x80000000); esz = ent & 0xFFFF
    if cnt>5000 or esz not in (12,24): return out
    for i in range(cnt):
        fa = ml+8+i*esz
        if rel:
            d=struct.unpack('<i',rd(fa,4))[0]; nm=slot2sel.get(fa+d)
            t=cstr(fa+4+struct.unpack('<i',rd(fa+4,4))[0])
        else:
            nm=cstr(deptr(u64(fa) or 0) or 0); t=cstr(deptr(u64(fa+8) or 0) or 0)
        if nm: out.append((nm,t))
    return out
# chained-fixup imports for bind resolution
a,sz,fo = sec('__objc_catlist')
for i in range(0,sz,8):
    c = deptr(struct.unpack_from('<Q', data, fo+i)[0])
    if not c: continue
    if cstr(deptr(u64(c) or 0) or 0) != sys.argv[2]: continue
    raw = u64(c+8)
    print(f"class field raw=0x{raw:016x} bind={raw>>63} ordinal={raw & 0xFFFFFF}")
    for kind,off in (('-',16),('+',24)):
        for nm,t in methods(deptr(u64(c+off) or 0)):
            print(f"  {kind} {nm}   types={t}")
