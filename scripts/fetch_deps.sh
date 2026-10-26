#!/usr/bin/env bash
# Pulls raylib + TinyCC from GitHub (or uses folders you provide), patches raylib for the iOS
# platform backend, and generates everything the Xcode project needs.
#   Provide your own raylib:   put it at Vendor/raylib  (must contain src/raylib.h) before running.
#   Pick another version:      RAYLIB_REF=master ./scripts/fetch_deps.sh
set -euo pipefail
cd "$(dirname "$0")/.."

RAYLIB_REPO="${RAYLIB_REPO:-https://github.com/raysan5/raylib.git}"
RAYLIB_REF="${RAYLIB_REF:-5.5}"
TCC_REPO="${TCC_REPO:-https://github.com/TinyCC/tinycc.git}"
TCC_REF="${TCC_REF:-mob}"

mkdir -p Vendor Generated Resources/include/sys

if [ ! -f Vendor/raylib/src/raylib.h ]; then
  echo "==> cloning raylib ($RAYLIB_REF)"
  git clone --depth 1 --branch "$RAYLIB_REF" "$RAYLIB_REPO" Vendor/raylib
else
  echo "==> using existing Vendor/raylib"
fi
if [ ! -f Vendor/tinycc/libtcc.c ]; then
  echo "==> cloning tinycc ($TCC_REF)"
  git clone --depth 1 --branch "$TCC_REF" "$TCC_REPO" Vendor/tinycc
else
  echo "==> using existing Vendor/tinycc"
fi

# --- raylib: hook our platform backend into rcore.c (idempotent) --------------------------
cp Platform/rcore_ios.c Vendor/raylib/src/platforms/rcore_ios.c
if ! grep -q 'PLATFORM_IOS' Vendor/raylib/src/rcore.c; then
  python3 - <<'PY'
import re, pathlib
p = pathlib.Path("Vendor/raylib/src/rcore.c")
s = p.read_text()
needle = '#include "platforms/rcore_android.c"'
assert needle in s, "unexpected rcore.c layout - check this raylib version"
s = s.replace(needle, needle + '\n#elif defined(PLATFORM_IOS)\n    #include "platforms/rcore_ios.c"', 1)
p.write_text(s)
print("patched rcore.c")
PY
fi

# --- TinyCC: config.h + generated predefs ------------------------------------------------
VER="$(cat Vendor/tinycc/VERSION)"
cat > Vendor/tinycc/config.h <<CFG
#define TCC_VERSION "$VER"
#define CONFIG_TCC_PREDEFS 1
#define CONFIG_TCC_BACKTRACE 0
#define CONFIG_TCC_BCHECK 0
#define CONFIG_TCCDIR "/tcc"
#define CONFIG_TCC_SEMLOCK 0
CFG
( cd Vendor/tinycc && cc -DC2STR conftest.c -o /tmp/c2str && /tmp/c2str include/tccdefs.h tccdefs_.h )

# --- Headers shipped inside the app (what your programs #include) ------------------------
cp Vendor/raylib/src/raylib.h Vendor/raylib/src/raymath.h Vendor/raylib/src/rlgl.h Resources/include/
cp Vendor/raylib/src/rcamera.h Vendor/raylib/src/rgestures.h Resources/include/ 2>/dev/null || true
for h in Vendor/tinycc/include/*.h; do
  [ "$(basename "$h")" = tccdefs.h ] || cp "$h" Resources/include/
done

python3 scripts/gen_symbols.py Vendor/raylib/src Generated/raylib_symbols.inc
echo "==> done. Next: xcodegen generate && open RaylibIDE.xcodeproj"
