/* Nib and storyboard loading for AppKit-lite: Apple's binary "NIBArchive" format (what ibtool writes for
   compiled .nib files and the scenes of .storyboardc bundles), NSIBObjectData connections, NSViewController,
   NSWindowController, NSStoryboard and NSApplicationMain. MRC (no ARC). */
#import "AppKitLite.h"
#import "AppKitDocument.h"
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <string.h>

@class NSStoryboard;
@interface NSViewController : NSResponder <NSCoding> {
@public
  NSView *_view; NSString *_nibName; NSBundle *_nibBundle; id _representedObject; NSString *_title;
  NSStoryboard *_storyboard; BOOL _loading;
}
- (id)initWithNibName:(NSString *)n bundle:(NSBundle *)b;
- (NSView *)view; - (void)setView:(NSView *)v; - (void)loadView; - (void)viewDidLoad; - (BOOL)isViewLoaded;
- (void)viewWillAppear; - (void)viewDidAppear;
@end
@interface NSWindow (XEFControllers)
- (void)setContentViewController:(NSViewController *)vc; - (NSViewController *)contentViewController;
- (NSWindowController *)windowController; - (void)setWindowController:(NSWindowController *)wc;
@end

/* ------------------------------------------------------------------ archive */

enum { NV_I8, NV_I16, NV_I32, NV_I64, NV_FALSE, NV_TRUE, NV_F32, NV_F64, NV_DATA, NV_NIL, NV_OBJ };

typedef struct { uint32_t cls, first, count; } XNObj;
typedef struct { uint32_t key; uint8_t type; int64_t i; double d; const uint8_t *data; uint32_t len; } XNVal;

static BOOL nib_varint(const uint8_t **p, const uint8_t *end, uint32_t *out) {
  uint32_t r = 0; int s = 0;
  while (*p < end && s < 35) {
    uint8_t b = *(*p)++;
    r |= (uint32_t)(b & 0x7f) << s; s += 7;
    if (b & 0x80) { *out = r; return YES; }   /* the high bit marks the last byte */
  }
  return NO;
}

static void nib_parse_frame(NSString *s, CGFloat *v, int n) {
  /* "{{x, y}, {w, h}}" / "{w, h}" */
  const char *c = [s UTF8String];
  for (int i = 0; i < n; i++) v[i] = 0;
  for (int i = 0; c && *c && i < n;) {
    if ((*c >= '0' && *c <= '9') || *c == '-' || *c == '.') { char *e; v[i++] = strtod(c, &e); c = e; } else c++;
  }
}

@interface XEFNibDecoder : NSCoder {
@public
  NSData *_data;
  const char **_keys; uint32_t _nkeys;
  NSString **_classes; uint32_t _nclasses;
  XNObj *_objs; uint32_t _nobjs;
  XNVal *_vals; uint32_t _nvals;
  id *_cache; BOOL *_done;
  uint32_t _cur;
  NSDictionary *_externals;
}
- (id)initWithNibData:(NSData *)d;
- (id)objectAtIndex:(uint32_t)i;
@end

