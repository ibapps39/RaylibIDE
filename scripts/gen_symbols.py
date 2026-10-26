#!/usr/bin/env python3
"""Generate Generated/raylib_symbols.inc: one RL_SYM(name) per RLAPI function in raylib.h / rlgl.h."""
import re, sys, pathlib
src = pathlib.Path(sys.argv[1])          # raylib/src
out = pathlib.Path(sys.argv[2])
# declared only for the legacy OpenGL 1.1 backend
SKIP = {"rlEnableStatePointer", "rlDisableStatePointer"}
names = []
pat = re.compile(r'^\s*RLAPI\s+[^;(]*?\b([A-Za-z_]\w*)\s*\(')
for h in ("raylib.h", "rlgl.h"):
    for line in (src / h).read_text(errors="ignore").splitlines():
        m = pat.match(line)
        if m and m.group(1) not in names and m.group(1) not in SKIP:
            names.append(m.group(1))
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("".join(f"RL_SYM({n})\n" for n in names))
print(f"{len(names)} symbols -> {out}")
