// raylib platform backend for iOS (OpenGL ES 3 via EAGL). Included from rcore.c
// when PLATFORM_IOS is defined (scripts/fetch_deps.sh patches rcore.c).
// The user's program runs on a background thread; this file never touches UIKit
// directly - everything UIKit-ish lives in ios_gl.m.

#include <dlfcn.h>
#include "ios_gl.h"
#include "tcc_runner.h"

typedef struct { int dummy; } PlatformData;
static PlatformData platform = { 0 };

unsigned int rlios_default_fbo = 0;

static void *IosGetProc(const char *name) { return dlsym(RTLD_DEFAULT, name); }

//----------------------------------------------------------------------------------
// Window / graphics
//----------------------------------------------------------------------------------
bool WindowShouldClose(void)
{
    if (rlrun_stop_requested()) return true;
    if (CORE.Window.ready) return CORE.Window.shouldClose;
    else return true;
}

void ToggleFullscreen(void)         { TRACELOG(LOG_WARNING, "ToggleFullscreen() not available on iOS"); }
void ToggleBorderlessWindowed(void) { TRACELOG(LOG_WARNING, "ToggleBorderlessWindowed() not available on iOS"); }
void MaximizeWindow(void)           { TRACELOG(LOG_WARNING, "MaximizeWindow() not available on iOS"); }
void MinimizeWindow(void)           { TRACELOG(LOG_WARNING, "MinimizeWindow() not available on iOS"); }
void RestoreWindow(void)            { TRACELOG(LOG_WARNING, "RestoreWindow() not available on iOS"); }
void SetWindowState(unsigned int flags)   { CORE.Window.flags |= flags; }
void ClearWindowState(unsigned int flags) { CORE.Window.flags &= ~flags; }
void SetWindowIcon(Image image)           { (void)image; }
void SetWindowIcons(Image *images, int count) { (void)images; (void)count; }
void SetWindowTitle(const char *title)    { CORE.Window.title = title; }
void SetWindowPosition(int x, int y)      { (void)x; (void)y; }
void SetWindowMonitor(int monitor)        { (void)monitor; }
void SetWindowMinSize(int width, int height) { CORE.Window.screenMin.width = width; CORE.Window.screenMin.height = height; }
void SetWindowMaxSize(int width, int height) { CORE.Window.screenMax.width = width; CORE.Window.screenMax.height = height; }
void SetWindowSize(int width, int height)    { (void)width; (void)height; TRACELOG(LOG_WARNING, "SetWindowSize() not available on iOS"); }
void SetWindowOpacity(float opacity)         { (void)opacity; }
void SetWindowFocused(void)                  { }
void *GetWindowHandle(void)                  { return NULL; }

int GetMonitorCount(void)   { return 1; }
int GetCurrentMonitor(void) { return 0; }
Vector2 GetMonitorPosition(int monitor) { (void)monitor; return (Vector2){ 0, 0 }; }
int GetMonitorWidth(int monitor)  { (void)monitor; return CORE.Window.display.width; }
int GetMonitorHeight(int monitor) { (void)monitor; return CORE.Window.display.height; }
int GetMonitorPhysicalWidth(int monitor)  { (void)monitor; return 0; }
int GetMonitorPhysicalHeight(int monitor) { (void)monitor; return 0; }
int GetMonitorRefreshRate(int monitor)    { (void)monitor; return 60; }
const char *GetMonitorName(int monitor)   { (void)monitor; return "iOS Display"; }
Vector2 GetWindowPosition(void) { return (Vector2){ 0, 0 }; }
Vector2 GetWindowScaleDPI(void) { return (Vector2){ 1.0f, 1.0f }; }

void SetClipboardText(const char *text) { ios_set_clipboard(text); }
const char *GetClipboardText(void)      { return ios_get_clipboard(); }

void ShowCursor(void)    { CORE.Input.Mouse.cursorHidden = false; }
void HideCursor(void)    { CORE.Input.Mouse.cursorHidden = true; }
void EnableCursor(void)  { CORE.Input.Mouse.cursorHidden = false; }
void DisableCursor(void) { CORE.Input.Mouse.cursorHidden = true; }

void SwapScreenBuffer(void)
{
    ios_gl_present();
    rlrun_checkpoint();      // lets "Stop" unwind a program that never calls WindowShouldClose()
}

//----------------------------------------------------------------------------------
// Misc
//----------------------------------------------------------------------------------
double GetTime(void)
{
    struct timespec ts = { 0 };
    clock_gettime(CLOCK_MONOTONIC, &ts);
    unsigned long long ns = (unsigned long long)ts.tv_sec*1000000000LLU + (unsigned long long)ts.tv_nsec;
    return (double)(ns - CORE.Time.base)*1e-9;
}

void OpenURL(const char *url)
{
    if (strchr(url, '\'') != NULL) TRACELOG(LOG_WARNING, "SYSTEM: Provided URL could be potentially malicious, avoid [\'] character");
    else ios_open_url(url);
}

//----------------------------------------------------------------------------------
// Input
//----------------------------------------------------------------------------------
int SetGamepadMappings(const char *mappings) { (void)mappings; return 0; }