@implementation XEFNibDecoder
- (id)initWithNibData:(NSData *)d {
  if (!(self = [super init])) return nil;
  _data = [d retain];
  const uint8_t *b = [d bytes], *end = b + [d length];
  if ([d length] < 50 || memcmp(b, "NIBArchive", 10)) { [self release]; return nil; }
  uint32_t h[10];
  memcpy(h, b + 10, sizeof h);
  _nobjs = h[2]; _nkeys = h[4]; _nvals = h[6]; _nclasses = h[8];
  _keys = calloc(_nkeys + 1, sizeof *_keys);
  _classes = calloc(_nclasses + 1, sizeof *_classes);
  _objs = calloc(_nobjs + 1, sizeof *_objs);
  _vals = calloc(_nvals + 1, sizeof *_vals);
  _cache = calloc(_nobjs + 1, sizeof *_cache);
  _done = calloc(_nobjs + 1, sizeof *_done);
  const uint8_t *p = b + h[5];
  for (uint32_t i = 0; i < _nkeys; i++) {
    uint32_t l = 0;
    if (!nib_varint(&p, end, &l) || p + l > end) goto bad;
    char *k = malloc(l + 1); memcpy(k, p, l); k[l] = 0; _keys[i] = k; p += l;
  }
  p = b + h[9];
  for (uint32_t i = 0; i < _nclasses; i++) {
    uint32_t l = 0, extra = 0;
    if (!nib_varint(&p, end, &l) || !nib_varint(&p, end, &extra)) goto bad;
    p += 4 * extra;
    if (p + l > end) goto bad;
    _classes[i] = [[NSString alloc] initWithBytes:p length:(l && !p[l - 1]) ? l - 1 : l encoding:NSUTF8StringEncoding];
    p += l;
  }
  p = b + h[7];
  for (uint32_t i = 0; i < _nvals; i++) {
    XNVal *v = &_vals[i];
    if (!nib_varint(&p, end, &v->key) || p >= end) goto bad;
    v->type = *p++;
    switch (v->type) {
    case NV_I8: v->i = (int8_t)*p; p += 1; break;
    case NV_I16: { int16_t x; memcpy(&x, p, 2); v->i = x; p += 2; break; }
    case NV_I32: { int32_t x; memcpy(&x, p, 4); v->i = x; p += 4; break; }
    case NV_I64: { int64_t x; memcpy(&x, p, 8); v->i = x; p += 8; break; }
    case NV_FALSE: v->i = 0; break;
    case NV_TRUE: v->i = 1; break;
    case NV_F32: { float f; memcpy(&f, p, 4); v->d = f; p += 4; break; }
    case NV_F64: { double f; memcpy(&f, p, 8); v->d = f; p += 8; break; }
    case NV_DATA: { uint32_t l = 0; if (!nib_varint(&p, end, &l) || p + l > end) goto bad; v->data = p; v->len = l; p += l; break; }
    case NV_NIL: break;
    case NV_OBJ: { uint32_t x; memcpy(&x, p, 4); v->i = x; p += 4; break; }
    default: goto bad;
    }
    if (v->type == NV_I8 || v->type == NV_I16 || v->type == NV_I32 || v->type == NV_I64) v->d = (double)v->i;
    if (v->type == NV_F32 || v->type == NV_F64) v->i = (int64_t)v->d;
  }
  p = b + h[3];
  for (uint32_t i = 0; i < _nobjs; i++)
    if (!nib_varint(&p, end, &_objs[i].cls) || !nib_varint(&p, end, &_objs[i].first) || !nib_varint(&p, end, &_objs[i].count)) goto bad;
  return self;
bad:
  NSLog(@"xef: malformed nib archive");
  [self release];
  return nil;
}
- (void)dealloc {
  for (uint32_t i = 0; i < _nkeys; i++) free((void *)_keys[i]);
  for (uint32_t i = 0; i < _nclasses; i++) [_classes[i] release];
  for (uint32_t i = 0; i < _nobjs; i++) if (_done[i]) [_cache[i] release];
  free(_keys); free(_classes); free(_objs); free(_vals); free(_cache); free(_done);
  [_data release]; [_externals release];
  [super dealloc];
}
- (BOOL)allowsKeyedCoding { return YES; }
- (NSInteger)versionForClassName:(NSString *)n { return 0; }
- (unsigned)systemVersion { return 1000; }

- (XNVal *)_val:(NSString *)key {
  if (_cur >= _nobjs) return NULL;
  const char *k = [key UTF8String];
  XNObj *o = &_objs[_cur];
  for (uint32_t i = o->first; i < o->first + o->count && i < _nvals; i++)
    if (_vals[i].key < _nkeys && !strcmp(_keys[_vals[i].key], k)) return &_vals[i];
  return NULL;
}
/* references stored under the anonymous key (inline collections) */
- (NSArray *)_anonymousObjectsOf:(uint32_t)idx {
  NSMutableArray *r = [NSMutableArray array];
  if (idx >= _nobjs) return r;
  XNObj *o = &_objs[idx];
  for (uint32_t i = o->first; i < o->first + o->count && i < _nvals; i++)
    if (_vals[i].type == NV_OBJ && _vals[i].key < _nkeys && !strcmp(_keys[_vals[i].key], "UINibEncoderEmptyKey")) {
      id x = [self objectAtIndex:(uint32_t)_vals[i].i];
      [r addObject:x ? x : [NSNull null]];
    }
  return r;
}
- (NSString *)_classNameOf:(uint32_t)idx { return idx < _nobjs && _objs[idx].cls < _nclasses ? _classes[_objs[idx].cls] : nil; }

