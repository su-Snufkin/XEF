/* Compiled asset catalogs (Assets.car): a BOM store holding CoreUI renditions. MTKTextureLoader's
   -newTextureWithName: reads texture sets from it: a container rendition ('TXTR', layout 1007) gives the
   pixel format, one rendition per mip level (layout 1008, mip in the Dimension2 attribute) holds the rows,
   raw or LZFSE-compressed, optionally split into row chunks. MRC. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <string.h>
#include "lzfse/lzfse.h"

enum {
  ATTR_ELEMENT = 1, ATTR_PART = 2, ATTR_DIMENSION2 = 9, ATTR_IDENTIFIER = 17,
  LAYOUT_TEXTURE = 1007, LAYOUT_TEXTURE_IMAGE = 1008, PART_TEXTURE_IMAGE = 181,
};

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static uint16_t be16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static uint32_t le32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint16_t le16(const uint8_t *p) { uint16_t v; memcpy(&v, p, 2); return v; }

typedef struct { const uint8_t *key, *val; uint32_t klen, vlen; } XCPair;

@interface XEFAssetCatalog : NSObject {
@public
  NSData *_data;
  const uint8_t *_b; uint32_t _len;
  uint32_t _iofs, _nblocks;
  NSMutableDictionary *_vars;      /* name -> block index */
  uint32_t _tokens[32]; uint32_t _ntokens;
}
+ (XEFAssetCatalog *)catalogForBundle:(NSBundle *)bundle;
- (id<MTLTexture>)newTextureNamed:(NSString *)name device:(id<MTLDevice>)device options:(NSDictionary *)options error:(NSError **)error;
@end

@implementation XEFAssetCatalog
+ (XEFAssetCatalog *)catalogForBundle:(NSBundle *)bundle {
  static NSMutableDictionary *cache;
  if (!cache) cache = [[NSMutableDictionary alloc] init];
  NSString *path = [bundle pathForResource:@"Assets" ofType:@"car"];
  if (!path) return nil;
  XEFAssetCatalog *c = [cache objectForKey:path];
  if (c) return c;
  NSData *d = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
  if (!d || [d length] < 32 || memcmp([d bytes], "BOMStore", 8)) return nil;
  c = [[[XEFAssetCatalog alloc] init] autorelease];
  c->_data = [d retain]; c->_b = [d bytes]; c->_len = (uint32_t)[d length];
  c->_iofs = be32(c->_b + 16);
  uint32_t vofs = be32(c->_b + 24);
  if (c->_iofs + 4 > c->_len || vofs + 4 > c->_len) return nil;
  c->_nblocks = be32(c->_b + c->_iofs);
  c->_vars = [[NSMutableDictionary alloc] init];
  uint32_t nv = be32(c->_b + vofs), p = vofs + 4;
  for (uint32_t i = 0; i < nv && p + 5 <= c->_len; i++) {
    uint32_t blk = be32(c->_b + p); uint8_t l = c->_b[p + 4];
    if (p + 5 + l > c->_len) break;
    NSString *n = [[[NSString alloc] initWithBytes:c->_b + p + 5 length:l encoding:NSUTF8StringEncoding] autorelease];
    [c->_vars setObject:@(blk) forKey:n];
    p += 5 + l;
  }
  uint32_t kf_len = 0;
  const uint8_t *kf = [c _blockForVar:@"KEYFORMAT" length:&kf_len];
  if (kf && kf_len >= 12) {
    c->_ntokens = MIN(le32(kf + 8), 32u);
    for (uint32_t i = 0; i < c->_ntokens && 12 + 4 * i + 4 <= kf_len; i++) c->_tokens[i] = le32(kf + 12 + 4 * i);
  }
  [cache setObject:c forKey:path];
  return c;
}

- (const uint8_t *)_block:(uint32_t)i length:(uint32_t *)len {
  if (i >= _nblocks) return NULL;
  uint32_t a = be32(_b + _iofs + 4 + 8 * i), l = be32(_b + _iofs + 8 + 8 * i);
  if ((uint64_t)a + l > _len) return NULL;
  if (len) *len = l;
  return _b + a;
}
- (const uint8_t *)_blockForVar:(NSString *)name length:(uint32_t *)len {
  NSNumber *n = [_vars objectForKey:name];
  return n ? [self _block:[n unsignedIntValue] length:len] : NULL;
}

