# raylib IDE for iOS

Write C, run **real raylib**, see the output — all inside one iOS app.

* **Editor**: syntax highlighting, auto-indent, autocomplete indexed from `raylib.h` / `raymath.h` / `rlgl.h`
  (+ libc and identifiers in your file), signature help, symbol bar above the keyboard, multi-file projects.
* **Compiler**: TinyCC embedded as a library, compiling to memory (ARM64 / Apple ABI).
* **raylib**: the actual raylib source, built into the app with a custom iOS platform backend
  (`Platform/rcore_ios.c` + `ios_gl.m`: EAGL / OpenGL ES 3, multitouch → mouse + touch + gestures).
* **Console**: stdout/stderr/`TraceLog` captured; compile errors are tappable and jump to the line.

## Build the .ipa (needs macOS — GitHub Actions does it for you)

1. Push this folder to a GitHub repo → Actions → **Build unsigned IPA** → download `RaylibIDE.ipa`.
   (`RAYLIB_REF` lets you pick any raylib tag/branch; default `5.5`.)
2. Or locally: `brew install xcodegen && ./scripts/fetch_deps.sh && xcodegen generate && open RaylibIDE.xcodeproj`.

**Bring your own raylib:** drop your copy at `Vendor/raylib` (must contain `src/raylib.h`) *before* running
`fetch_deps.sh`; it is used instead of cloning from GitHub.

Install the unsigned .ipa with AltStore / Sideloadly / TrollStore.

## JIT is required to run programs

iOS only lets an app execute freshly generated machine code when JIT is enabled for it:
StikJIT / AltStore "Enable JIT", a TrollStore install, or launching from Xcode. Settings → JIT shows the status.
Without JIT you can still edit; Run reports the problem instead of crashing.

## Notes / limits

* C only (TinyCC). C++ is not supported.
* `InitWindow(w, h, …)` gives a *w×h* pixel surface, aspect-fit on screen; `InitWindow(0,0,…)` or
  `FLAG_FULLSCREEN_MODE` uses native resolution. Touch = `IsMouseButtonDown` + `GetMousePosition` + `GetTouch*` + gestures.
  No hardware-keyboard input yet.
* Projects live in Files → *On My iPhone → RaylibIDE → Projects*; the program's working directory is its project folder.
* In-app *Settings → Download headers* refreshes autocomplete/`#include` headers from GitHub. The compiled raylib
  library is fixed at build time, so keep header and library versions matching.
* Programs that call `exit()`/`abort()` or crash (SIGSEGV etc.) are caught and unwound instead of killing the app.
