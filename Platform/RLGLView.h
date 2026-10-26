#import <UIKit/UIKit.h>

// Container view hosting the CAEAGLLayer surface raylib renders into.
// The surface is aspect-fit inside the container so InitWindow(w,h) keeps its exact pixel size.
@interface RLGLView : UIView
@property (class, atomic, weak, nullable) RLGLView *active;   // the view raylib will attach to
@property (nonatomic, readonly) UIView *glView;
// Called on the main thread by the platform layer. (0,0) = native pixel size of the container.
- (CGSize)configureWithPixelSize:(CGSize)pixels;
@end
