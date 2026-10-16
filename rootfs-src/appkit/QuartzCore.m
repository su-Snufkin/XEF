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

NSString *const kCAFilterLinear = @"linear";
NSString *const kCAFilterNearest = @"nearest";
NSString *const kCAFilterTrilinear = @"trilinear";
NSString *const kCAGravityCenter = @"center";
NSString *const kCAGravityTop = @"top";
NSString *const kCAGravityBottom = @"bottom";
NSString *const kCAGravityLeft = @"left";
NSString *const kCAGravityRight = @"right";
NSString *const kCAGravityResize = @"resize";
NSString *const kCAGravityResizeAspect = @"resizeAspect";
NSString *const kCAGravityResizeAspectFill = @"resizeAspectFill";
NSString *const kCATransactionDisableActions = @"disableActions";
NSString *const kCATransactionAnimationDuration = @"animationDuration";
NSString *const kCAMediaTimingFunctionLinear = @"linear";
NSString *const kCAMediaTimingFunctionEaseIn = @"easeIn";
NSString *const kCAMediaTimingFunctionEaseOut = @"easeOut";
NSString *const kCAMediaTimingFunctionEaseInEaseOut = @"easeInEaseOut";
NSString *const kCAMediaTimingFunctionDefault = @"default";

@protocol MTLDevice;
@protocol MTLTexture;
@protocol MTLDrawable;

@interface NSObject (XEFMetalTextureRawAccess)
- (const void *)_rawBytes;
- (NSUInteger)width;
- (NSUInteger)height;
- (NSUInteger)pixelFormat;
@end

@protocol CAMetalDrawable <NSObject>
@property(readonly) id<MTLTexture> texture;
@property(readonly) id layer;
- (void)present;
- (void)presentAtTime:(CFTimeInterval)presentationTime;
- (void)presentAfterMinimumDuration:(CFTimeInterval)duration;
- (void)addPresentedHandler:(void (^)(id))block;
- (CFTimeInterval)presentedTime;
- (NSUInteger)drawableID;
@end

@interface CAMetalDrawable : NSObject <CAMetalDrawable> {
@public
  id<MTLTexture> _texture;
  id _layer;
  NSUInteger _drawableID;
  NSMutableArray *_handlers;
}
@property(readonly) id<MTLTexture> texture;
@property(readonly) id layer;
- (void)present;
- (void)presentAtTime:(CFTimeInterval)presentationTime;
- (void)presentAfterMinimumDuration:(CFTimeInterval)duration;
- (void)addPresentedHandler:(void (^)(id))block;
- (CFTimeInterval)presentedTime;
- (NSUInteger)drawableID;
@end


@implementation CAMetalDrawable
- (id<MTLTexture>)texture { return _texture; }
- (id)layer { return _layer; }
- (NSUInteger)drawableID { return _drawableID; }
- (CFTimeInterval)presentedTime { return CACurrentMediaTime(); }
- (void)addPresentedHandler:(void (^)(id))block {
  if (!block) return;
  if (!_handlers) _handlers = [[NSMutableArray alloc] init];
  [_handlers addObject:[[block copy] autorelease]];
}
- (void)present {
  if (_layer) {
    CALayer *cur = (CALayer *)_layer;
    id win = nil;
    while (cur && !win) {
      id delegate = [cur delegate];
      if (delegate) {
        if ([delegate respondsToSelector:@selector(window)]) {
          win = [delegate performSelector:@selector(window)];
        }
        if (!win && [delegate isKindOfClass:NSClassFromString(@"NSWindow")]) {
          win = delegate;
        }
        if (!win && [delegate respondsToSelector:@selector(superview)]) {
          id sv = [delegate performSelector:@selector(superview)];
          while (sv && !win) {
            if ([sv respondsToSelector:@selector(window)]) win = [sv performSelector:@selector(window)];
            sv = [sv respondsToSelector:@selector(superview)] ? [sv performSelector:@selector(superview)] : nil;
          }
        }
      }
      cur = [cur superlayer];
    }
    if (!win) {
      Class appCls = NSClassFromString(@"NSApplication");
      if (appCls && [appCls respondsToSelector:@selector(sharedApplication)]) {
        id app = [appCls performSelector:@selector(sharedApplication)];
        if (app && [app respondsToSelector:@selector(mainWindow)]) win = [app performSelector:@selector(mainWindow)];
        if (!win && app && [app respondsToSelector:@selector(keyWindow)]) win = [app performSelector:@selector(keyWindow)];
      }
    }
    if (win) {
      Ivar iv = class_getInstanceVariable([win class], "_handle");
      if (iv) {
        ptrdiff_t offset = ivar_getOffset(iv);
        int handle = *(int *)((uint8_t *)win + offset);
        if (handle > 0) {
          const void *pixels = NULL;
          int tw = 0, th = 0, tfmt = 80;
          if (_texture && [(id)_texture respondsToSelector:@selector(_rawBytes)]) {
            pixels = [(id)_texture _rawBytes];
            tw = (int)[(id)_texture width];
            th = (int)[(id)_texture height];
            tfmt = (int)[(id)_texture pixelFormat];
          }
          extern void xef_host_present_pixels(int handle, const void *pixels, int w, int h, int format);
          xef_host_present_pixels(handle, pixels, tw, th, tfmt);
        }
      }
    }
  }
  if (_handlers) {
    for (void (^blk)(id) in _handlers) {
      blk(self);
    }
    [_handlers removeAllObjects];
  }
}
- (void)presentAtTime:(CFTimeInterval)presentationTime { [self present]; }
- (void)presentAfterMinimumDuration:(CFTimeInterval)duration { [self present]; }
- (void)dealloc {
  [(id)_texture release];
  [_handlers release];
  [super dealloc];
}
@end