/* every (key, value) of a BOM tree, following the leaf chain */
- (NSData *)_tree:(NSString *)name {
  NSMutableData *out = [NSMutableData data];
  uint32_t tl = 0;
  const uint8_t *t = [self _blockForVar:name length:&tl];
  if (!t || tl < 12 || memcmp(t, "tree", 4)) return out;
  uint32_t node = be32(t + 8);
  for (int depth = 0; depth < 64; depth++) {   /* descend to the first leaf */
    uint32_t nl = 0;
    const uint8_t *n = [self _block:node length:&nl];
    if (!n || nl < 12) return out;
    if (be16(n)) break;
    node = be32(n + 12);
  }
  for (int guard = 0; node && guard < 1000000; guard++) {
    uint32_t nl = 0;
    const uint8_t *n = [self _block:node length:&nl];
    if (!n || nl < 12) break;
    uint16_t count = be16(n + 2);
    for (uint16_t i = 0; i < count && 12 + 8 * i + 8 <= nl; i++) {
      XCPair pr = {0};
      pr.val = [self _block:be32(n + 12 + 8 * i) length:&pr.vlen];
      pr.key = [self _block:be32(n + 16 + 8 * i) length:&pr.klen];
      if (pr.val && pr.key) [out appendBytes:&pr length:sizeof pr];
    }
    node = be32(n + 4);
  }
  return out;
}

static uint16_t rendition_attr(XEFAssetCatalog *c, const XCPair *r, uint32_t attr, BOOL *found) {
  for (uint32_t i = 0; i < c->_ntokens && 2 * i + 2 <= r->klen; i++)
    if (c->_tokens[i] == attr) { if (found) *found = YES; return le16(r->key + 2 * i); }
  if (found) *found = NO;
  return 0;
}

/* pixel rows of one image rendition (BGRA, rowbytes from the header) */
static NSMutableData *rendition_pixels(const XCPair *r, uint32_t *w, uint32_t *h, uint32_t *rowbytes) {
  if (r->vlen < 184 || memcmp(r->val, "ISTC", 4)) return nil;
  *w = le32(r->val + 12); *h = le32(r->val + 16);
  uint32_t tlv_len = le32(r->val + 168);
  *rowbytes = *w * 4;
  for (uint32_t p = 184; p + 8 <= 184 + tlv_len && p + 8 <= r->vlen;) {
    uint32_t t = le32(r->val + p), l = le32(r->val + p + 4);
    if (t == 0x3ef && l >= 4) *rowbytes = le32(r->val + p + 8);
    p += 8 + l;
  }
  const uint8_t *q = r->val + 184 + tlv_len, *end = r->val + r->vlen;
  if (q + 16 > end || memcmp(q, "MLEC", 4)) return nil;
  uint32_t flags = le32(q + 4), comp = le32(q + 8), n = le32(q + 12);
  q += 16;
  NSMutableData *out = [NSMutableData dataWithLength:(NSUInteger)*rowbytes * *h];
  uint8_t *dst = [out mutableBytes];
  size_t total = [out length], done = 0;
  void *scratch = malloc(lzfse_decode_scratch_size());
  BOOL ok = YES;
  uint32_t chunks = (flags & 1) ? n : 1;
  for (uint32_t c = 0; c < chunks && ok; c++) {
    uint32_t len = n, rows = *h;
    if (flags & 1) {   /* 'KCBC' row chunks */
      if (q + 20 > end || memcmp(q, "KCBC", 4)) { ok = NO; break; }
      rows = le32(q + 12); len = le32(q + 16);
      q += 20;
    }
    if (q + len > end) { ok = NO; break; }
    size_t want = MIN((size_t)rows * *rowbytes, total - done);
    if (comp == 0) memcpy(dst + done, q, MIN((size_t)len, want));
    else if (comp == 4) { if (lzfse_decode_buffer(dst + done, want, q, len, scratch) != want) ok = NO; }
    else { NSLog(@"xef: asset catalog compression %u is not supported", comp); ok = NO; }
    done += want;
    q += len;
  }
  free(scratch);
  return ok ? out : nil;
}

