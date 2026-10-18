/* AppKit-lite asset catalogs: +[NSColor colorNamed:] and +[NSImage imageNamed:] read the bundle's compiled asset
 * catalog (Assets.car, a BOM store of CoreUI renditions; the layout is the one MetalKitAssets.m reads textures from).
 * Named colours are 'COLR' renditions (layout 1009): colour space, component count and doubles. Images are bitmap
 * renditions (layout 12, premultiplied BGRA 'ARGB' or gray 'GA8 ', raw or LZFSE-compressed 'MLEC' payloads). The light
 * appearance and the 1x scale (else the smallest available) are preferred. MRC. */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#include <string.h>
#include <objc/runtime.h>
#include "lzfse/lzfse.h"

enum { A_ELEMENT = 1, A_PART = 2, A_IDENTIFIER = 17, A_SCALE = 12, A_APPEARANCE = 24, L_BITMAP = 12, L_COLOR = 1009 };

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static uint16_t be16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static uint32_t le32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint16_t le16(const uint8_t *p) { uint16_t v; memcpy(&v, p, 2); return v; }

typedef struct { const uint8_t *key, *val; uint32_t klen, vlen; } CarPair;

@interface XEFCarFile : NSObject {
@public
  NSData *_data; const uint8_t *_b; uint32_t _len, _iofs, _nblocks; NSMutableDictionary *_vars;
  uint32_t _tokens[32]; uint32_t _ntokens;
  NSMutableDictionary *_facets;      /* name -> identifier */
  NSData *_renditions;               /* CarPair[] */
  NSMutableDictionary *_colors, *_images;
}
+ (XEFCarFile *)catalogForBundle:(NSBundle *)b;
- (NSColor *)colorNamed:(NSString *)n;
- (NSImage *)imageNamed:(NSString *)n;
@end

@implementation XEFCarFile
- (const uint8_t *)_block:(uint32_t)i length:(uint32_t *)len {
  if (i >= _nblocks) return NULL;
  uint32_t a = be32(_b + _iofs + 4 + 8 * i), l = be32(_b + _iofs + 8 + 8 * i);
  if ((uint64_t)a + l > _len) return NULL;
  if (len) *len = l;
  return _b + a; }
- (const uint8_t *)_var:(NSString *)n length:(uint32_t *)len { NSNumber *v = [_vars objectForKey:n]; return v ? [self _block:[v unsignedIntValue] length:len] : NULL; }
- (NSData *)_tree:(NSString *)name {
  NSMutableData *out = [NSMutableData data];
  uint32_t tl = 0; const uint8_t *t = [self _var:name length:&tl];
  if (!t || tl < 12 || memcmp(t, "tree", 4)) return out;
  uint32_t node = be32(t + 8);
  for (int d = 0; d < 64; d++) { uint32_t nl = 0; const uint8_t *n = [self _block:node length:&nl]; if (!n || nl < 16) return out; if (be16(n)) break; node = be32(n + 12); }
  for (int g = 0; node && g < 1000000; g++) {
    uint32_t nl = 0; const uint8_t *n = [self _block:node length:&nl];
    if (!n || nl < 12) break;
    uint16_t count = be16(n + 2);
    for (uint16_t i = 0; i < count && 12 + 8 * i + 8 <= nl; i++) {
      CarPair p = {0};
      p.val = [self _block:be32(n + 12 + 8 * i) length:&p.vlen];
      p.key = [self _block:be32(n + 16 + 8 * i) length:&p.klen];
      if (p.val && p.key) [out appendBytes:&p length:sizeof p]; }
    node = be32(n + 4); }
  return out; }
+ (XEFCarFile *)catalogForBundle:(NSBundle *)bundle {
  static NSMutableDictionary *cache;
  NSString *path = [bundle pathForResource:@"Assets" ofType:@"car"];
  if (!path) return nil;
  @synchronized ([XEFCarFile class]) {
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    id c = [cache objectForKey:path];
    if (c) return c == [NSNull null] ? nil : c;
    XEFCarFile *f = [[[XEFCarFile alloc] init] autorelease];
    if (![f _load:path]) { [cache setObject:[NSNull null] forKey:path]; return nil; }
    [cache setObject:f forKey:path];
    return f; } }