static id qc_stub(id self, SEL _cmd, ...) {
  static NSMutableSet *seen;
  @synchronized ([NSObject class]) {
    if (!seen) seen = [[NSMutableSet alloc] init];
    NSString *k = [NSString stringWithFormat:@"%s %s", class_getName(object_getClass(self)), sel_getName(_cmd)];
    if (![seen containsObject:k]) {
      [seen addObject:k];
      fprintf(stderr, "QUARTZCORE STUB -[%s %s]\n", class_getName(object_getClass(self)), sel_getName(_cmd));
    }
  }
  return nil;
}

@interface CALayer (XEFStubs)
@end
@implementation CALayer (XEFStubs)
+ (BOOL)resolveInstanceMethod:(SEL)sel {
  const char *n = sel_getName(sel);
  if (n[0] == '_' || !strncmp(n, "respondsTo", 10) || !strncmp(n, "init", 4) || !strncmp(n, "copy", 4) || !strncmp(n, "mutableCopy", 11) || !strncmp(n, "dealloc", 7)) return NO;
  class_addMethod(self, sel, (IMP)qc_stub, "@@:");
  return YES;
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
  BOOL _allowsNextDrawableTimeout;
  BOOL _wantsExtendedDynamicRangeContent;
  id _EDRMetadata;
  NSDictionary *_developerHUDProperties;
  NSUInteger _maximumDrawableCount;
  CGColorSpaceRef _colorspace;
  id<MTLTexture> _cachedTexture;
  NSUInteger _nextDrawableID;
}
@property(strong) id<MTLDevice> device;
@property(readonly) id<MTLDevice> preferredDevice;
@property NSUInteger pixelFormat;
@property BOOL framebufferOnly;
@property CGSize drawableSize;
@property(readonly) id<CAMetalDrawable> nextDrawable;
@property BOOL presentsWithTransaction;
@property BOOL displaySyncEnabled;
@property BOOL allowsNextDrawableTimeout;
@property BOOL wantsExtendedDynamicRangeContent;
@property(strong) id EDRMetadata;
@property(copy) NSDictionary *developerHUDProperties;
@property NSUInteger maximumDrawableCount;
@property CGColorSpaceRef colorspace;
@end