- (id)objectAtIndex:(uint32_t)idx {
  if (idx >= _nobjs) return nil;
  if (_done[idx]) return _cache[idx];
  NSString *cn = [self _classNameOf:idx];
  uint32_t saved = _cur;
  _cur = idx;
  id r = nil;
  XNVal *v;
  if ([cn isEqualToString:@"NSString"] || [cn isEqualToString:@"NSMutableString"] || [cn isEqualToString:@"NSLocalizableString"]) {
    v = [self _val:@"NS.bytes"];
    r = [[NSString alloc] initWithBytes:v ? v->data : "" length:v ? v->len : 0 encoding:NSUTF8StringEncoding];
    if ([cn isEqualToString:@"NSMutableString"]) { id m = [r mutableCopy]; [r release]; r = m; }
  } else if ([cn isEqualToString:@"NSData"] || [cn isEqualToString:@"NSMutableData"]) {
    v = [self _val:@"NS.bytes"];
    r = [[NSMutableData alloc] initWithBytes:v ? v->data : "" length:v ? v->len : 0];
  } else if ([cn isEqualToString:@"NSNumber"]) {
    if ((v = [self _val:@"NS.intval"])) r = [[NSNumber alloc] initWithLongLong:v->i];
    else if ((v = [self _val:@"NS.dblval"])) r = [[NSNumber alloc] initWithDouble:v->d];
    else if ((v = [self _val:@"NS.boolval"])) r = [[NSNumber alloc] initWithBool:v->i != 0];
    else r = [[NSNumber alloc] initWithInt:0];
  } else if ([cn isEqualToString:@"NSArray"] || [cn isEqualToString:@"NSMutableArray"]) {
    r = [[NSMutableArray alloc] initWithArray:[self _anonymousObjectsOf:idx]];
  } else if ([cn isEqualToString:@"NSSet"] || [cn isEqualToString:@"NSMutableSet"]) {
    r = [[NSMutableSet alloc] initWithArray:[self _anonymousObjectsOf:idx]];
  } else if ([cn isEqualToString:@"NSDictionary"] || [cn isEqualToString:@"NSMutableDictionary"]) {
    NSArray *kv = [self _anonymousObjectsOf:idx];   /* key, value, key, value ... */
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    for (NSUInteger i = 0; i + 1 < [kv count]; i += 2) [d setObject:[kv objectAtIndex:i + 1] forKey:[kv objectAtIndex:i]];
    r = d;
  } else if ([cn isEqualToString:@"NSNull"]) {
    r = [[NSNull null] retain];
  } else if ([cn isEqualToString:@"NSCustomObject"]) {
    NSString *n = [self decodeObjectForKey:@"NSClassName"];
    Class c = NSClassFromString(n);
    if (c && [c isSubclassOfClass:[NSApplication class]]) r = [[c sharedApplication] retain];
    else r = [[(c ? c : [NSObject class]) alloc] init];
  } else if ([cn isEqualToString:@"NSNibExternalObjectPlaceholder"]) {
    NSString *ident = [self decodeObjectForKey:@"NSExternalObjectPlaceholderIdentifier"];
    r = [[_externals objectForKey:ident] retain];
  } else if ([cn isEqualToString:@"NSCustomResource"] || [cn isEqualToString:@"NSValue"] || [cn isEqualToString:@"NSFont"]) {
    r = nil;   /* images, fonts and geometry values are not used by the AppKit-lite views */
  } else {
    Class c = NSClassFromString(cn);
    if ([cn isEqualToString:@"NSClassSwapper"]) {
      NSString *n = [self decodeObjectForKey:@"NSClassName"], *orig = [self decodeObjectForKey:@"NSOriginalClassName"];
      c = NSClassFromString(n);
      if (!c) { NSLog(@"xef: nib class %@ not found, using %@", n, orig); c = NSClassFromString(orig); }
    }
    if (!c || ![c instancesRespondToSelector:@selector(initWithCoder:)]) {
      if (!c) NSLog(@"xef: nib class %@ is not implemented", cn);
      r = nil;
    } else {
      id o = [c alloc];
      _cache[idx] = o; _done[idx] = YES;   /* cycles (next responders, superviews) see the object being decoded */
      r = [o initWithCoder:self];
      _done[idx] = NO;
    }
  }
  _cache[idx] = r; _done[idx] = YES;
  _cur = saved;
  return r;
}

- (BOOL)containsValueForKey:(NSString *)k { return [self _val:k] != NULL; }
- (id)decodeObjectForKey:(NSString *)k {
  XNVal *v = [self _val:k];
  return v && v->type == NV_OBJ ? [self objectAtIndex:(uint32_t)v->i] : nil;
}
- (id)decodeObjectOfClass:(Class)c forKey:(NSString *)k { return [self decodeObjectForKey:k]; }
- (id)decodeObjectOfClasses:(NSSet *)c forKey:(NSString *)k { return [self decodeObjectForKey:k]; }
- (BOOL)decodeBoolForKey:(NSString *)k { XNVal *v = [self _val:k]; return v && v->i != 0; }
- (int)decodeIntForKey:(NSString *)k { XNVal *v = [self _val:k]; return v ? (int)v->i : 0; }
- (int32_t)decodeInt32ForKey:(NSString *)k { XNVal *v = [self _val:k]; return v ? (int32_t)v->i : 0; }
- (int64_t)decodeInt64ForKey:(NSString *)k { XNVal *v = [self _val:k]; return v ? v->i : 0; }
- (NSInteger)decodeIntegerForKey:(NSString *)k { XNVal *v = [self _val:k]; return v ? (NSInteger)v->i : 0; }
- (float)decodeFloatForKey:(NSString *)k { XNVal *v = [self _val:k]; return v ? (float)v->d : 0; }
- (double)decodeDoubleForKey:(NSString *)k { XNVal *v = [self _val:k]; return v ? v->d : 0; }
- (const uint8_t *)decodeBytesForKey:(NSString *)k returnedLength:(NSUInteger *)len {
  XNVal *v = [self _val:k];
  if (len) *len = v && v->type == NV_DATA ? v->len : 0;
  return v && v->type == NV_DATA ? v->data : NULL;
}
- (NSSize)decodeSizeForKey:(NSString *)k {
  CGFloat f[2]; id o = [self decodeObjectForKey:k];
  nib_parse_frame([o isKindOfClass:[NSString class]] ? o : nil, f, 2);
  return NSMakeSize(f[0], f[1]);
}
- (NSPoint)decodePointForKey:(NSString *)k { NSSize s = [self decodeSizeForKey:k]; return NSMakePoint(s.width, s.height); }
- (NSRect)decodeRectForKey:(NSString *)k {
  CGFloat f[4]; id o = [self decodeObjectForKey:k];
  nib_parse_frame([o isKindOfClass:[NSString class]] ? o : nil, f, 4);
  return NSMakeRect(f[0], f[1], f[2], f[3]);
}
@end