- (BOOL)_load:(NSString *)path {
  _data = [[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL] retain];
  if (!_data || [_data length] < 32 || memcmp([_data bytes], "BOMStore", 8)) return NO;
  _b = [_data bytes]; _len = (uint32_t)[_data length];
  _iofs = be32(_b + 16); uint32_t vofs = be32(_b + 24);
  if (_iofs + 4 > _len || vofs + 4 > _len) return NO;
  _nblocks = be32(_b + _iofs);
  _vars = [[NSMutableDictionary alloc] init];
  uint32_t nv = be32(_b + vofs), p = vofs + 4;
  for (uint32_t i = 0; i < nv && p + 5 <= _len; i++) {
    uint32_t blk = be32(_b + p); uint8_t l = _b[p + 4];
    if (p + 5 + l > _len) break;
    [_vars setObject:@(blk) forKey:[[[NSString alloc] initWithBytes:_b + p + 5 length:l encoding:NSUTF8StringEncoding] autorelease]];
    p += 5 + l; }
  uint32_t kl = 0; const uint8_t *kf = [self _var:@"KEYFORMAT" length:&kl];
  if (kf && kl >= 12) { _ntokens = MIN(le32(kf + 8), 32u); for (uint32_t i = 0; i < _ntokens && 12 + 4 * i + 4 <= kl; i++) _tokens[i] = le32(kf + 12 + 4 * i); }
  _facets = [[NSMutableDictionary alloc] init];
  NSData *fd = [self _tree:@"FACETKEYS"]; const CarPair *fp = [fd bytes];
  for (NSUInteger i = 0; i < [fd length] / sizeof(CarPair); i++) {
    NSString *n = [[[NSString alloc] initWithBytes:fp[i].key length:fp[i].klen encoding:NSUTF8StringEncoding] autorelease];
    uint16_t cnt = fp[i].vlen >= 6 ? le16(fp[i].val + 4) : 0;
    for (uint16_t k = 0; k < cnt && 6 + 4 * k + 4 <= fp[i].vlen; k++)
      if (le16(fp[i].val + 6 + 4 * k) == A_IDENTIFIER && n) [_facets setObject:@(le16(fp[i].val + 8 + 4 * k)) forKey:n]; }
  _renditions = [[self _tree:@"RENDITIONS"] retain];
  _colors = [[NSMutableDictionary alloc] init]; _images = [[NSMutableDictionary alloc] init];
  return YES; }
- (void)dealloc { [_data release]; [_vars release]; [_facets release]; [_renditions release]; [_colors release]; [_images release]; [super dealloc]; }
- (uint16_t)_attr:(uint32_t)a of:(const CarPair *)r found:(BOOL *)found {
  for (uint32_t i = 0; i < _ntokens && 2 * i + 2 <= r->klen; i++) if (_tokens[i] == a) { if (found) *found = YES; return le16(r->key + 2 * i); }
  if (found) *found = NO; return 0; }
/* the renditions of a facet with the given layout, best first (light appearance, then scale 1, then smallest scale) */
- (NSArray *)_renditionsNamed:(NSString *)n layout:(uint16_t)layout {
  NSNumber *ident = [_facets objectForKey:n];
  if (!ident) return nil;
  const CarPair *rp = [_renditions bytes]; NSUInteger nr = [_renditions length] / sizeof(CarPair);
  NSMutableArray *found = [NSMutableArray array];
  for (NSUInteger i = 0; i < nr; i++) {
    BOOL f = NO;
    if ([self _attr:A_IDENTIFIER of:&rp[i] found:&f] != [ident unsignedShortValue] || !f || rp[i].vlen < 184 || memcmp(rp[i].val, "ISTC", 4)) continue;
    if (le16(rp[i].val + 36) != layout) continue;
    [found addObject:@(i)]; }
  [found sortUsingComparator:^NSComparisonResult(NSNumber *x, NSNumber *y) {
    const CarPair *a = &rp[[x unsignedIntegerValue]], *b = &rp[[y unsignedIntegerValue]];
    uint16_t aa = [self _attr:A_APPEARANCE of:a found:NULL], ba = [self _attr:A_APPEARANCE of:b found:NULL];
    if (aa != ba) return aa < ba ? NSOrderedAscending : NSOrderedDescending;
    uint16_t as = [self _attr:A_SCALE of:a found:NULL], bs = [self _attr:A_SCALE of:b found:NULL];
    if (as == 0) as = 1; if (bs == 0) bs = 1;
    if (as != bs) return (as == 1 || (bs != 1 && as < bs)) ? NSOrderedAscending : NSOrderedDescending;
    return NSOrderedSame; }];
  return found; }
