// C-visible interface to the UIKit/EAGL host (implemented in ios_gl.m).
#ifndef IOS_GL_H
#define IOS_GL_H
#ifdef __cplusplus
extern "C" {
#endif

// Create the GL context + FBO on the calling (game) thread. reqW/reqH = 0 -> native size.
int  ios_gl_create(int reqW, int reqH, int *outW, int *outH, unsigned int *outFbo);
void ios_gl_present(void);
void ios_gl_destroy(void);

// Touch snapshot in normalized [0,1] coordinates of the GL surface. Returns active count.
int  ios_touch_snapshot(int *ids, float *xs, float *ys, int maxPoints);

void ios_open_url(const char *url);
void ios_set_clipboard(const char *text);
const char *ios_get_clipboard(void);   // pointer valid until next call

#ifdef __cplusplus
}
#endif
#endif