void SetMousePosition(int x, int y)
{
    CORE.Input.Mouse.currentPosition = (Vector2){ (float)x, (float)y };
    CORE.Input.Mouse.previousPosition = CORE.Input.Mouse.currentPosition;
}

void SetMouseCursor(int cursor) { (void)cursor; }
const char *GetKeyName(int key) { (void)key; return ""; }

void PollInputEvents(void)
{
    rlrun_checkpoint();

#if defined(SUPPORT_GESTURES_SYSTEM)
    UpdateGestures();
#endif

    CORE.Input.Keyboard.keyPressedQueueCount = 0;
    CORE.Input.Keyboard.charPressedQueueCount = 0;
    for (int i = 0; i < MAX_KEYBOARD_KEYS; i++) CORE.Input.Keyboard.keyRepeatInFrame[i] = 0;
    CORE.Input.Gamepad.lastButtonPressed = 0;

    for (int i = 0; i < MAX_TOUCH_POINTS; i++) CORE.Input.Touch.previousTouchState[i] = CORE.Input.Touch.currentTouchState[i];
    for (int i = 0; i < MAX_KEYBOARD_KEYS; i++) CORE.Input.Keyboard.previousKeyState[i] = CORE.Input.Keyboard.currentKeyState[i];

    // Read the touch snapshot written by the UI thread
    int ids[MAX_TOUCH_POINTS]; float xs[MAX_TOUCH_POINTS], ys[MAX_TOUCH_POINTS];
    int n = ios_touch_snapshot(ids, xs, ys, MAX_TOUCH_POINTS);
    int prevCount = CORE.Input.Touch.pointCount;

    CORE.Input.Touch.pointCount = n;
    for (int i = 0; i < n; i++)
    {
        CORE.Input.Touch.pointId[i] = ids[i];
        CORE.Input.Touch.position[i] = (Vector2){ xs[i]*CORE.Window.screen.width, ys[i]*CORE.Window.screen.height };
    }

#if defined(SUPPORT_GESTURES_SYSTEM)
    if (n > 0 || prevCount > 0)
    {
        GestureEvent ge = { 0 };
        ge.pointCount = n;
        if (n > prevCount) ge.touchAction = TOUCH_ACTION_DOWN;
        else if (n < prevCount) ge.touchAction = TOUCH_ACTION_UP;
        else ge.touchAction = TOUCH_ACTION_MOVE;
        for (int i = 0; i < n; i++)
        {
            ge.pointId[i] = CORE.Input.Touch.pointId[i];
            ge.position[i] = (Vector2){ xs[i], ys[i] };      // gestures expect normalized coords
        }
        ProcessGestureEvent(ge);
    }
#endif

    CORE.Input.Touch.currentTouchState[MOUSE_BUTTON_LEFT] = (n > 0)? 1 : 0;

    if (n > 0)
    {
        CORE.Input.Mouse.previousPosition = (prevCount > 0)? CORE.Input.Mouse.currentPosition : CORE.Input.Touch.position[0];
        CORE.Input.Mouse.currentPosition = CORE.Input.Touch.position[0];
    }
    else CORE.Input.Mouse.previousPosition = CORE.Input.Mouse.currentPosition;
    CORE.Input.Mouse.currentWheelMove = (Vector2){ 0.0f, 0.0f };
}

//----------------------------------------------------------------------------------
// Init / close
//----------------------------------------------------------------------------------
int InitPlatform(void)
{
    int reqW = CORE.Window.screen.width, reqH = CORE.Window.screen.height;
    if ((CORE.Window.flags & FLAG_FULLSCREEN_MODE) || reqW <= 0 || reqH <= 0) { reqW = 0; reqH = 0; }

    int w = 0, h = 0;
    unsigned int fbo = 0;
    if (ios_gl_create(reqW, reqH, &w, &h, &fbo) != 0)
    {
        TRACELOG(LOG_FATAL, "PLATFORM: Failed to create OpenGL ES 3 context");
        return -1;
    }
    rlios_default_fbo = fbo;

    CORE.Window.fullscreen = true;
    CORE.Window.display.width = w;
    CORE.Window.display.height = h;
    CORE.Window.screen.width = w;
    CORE.Window.screen.height = h;
    CORE.Window.render.width = w;
    CORE.Window.render.height = h;
    CORE.Window.currentFbo.width = w;
    CORE.Window.currentFbo.height = h;
    CORE.Window.renderOffset.x = 0;
    CORE.Window.renderOffset.y = 0;
    CORE.Window.ready = true;

    rlLoadExtensions((void *)IosGetProc);

    InitTimer();
    CORE.Storage.basePath = GetWorkingDirectory();

    TRACELOG(LOG_INFO, "DISPLAY: Device initialized successfully");
    TRACELOG(LOG_INFO, "    > Render size:  %i x %i", w, h);
    TRACELOG(LOG_INFO, "PLATFORM: iOS (EAGL, OpenGL ES 3): Initialized successfully");
    return 0;
}

void ClosePlatform(void)
{
    ios_gl_destroy();
}
