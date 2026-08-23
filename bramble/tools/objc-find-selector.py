#!/usr/bin/env python3
"""Map ObjC selector -> owning class(es) in a stripped arm64 Mach-O with chained fixups."""
import sys, struct, re, mmap

path = sys.argv[1]
needles = [n.encode() for n in sys.argv[2:]]
f = open(path, 'rb'); data = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)

magic, cputype, cpusub, ftype, ncmds, sizeofcmds, flags, _r = struct.unpack_from('<IiiIIIII', data, 0)
assert magic == 0xfeedfacf, hex(magic)
secs = []          # (segname, sectname, addr, size, off)
off = 32
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', data, off)
    if cmd == 0x19:  # LC_SEGMENT_64
        segname = data[off+8:off+24].rstrip(b'\0').decode()
        vmaddr, vmsize, fileoff, filesize, _mx, _in, nsects, _fl = struct.unpack_from('<QQQQiiII', data, off+24)
        so = off + 72
        for _s in range(nsects):
            sectname = data[so:so+16].rstrip(b'\0').decode()
            addr, size = struct.unpack_from('<QQ', data, so+32)
            foff = struct.unpack_from('<I', data, so+48)[0]
            secs.append((segname, sectname, addr, size, foff))
            so += 80
    off += cmdsize

BASE = 0x100000000
def a2o(addr):
    for _sg, _sn, a, sz, fo in secs:
        if a <= addr < a + sz:
            return fo + (addr - a)
    return None
def sec(name):
    for sg, sn, a, sz, fo in secs:
        if sn == name:
            return (a, sz, fo)
    return None
def rd(addr, n):
    o = a2o(addr)
    return None if o is None else data[o:o+n]
def u64(addr):
    b = rd(addr, 8)
    return None if b is None else struct.unpack('<Q', b)[0]
def deptr(raw):
    """decode chained-fixup rebase; return vmaddr or None for binds"""
    if raw == 0: return None
    if raw >> 63:  # bind
        return None
    t = raw & 0xFFFFFFFFF
    return t if t >= BASE else BASE + t
def cstr(addr):
    o = a2o(addr)
    if o is None: return None
    e = data.find(b'\0', o)
    return data[o:e].decode('utf8', 'replace')

mn = sec('__objc_methname')
targets = {}
if mn:
    a, sz, fo = mn
    for m in re.finditer(b'|'.join(re.escape(n) + b'\0' for n in needles), data[fo:fo+sz]):
        s = m.group()[:-1].decode()
        # must start right after a NUL
        if m.start() == 0 or data[fo+m.start()-1] == 0:
            targets[a + m.start()] = s
if not targets:
    print("selector strings not found in __objc_methname"); sys.exit(1)
for k, v in targets.items(): print(f"  sel '{v}' @ {hex(k)}")

# selrefs pointing at those strings
selrefs = {}
sr = sec('__objc_selrefs')
a, sz, fo = sr
for i in range(0, sz, 8):
    tgt = deptr(struct.unpack_from('<Q', data, fo + i)[0])
    if tgt in targets:
        selrefs[a + i] = targets[tgt]
print("selrefs:", {hex(k): v for k, v in selrefs.items()})

def scan_methods(mlist_addr, cls, kind):
    if not mlist_addr: return
    hdr = rd(mlist_addr, 8)
    if not hdr: return
    ent, cnt = struct.unpack('<II', hdr)
    rel = bool(ent & 0x80000000)
    esz = ent & 0xFFFF
    if cnt > 20000 or esz not in (12, 24): return
    for i in range(cnt):
        fa = mlist_addr + 8 + i * esz
        if rel:
            b = rd(fa, 4)
            if not b: continue
            d = struct.unpack('<i', b)[0]
            slot = fa + d
            if slot in selrefs:
                print(f"{kind}[{cls} {selrefs[slot]}]")
        else:
            n = deptr(u64(fa) or 0)
            if n in targets:
                print(f"{kind}[{cls} {targets[n]}]")

def do_class(cls_addr, meta=False):
    isa = deptr(u64(cls_addr) or 0)
    ro = deptr(u64(cls_addr + 32) or 0)
    if not ro: return None
    ro &= ~0x3
    name = deptr(u64(ro + 24) or 0)
    nm = cstr(name) if name else None
    if not nm: return None
    scan_methods(deptr(u64(ro + 32) or 0), nm, '-' if not meta else '+')
    return isa

cl = sec('__objc_classlist')
a, sz, fo = cl
for i in range(0, sz, 8):
    c = deptr(struct.unpack_from('<Q', data, fo + i)[0])
    if not c: continue
    isa = do_class(c)
    if isa: do_class(isa, meta=True)

# categories
ct = sec('__objc_catlist')
if ct:
    a, sz, fo = ct
    for i in range(0, sz, 8):
        c = deptr(struct.unpack_from('<Q', data, fo + i)[0])
        if not c: continue
        nm = cstr(deptr(u64(c) or 0) or 0) or '?'
        scan_methods(deptr(u64(c + 16) or 0), f"CATEGORY {nm}", '-')
        scan_methods(deptr(u64(c + 24) or 0), f"CATEGORY {nm}", '+')
