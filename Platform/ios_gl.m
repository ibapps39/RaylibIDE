#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/ES3/gl.h>      // real GL here: this TU does NOT see the FBO-0 shim
#import <OpenGLES/ES3/glext.h>
#include <pthread.h>
#include <unistd.h>
#import "RLGLView.h"
#include "ios_gl.h"
#include "tcc_runner.h"

#define MAX_TOUCHES 10

//------------------------------------------------------------------------------
// Shared touch state (UI thread writes, game thread reads)
//------------------------------------------------------------------------------
static pthread_mutex_t g_touchLock = PTHREAD_MUTEX_INITIALIZER;
static struct { int active; int id; float x, y; } g_touch[MAX_TOUCHES];

//------------------------------------------------------------------------------
// App activity (GL work is not allowed in the background)
//------------------------------------------------------------------------------
static volatile int g_appActive = 1;
__attribute__((constructor)) static void ios_gl_observe(void)
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n){ g_appActive = 0; }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n){ g_appActive = 1; }];
}

//------------------------------------------------------------------------------
// Views
//------------------------------------------------------------------------------
@interface RLGLLayerView : UIView @end
@implementation RLGLLayerView
+ (Class)layerClass { return [CAEAGLLayer class]; }
@end

static __weak RLGLView *s_active;

@implementation RLGLView {
    RLGLLayerView *_gl;
    CGSize _pixelSize;
    NSMapTable<UITouch *, NSNumber *> *_ids;
    int _nextId;
}
+ (RLGLView *)active { return s_active; }
+ (void)setActive:(RLGLView *)v { s_active = v; }
- (UIView *)glView { return _gl; }

- (instancetype)initWithFrame:(CGRect)f
{
    if ((self = [super initWithFrame:f])) {
        _gl = [[RLGLLayerView alloc] initWithFrame:self.bounds];
        _gl.userInteractionEnabled = NO;
        [self addSubview:_gl];
        self.backgroundColor = UIColor.blackColor;
        self.multipleTouchEnabled = YES;
        _ids = [NSMapTable weakToStrongObjectsMapTable];
        _nextId = 1;
    }
    return self;
}

- (CGSize)configureWithPixelSize:(CGSize)p
{
    [self layoutIfNeeded];
    if (p.width < 1 || p.height < 1) {
        CGFloat sc = UIScreen.mainScreen.scale;
        p = CGSizeMake(round(self.bounds.size.width*sc), round(self.bounds.size.height*sc));
    }
    _pixelSize = p;
    [self setNeedsLayout];
    [self layoutIfNeeded];
    return p;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGSize b = self.bounds.size;
    if (_pixelSize.width < 1 || b.width < 1 || b.height < 1) {
        _gl.frame = self.bounds;
        _gl.contentScaleFactor = UIScreen.mainScreen.scale;
        return;
    }
    CGFloat s = MIN(b.width/_pixelSize.width, b.height/_pixelSize.height);
    CGSize r = CGSizeMake(_pixelSize.width*s, _pixelSize.height*s);
    _gl.frame = CGRectMake((b.width-r.width)/2, (b.height-r.height)/2, r.width, r.height);
    _gl.contentScaleFactor = _pixelSize.width / r.width;     // drawable stays exactly _pixelSize
}

- (void)updateTouches:(NSSet<UITouch *> *)touches ended:(BOOL)ended
{
    pthread_mutex_lock(&g_touchLock);
    for (UITouch *t in touches) {
        NSNumber *n = [_ids objectForKey:t];
        if (!n) { n = @(_nextId++); [_ids setObject:n forKey:t]; }
        int tid = n.intValue;
        int slot = -1;
        for (int i = 0; i < MAX_TOUCHES; i++) if (g_touch[i].active && g_touch[i].id == tid) { slot = i; break; }
        if (ended) { if (slot >= 0) g_touch[slot].active = 0; [_ids removeObjectForKey:t]; continue; }
        if (slot < 0) for (int i = 0; i < MAX_TOUCHES; i++) if (!g_touch[i].active) { slot = i; break; }
        if (slot < 0) continue;
        CGPoint p = [t locationInView:_gl];
        CGSize gs = _gl.bounds.size;
        g_touch[slot].active = 1; g_touch[slot].id = tid;
        g_touch[slot].x = MIN(MAX(p.x/MAX(gs.width,1), 0), 1);
        g_touch[slot].y = MIN(MAX(p.y/MAX(gs.height,1), 0), 1);
    }
    pthread_mutex_unlock(&g_touchLock);
}
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e     { [self updateTouches:t ended:NO]; }
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e     { [self updateTouches:t ended:NO]; }
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e     { [self updateTouches:t ended:YES]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self updateTouches:t ended:YES]; }
@end