- (NSColor *)colorNamed:(NSString *)n {
  @synchronized (self) {
    id c = [_colors objectForKey:n];
    if (c) return c == [NSNull null] ? nil : c;
    NSColor *col = nil;
    const CarPair *rp = [_renditions bytes];
    for (NSNumber *i in [self _renditionsNamed:n layout:L_COLOR]) {
      const CarPair *r = &rp[[i unsignedIntegerValue]];
      const uint8_t *q = r->val + 184 + le32(r->val + 168), *end = r->val + r->vlen;
      if (q + 16 > end || memcmp(q, "RLOC", 4)) continue;
      uint32_t cnt = le32(q + 12);
      if (cnt < 1 || cnt > 5 || q + 16 + 8 * cnt > end) continue;
      double v[5]; memcpy(v, q + 16, 8 * cnt);
      if (cnt <= 2) col = [NSColor colorWithCalibratedWhite:v[0] alpha:cnt == 2 ? v[1] : 1];
      else col = [NSColor colorWithCalibratedRed:v[0] green:v[1] blue:v[2] alpha:cnt >= 4 ? v[3] : 1];
      break; }
    [_colors setObject:col ?: (id)[NSNull null] forKey:n];
    return col; } }
/* bitmap payload ('MLEC': raw or LZFSE, optionally in 'KCBC' row chunks) -> rows of rowbytes */
static NSMutableData *bitmap_rows(const CarPair *r, uint32_t w, uint32_t h, uint32_t rowbytes) {
  const uint8_t *q = r->val + 184 + le32(r->val + 168), *end = r->val + r->vlen;
  if (q + 16 > end || memcmp(q, "MLEC", 4)) return nil;
  uint32_t flags = le32(q + 4), comp = le32(q + 8), n = le32(q + 12);
  q += 16;
  NSMutableData *out = [NSMutableData dataWithLength:(NSUInteger)rowbytes * h];
  uint8_t *dst = [out mutableBytes]; size_t total = [out length], done = 0;
  void *scratch = malloc(lzfse_decode_scratch_size());
  BOOL ok = YES;
  uint32_t chunks = (flags & 1) ? n : 1;
  for (uint32_t c = 0; c < chunks && ok; c++) {
    uint32_t len = n, rows = h;
    if (flags & 1) { if (q + 20 > end || memcmp(q, "KCBC", 4)) { ok = NO; break; } rows = le32(q + 12); len = le32(q + 16); q += 20; }
    if (q + len > end) { ok = NO; break; }
    size_t want = MIN((size_t)rows * rowbytes, total - done);
    if (comp == 0) memcpy(dst + done, q, MIN((size_t)len, want));
    else if (comp == 4) { if (lzfse_decode_buffer(dst + done, want, q, len, scratch) != want) ok = NO; }
    else { NSLog(@"xef: asset catalog compression %u is not supported", comp); ok = NO; }
    done += want; q += len; }
  free(scratch);
  return ok ? out : nil; }