- (id<MTLTexture>)newTextureNamed:(NSString *)name device:(id<MTLDevice>)device options:(NSDictionary *)options error:(NSError **)error {
  /* facet: name -> identifier */
  NSData *facets = [self _tree:@"FACETKEYS"];
  const XCPair *fp = [facets bytes];
  BOOL have = NO;
  uint16_t ident = 0;
  for (NSUInteger i = 0; i < [facets length] / sizeof(XCPair) && !have; i++) {
    if (fp[i].klen != [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] || memcmp(fp[i].key, [name UTF8String], fp[i].klen)) continue;
    const uint8_t *v = fp[i].val;
    uint16_t cnt = fp[i].vlen >= 6 ? le16(v + 4) : 0;
    for (uint16_t k = 0; k < cnt && 6 + 4 * k + 4 <= fp[i].vlen; k++)
      if (le16(v + 6 + 4 * k) == ATTR_IDENTIFIER) { ident = le16(v + 8 + 4 * k); have = YES; }
  }
  if (!have) return nil;
  NSData *rends = [self _tree:@"RENDITIONS"];
  const XCPair *rp = [rends bytes];
  NSUInteger nr = [rends length] / sizeof(XCPair);
  MTLPixelFormat fmt = MTLPixelFormatRGBA8Unorm_sRGB;
  NSMutableDictionary *mips = [NSMutableDictionary dictionary];   /* level -> index */
  for (NSUInteger i = 0; i < nr; i++) {
    BOOL f = NO;
    if (rendition_attr(self, &rp[i], ATTR_IDENTIFIER, &f) != ident || !f) continue;
    if (rp[i].vlen < 184) continue;
    uint16_t layout = le16(rp[i].val + 36);
    if (layout == LAYOUT_TEXTURE) {
      const uint8_t *t = rp[i].val + 184 + le32(rp[i].val + 168);
      if (t + 12 <= rp[i].val + rp[i].vlen && !memcmp(t, "RTXT", 4)) fmt = le32(t + 8);
    } else if (layout == LAYOUT_TEXTURE_IMAGE && rendition_attr(self, &rp[i], ATTR_PART, NULL) == PART_TEXTURE_IMAGE) {
      [mips setObject:@(i) forKey:@(rendition_attr(self, &rp[i], ATTR_DIMENSION2, NULL))];
    }
  }
  if (![mips count]) return nil;
  NSUInteger levels = 0;
  while ([mips objectForKey:@(levels)]) levels++;
  if (!levels) return nil;
  BOOL srgb = fmt == MTLPixelFormatRGBA8Unorm_sRGB || fmt == MTLPixelFormatBGRA8Unorm_sRGB;
  if ([options objectForKey:@"MTKTextureLoaderOptionSRGB"]) srgb = [[options objectForKey:@"MTKTextureLoaderOptionSRGB"] boolValue];
  MTLPixelFormat outFmt = srgb ? MTLPixelFormatRGBA8Unorm_sRGB : MTLPixelFormatRGBA8Unorm;
  id<MTLTexture> tex = nil;
  for (NSUInteger l = 0; l < levels; l++) {
    uint32_t w = 0, h = 0, rb = 0;
    NSMutableData *px = rendition_pixels(&rp[[[mips objectForKey:@(l)] unsignedIntegerValue]], &w, &h, &rb);
    if (!px) { if (error) *error = [NSError errorWithDomain:@"MTKTextureLoaderErrorDomain" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Unreadable asset catalog texture"}]; [tex release]; return nil; }
    uint8_t *b = [px mutableBytes];   /* texture renditions are stored in the texture's own channel order */
    if (!tex) {
      MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:outFmt width:w height:h mipmapped:levels > 1];
      td.mipmapLevelCount = levels;
      NSNumber *u = [options objectForKey:@"MTKTextureLoaderOptionTextureUsage"], *s = [options objectForKey:@"MTKTextureLoaderOptionTextureStorageMode"];
      td.usage = u ? [u unsignedIntegerValue] : MTLTextureUsageShaderRead;
      if (s) td.storageMode = [s unsignedIntegerValue];
      tex = [device newTextureWithDescriptor:td];
      if (!tex) return nil;
    }
    [tex replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:l withBytes:b bytesPerRow:rb];
  }
  return tex;
}
- (void)dealloc { [_data release]; [_vars release]; [super dealloc]; }
@end