//------------------------------------------------------------------------------
// C API (game thread)
//------------------------------------------------------------------------------
static EAGLContext *g_ctx;
static GLuint g_fbo, g_color, g_depth;

int ios_gl_create(int reqW, int reqH, int *outW, int *outH, unsigned int *outFbo)
{
    __block CAEAGLLayer *layer = nil;
    __block BOOL ok = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        RLGLView *v = RLGLView.active;
        if (!v) return;
        [v configureWithPixelSize:CGSizeMake(reqW, reqH)];
        layer = (CAEAGLLayer *)v.glView.layer;
        layer.opaque = YES;
        layer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking: @NO,
                                      kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8 };
        ok = YES;
    });
    if (!ok) return -1;

    g_ctx = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!g_ctx || ![EAGLContext setCurrentContext:g_ctx]) return -2;

    glGenFramebuffers(1, &g_fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);

    glGenRenderbuffers(1, &g_color);
    glBindRenderbuffer(GL_RENDERBUFFER, g_color);
    if (![g_ctx renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer]) return -3;
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, g_color);

    GLint w = 0, h = 0;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &w);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &h);

    glGenRenderbuffers(1, &g_depth);
    glBindRenderbuffer(GL_RENDERBUFFER, g_depth);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, w, h);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, g_depth);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, g_depth);

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) return -4;

    *outW = w; *outH = h; *outFbo = g_fbo;
    memset(g_touch, 0, sizeof g_touch);
    return 0;
}

void ios_gl_present(void)
{
    if (!g_ctx) return;
    if (!g_appActive) {                       // never touch the GPU from the background
        glFinish();
        while (!g_appActive && !rlrun_stop_requested()) usleep(30000);
    }
    glBindRenderbuffer(GL_RENDERBUFFER, g_color);
    [g_ctx presentRenderbuffer:GL_RENDERBUFFER];
}

void ios_gl_destroy(void)
{
    if (!g_ctx) return;
    [EAGLContext setCurrentContext:g_ctx];
    if (g_depth) glDeleteRenderbuffers(1, &g_depth);
    if (g_color) glDeleteRenderbuffers(1, &g_color);
    if (g_fbo)   glDeleteFramebuffers(1, &g_fbo);
    g_depth = g_color = g_fbo = 0;
    [EAGLContext setCurrentContext:nil];
    g_ctx = nil;
}

int ios_touch_snapshot(int *ids, float *xs, float *ys, int maxPoints)
{
    int n = 0;
    pthread_mutex_lock(&g_touchLock);
    for (int i = 0; i < MAX_TOUCHES && n < maxPoints; i++)
        if (g_touch[i].active) { ids[n] = g_touch[i].id; xs[n] = g_touch[i].x; ys[n] = g_touch[i].y; n++; }
    pthread_mutex_unlock(&g_touchLock);
    return n;
}

void ios_open_url(const char *url)
{
    NSString *s = [NSString stringWithUTF8String:url];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *u = [NSURL URLWithString:s];
        if (u) [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
    });
}

void ios_set_clipboard(const char *text)
{
    NSString *s = [NSString stringWithUTF8String:text ? text : ""];
    dispatch_sync(dispatch_get_main_queue(), ^{ UIPasteboard.generalPasteboard.string = s; });
}

const char *ios_get_clipboard(void)
{
    static char buf[4096];
    __block NSString *s = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ s = UIPasteboard.generalPasteboard.string; });
    snprintf(buf, sizeof buf, "%s", s ? s.UTF8String : "");
    return buf;
}