- (NSImage *)imageNamed:(NSString *)n {
  @synchronized (self) {
    id c = [_images objectForKey:n];
    if (c) return c == [NSNull null] ? nil : c;
    NSImage *img = nil;
    const CarPair *rp = [_renditions bytes];
    for (NSNumber *i in [self _renditionsNamed:n layout:L_BITMAP]) {
      const CarPair *r = &rp[[i unsignedIntegerValue]];
      uint32_t w = le32(r->val + 12), h = le32(r->val + 16), scale = le32(r->val + 20), pf = le32(r->val + 24);
      if (!w || !h || (pf != 0x41524742 /*ARGB*/ && pf != 0x47413820 /*GA8 */)) continue;
      uint32_t bpp = pf == 0x41524742 ? 4 : 2, rowbytes = w * bpp, tlv = le32(r->val + 168);
      for (uint32_t p = 184; p + 8 <= 184 + tlv && p + 8 <= r->vlen;) { uint32_t t = le32(r->val + p), l = le32(r->val + p + 4); if (t == 0x3ef && l >= 4) rowbytes = le32(r->val + p + 8); p += 8 + l; }
      NSMutableData *rows = bitmap_rows(r, w, h, rowbytes);
      if (!rows) continue;
      NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                         isPlanar:NO colorSpaceName:@"NSDeviceRGBColorSpace" bitmapFormat:0 bytesPerRow:w * 4 bitsPerPixel:32] autorelease];
      uint8_t *dst = [rep bitmapData]; const uint8_t *src = [rows bytes];
      for (uint32_t y = 0; y < h; y++)
        for (uint32_t x = 0; x < w; x++) {   /* -> premultiplied RGBA */
          const uint8_t *s = src + (size_t)y * rowbytes + x * bpp; uint8_t *d = dst + ((size_t)y * w + x) * 4;
          if (bpp == 4) { d[0] = s[2]; d[1] = s[1]; d[2] = s[0]; d[3] = s[3]; }
          else { uint8_t a = s[1]; d[0] = d[1] = d[2] = (uint8_t)(s[0] * a / 255); d[3] = a; } }
      CGFloat sc = scale ? scale / 100.0 : 1; if (sc <= 0) sc = 1; if (scale > 0 && scale < 10) sc = scale;
      img = [[[NSImage alloc] initWithSize:NSMakeSize(w / sc, h / sc)] autorelease];
      [img addRepresentation:rep];
      break; }
    [_images setObject:img ?: (id)[NSNull null] forKey:n];
    return img; } }
@end

/* catalogs searched: the given bundle, else the main bundle and the loaded frameworks */
static NSArray *catalog_bundles(NSBundle *b) { return b ? @[b] : [@[[NSBundle mainBundle]] arrayByAddingObjectsFromArray:[NSBundle allFrameworks]]; }

@implementation NSColor (XEFAssets)
+ (NSColor *)colorNamed:(NSString *)n bundle:(NSBundle *)b {
  if (![n length]) return nil;
  for (NSBundle *bb in catalog_bundles(b)) { NSColor *c = [[XEFCarFile catalogForBundle:bb] colorNamed:n]; if (c) return c; }
  if (getenv("XEF_ASSET_DEBUG")) NSLog(@"xef: colorNamed %@ not found (bundle %@)", n, b);
  return nil; }
+ (NSColor *)colorNamed:(NSString *)n { return [self colorNamed:n bundle:nil]; }
@end

@implementation NSImage (XEFAssets)
static NSMutableDictionary *g_named_images;
+ (NSImage *)imageNamed:(NSString *)n {
  if (![n length]) return nil;
  NSImage *img = [g_named_images objectForKey:n];
  if (img) return img;
  for (NSBundle *bb in catalog_bundles(nil)) { img = [[XEFCarFile catalogForBundle:bb] imageNamed:n]; if (img) break; }
  if (img) { if (!g_named_images) g_named_images = [[NSMutableDictionary alloc] init]; [g_named_images setObject:img forKey:n]; }
  return img; }
- (BOOL)setName:(NSString *)n {
  if (!n) return NO;
  if (!g_named_images) g_named_images = [[NSMutableDictionary alloc] init];
  [g_named_images setObject:self forKey:n]; return YES; }
@end

@implementation NSBundle (XEFAssets)
- (NSImage *)imageForResource:(NSString *)n { return [[XEFCarFile catalogForBundle:self] imageNamed:n]; }
@end