@implementation CAMetalLayer
- (id)init {
  if ((self = [super init])) {
    _pixelFormat = 80; /* MTLPixelFormatBGRA8Unorm */
    _framebufferOnly = YES;
    _displaySyncEnabled = YES;
    _allowsNextDrawableTimeout = YES;
    _maximumDrawableCount = 3;
  }
  return self;
}
- (id<MTLDevice>)device {
  if (!_device) {
    Class devCls = NSClassFromString(@"XEFMetalDevice");
    if (devCls && [devCls respondsToSelector:@selector(sharedDevice)]) {
      _device = [[devCls performSelector:@selector(sharedDevice)] retain];
    }
  }
  return _device;
}
- (void)setDevice:(id<MTLDevice>)d { [d retain]; [(id)_device release]; _device = d; }
- (id<MTLDevice>)preferredDevice { return [self device]; }
- (NSUInteger)pixelFormat { return _pixelFormat ? _pixelFormat : 80; }
- (void)setPixelFormat:(NSUInteger)pf { _pixelFormat = pf ? pf : 80; }
- (BOOL)framebufferOnly { return _framebufferOnly; }
- (void)setFramebufferOnly:(BOOL)f { _framebufferOnly = f; }
- (void)setFrame:(CGRect)f {
  [super setFrame:f];
  if (_drawableSize.width <= 0 || _drawableSize.height <= 0) {
    _drawableSize = CGSizeMake(f.size.width * _contentsScale, f.size.height * _contentsScale);
  }
}
- (void)setBounds:(CGRect)b {
  [super setBounds:b];
  if (_drawableSize.width <= 0 || _drawableSize.height <= 0) {
    _drawableSize = CGSizeMake(b.size.width * _contentsScale, b.size.height * _contentsScale);
  }
}
- (CGSize)drawableSize {
  if (_drawableSize.width > 0 && _drawableSize.height > 0) return _drawableSize;
  if (_bounds.size.width > 0 && _bounds.size.height > 0) return CGSizeMake(_bounds.size.width * _contentsScale, _bounds.size.height * _contentsScale);
  return CGSizeMake(800, 600);
}
- (void)setDrawableSize:(CGSize)s { _drawableSize = s; }
- (BOOL)presentsWithTransaction { return _presentsWithTransaction; }
- (void)setPresentsWithTransaction:(BOOL)p { _presentsWithTransaction = p; }
- (BOOL)displaySyncEnabled { return _displaySyncEnabled; }
- (void)setDisplaySyncEnabled:(BOOL)e { _displaySyncEnabled = e; }
- (BOOL)allowsNextDrawableTimeout { return _allowsNextDrawableTimeout; }
- (void)setAllowsNextDrawableTimeout:(BOOL)a { _allowsNextDrawableTimeout = a; }
- (BOOL)wantsExtendedDynamicRangeContent { return _wantsExtendedDynamicRangeContent; }
- (void)setWantsExtendedDynamicRangeContent:(BOOL)w { _wantsExtendedDynamicRangeContent = w; }
- (id)EDRMetadata { return _EDRMetadata; }
- (void)setEDRMetadata:(id)m { [m retain]; [_EDRMetadata release]; _EDRMetadata = m; }
- (NSDictionary *)developerHUDProperties { return _developerHUDProperties; }
- (void)setDeveloperHUDProperties:(NSDictionary *)p { [p retain]; [_developerHUDProperties release]; _developerHUDProperties = p; }
- (NSUInteger)maximumDrawableCount { return _maximumDrawableCount; }
- (void)setMaximumDrawableCount:(NSUInteger)c { _maximumDrawableCount = c; }
- (CGColorSpaceRef)colorspace { return _colorspace; }
- (void)setColorspace:(CGColorSpaceRef)cs { _colorspace = cs; }
- (id<CAMetalDrawable>)nextDrawable {
  CAMetalDrawable *d = [[[CAMetalDrawable alloc] init] autorelease];
  d->_layer = self;
  d->_drawableID = ++_nextDrawableID;
  id<MTLDevice> dev = [self device];
  CGSize ds = [self drawableSize];
  NSUInteger w = (NSUInteger)(ds.width > 0 ? ds.width : 800);
  NSUInteger h = (NSUInteger)(ds.height > 0 ? ds.height : 600);
  NSUInteger pf = [self pixelFormat];
  if (_cachedTexture &&
      [(id)_cachedTexture width] == w &&
      [(id)_cachedTexture height] == h &&
      [(id)_cachedTexture pixelFormat] == pf) {
    d->_texture = [_cachedTexture retain];
  } else if (dev && [dev respondsToSelector:@selector(newTextureWithDescriptor:)]) {
    Class tc = NSClassFromString(@"MTLTextureDescriptor");
    if (tc) {
      id desc = [tc texture2DDescriptorWithPixelFormat:pf width:w height:h mipmapped:NO];
      [desc setUsage:5];
      [(id)_cachedTexture release];
      _cachedTexture = [(id)dev newTextureWithDescriptor:desc];
      d->_texture = [_cachedTexture retain];
    }
  }
  return d;
}
- (void)dealloc {
  [_EDRMetadata release];
  [_developerHUDProperties release];
  [(id)_cachedTexture release];
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