/* ------------------------------------------------------------------ AppKit classes in nibs */

@interface NSWindowTemplate : NSObject <NSCoding> {
@public
  NSRect _rect; NSUInteger _style; NSString *_title, *_class; NSView *_view; NSSize _minSize; BOOL _visibleAtLaunch;
  NSWindow *_window;
}
- (id)_xefNibInstantiate;
@end

@implementation NSWindowTemplate
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super init])) {
    _rect = [c decodeRectForKey:@"NSWindowRect"];
    _style = (NSUInteger)[c decodeIntegerForKey:@"NSWindowStyleMask"];
    _title = [[c decodeObjectForKey:@"NSWindowTitle"] copy];
    _class = [[c decodeObjectForKey:@"NSWindowClass"] copy];
    _view = [[c decodeObjectForKey:@"NSWindowView"] retain];
    _minSize = [c decodeSizeForKey:@"NSMinSize"];
    _visibleAtLaunch = !([c decodeIntegerForKey:@"NSWTFlags"] & 0x80000);   /* "visible at launch" unless the defer bit says otherwise */
  }
  return self;
}
- (void)encodeWithCoder:(NSCoder *)c {}
- (id)_xefNibInstantiate {
  if (!_window) {
    Class wc = NSClassFromString(_class);
    if (!wc || ![wc isSubclassOfClass:[NSWindow class]]) wc = [NSWindow class];
    NSRect r = _rect;
    if (r.size.width < 1 || r.size.height < 1) r.size = NSMakeSize(480, 270);
    _window = [[wc alloc] initWithContentRect:r styleMask:_style backing:NSBackingStoreBuffered defer:NO];
    if (_title) [_window setTitle:_title];
    if (_view) [_window setContentView:_view];
  }
  return _window;
}
- (void)dealloc { [_title release]; [_class release]; [_view release]; [super dealloc]; }
@end

@implementation NSObject (NSNibAwaking)
- (void)awakeFromNib {}
- (void)prepareForInterfaceBuilder {}
@end

@implementation NSResponder (XEFNib)
- (id)initWithCoder:(NSCoder *)c { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)c {}
@end

@implementation NSView (XEFNib)
- (id)initWithCoder:(NSCoder *)c {
  NSRect f = NSZeroRect;
  if ([c containsValueForKey:@"NSFrame"]) f = [c decodeRectForKey:@"NSFrame"];
  else if ([c containsValueForKey:@"NSFrameSize"]) f.size = [c decodeSizeForKey:@"NSFrameSize"];
  if (!(self = [self _xefInitWithFrame:f])) return nil;
  NSUInteger flags = (NSUInteger)[c decodeIntegerForKey:@"NSvFlags"];
  _hidden = (flags & 0x80000000u) != 0;
  _autoresizingMask = flags & 0x3f;
  _autoresizesSubviews = (flags & 0x100) != 0;
  if ([c decodeBoolForKey:@"NSViewWantsBestResolutionOpenGLSurface"]) [self setWantsBestResolutionOpenGLSurface:YES];
  if ([c decodeBoolForKey:@"NSViewIsLayerTreeHost"] || [c decodeBoolForKey:@"NSViewWantsLayer"]) [self setWantsLayer:YES];
  for (id s in [c decodeObjectForKey:@"NSSubviews"])
    if ([s isKindOfClass:[NSView class]]) [self addSubview:s];
  return self;
}
@end



/* ------------------------------------------------------------------ loading */

