#!/usr/bin/env python3
# clean-typescript.py IN OUT_TXT [OUT_RAW] — текст записи `script` без \r и управляющих последовательностей терминала;
# строка-заголовок «Script started …» заменяется короткой (полные пути в команде — только имена файлов).
# OUT_RAW (необязательно) — сырая запись с той же заменой заголовка, для scriptreplay вместе с файлом времени.
import re
import sys

src, out_txt = sys.argv[1], sys.argv[2]
out_raw = sys.argv[3] if len(sys.argv) > 3 else None
data = open(src, "rb").read()
first, rest = data.split(b"\n", 1)
m = re.search(rb"Script started on (\S+ \S+)", first)
cmd = re.search(rb'COMMAND="([^"]*)"', first)
args = []
if cmd:
    for a in cmd.group(1).split():
        args.append(a.rsplit(b"/", 1)[-1])
hdr = b"Script started on " + (m.group(1) if m else b"?") + b' [COMMAND="' + b" ".join(args) + b'"]'
if out_raw:
    open(out_raw, "wb").write(hdr + b"\n" + rest)
text = rest.decode("utf-8", "replace")
text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)
text = re.sub(r"\x1b[()][0-9A-Za-z]", "", text)
text = re.sub(r"\x1b[c78=>DEHMZ]", "", text)
text = text.replace("\r", "")
text = re.sub(r"[\x00-\x08\x0b-\x1f]", "", text)
open(out_txt, "w").write(hdr.decode() + "\n" + text)
print("ok", out_txt)
