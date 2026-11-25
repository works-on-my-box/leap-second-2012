#!/usr/bin/env python3
# mkcpio.py ROOTDIR OUT.cpio.gz — архив initramfs (newc) из каталога без root:
# владелец всех файлов 0:0, плюс узлы /dev/console и /dev/ttyS0 (их нельзя создать mknod без root).
import gzip
import os
import stat
import sys

root, out = sys.argv[1], sys.argv[2]
ino = [100]


def hdr(name, mode, size, rdevmaj=0, rdevmin=0, mtime=0):
    ino[0] += 1
    n = name.encode() + b"\0"
    fields = [ino[0], mode, 0, 0, 1, mtime, size, 0, 0, rdevmaj, rdevmin, len(n), 0]
    h = b"070701" + b"".join(b"%08X" % f for f in fields) + n
    return h + b"\0" * ((4 - len(h) % 4) % 4)


def pad(data):
    return data + b"\0" * ((4 - len(data) % 4) % 4)


with gzip.open(out, "wb", compresslevel=6) as f:
    entries = []
    for dp, dns, fns in os.walk(root):
        dns.sort()
        for nm in sorted(dns) + sorted(fns):
            entries.append(os.path.join(dp, nm))
    f.write(hdr("dev", stat.S_IFDIR | 0o755, 0))
    for p in entries:
        rel = os.path.relpath(p, root)
        st = os.lstat(p)
        if rel == "dev":
            continue
        if stat.S_ISLNK(st.st_mode):
            t = os.readlink(p).encode()
            f.write(hdr(rel, stat.S_IFLNK | 0o777, len(t), mtime=int(st.st_mtime)) + pad(t))
        elif stat.S_ISDIR(st.st_mode):
            f.write(hdr(rel, stat.S_IFDIR | stat.S_IMODE(st.st_mode), 0, mtime=int(st.st_mtime)))
        elif stat.S_ISREG(st.st_mode):
            with open(p, "rb") as g:
                d = g.read()
            f.write(hdr(rel, stat.S_IFREG | stat.S_IMODE(st.st_mode), len(d), mtime=int(st.st_mtime)) + pad(d))
    f.write(hdr("dev/console", stat.S_IFCHR | 0o600, 0, 5, 1))
    f.write(hdr("dev/ttyS0", stat.S_IFCHR | 0o660, 0, 4, 64))
    f.write(hdr("dev/null", stat.S_IFCHR | 0o666, 0, 1, 3))
    f.write(hdr("TRAILER!!!", 0, 0))
print("written", out, len(entries) + 4, "entries")