/* outlet: setter, then instance variable, then key-value coding */
static void nib_connect_outlet(id src, NSString *label, id dst) {
  if (!src || ![label length]) return;
  NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[label substringToIndex:1] uppercaseString], [label substringFromIndex:1]];
  SEL s = NSSelectorFromString(setter);
  if ([src respondsToSelector:s]) { ((void (*)(id, SEL, id))objc_msgSend)(src, s, dst); return; }
  for (NSString *n in @[label, [@"_" stringByAppendingString:label]]) {
    Ivar iv = class_getInstanceVariable(object_getClass(src), [n UTF8String]);
    if (iv) {
      const char *t = ivar_getTypeEncoding(iv);
      if (t && t[0] == '@') { object_setIvar(src, iv, [dst retain]); return; }
    }
  }
  @try { [src setValue:dst forKey:label]; } @catch (id e) { NSLog(@"xef: nib outlet %@ of %@ not connected", label, [src class]); }
}

/* instantiates a nib: returns the top-level objects (autoreleased array) or nil */
static NSArray *xef_nib_instantiate(NSData *data, id owner, NSDictionary *externals) {
  XEFNibDecoder *d = [[XEFNibDecoder alloc] initWithNibData:data];
  if (!d) return nil;
  d->_externals = [externals retain];
  d->_cur = 0;
  XNVal *od = [d _val:@"IB.objectdata"];
  if (!od || od->type != NV_OBJ) { [d release]; return nil; }
  uint32_t ib = (uint32_t)od->i;
  d->_cur = ib;
  XNVal *rv = [d _val:@"NSRoot"];
  uint32_t root = rv && rv->type == NV_OBJ ? (uint32_t)rv->i : ~0u;
  if (root < d->_nobjs) {   /* File's Owner */
    d->_cache[root] = [(owner ? owner : [[[NSObject alloc] init] autorelease]) retain];
    d->_done[root] = YES;
  }
  XNVal *kv = [d _val:@"NSObjectsKeys"], *pv = [d _val:@"NSObjectsValues"], *cv = [d _val:@"NSConnections"], *wv = [d _val:@"NSVisibleWindows"];
  uint32_t keys_idx = kv ? (uint32_t)kv->i : ~0u, parents_idx = pv ? (uint32_t)pv->i : ~0u;
  NSArray *objects = [d _anonymousObjectsOf:keys_idx];
  NSArray *parents = [d _anonymousObjectsOf:parents_idx];
  NSArray *visible = wv ? [d _anonymousObjectsOf:(uint32_t)wv->i] : @[];
  /* window templates become windows before anything is connected to them */
  for (uint32_t i = 0; i < d->_nobjs; i++)
    if (d->_done[i] && [d->_cache[i] respondsToSelector:@selector(_xefNibInstantiate)]) {
      id w = [[d->_cache[i] _xefNibInstantiate] retain];
      [d->_cache[i] release];
      d->_cache[i] = w;
    }
  #define RESOLVE(x) ([(x) respondsToSelector:@selector(_xefNibInstantiate)] ? [(x) _xefNibInstantiate] : (x))
  /* connections */
  NSMutableArray *refs = [NSMutableArray array];
  if (cv && cv->type == NV_OBJ) {
    XNObj *co = &d->_objs[(uint32_t)cv->i];
    for (uint32_t i = co->first; i < co->first + co->count; i++)
      if (d->_vals[i].type == NV_OBJ) [refs addObject:@((uint32_t)d->_vals[i].i)];
  }
  for (NSNumber *n in refs) {
    uint32_t ci = [n unsignedIntValue];
    NSString *cls = [d _classNameOf:ci];
    d->_cur = ci;
    if ([cls isEqualToString:@"NSNibOutletConnector"]) {
      id src = RESOLVE([d decodeObjectForKey:@"NSSource"]), dst = RESOLVE([d decodeObjectForKey:@"NSDestination"]);
      nib_connect_outlet(src, [d decodeObjectForKey:@"NSLabel"], dst);
    } else if ([cls isEqualToString:@"NSNibControlConnector"]) {
      id src = RESOLVE([d decodeObjectForKey:@"NSSource"]), dst = RESOLVE([d decodeObjectForKey:@"NSDestination"]);
      NSString *label = [d decodeObjectForKey:@"NSLabel"];
      if ([src respondsToSelector:@selector(setTarget:)]) [src setTarget:dst];
      if ([label length] && [src respondsToSelector:@selector(setAction:)]) ((void (*)(id, SEL, SEL))objc_msgSend)(src, @selector(setAction:), NSSelectorFromString(label));
    } else if ([cls isEqualToString:@"NSIBUserDefinedRuntimeAttributesConnector"]) {
      id obj = RESOLVE([d decodeObjectForKey:@"NSObject"]);
      NSArray *vals = [d decodeObjectForKey:@"NSValues"], *paths = [d decodeObjectForKey:@"NSKeyPaths"];
      for (NSUInteger i = 0; i < [paths count] && i < [vals count]; i++) {
        id v = RESOLVE([vals objectAtIndex:i]);
        @try { [obj setValue:(v == [NSNull null] ? nil : v) forKeyPath:[paths objectAtIndex:i]]; }
        @catch (id e) { NSLog(@"xef: nib runtime attribute %@ of %@ not set", [paths objectAtIndex:i], [obj class]); }
      }
    }
  }
  /* top-level objects: children of File's Owner, then awakeFromNib on everything */
  id ownerObj = root < d->_nobjs ? d->_cache[root] : nil;
  NSMutableArray *top = [NSMutableArray array];
  NSMutableArray *all = [NSMutableArray array];
  for (NSUInteger i = 0; i < [objects count]; i++) {
    id o = RESOLVE([objects objectAtIndex:i]);
    if (o == [NSNull null] || !o) continue;
    if (![all containsObject:o]) [all addObject:o];
    id p = i < [parents count] ? [parents objectAtIndex:i] : nil;
    if (p == ownerObj && o != ownerObj && ![o isKindOfClass:[NSApplication class]] && ![top containsObject:o]) [top addObject:o];
  }
  /* named objects: the application's main, windows and services menus */
  XNVal *nk = [d _val:@"NSNamesKeys"], *nv = [d _val:@"NSNamesValues"];
  if (nk && nv && nk->type == NV_OBJ && nv->type == NV_OBJ) {
    NSArray *objs = [d _anonymousObjectsOf:(uint32_t)nk->i], *names = [d _anonymousObjectsOf:(uint32_t)nv->i];
    for (NSUInteger i = 0; i < [objs count] && i < [names count]; i++) {
      id o = RESOLVE([objs objectAtIndex:i]); NSString *n = [names objectAtIndex:i];
      if (![n isKindOfClass:[NSString class]] || ![o isKindOfClass:[NSMenu class]]) continue;
      if ([n isEqualToString:@"_NSMainMenu"]) [NSApp setMainMenu:o];
      else if ([n isEqualToString:@"_NSWindowsMenu"]) [NSApp setWindowsMenu:o];
      else if ([n isEqualToString:@"_NSServicesMenu"]) [NSApp setServicesMenu:o]; } }
  for (id o in all)
    if ([o respondsToSelector:@selector(awakeFromNib)]) [o awakeFromNib];
  for (id w in visible) {
    id win = RESOLVE(w);
    if ([win isKindOfClass:[NSWindow class]]) [win makeKeyAndOrderFront:nil];
  }
  #undef RESOLVE
  [top makeObjectsPerformSelector:@selector(retain)];   /* the caller owns the top-level objects, as in AppKit */
  [d release];
  return top;
}

