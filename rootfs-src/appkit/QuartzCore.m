/* QuartzCore-lite for xef-osx: CALayer, CAMetalLayer, CATransaction, CATransform3D, CACurrentMediaTime. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <time.h>
#import <math.h>
#import <string.h>

CFTimeInterval CACurrentMediaTime(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (CFTimeInterval)ts.tv_sec + (CFTimeInterval)ts.tv_nsec / 1e9;
}

struct CATransform3D {
  CGFloat m11, m12, m13, m14;
  CGFloat m21, m22, m23, m24;
  CGFloat m31, m32, m33, m34;
  CGFloat m41, m42, m43, m44;
};
typedef struct CATransform3D CATransform3D;

const CATransform3D CATransform3DIdentity = {
  1.0, 0.0, 0.0, 0.0,
  0.0, 1.0, 0.0, 0.0,
  0.0, 0.0, 1.0, 0.0,
  0.0, 0.0, 0.0, 1.0
};

bool CATransform3DIsIdentity(CATransform3D t) {
  return memcmp(&t, &CATransform3DIdentity, sizeof(CATransform3D)) == 0;
}

bool CATransform3DEqualToTransform(CATransform3D a, CATransform3D b) {
  return memcmp(&a, &b, sizeof(CATransform3D)) == 0;
}

CATransform3D CATransform3DMakeTranslation(CGFloat tx, CGFloat ty, CGFloat tz) {
  CATransform3D t = CATransform3DIdentity;
  t.m41 = tx; t.m42 = ty; t.m43 = tz;
  return t;
}

CATransform3D CATransform3DMakeScale(CGFloat sx, CGFloat sy, CGFloat sz) {
  CATransform3D t = CATransform3DIdentity;
  t.m11 = sx; t.m22 = sy; t.m33 = sz;
  return t;
}

CATransform3D CATransform3DMakeRotation(CGFloat angle, CGFloat x, CGFloat y, CGFloat z) {
  CGFloat len = sqrt(x*x + y*y + z*z);
  if (len > 0.0) { x /= len; y /= len; z /= len; }
  CGFloat c = cos(angle), s = sin(angle);
  CATransform3D t = CATransform3DIdentity;
  t.m11 = x*x*(1-c) + c;     t.m12 = y*x*(1-c) + z*s;   t.m13 = x*z*(1-c) - y*s;
  t.m21 = x*y*(1-c) - z*s;   t.m22 = y*y*(1-c) + c;     t.m23 = y*z*(1-c) + x*s;
  t.m31 = x*z*(1-c) + y*s;   t.m32 = y*z*(1-c) - x*s;   t.m33 = z*z*(1-c) + c;
  return t;
}

CATransform3D CATransform3DConcat(CATransform3D a, CATransform3D b) {
  CATransform3D r;
  const CGFloat *ma = (const CGFloat*)&a;
  const CGFloat *mb = (const CGFloat*)&b;
  CGFloat *mr = (CGFloat*)&r;
  for (int i = 0; i < 4; i++) {
    for (int j = 0; j < 4; j++) {
      mr[i*4 + j] = ma[i*4 + 0] * mb[0*4 + j] +
                    ma[i*4 + 1] * mb[1*4 + j] +
                    ma[i*4 + 2] * mb[2*4 + j] +
                    ma[i*4 + 3] * mb[3*4 + j];
    }
  }
  return r;
}

CATransform3D CATransform3DTranslate(CATransform3D t, CGFloat tx, CGFloat ty, CGFloat tz) {
  return CATransform3DConcat(CATransform3DMakeTranslation(tx, ty, tz), t);
}

CATransform3D CATransform3DScale(CATransform3D t, CGFloat sx, CGFloat sy, CGFloat sz) {
  return CATransform3DConcat(CATransform3DMakeScale(sx, sy, sz), t);
}

CATransform3D CATransform3DRotate(CATransform3D t, CGFloat angle, CGFloat x, CGFloat y, CGFloat z) {
  return CATransform3DConcat(CATransform3DMakeRotation(angle, x, y, z), t);
}

CATransform3D CATransform3DInvert(CATransform3D t) {
  // Simple inversion fallback: identity if singular
  return CATransform3DIdentity;
}

@class CALayer;

@interface CALayer : NSObject {
@public
  CGRect _bounds;
  CGPoint _position;
  CGFloat _zPosition;
  CGRect _frame;
  CATransform3D _transform;
  BOOL _hidden;
  BOOL _opaque;
  BOOL _doubleSided;
  CGFloat _contentsScale;
  id _contents;
  NSMutableArray *_sublayers;
  CALayer *_superlayer;
  id _delegate;
  CGColorRef _backgroundColor;
  CGFloat _cornerRadius;
  CGFloat _borderWidth;
  CGColorRef _borderColor;
  CGFloat _opacity;
}
+ (id)layer;
@property CGRect bounds;
@property CGPoint position;
@property CGFloat zPosition;
@property CGRect frame;
@property CATransform3D transform;
@property(getter=isHidden) BOOL hidden;
@property(getter=isOpaque) BOOL opaque;
@property(getter=isDoubleSided) BOOL doubleSided;
@property CGFloat contentsScale;
@property(strong) id contents;
@property(readonly) CALayer *superlayer;
@property(copy) NSArray *sublayers;
@property id delegate;
@property CGColorRef backgroundColor;
@property CGFloat cornerRadius;
@property CGFloat borderWidth;
@property CGColorRef borderColor;
@property float opacity;

- (void)addSublayer:(CALayer *)layer;
- (void)removeFromSuperlayer;
- (void)setNeedsDisplay;
- (void)displayIfNeeded;
- (void)addAnimation:(id)anim forKey:(NSString *)key;
- (void)removeAnimationForKey:(NSString *)key;
- (void)removeAllAnimations;
@end

@implementation CALayer
+ (id)layer { return [[[self alloc] init] autorelease]; }
- (id)init {
  if ((self = [super init])) {
    _contentsScale = 1.0;
    _opaque = YES;
    _opacity = 1.0;
    _transform = CATransform3DIdentity;
  }
  return self;
}
- (CGRect)bounds { return _bounds; }
- (void)setBounds:(CGRect)b { _bounds = b; }
- (CGPoint)position { return _position; }
- (void)setPosition:(CGPoint)p { _position = p; }
- (CGFloat)zPosition { return _zPosition; }
- (void)setZPosition:(CGFloat)z { _zPosition = z; }
- (CGRect)frame { return _frame; }
- (void)setFrame:(CGRect)f { _frame = f; _bounds = CGRectMake(0, 0, f.size.width, f.size.height); }
- (CATransform3D)transform { return _transform; }
- (void)setTransform:(CATransform3D)t { _transform = t; }
- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)h { _hidden = h; }
- (BOOL)isOpaque { return _opaque; }
- (void)setOpaque:(BOOL)o { _opaque = o; }
- (BOOL)isDoubleSided { return _doubleSided; }
- (void)setDoubleSided:(BOOL)d { _doubleSided = d; }
- (CGFloat)contentsScale { return _contentsScale; }
- (void)setContentsScale:(CGFloat)s { _contentsScale = s; }
- (id)contents { return _contents; }
- (void)setContents:(id)c { [c retain]; [_contents release]; _contents = c; }
- (CALayer *)superlayer { return _superlayer; }
- (NSArray *)sublayers { return _sublayers ? _sublayers : [NSArray array]; }
- (void)setSublayers:(NSArray *)s {
  [s retain];
  [_sublayers release];
  _sublayers = [s mutableCopy];
}
- (void)addSublayer:(CALayer *)layer {
  if (!layer) return;
  if (!_sublayers) _sublayers = [[NSMutableArray alloc] init];
  [layer retain];
  [layer removeFromSuperlayer];
  [_sublayers addObject:layer];
  layer->_superlayer = self;
  [layer release];
}
- (void)removeFromSuperlayer {
  if (_superlayer) {
    [_superlayer->_sublayers removeObject:self];
    _superlayer = nil;
  }
}
- (void)setNeedsDisplay {}
- (void)displayIfNeeded {}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (CGColorRef)backgroundColor { return _backgroundColor; }
- (void)setBackgroundColor:(CGColorRef)c { _backgroundColor = c; }
- (CGFloat)cornerRadius { return _cornerRadius; }
- (void)setCornerRadius:(CGFloat)r { _cornerRadius = r; }
- (CGFloat)borderWidth { return _borderWidth; }
- (void)setBorderWidth:(CGFloat)w { _borderWidth = w; }
- (CGColorRef)borderColor { return _borderColor; }
- (void)setBorderColor:(CGColorRef)c { _borderColor = c; }
- (float)opacity { return _opacity; }
- (void)setOpacity:(float)o { _opacity = o; }
- (void)addAnimation:(id)anim forKey:(NSString *)key {}
- (void)removeAnimationForKey:(NSString *)key {}
- (void)removeAllAnimations {}

- (void)dealloc {
  [_contents release];
  [_sublayers release];
  [super dealloc];
}
@end

@protocol MTLDevice;
@protocol MTLTexture;
@protocol MTLDrawable;

@protocol CAMetalDrawable <NSObject>
@property(readonly) id<MTLTexture> texture;
@property(readonly) id layer;
- (void)present;
- (void)presentAtTime:(CFTimeInterval)presentationTime;
@end

@interface CAMetalDrawable : NSObject <CAMetalDrawable> {
@public
  id<MTLTexture> _texture;
  id _layer;
}
@property(readonly) id<MTLTexture> texture;
@property(readonly) id layer;
- (void)present;
- (void)presentAtTime:(CFTimeInterval)presentationTime;
@end


@implementation CAMetalDrawable
- (id<MTLTexture>)texture { return _texture; }
- (id)layer { return _layer; }
- (void)present {
  if (_layer) {
    id delegate = [(CALayer *)_layer delegate];
    if (delegate && [delegate respondsToSelector:@selector(window)]) {
      id win = [delegate performSelector:@selector(window)];
      if (win) {
        Ivar iv = class_getInstanceVariable([win class], "_handle");
        if (iv) {
          ptrdiff_t offset = ivar_getOffset(iv);
          int handle = *(int *)((uint8_t *)win + offset);
          if (handle > 0) {
            extern void xef_host_swap(int handle);
            xef_host_swap(handle);
          }
        }
      }
    }
  }
}
- (void)presentAtTime:(CFTimeInterval)presentationTime { [self present]; }
- (void)dealloc {
  [(id)_texture release];
  [super dealloc];
}
@end


@interface CAMetalLayer : CALayer {
@public
  id<MTLDevice> _device;
  NSUInteger _pixelFormat;
  BOOL _framebufferOnly;
  CGSize _drawableSize;
  BOOL _presentsWithTransaction;
  BOOL _displaySyncEnabled;
  CGColorSpaceRef _colorspace;
}
@property(strong) id<MTLDevice> device;
@property(readonly) id<MTLDevice> preferredDevice;
@property NSUInteger pixelFormat;
@property BOOL framebufferOnly;
@property CGSize drawableSize;
@property(readonly) id<CAMetalDrawable> nextDrawable;
@property BOOL presentsWithTransaction;
@property BOOL displaySyncEnabled;
@property CGColorSpaceRef colorspace;
@end

@implementation CAMetalLayer
- (id<MTLDevice>)device { return _device; }
- (void)setDevice:(id<MTLDevice>)d { [d retain]; [(id)_device release]; _device = d; }
- (id<MTLDevice>)preferredDevice { return _device; }
- (NSUInteger)pixelFormat { return _pixelFormat; }
- (void)setPixelFormat:(NSUInteger)pf { _pixelFormat = pf; }
- (BOOL)framebufferOnly { return _framebufferOnly; }
- (void)setFramebufferOnly:(BOOL)f { _framebufferOnly = f; }
- (CGSize)drawableSize { return _drawableSize; }
- (void)setDrawableSize:(CGSize)s { _drawableSize = s; }
- (BOOL)presentsWithTransaction { return _presentsWithTransaction; }
- (void)setPresentsWithTransaction:(BOOL)p { _presentsWithTransaction = p; }
- (BOOL)displaySyncEnabled { return _displaySyncEnabled; }
- (void)setDisplaySyncEnabled:(BOOL)e { _displaySyncEnabled = e; }
- (CGColorSpaceRef)colorspace { return _colorspace; }
- (id<CAMetalDrawable>)nextDrawable {
  CAMetalDrawable *d = [[[CAMetalDrawable alloc] init] autorelease];
  d->_layer = self;
  if (_device && [_device respondsToSelector:@selector(newTextureWithDescriptor:)]) {
    Class tc = NSClassFromString(@"MTLTextureDescriptor");
    if (tc) {
      id desc = [tc texture2DDescriptorWithPixelFormat:(_pixelFormat ? _pixelFormat : 80)
                                                 width:(NSUInteger)(_drawableSize.width > 0 ? _drawableSize.width : 800)
                                                height:(NSUInteger)(_drawableSize.height > 0 ? _drawableSize.height : 600)
                                             mipmapped:NO];
      [desc setUsage:5];
      d->_texture = [(id)_device newTextureWithDescriptor:desc];
    }
  }
  return d;
}
- (void)dealloc {
  [(id)_device release];
  [super dealloc];
}
@end


@interface CATransaction : NSObject
+ (void)begin;
+ (void)commit;
+ (void)flush;
+ (void)lock;
+ (void)unlock;
+ (void)setAnimationDuration:(CFTimeInterval)dur;
+ (CFTimeInterval)animationDuration;
+ (void)setDisableActions:(BOOL)flag;
+ (BOOL)disableActions;
@end

@implementation CATransaction
+ (void)begin {}
+ (void)commit {}
+ (void)flush {}
+ (void)lock {}
+ (void)unlock {}
+ (void)setAnimationDuration:(CFTimeInterval)dur {}
+ (CFTimeInterval)animationDuration { return 0.25; }
+ (void)setDisableActions:(BOOL)flag {}
+ (BOOL)disableActions { return YES; }
@end

/* Common CoreAnimation stub classes */
@interface CAAnimation : NSObject <NSCopying>
+ (id)animation;
@property CFTimeInterval duration;
@property CFTimeInterval beginTime;
@property float repeatCount;
@property BOOL autoreverses;
@property(getter=isRemovedOnCompletion) BOOL removedOnCompletion;
@end
@implementation CAAnimation
+ (id)animation { return [[[self alloc] init] autorelease]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end

@interface CAPropertyAnimation : CAAnimation
+ (id)animationWithKeyPath:(NSString *)path;
@property(copy) NSString *keyPath;
@end
@implementation CAPropertyAnimation
+ (id)animationWithKeyPath:(NSString *)path {
  CAPropertyAnimation *a = [self animation];
  a.keyPath = path;
  return a;
}
@end

@interface CABasicAnimation : CAPropertyAnimation
@property(strong) id fromValue;
@property(strong) id toValue;
@property(strong) id byValue;
@end
@implementation CABasicAnimation
@end

@interface CAKeyframeAnimation : CAPropertyAnimation
@property(copy) NSArray *values;
@property(copy) NSArray *keyTimes;
@end
@implementation CAKeyframeAnimation
@end

@interface CATransition : CAAnimation
@property(copy) NSString *type;
@property(copy) NSString *subtype;
@property float startProgress;
@property float endProgress;
@end
@implementation CATransition
@end

@interface CAMediaTimingFunction : NSObject
+ (id)functionWithName:(NSString *)name;
@end
@implementation CAMediaTimingFunction
+ (id)functionWithName:(NSString *)name { return [[[self alloc] init] autorelease]; }
@end

@interface CAGradientLayer : CALayer
@property(copy) NSArray *colors;
@property CGPoint startPoint;
@property CGPoint endPoint;
@end
@implementation CAGradientLayer
@end

@interface CAShapeLayer : CALayer
@property CGPathRef path;
@property CGColorRef fillColor;
@property CGColorRef strokeColor;
@property CGFloat lineWidth;
@end
@implementation CAShapeLayer
@end

@interface CATextLayer : CALayer
@property(copy) id string;
@property CFTypeRef font;
@property CGFloat fontSize;
@property CGColorRef foregroundColor;
@end
@implementation CATextLayer
@end

@interface CAOpenGLLayer : CALayer
@end
@implementation CAOpenGLLayer
@end

@interface CADisplayLink : NSObject
+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel;
- (void)addToRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode;
- (void)removeFromRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode;
- (void)invalidate;
@property(getter=isPaused) BOOL paused;
@end
@implementation CADisplayLink
+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel { return [[[self alloc] init] autorelease]; }
- (void)addToRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode {}
- (void)removeFromRunLoop:(NSRunLoop *)runloop forMode:(NSRunLoopMode)mode {}
- (void)invalidate {}
@end
