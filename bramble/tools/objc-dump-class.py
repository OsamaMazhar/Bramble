import sys, struct, mmap, os, re
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'objc-find-selector.py')).read().split("mn = sec('__objc_methname')")[0])

# reverse map: selref slot -> selector string, built lazily over __objc_selrefs
mn_a, mn_sz, mn_fo = sec('__objc_methname')
sr_a, sr_sz, sr_fo = sec('__objc_selrefs')
slot2sel = {}
for i in range(0, sr_sz, 8):
    t = deptr(struct.unpack_from('<Q', data, sr_fo + i)[0])
    if t is not None and mn_a <= t < mn_a + mn_sz:
        slot2sel[sr_a + i] = cstr(t)

def methods(mlist_addr):
    out = []
    if not mlist_addr: return out
    hdr = rd(mlist_addr, 8)
    if not hdr: return out
    ent, cnt = struct.unpack('<II', hdr)
    rel = bool(ent & 0x80000000); esz = ent & 0xFFFF
    if cnt > 20000 or esz not in (12, 24): return out
    for i in range(cnt):
        fa = mlist_addr + 8 + i * esz
        if rel:
            d = struct.unpack('<i', rd(fa, 4))[0]
            nm = slot2sel.get(fa + d)
            ty = None
            d2b = rd(fa + 4, 4)
            if d2b:
                ty = cstr(fa + 4 + struct.unpack('<i', d2b)[0])
        else:
            nm = cstr(deptr(u64(fa) or 0) or 0)
            ty = cstr(deptr(u64(fa + 8) or 0) or 0)
        if nm: out.append((nm, ty))
    return out

want = set(sys.argv[2].split(','))
pat = re.compile(sys.argv[3], re.I) if len(sys.argv) > 3 else None
a, sz, fo = sec('__objc_classlist')
for i in range(0, sz, 8):
    c = deptr(struct.unpack_from('<Q', data, fo + i)[0])
    if not c: continue
    ro = deptr(u64(c + 32) or 0)
    if not ro: continue
    ro &= ~0x3
    nm = cstr(deptr(u64(ro + 24) or 0) or 0)
    if nm not in want: continue
    for kind, addr in (('-', deptr(u64(ro + 32) or 0)),
                       ('+', (lambda m: deptr(u64((m & ~0x3) + 32) or 0) if m else None)(deptr(u64(deptr(u64(c) or 0) + 32) or 0) if deptr(u64(c) or 0) else None))):
        for s, t in methods(addr):
            if pat is None or pat.search(s):
                print(f"{kind}[{nm} {s}]   {t or ''}")