/* ------------------------------------------------------------------ storyboards */

@interface NSStoryboard : NSObject {
@public
  NSString *_path; NSDictionary *_info; NSBundle *_bundle;
}
+ (NSStoryboard *)storyboardWithName:(NSString *)name bundle:(NSBundle *)bundle;
+ (NSStoryboard *)mainStoryboard;
- (id)instantiateInitialController;
- (id)instantiateControllerWithIdentifier:(NSString *)ident;
- (NSArray *)_instantiateNib:(NSString *)nib owner:(id)owner;
@end

/* the owner of a storyboard scene nib: the scene's controller arrives through the "sceneController" outlet */
@interface XEFStoryboardSceneOwner : NSObject { @public id _sceneController; }
@end
@implementation XEFStoryboardSceneOwner
- (void)setSceneController:(id)c { _sceneController = c; }
@end

static NSStoryboard *g_main_storyboard;

@implementation NSStoryboard
+ (NSStoryboard *)storyboardWithName:(NSString *)name bundle:(NSBundle *)bundle {
  if (!bundle) bundle = [NSBundle mainBundle];
  NSString *path = [bundle pathForResource:name ofType:@"storyboardc"];
  if (!path) path = [[bundle resourcePath] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"storyboardc"]];
  NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
  if (!info) { NSLog(@"xef: storyboard %@ not found", name); return nil; }
  NSStoryboard *s = [[[NSStoryboard alloc] init] autorelease];
  s->_path = [path copy]; s->_info = [info retain]; s->_bundle = [bundle retain];
  return s;
}
+ (NSStoryboard *)mainStoryboard { return g_main_storyboard; }
- (NSArray *)_instantiateNib:(NSString *)nib owner:(id)owner {
  NSData *data = [NSData dataWithContentsOfFile:[[_path stringByAppendingPathComponent:nib] stringByAppendingPathExtension:@"nib"]];
  if (!data) { NSLog(@"xef: storyboard nib %@ missing", nib); return nil; }
  return xef_nib_instantiate(data, owner, @{@"NSStoryboardPlaceholder": self});
}
- (id)instantiateControllerWithIdentifier:(NSString *)ident {
  NSString *nib = [[_info objectForKey:@"NSViewControllerIdentifiersToNibNames"] objectForKey:ident];
  if (!nib) return nil;
  XEFStoryboardSceneOwner *o = [[[XEFStoryboardSceneOwner alloc] init] autorelease];
  NSArray *top = [self _instantiateNib:nib owner:o];
  id c = o->_sceneController;
  if (!c) for (id t in top) if ([t isKindOfClass:[NSViewController class]] || [t isKindOfClass:[NSWindowController class]]) c = t;
  return c;
}
- (id)instantiateInitialController {
  NSString *entry = [_info objectForKey:@"NSStoryboardDesignatedEntryPointIdentifier"];
  return entry ? [self instantiateControllerWithIdentifier:entry] : nil;
}
- (void)dealloc { [_path release]; [_info release]; [_bundle release]; [super dealloc]; }
@end

/* ------------------------------------------------------------------ controllers */


@implementation NSViewController
- (id)initWithNibName:(NSString *)n bundle:(NSBundle *)b {
  if ((self = [super init])) { _nibName = [n copy]; _nibBundle = [b retain]; }
  return self;
}
- (id)init { return [self initWithNibName:nil bundle:nil]; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super init])) _nibName = [[c decodeObjectForKey:@"NSNibName"] copy];
  return self;
}
- (void)encodeWithCoder:(NSCoder *)c {}
- (NSString *)nibName { return _nibName; }
- (NSBundle *)nibBundle { return _nibBundle; }
- (NSStoryboard *)storyboard { return _storyboard; }
- (void)setStoryboard:(NSStoryboard *)s { _storyboard = s; }
- (id)representedObject { return _representedObject; }
- (void)setRepresentedObject:(id)o { [o retain]; [_representedObject release]; _representedObject = o; }
- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)t { [t retain]; [_title release]; _title = t; }
- (BOOL)isViewLoaded { return _view != nil; }
- (void)setView:(NSView *)v {
  [v retain]; [_view release]; _view = v;
  if (v) [v setNextResponder:self];
}
- (void)loadView {
  if (_nibName) {
    if (_storyboard) [_storyboard _instantiateNib:_nibName owner:self];
    else {
      NSBundle *b = _nibBundle ? _nibBundle : [NSBundle mainBundle];
      NSData *data = [NSData dataWithContentsOfFile:[b pathForResource:_nibName ofType:@"nib"]];
      if (data) xef_nib_instantiate(data, self, nil);
    }
  }
  if (!_view) [self setView:[[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 270)] autorelease]];
}
- (NSView *)view {
  if (!_view && !_loading) {
    _loading = YES;
    [self loadView];
    _loading = NO;
    [self viewDidLoad];
  }
  return _view;
}
- (void)viewDidLoad {}
- (void)viewWillAppear {} - (void)viewDidAppear {} - (void)viewWillDisappear {} - (void)viewDidDisappear {}
- (void)viewWillLayout {} - (void)viewDidLayout {} - (void)updateViewConstraints {}
- (NSSize)preferredContentSize { return _view ? [_view frame].size : NSZeroSize; }
- (void)dealloc { [_view release]; [_nibName release]; [_nibBundle release]; [_representedObject release]; [_title release]; [super dealloc]; }
@end


@implementation NSWindow (XEFControllers)
- (void)setContentViewController:(NSViewController *)vc {
  objc_setAssociatedObject(self, "xef.contentViewController", vc, OBJC_ASSOCIATION_RETAIN);
  NSView *v = [vc view];
  if (v) {
    NSRect cr = [self contentRectForFrameRect:[self frame]];
    if ([v frame].size.width > 0 && [v frame].size.height > 0) [self setContentSize:[v frame].size];
    else [v setFrame:NSMakeRect(0, 0, cr.size.width, cr.size.height)];
    [self setContentView:v];
    [v setNextResponder:vc];
    [vc setNextResponder:self];
  }
}
- (NSViewController *)contentViewController { return objc_getAssociatedObject(self, "xef.contentViewController"); }
- (NSWindowController *)windowController { return objc_getAssociatedObject(self, "xef.windowController"); }
- (void)setWindowController:(NSWindowController *)wc { objc_setAssociatedObject(self, "xef.windowController", wc, OBJC_ASSOCIATION_ASSIGN); }
@end

@implementation NSWindowController
- (id)initWithWindow:(NSWindow *)w {
  if ((self = [super init])) { _window = [w retain]; _loaded = w != nil; [w setWindowController:self]; }
  return self;
}
- (id)initWithWindowNibName:(NSString *)n { return [self initWithWindowNibName:n owner:self]; }
- (id)initWithWindowNibName:(NSString *)n owner:(id)o {
  if ((self = [super init])) { _nibName = [n copy]; _owner = o; }
  return self;
}
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super init])) {
    id tmpl = [c decodeObjectForKey:@"IBWindowTemplate"];
    if ([tmpl respondsToSelector:@selector(_xefNibInstantiate)]) { _window = [[tmpl _xefNibInstantiate] retain]; _loaded = YES; }
    _content = [[c decodeObjectForKey:@"IBWindowTemplateContentViewController"] retain];
  }
  return self;
}
- (void)encodeWithCoder:(NSCoder *)c {}
- (NSStoryboard *)storyboard { return _storyboard; }
- (void)setStoryboard:(NSStoryboard *)s { _storyboard = s; }
- (void)setWindow:(NSWindow *)w { [w retain]; [_window release]; _window = w; [w setWindowController:self]; }
- (void)windowWillLoad {} - (void)windowDidLoad {}
- (void)loadWindow {
  if (_nibName) {
    NSData *data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:_nibName ofType:@"nib"]];
    id doc = [self document];
    BOOL docOwner = [_owner isKindOfClass:[NSDocument class]];
    if (docOwner) [_owner _xefSetLoadingWindowController:self];
    if (doc) [doc windowControllerWillLoadNib:self];
    if (data) xef_nib_instantiate(data, _owner ? _owner : self, nil);
    else NSLog(@"xef: window nib %@ not found", _nibName);
    if (docOwner) [_owner _xefSetLoadingWindowController:nil];
    if (doc) [doc windowControllerDidLoadNib:self];
  }
}
- (NSWindow *)window {
  if (!_loaded) {
    _loaded = YES;
    [self windowWillLoad];
    [self loadWindow];
    [self windowDidLoad];
  }
  return _window;
}
- (BOOL)isWindowLoaded { return _loaded && _window; }
- (NSViewController *)contentViewController { return _content ? _content : [_window contentViewController]; }
- (void)setContentViewController:(NSViewController *)vc {
  [vc retain]; [_content release]; _content = vc;
  [[self window] setContentViewController:vc];
}
- (void)showWindow:(id)sender {
  NSWindow *w = [self window];
  [w setWindowController:self];
  if (_content && [w contentViewController] != _content) {
    [_content viewWillAppear];
    [w setContentViewController:_content];
  }
  [w makeKeyAndOrderFront:sender];
  if (_content) [_content viewDidAppear];
}
- (void)close { [_window close]; }
- (void)dealloc { [_window release]; [_content release]; [_nibName release]; [super dealloc]; }
@end

/* ------------------------------------------------------------------ NSBundle loading and NSApplicationMain */

@implementation NSBundle (XEFNibLoading)
- (BOOL)loadNibNamed:(NSString *)name owner:(id)owner topLevelObjects:(NSArray **)top {
  NSString *p = [self pathForResource:name ofType:@"nib"];
  NSData *data = p ? [NSData dataWithContentsOfFile:p] : nil;
  if (!data) {   /* keyed-archive nibs (designable.nib inside a nib directory) are not supported */
    NSLog(@"xef: nib %@ not found or not a compiled NIBArchive", name);
    return NO;
  }
  NSArray *t = xef_nib_instantiate(data, owner, nil);
  if (top) *top = t;
  return t != nil;
}
+ (BOOL)loadNibNamed:(NSString *)name owner:(id)owner {
  return [[NSBundle mainBundle] loadNibNamed:name owner:owner topLevelObjects:NULL];
}
@end

int NSApplicationMain(int argc, const char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
  Class pc = NSClassFromString([info objectForKey:@"NSPrincipalClass"]);
  if (!pc || ![pc isSubclassOfClass:[NSApplication class]]) pc = [NSApplication class];
  NSApplication *app = [pc sharedApplication];
  NSString *sb = [info objectForKey:@"NSMainStoryboardFile"], *nib = [info objectForKey:@"NSMainNibFile"];
  id initial = nil;
  if (sb) {
    g_main_storyboard = [[NSStoryboard storyboardWithName:sb bundle:[NSBundle mainBundle]] retain];
    NSString *menu = [g_main_storyboard->_info objectForKey:@"NSStoryboardMainMenu"];
    if (menu) [g_main_storyboard _instantiateNib:menu owner:app];
    initial = [g_main_storyboard instantiateInitialController];
  } else if (nib) {
    [[NSBundle mainBundle] loadNibNamed:nib owner:app topLevelObjects:NULL];
  }
  if ([initial isKindOfClass:[NSWindowController class]]) {
    [initial retain];
    [initial showWindow:nil];
  } else if ([initial isKindOfClass:[NSViewController class]]) {
    NSView *v = [initial view];
    NSRect r = [v frame];
    if (r.size.width < 1) r = NSMakeRect(0, 0, 480, 270);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:r styleMask:15 backing:NSBackingStoreBuffered defer:NO];
    [w setContentViewController:initial];
    [w makeKeyAndOrderFront:nil];
  }
  [pool release];
  [app run];
  return 0;
}
