/* AppKit-lite TextKit 2: NSTextRange, NSTextContentStorage (paragraph elements), NSTextLayoutManager (paragraph fragments with
   greedy word-wrapped line fragments), selection and navigation. Behaviours were matched against macOS (tests/darwin/mac/appkit_textkit2.m). */
#import "AppKitTextKit2.h"
#include <objc/runtime.h>
#include <objc/message.h>
#include <math.h>

/* ---- locations ---- */
@interface NSCountableTextLocation : NSObject <NSTextLocation, NSCopying> { @public NSInteger _i; }
+ (id)at:(NSInteger)i;
@end
@implementation NSCountableTextLocation
+ (id)at:(NSInteger)i { NSCountableTextLocation *l = [[self alloc] init]; l->_i = i; return [l autorelease]; }
- (id)location { return self; }
- (NSInteger)compare:(id)o { NSInteger b = [o isKindOfClass:[NSCountableTextLocation class]] ? ((NSCountableTextLocation *)o)->_i : 0; return _i < b ? -1 : (_i > b ? 1 : 0); }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSCountableTextLocation class]] && ((NSCountableTextLocation *)o)->_i == _i; }
- (NSUInteger)hash { return (NSUInteger)_i; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)description { return [NSString stringWithFormat:@"%ld", (long)_i]; }
@end
static NSInteger LI(id l) { return [l isKindOfClass:[NSCountableTextLocation class]] ? ((NSCountableTextLocation *)l)->_i : 0; }
static NSTextRange *MR(NSInteger a, NSInteger b) { return [[[NSTextRange alloc] initWithLocation:[NSCountableTextLocation at:a] endLocation:[NSCountableTextLocation at:b]] autorelease]; }
static NSRange RR(NSTextRange *r) { NSInteger a = LI([r location]), b = LI([r endLocation]); return NSMakeRange(a, b - a); }

@implementation NSTextRange
- (id)initWithLocation:(id)l endLocation:(id)e { if ([l compare:e] > 0) { [self release]; return nil; } self = [super init]; _loc = [l retain]; _end = [e retain]; return self; }
- (id)initWithLocation:(id)l { self = [super init]; _loc = [l retain]; _end = [l retain]; return self; }
- (void)dealloc { [_loc release]; [_end release]; [super dealloc]; }
- (BOOL)isEmpty { return [_loc compare:_end] == 0; }
- (id)location { return _loc; } - (id)endLocation { return _end; }
- (BOOL)isEqualToTextRange:(NSTextRange *)r { return [_loc compare:[r location]] == 0 && [_end compare:[r endLocation]] == 0; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSTextRange class]] && [self isEqualToTextRange:o]; }
- (NSUInteger)hash { return (NSUInteger)(LI(_loc) * 31 + LI(_end)); }
- (BOOL)containsLocation:(id)l { return [_loc compare:l] <= 0 && [l compare:_end] < 0; }
- (BOOL)containsRange:(NSTextRange *)r { return [_loc compare:[r location]] <= 0 && [[r endLocation] compare:_end] <= 0; }
- (BOOL)intersectsWithTextRange:(NSTextRange *)r { return [_loc compare:[r endLocation]] < 0 && [[r location] compare:_end] < 0; }
- (NSTextRange *)textRangeByIntersectingWithTextRange:(NSTextRange *)r {
  if (![self intersectsWithTextRange:r]) return nil;
  id a = [_loc compare:[r location]] >= 0 ? _loc : [r location], b = [_end compare:[r endLocation]] <= 0 ? _end : [r endLocation];
  return [[[NSTextRange alloc] initWithLocation:a endLocation:b] autorelease]; }
- (NSTextRange *)textRangeByFormingUnionWithTextRange:(NSTextRange *)r {
  id a = [_loc compare:[r location]] <= 0 ? _loc : [r location], b = [_end compare:[r endLocation]] >= 0 ? _end : [r endLocation];
  return [[[NSTextRange alloc] initWithLocation:a endLocation:b] autorelease]; }
- (NSString *)description { return [NSString stringWithFormat:@"%@...%@", _loc, _end]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end

/* ---- elements ---- */
@implementation NSTextElement
- (id)initWithTextContentManager:(NSTextContentManager *)m { self = [super init]; _cm = m; return self; }
- (NSTextContentManager *)textContentManager { return _cm; } - (void)setTextContentManager:(NSTextContentManager *)m { _cm = m; }
- (NSTextRange *)elementRange { return _range; } - (void)setElementRange:(NSTextRange *)r { [r retain]; [_range release]; _range = r; }
- (NSArray *)childElements { return nil; } - (NSTextElement *)parentElement { return nil; } - (BOOL)isRepresentedElement { return YES; }
- (void)dealloc { [_range release]; [super dealloc]; }
@end

@implementation NSTextParagraph
- (id)initWithAttributedString:(NSAttributedString *)a { self = [super init]; _as = [a copy]; return self; }
- (NSAttributedString *)attributedString { return _as; }
- (NSTextRange *)paragraphContentRange {
  if (!_range) return nil; NSString *s = [_as string]; NSUInteger n = [s length], e = n;
  while (e > 0 && [s characterAtIndex:e - 1] == '\n') e--; if (n && e == n) e = n; else if (n && e < n) e = n - (n - e > 0 ? 1 : 0);
  NSInteger st = LI([_range location]); return MR(st, st + (NSInteger)e); }
- (NSTextRange *)paragraphSeparatorRange {
  if (!_range) return nil; NSString *s = [_as string]; NSUInteger n = [s length]; NSInteger st = LI([_range location]);
  NSUInteger e = n; if (n && [s characterAtIndex:n - 1] == '\n') e = n - 1;
  return MR(st + (NSInteger)e, st + (NSInteger)n); }
- (void)dealloc { [_as release]; [super dealloc]; }
@end

/* ---- content managers ---- */
@implementation NSTextContentManager
- (id)init { self = [super init]; _lms = [[NSMutableArray alloc] init]; _autoLM = YES; return self; }
- (void)dealloc { for (NSTextLayoutManager *m in _lms) m->_cm = nil; [_lms release]; [super dealloc]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSArray *)textLayoutManagers { return [NSArray arrayWithArray:_lms]; }
- (void)addTextLayoutManager:(NSTextLayoutManager *)m { if ([_lms containsObject:m]) return; [_lms addObject:m]; m->_cm = self; [m invalidateLayoutForRange:nil]; }
- (void)removeTextLayoutManager:(NSTextLayoutManager *)m { if (m->_cm == self) m->_cm = nil; if (_primary == m) _primary = nil; [_lms removeObject:m]; }
- (NSTextLayoutManager *)primaryTextLayoutManager { return _primary; }
- (void)setPrimaryTextLayoutManager:(NSTextLayoutManager *)m { _primary = m; }
- (void)synchronizeTextLayoutManagers:(void (^)(NSError *))h { [self _xefContentChanged]; if (h) h(nil); }
- (void)synchronizeToBackingStore:(void (^)(NSError *))h { if (h) h(nil); }
- (NSArray *)textElementsForRange:(NSTextRange *)r {
  NSMutableArray *out = [NSMutableArray array];
  [self enumerateTextElementsFromLocation:[r location] options:0 usingBlock:^BOOL(NSTextElement *e) {
    if ([r containsRange:[e elementRange]]) { [out addObject:e]; return YES; }
    return [[e elementRange] location] ? [[[e elementRange] location] compare:[r endLocation]] < 0 : NO; }];
  return out; }
- (BOOL)hasEditingTransaction { return _editing; }
- (void)performEditingTransactionUsingBlock:(void (^)(void))b { BOOL old = _editing; _editing = YES; if (b) b(); _editing = old; if (!old) [self _xefContentChanged]; }
- (void)recordEditActionInRange:(NSTextRange *)r newTextRange:(NSTextRange *)n {}
- (BOOL)automaticallySynchronizesTextLayoutManagers { return _autoLM; } - (void)setAutomaticallySynchronizesTextLayoutManagers:(BOOL)f { _autoLM = f; }
- (BOOL)automaticallySynchronizesToBackingStore { return _autoStore; } - (void)setAutomaticallySynchronizesToBackingStore:(BOOL)f { _autoStore = f; }
- (NSTextRange *)documentRange { return nil; }
- (id)locationFromLocation:(id)l withOffset:(NSInteger)o { return nil; } - (NSInteger)offsetFromLocation:(id)a toLocation:(id)b { return 0; }
- (id)enumerateTextElementsFromLocation:(id)l options:(NSUInteger)o usingBlock:(BOOL (^)(NSTextElement *))b { return nil; }
- (void)replaceContentsInRange:(NSTextRange *)r withTextElements:(NSArray *)e {}
- (void)_xefContentChanged { for (NSTextLayoutManager *m in _lms) [m invalidateLayoutForRange:nil]; }
@end

@implementation NSTextContentStorage
- (id)init { self = [super init]; _storage = [[NSTextStorage alloc] init]; return self; }
- (void)dealloc { [_attr release]; [_storage release]; [super dealloc]; }
- (NSAttributedString *)attributedString { return _storage ? (NSAttributedString *)_storage : _attr; }
- (void)setAttributedString:(NSAttributedString *)a { [_storage release]; _storage = nil; [a retain]; [_attr release]; _attr = a ? [a copy] : nil; [a release]; [self _xefContentChanged]; }
- (NSTextStorage *)textStorage { return _storage; }
- (void)setTextStorage:(NSTextStorage *)s { [s retain]; [_storage release]; _storage = s; [_attr release]; _attr = nil; [self _xefContentChanged]; }
- (BOOL)includesTextListMarkers { return _listMarkers; } - (void)setIncludesTextListMarkers:(BOOL)f { _listMarkers = f; }
- (NSString *)_str { NSAttributedString *a = [self attributedString]; return a ? [a string] : @""; }
- (NSTextRange *)documentRange { return MR(0, (NSInteger)[[self _str] length]); }
- (id)locationFromLocation:(id)l withOffset:(NSInteger)o { NSInteger n = LI(l) + o; if (n < 0 || n > (NSInteger)[[self _str] length]) return nil; return [NSCountableTextLocation at:n]; }
- (NSInteger)offsetFromLocation:(id)a toLocation:(id)b {
  if (!a || !b) [NSException raise:NSInvalidArgumentException format:@"nil location"];
  return LI(b) - LI(a); }
- (id)enumerateTextElementsFromLocation:(id)l options:(NSUInteger)o usingBlock:(BOOL (^)(NSTextElement *))b {
  NSString *s = [self _str]; NSAttributedString *as = [self attributedString]; NSUInteger n = [s length], pos = 0;
  if (o & 1) return nil;                      /* reverse from a nil location enumerates nothing, as on macOS */
  NSInteger from = l ? LI(l) : 0; id last = nil;
  while (pos < n) {
    NSRange pr = [s paragraphRangeForRange:NSMakeRange(pos, 0)]; if (!pr.length) break;
    if ((NSInteger)NSMaxRange(pr) > from || (!l)) {
      NSTextParagraph *p = [[[NSTextParagraph alloc] initWithAttributedString:[as attributedSubstringFromRange:pr]] autorelease];
      p->_cm = self; [p setElementRange:MR((NSInteger)pr.location, (NSInteger)NSMaxRange(pr))]; last = p;
      if (!b(p)) return [NSCountableTextLocation at:(NSInteger)NSMaxRange(pr)];
    }
    pos = NSMaxRange(pr); }
  return nil; }
- (NSAttributedString *)attributedStringForTextElement:(NSTextElement *)e { return [e isKindOfClass:[NSTextParagraph class]] ? [(NSTextParagraph *)e attributedString] : nil; }
- (NSTextElement *)textElementForAttributedString:(NSAttributedString *)a { NSTextParagraph *p = [[[NSTextParagraph alloc] initWithAttributedString:a] autorelease]; p->_cm = self; return p; }
- (NSTextRange *)adjustedRangeFromRange:(NSTextRange *)r forEditingTextSelection:(BOOL)f { return nil; }
- (void)processEditingForTextStorage:(NSTextStorage *)s edited:(NSUInteger)m range:(NSRange)r changeInLength:(NSInteger)d invalidatedRange:(NSRange)i { [self _xefContentChanged]; }
- (void)performEditingTransactionForTextStorage:(NSTextStorage *)s usingBlock:(void (^)(void))b { [self performEditingTransactionUsingBlock:b]; }
- (void)replaceContentsInRange:(NSTextRange *)r withTextElements:(NSArray *)e {}
@end

/* ---- line fragments ---- */
@implementation NSTextLineFragment
- (id)initWithAttributedString:(NSAttributedString *)a range:(NSRange)r { self = [super init]; _as = [a copy]; _range = r; return self; }
- (id)initWithString:(NSString *)s attributes:(NSDictionary *)at range:(NSRange)r { return [self initWithAttributedString:[[[NSAttributedString alloc] initWithString:s attributes:at] autorelease] range:r]; }
- (void)dealloc { [_as release]; [super dealloc]; }
- (NSAttributedString *)attributedString { return _as; } - (NSRange)characterRange { return _range; }
- (NSRect)typographicBounds { return _bounds; } - (NSPoint)glyphOrigin { return _origin; }
- (NSDictionary *)_attrs { NSUInteger n = [_as length]; return n && _range.location < n ? [_as attributesAtIndex:_range.location effectiveRange:NULL] : [NSDictionary dictionary]; }
- (CGFloat)_xFor:(NSUInteger)i { if (!_laid || i <= _range.location) return 0; NSUInteger e = MIN(i, NSMaxRange(_range)); return [[[_as string] substringWithRange:NSMakeRange(_range.location, e - _range.location)] sizeWithAttributes:[self _attrs]].width; }
- (void)drawAtPoint:(NSPoint)p inContext:(CGContextRef)c { [[[_as attributedSubstringFromRange:_range] retain] autorelease]; [[_as attributedSubstringFromRange:_range] drawAtPoint:NSMakePoint(p.x, p.y)]; }
- (NSPoint)locationForCharacterAtIndex:(NSInteger)i { return NSMakePoint([self _xFor:(NSUInteger)i], _origin.y); }
- (NSInteger)characterIndexForPoint:(NSPoint)p {
  if (!_laid) return 0;
  for (NSUInteger i = _range.location; i < NSMaxRange(_range); i++) { CGFloat a = [self _xFor:i], b = [self _xFor:i + 1]; if (p.x < (a + b) / 2) return (NSInteger)i; }
  return (NSInteger)NSMaxRange(_range) - ([[[_as string] substringWithRange:_range] hasSuffix:@"\n"] ? 1 : 0); }
- (CGFloat)fractionOfDistanceThroughGlyphForPoint:(NSPoint)p {
  if (!_laid) return 0; NSInteger i = [self characterIndexForPoint:p]; CGFloat a = [self _xFor:(NSUInteger)i], b = [self _xFor:(NSUInteger)i + 1];
  return b > a ? MAX(0, MIN(1, (p.x - a) / (b - a))) : 0; }
@end

/* ---- layout fragments ---- */
@implementation NSTextLayoutFragment
- (id)initWithTextElement:(NSTextElement *)e range:(NSTextRange *)r { self = [super init]; _el = [e retain]; _range = [(r ? r : [e elementRange]) retain]; _lines = [[NSArray alloc] init]; return self; }
- (void)dealloc { [_el release]; [_range release]; [_lines release]; [super dealloc]; }
- (NSTextLayoutManager *)textLayoutManager { return _lm; } - (NSTextElement *)textElement { return _el; } - (NSTextRange *)rangeInElement { return _range; }
- (NSArray *)textLineFragments { return _lines; }
- (NSTextLineFragment *)textLineFragmentForVerticalOffset:(CGFloat)o requiresExactMatch:(BOOL)e {
  for (NSTextLineFragment *l in _lines) if (o >= l->_bounds.origin.y && o < NSMaxY(l->_bounds)) return l;
  return e ? nil : [_lines lastObject]; }
- (NSTextLineFragment *)textLineFragmentForTextLocation:(id)l isUpstreamAffinity:(BOOL)u {
  NSInteger st = LI([_range location]), i = LI(l) - st;
  for (NSTextLineFragment *ln in _lines) if ((NSInteger)ln->_range.location <= i && i < (NSInteger)NSMaxRange(ln->_range)) return ln;
  return [_lines lastObject]; }
- (id)layoutQueue { return _queue; } - (void)setLayoutQueue:(id)q { _queue = q; }
- (NSInteger)state { return _state; } - (void)invalidateLayout { _state = 0; }
- (NSRect)layoutFragmentFrame { return _frame; }
- (NSRect)renderingSurfaceBounds { return NSMakeRect(0, 0, _frame.size.width, _frame.size.height); }
- (CGFloat)leadingPadding { return 0; } - (CGFloat)trailingPadding { return 0; } - (CGFloat)topMargin { return 0; } - (CGFloat)bottomMargin { return 0; }
- (void)drawAtPoint:(NSPoint)p inContext:(CGContextRef)c { for (NSTextLineFragment *l in _lines) [l drawAtPoint:NSMakePoint(p.x + l->_bounds.origin.x, p.y + l->_bounds.origin.y) inContext:c]; }
- (NSArray *)textAttachmentViewProviders { return [NSArray array]; }
- (NSRect)frameForTextAttachmentAtLocation:(id)l { return NSZeroRect; }
@end

/* ---- selection ---- */
@implementation NSTextSelection
- (id)initWithRanges:(NSArray *)r affinity:(NSInteger)a granularity:(NSInteger)g { self = [super init]; _ranges = [r copy]; _aff = a; _gran = g; _anchor = 0; return self; }
- (id)initWithRange:(NSTextRange *)r affinity:(NSInteger)a granularity:(NSInteger)g { return [self initWithRanges:[NSArray arrayWithObject:r] affinity:a granularity:g]; }
- (id)initWithLocation:(id)l affinity:(NSInteger)a { return [self initWithRange:[[[NSTextRange alloc] initWithLocation:l] autorelease] affinity:a granularity:0]; }
- (void)dealloc { [_ranges release]; [_secondary release]; [_typing release]; [super dealloc]; }
- (NSArray *)textRanges { return _ranges; } - (NSInteger)granularity { return _gran; } - (NSInteger)affinity { return _aff; }
- (BOOL)isTransient { return NO; }
- (CGFloat)anchorPositionOffset { return _anchor; } - (void)setAnchorPositionOffset:(CGFloat)o { _anchor = o; }
- (BOOL)isLogical { return _logical; } - (void)setLogical:(BOOL)f { _logical = f; }
- (id)secondarySelectionLocation { return _secondary; } - (void)setSecondarySelectionLocation:(id)l { [l retain]; [_secondary release]; _secondary = l; }
- (NSDictionary *)typingAttributes { return _typing; } - (void)setTypingAttributes:(NSDictionary *)d { [d retain]; [_typing release]; _typing = d; }
- (NSTextSelection *)textSelectionWithTextRanges:(NSArray *)r { NSTextSelection *s = [[[NSTextSelection alloc] initWithRanges:r affinity:_aff granularity:_gran] autorelease]; s->_logical = _logical; s->_anchor = _anchor; return s; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end


/* Word ranges: runs of letters/digits (with inner apostrophes); the host NSString does not implement NSStringEnumerationByWords. */
static void XEFWords(NSString *s, NSRange in, void (^b)(NSString *, NSRange, NSRange, BOOL *)) {
  NSCharacterSet *al = [NSCharacterSet alphanumericCharacterSet]; NSUInteger i = in.location, end = NSMaxRange(in); BOOL stop = NO;
  while (i < end && !stop) {
    while (i < end && ![al characterIsMember:[s characterAtIndex:i]]) i++;
    NSUInteger st = i; while (i < end && ([al characterIsMember:[s characterAtIndex:i]] || ([s characterAtIndex:i] == '\'' && i + 1 < end && i > st && [al characterIsMember:[s characterAtIndex:i + 1]]))) i++;
    if (i > st) { NSRange r = NSMakeRange(st, i - st); b([s substringWithRange:r], r, r, &stop); } }
}

/* ---- layout manager ---- */
@implementation NSTextLayoutManager
- (id)init { self = [super init]; _fontLeading = YES; _resolves = YES; _sels = [[NSArray alloc] init]; _ra = [[NSMutableArray alloc] init]; return self; }
- (id)initWithCoder:(NSCoder *)c { return [self init]; }
- (void)dealloc { if (_cm) [_cm->_lms removeObject:self]; [_sels release]; [_nav release]; [_vlc release]; [_frags release]; [_sig release]; [_ra release]; [_tc release]; [super dealloc]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)usesFontLeading { return _fontLeading; } - (void)setUsesFontLeading:(BOOL)f { _fontLeading = f; }
- (BOOL)limitsLayoutForSuspiciousContents { return _limits; } - (void)setLimitsLayoutForSuspiciousContents:(BOOL)f { _limits = f; }
- (BOOL)usesHyphenation { return _hyph; } - (void)setUsesHyphenation:(BOOL)f { _hyph = f; }
- (BOOL)resolvesNaturalAlignmentWithBaseWritingDirection { return _resolves; } - (void)setResolvesNaturalAlignmentWithBaseWritingDirection:(BOOL)f { _resolves = f; }
- (NSTextContentManager *)textContentManager { return _cm; }
- (void)replaceTextContentManager:(NSTextContentManager *)m { if (_cm) [_cm removeTextLayoutManager:self]; [m addTextLayoutManager:self]; }
- (NSTextContainer *)textContainer { return _tc; }
- (void)setTextContainer:(NSTextContainer *)c { if (_tc) [_tc setTextLayoutManager:nil]; [c retain]; [_tc release]; _tc = c; [c setTextLayoutManager:self]; [self invalidateLayoutForRange:nil]; }
- (NSTextViewportLayoutController *)textViewportLayoutController { if (!_cm || !_tc) return nil; if (!_vlc) _vlc = [[NSTextViewportLayoutController alloc] initWithTextLayoutManager:self]; return _vlc; }
- (id)layoutQueue { return _queue; } - (void)setLayoutQueue:(id)q { _queue = q; }
- (NSArray *)textSelections { return _sels; } - (void)setTextSelections:(NSArray *)s { [s retain]; [_sels release]; _sels = s ? s : [[NSArray alloc] init]; }
- (NSTextSelectionNavigation *)textSelectionNavigation { if (!_nav) { _nav = [[NSTextSelectionNavigation alloc] initWithDataSource:self]; _nav->_noncontig = YES; } return _nav; }
- (void)setTextSelectionNavigation:(NSTextSelectionNavigation *)n { [n retain]; [_nav release]; _nav = n; }
- (NSTextRange *)documentRange { return _cm ? [_cm documentRange] : nil; }
- (id)locationFromLocation:(id)l withOffset:(NSInteger)o { return [_cm locationFromLocation:l withOffset:o]; }
- (NSInteger)offsetFromLocation:(id)a toLocation:(id)b { return [_cm offsetFromLocation:a toLocation:b]; }
- (NSInteger)baseWritingDirectionAtLocation:(id)l { return 0; }

/* layout */
- (CGFloat)_avail { CGFloat w = _tc ? [_tc containerSize].width : 1e7, p = _tc ? [_tc lineFragmentPadding] : 5; return MAX(1, w - 2 * p); }
- (void)invalidateLayoutForRange:(NSTextRange *)r { [_frags release]; _frags = nil; [_sig release]; _sig = nil; }
static CGFloat LineHeight(NSFont *f) { CGFloat h = [f ascender] - [f descender] + [f leading]; return h > 0 ? ceil(h) : 14; }
- (void)_layout {
  if (!_cm || !_tc) { [_frags release]; _frags = [[NSMutableArray alloc] init]; return; }
  NSAttributedString *as = [(NSTextContentStorage *)_cm isKindOfClass:[NSTextContentStorage class]] ? [(NSTextContentStorage *)_cm attributedString] : nil;
  NSString *sig = [NSString stringWithFormat:@"%lu/%lu/%g", (unsigned long)[as length], (unsigned long)[[as string] hash], [_tc containerSize].width];
  if (_frags && [sig isEqualToString:_sig]) return;
  [_frags release]; _frags = [[NSMutableArray alloc] init]; [_sig release]; _sig = [sig retain];
  CGFloat y = 0, avail = [self _avail], pad = [_tc lineFragmentPadding];
  __block CGFloat yy = 0; __block NSMutableArray *frags = _frags;
  [_cm enumerateTextElementsFromLocation:nil options:0 usingBlock:^BOOL(NSTextElement *e) {
    NSTextParagraph *p = (NSTextParagraph *)e; NSAttributedString *pa = [p attributedString]; NSString *s = [pa string];
    NSDictionary *at = [s length] ? [pa attributesAtIndex:0 effectiveRange:NULL] : [NSDictionary dictionary];
    NSFont *font = [at objectForKey:NSFontAttributeName]; if (!font) font = [NSFont systemFontOfSize:12];
    CGFloat lh = LineHeight(font), asc = ceil([font ascender]);
    NSMutableArray *lines = [NSMutableArray array]; NSUInteger i = 0, n = [s length]; CGFloat maxw = 0, ly = 0;
    do {
      NSUInteger j = i, lastBreak = i; CGFloat w = 0;
      while (j < n) {
        unichar ch = [s characterAtIndex:j]; if (ch == '\n') { j++; break; }
        CGFloat cw = [[s substringWithRange:NSMakeRange(i, j + 1 - i)] sizeWithAttributes:at].width;
        if (cw > avail && j > i) { j = lastBreak > i ? lastBreak : j; break; }
        if (ch == ' ') lastBreak = j + 1; j++; w = cw; }
      if (j == i && i < n) j = i + 1;
      NSRange lr = NSMakeRange(i, j - i);
      NSString *vis = [s substringWithRange:lr]; while ([vis hasSuffix:@"\n"]) vis = [vis substringToIndex:[vis length] - 1];
      w = [vis sizeWithAttributes:at].width; maxw = MAX(maxw, w);
      NSTextLineFragment *lf = [[[NSTextLineFragment alloc] initWithAttributedString:pa range:lr] autorelease];
      lf->_laid = YES; lf->_bounds = NSMakeRect(0, ly, w, lh); lf->_origin = NSMakePoint(0, asc); [lines addObject:lf]; ly += lh; i = j;
    } while (i < n);
    NSTextLayoutFragment *f = [[[NSTextLayoutFragment alloc] initWithTextElement:e range:[e elementRange]] autorelease];
    f->_lm = self; f->_state = 3; [f->_lines release]; f->_lines = [lines copy]; f->_frame = NSMakeRect(pad, yy, maxw, ly);
    [frags addObject:f]; yy += ly; return YES; }];
  (void)y;
}
- (NSTextRange *)ensureLayoutForRange:(NSTextRange *)r { [self _layout]; return r; }
- (void)ensureLayoutForBounds:(NSRect)b { [self _layout]; }
- (id)enumerateTextLayoutFragmentsFromLocation:(id)l options:(NSUInteger)o usingBlock:(BOOL (^)(NSTextLayoutFragment *))b {
  [self _layout]; NSArray *fr = (o & 1) ? [[_frags reverseObjectEnumerator] allObjects] : _frags;
  id last = nil;
  for (NSTextLayoutFragment *f in fr) {
    if (l && [[[f rangeInElement] endLocation] compare:l] <= 0 && !(o & 1)) continue;
    last = [[f rangeInElement] endLocation]; if (!b(f)) return last; }
  return nil; }
- (NSTextLayoutFragment *)textLayoutFragmentForPosition:(NSPoint)p {
  [self _layout]; for (NSTextLayoutFragment *f in _frags) if (p.y >= f->_frame.origin.y && p.y < NSMaxY(f->_frame)) return f; return nil; }
- (NSTextLayoutFragment *)textLayoutFragmentForLocation:(id)l {
  [self _layout]; NSTextLayoutFragment *last = nil;
  for (NSTextLayoutFragment *f in _frags) { last = f; if ([[f rangeInElement] containsLocation:l]) return f; }
  return last && l && [l compare:[[last rangeInElement] endLocation]] == 0 ? last : nil; }
- (NSRect)usageBoundsForTextContainer {
  [self _layout]; NSRect u = NSZeroRect; BOOL first = YES; for (NSTextLayoutFragment *f in _frags) { u = first ? f->_frame : NSUnionRect(u, f->_frame); first = NO; } return u; }

/* rendering attributes */
- (void)setRenderingAttributes:(NSDictionary *)a forTextRange:(NSTextRange *)r {
  NSMutableArray *keep = [NSMutableArray array]; for (NSDictionary *e in _ra) if (![[e objectForKey:@"r"] intersectsWithTextRange:r]) [keep addObject:e];
  [_ra release]; _ra = [keep retain]; if (a.count) [_ra addObject:[NSDictionary dictionaryWithObjectsAndKeys:r, @"r", [[a copy] autorelease], @"a", nil]]; }
- (void)addRenderingAttribute:(NSString *)n value:(id)v forTextRange:(NSTextRange *)r { if (!v) return; [_ra addObject:[NSDictionary dictionaryWithObjectsAndKeys:r, @"r", [NSDictionary dictionaryWithObject:v forKey:n], @"a", nil]]; }
- (void)removeRenderingAttribute:(NSString *)n forTextRange:(NSTextRange *)r {
  NSMutableArray *keep = [NSMutableArray array];
  for (NSDictionary *e in _ra) { if (![[e objectForKey:@"r"] intersectsWithTextRange:r] || ![[e objectForKey:@"a"] objectForKey:n]) { [keep addObject:e]; continue; }
    NSMutableDictionary *d = [[[e objectForKey:@"a"] mutableCopy] autorelease]; [d removeObjectForKey:n]; if (d.count) [keep addObject:[NSDictionary dictionaryWithObjectsAndKeys:[e objectForKey:@"r"], @"r", d, @"a", nil]]; }
  [_ra release]; _ra = [keep retain]; }
- (void)invalidateRenderingAttributesForTextRange:(NSTextRange *)r {}
- (id)renderingAttributesValidator { return _validator; } - (void)setRenderingAttributesValidator:(id)v { [v retain]; [_validator release]; _validator = v; }
+ (NSDictionary *)linkRenderingAttributes { return [NSDictionary dictionaryWithObjectsAndKeys:[NSColor linkColor], NSForegroundColorAttributeName, [NSNumber numberWithInt:1], NSUnderlineStyleAttributeName, nil]; }
- (NSDictionary *)renderingAttributesForLink:(id)l atLocation:(id)loc { return [[self class] linkRenderingAttributes]; }
- (void)enumerateRenderingAttributesFromLocation:(id)l reverse:(BOOL)rev usingBlock:(BOOL (^)(NSTextLayoutManager *, NSDictionary *, NSTextRange *))b {
  NSArray *es = [_ra sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) { NSInteger a = LI([[x objectForKey:@"r"] location]), c = LI([[y objectForKey:@"r"] location]); return a < c ? NSOrderedAscending : (a > c ? NSOrderedDescending : NSOrderedSame); }];
  if (rev) es = [[es reverseObjectEnumerator] allObjects];
  for (NSDictionary *e in es) { NSTextRange *r = [e objectForKey:@"r"]; if (l && !rev && [[r endLocation] compare:l] <= 0) continue; if (l && rev && [[r location] compare:l] > 0) continue; if (!b(self, [e objectForKey:@"a"], r)) break; } }

/* segments, substrings, granularity */
- (id)enumerateTextSegmentsInRange:(NSTextRange *)r type:(NSInteger)t options:(NSUInteger)o usingBlock:(BOOL (^)(NSTextRange *, NSRect, CGFloat, NSTextContainer *))b {
  [self _layout];
  for (NSTextLayoutFragment *f in _frags) {
    NSTextRange *fr = [f rangeInElement]; if (![fr intersectsWithTextRange:r] && !([r isEmpty] && [fr containsLocation:[r location]])) continue;
    NSInteger fs = LI([fr location]); NSInteger a = MAX(LI([r location]), fs), e = MIN(LI([r endLocation]), LI([fr endLocation]));
    for (NSTextLineFragment *l in [f textLineFragments]) {
      NSInteger ls = fs + (NSInteger)l->_range.location, le = fs + (NSInteger)NSMaxRange(l->_range);
      NSInteger sa = MAX(a, ls), se = MIN(e, le); if (sa > se || (sa == se && ![r isEmpty])) continue;
      CGFloat x0 = [l _xFor:(NSUInteger)(sa - fs)], x1 = [l _xFor:(NSUInteger)(se - fs)];
      NSRect rect = NSMakeRect(f->_frame.origin.x + l->_bounds.origin.x + x0, f->_frame.origin.y + l->_bounds.origin.y, x1 - x0, l->_bounds.size.height);
      if (!b(MR(sa, se), rect, l->_origin.y, _tc)) return nil; } }
  return nil; }
- (void)replaceContentsInRange:(NSTextRange *)r withTextElements:(NSArray *)e {}
- (void)replaceContentsInRange:(NSTextRange *)r withAttributedString:(NSAttributedString *)a {}
- (id)enumerateSubstringsFromLocation:(id)l options:(NSUInteger)o usingBlock:(void (^)(NSString *, NSTextRange *, NSTextRange *, BOOL *))b {
  NSString *s = [(NSTextContentStorage *)_cm isKindOfClass:[NSTextContentStorage class]] ? [(NSTextContentStorage *)_cm _str] : @""; NSInteger from = l ? LI(l) : 0;
  void (^cb)(NSString *, NSRange, NSRange, BOOL *) = ^(NSString *sub, NSRange sr, NSRange er, BOOL *stop) { b(sub, MR((NSInteger)sr.location, (NSInteger)NSMaxRange(sr)), MR((NSInteger)er.location, (NSInteger)NSMaxRange(er)), stop); };
  NSRange all = NSMakeRange((NSUInteger)from, [s length] - (NSUInteger)from);
  if (o & NSStringEnumerationByWords) XEFWords(s, all, cb); else [s enumerateSubstringsInRange:all options:o usingBlock:cb];
  return nil; }
- (NSTextRange *)textRangeForSelectionGranularity:(NSInteger)g enclosingLocation:(id)l {
  NSString *s = [(NSTextContentStorage *)_cm isKindOfClass:[NSTextContentStorage class]] ? [(NSTextContentStorage *)_cm _str] : @""; NSUInteger n = [s length], i = (NSUInteger)LI(l);
  if (i > n) return nil;
  switch (g) {
    case 0: { if (i >= n) return MR((NSInteger)n, (NSInteger)n); NSRange r = [s rangeOfComposedCharacterSequenceAtIndex:i]; return MR((NSInteger)r.location, (NSInteger)NSMaxRange(r)); }
    case 1: { __block NSRange found = NSMakeRange(i, 0); XEFWords(s, NSMakeRange(0, n), ^(NSString *w, NSRange wr, NSRange er, BOOL *st) { if (i >= wr.location && i <= NSMaxRange(wr)) { found = wr; *st = YES; } }); return MR((NSInteger)found.location, (NSInteger)NSMaxRange(found)); }
    case 2: { __block NSRange found = NSMakeRange(i, 0); [s enumerateSubstringsInRange:NSMakeRange(0, n) options:NSStringEnumerationBySentences usingBlock:^(NSString *w, NSRange wr, NSRange er, BOOL *st) { if (i >= er.location && i < NSMaxRange(er)) { found = er; *st = YES; } }]; return MR((NSInteger)found.location, (NSInteger)NSMaxRange(found)); }
    case 3: case 4: { NSRange r = [s paragraphRangeForRange:NSMakeRange(MIN(i, n ? n - 1 : 0), 0)]; return MR((NSInteger)r.location, (NSInteger)NSMaxRange(r)); }
    default: return [self documentRange]; } }
- (void)enumerateCaretOffsetsInLineFragmentAtLocation:(id)l usingBlock:(void (^)(CGFloat, id, BOOL, BOOL *))b {
  NSTextLayoutFragment *f = [self textLayoutFragmentForLocation:l]; NSTextLineFragment *lf = [f textLineFragmentForTextLocation:l isUpstreamAffinity:NO]; if (!lf) return;
  NSInteger fs = LI([[f rangeInElement] location]); BOOL stop = NO;
  for (NSUInteger i = lf->_range.location; i <= NSMaxRange(lf->_range) && !stop; i++) b([lf _xFor:i], [NSCountableTextLocation at:fs + (NSInteger)i], YES, &stop); }
- (NSTextRange *)lineFragmentRangeForPoint:(NSPoint)p inContainerAtLocation:(id)l {
  NSTextLayoutFragment *f = [self textLayoutFragmentForPosition:p]; if (!f) return nil;
  NSTextLineFragment *lf = [f textLineFragmentForVerticalOffset:p.y - f->_frame.origin.y requiresExactMatch:NO]; NSInteger fs = LI([[f rangeInElement] location]);
  return MR(fs + (NSInteger)lf->_range.location, fs + (NSInteger)NSMaxRange(lf->_range)); }
@end

@implementation NSTextContainer (XEFTextKit2)
- (NSTextLayoutManager *)textLayoutManager { return objc_getAssociatedObject(self, "xef.tlm"); }
- (void)setTextLayoutManager:(NSTextLayoutManager *)m { objc_setAssociatedObject(self, "xef.tlm", m, OBJC_ASSOCIATION_ASSIGN); }
@end

/* ---- navigation ---- */
@implementation NSTextSelectionNavigation
- (id)initWithDataSource:(id)d { self = [super init]; _ds = d; return self; }
- (id)textSelectionDataSource { return _ds; }
- (BOOL)allowsNonContiguousRanges { return _noncontig; } - (void)setAllowsNonContiguousRanges:(BOOL)f { _noncontig = f; }
- (BOOL)rotatesCoordinateSystemForLayoutOrientation { return _rotates; } - (void)setRotatesCoordinateSystemForLayoutOrientation:(BOOL)f { _rotates = f; }
- (void)flushLayoutCache {}
- (NSString *)_str { NSTextContentManager *cm = [(NSTextLayoutManager *)_ds textContentManager]; return [cm isKindOfClass:[NSTextContentStorage class]] ? [(NSTextContentStorage *)cm _str] : @""; }
- (NSTextSelection *)destinationSelectionForTextSelection:(NSTextSelection *)sel direction:(NSInteger)d destination:(NSInteger)dst extending:(BOOL)ext confined:(BOOL)c {
  NSString *s = [self _str]; NSInteger n = (NSInteger)[s length];
  NSTextRange *cur = [[sel textRanges] firstObject]; if (!cur) return nil;
  BOOL fwd = (d == 0 || d == 2);              /* right, down */
  NSInteger a = LI([cur location]), e = LI([cur endLocation]);
  NSInteger anchor = (e > a && ext) ? ([sel affinity] == 0 ? a : e) : a, head = fwd ? e : a;
  if (ext && e > a) { anchor = a; head = e; }
  NSInteger t = head;
  if (!ext && e > a) t = fwd ? e : a;
  else switch (dst) {
    case 0: t = fwd ? MIN(n, head + 1) : MAX(0, head - 1); break;
    case 1: { NSInteger p = head; if (fwd) { __block NSInteger r = n; XEFWords(s, NSMakeRange(0, n), ^(NSString *w, NSRange wr, NSRange er, BOOL *st) { if ((NSInteger)NSMaxRange(wr) > p) { r = (NSInteger)NSMaxRange(wr); *st = YES; } }); t = r; }
              else { __block NSInteger r = 0; XEFWords(s, NSMakeRange(0, n), ^(NSString *w, NSRange wr, NSRange er, BOOL *st) { if ((NSInteger)wr.location < p) r = (NSInteger)wr.location; else *st = YES; }); t = r; } break; }
    case 2: case 3: { NSRange pr = [s paragraphRangeForRange:NSMakeRange(MIN((NSUInteger)head, n ? (NSUInteger)n - 1 : 0), 0)]; NSInteger end = (NSInteger)NSMaxRange(pr); if (end > (NSInteger)pr.location && [s characterAtIndex:(NSUInteger)end - 1] == '\n') end--; t = fwd ? end : (NSInteger)pr.location; break; }
    default: t = fwd ? n : 0; }
  NSTextRange *nr = ext ? MR(MIN(anchor, t), MAX(anchor, t)) : MR(t, t);
  NSTextSelection *r = [[[NSTextSelection alloc] initWithRanges:[NSArray arrayWithObject:nr] affinity:[sel affinity] granularity:[sel granularity]] autorelease]; return r; }
- (NSArray *)textSelectionsInteractingAtPoint:(NSPoint)p inContainerAtLocation:(id)l anchors:(NSArray *)a modifiers:(NSUInteger)m selecting:(BOOL)s bounds:(NSRect)b {
  NSTextLayoutManager *lm = (NSTextLayoutManager *)_ds; NSTextLayoutFragment *f = [lm textLayoutFragmentForPosition:p]; if (!f) return [NSArray array];
  NSTextLineFragment *lf = [f textLineFragmentForVerticalOffset:p.y - f->_frame.origin.y requiresExactMatch:NO];
  NSInteger i = LI([[f rangeInElement] location]) + [lf characterIndexForPoint:NSMakePoint(p.x - f->_frame.origin.x, p.y)];
  return [NSArray arrayWithObject:[[[NSTextSelection alloc] initWithLocation:[NSCountableTextLocation at:i] affinity:0] autorelease]]; }
- (NSTextSelection *)textSelectionForSelectionGranularity:(NSInteger)g enclosingTextSelection:(NSTextSelection *)s {
  NSTextRange *r = [[s textRanges] firstObject]; NSTextRange *e = [(NSTextLayoutManager *)_ds textRangeForSelectionGranularity:g enclosingLocation:[r location]]; if (!e) return nil;
  return [[[NSTextSelection alloc] initWithRange:e affinity:[s affinity] granularity:g] autorelease]; }
- (NSTextSelection *)textSelectionForSelectionGranularity:(NSInteger)g enclosingPoint:(NSPoint)p inContainerAtLocation:(id)l {
  NSArray *a = [self textSelectionsInteractingAtPoint:p inContainerAtLocation:l anchors:nil modifiers:0 selecting:NO bounds:NSZeroRect]; if (![a count]) return nil;
  return [self textSelectionForSelectionGranularity:g enclosingTextSelection:[a objectAtIndex:0]]; }
- (id)resolvedInsertionLocationForTextSelection:(NSTextSelection *)s writingDirection:(NSInteger)d { NSTextRange *r = [[s textRanges] firstObject]; return d == 1 ? [r endLocation] : [r location]; }
- (NSArray *)deletionRangesForTextSelection:(NSTextSelection *)s direction:(NSInteger)d destination:(NSInteger)dst allowsDecomposition:(BOOL)a {
  NSTextRange *r = [[s textRanges] firstObject]; if (![r isEmpty]) return [NSArray arrayWithObject:r];
  NSTextSelection *t = [self destinationSelectionForTextSelection:s direction:d destination:dst extending:YES confined:NO]; NSTextRange *tr = [[t textRanges] firstObject];
  NSInteger l = LI([r location]), x = LI([tr location]), y = LI([tr endLocation]); NSInteger lo = MIN(l, MIN(x, y)), hi = MAX(l, MAX(x, y));
  return hi > lo ? [NSArray arrayWithObject:MR(lo, hi)] : [NSArray array]; }
@end

@implementation NSTextViewportLayoutController
- (id)initWithTextLayoutManager:(NSTextLayoutManager *)m { self = [super init]; _lm = m; return self; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSTextLayoutManager *)textLayoutManager { return _lm; }
- (NSRect)viewportBounds { return _vb; }
- (NSTextRange *)viewportRange { return _vr; }
- (void)layoutViewport {
  [_lm ensureLayoutForRange:[_lm documentRange]];
  if ([_delegate respondsToSelector:@selector(viewportBoundsForTextViewportLayoutController:)]) { NSRect (*f)(id, SEL, id) = (NSRect (*)(id, SEL, id))objc_msgSend; _vb = f(_delegate, @selector(viewportBoundsForTextViewportLayoutController:), self); }
  else _vb = [_lm usageBoundsForTextContainer];
  __block NSInteger lo = -1, hi = -1;
  if ([_delegate respondsToSelector:@selector(textViewportLayoutControllerWillLayout:)]) [_delegate performSelector:@selector(textViewportLayoutControllerWillLayout:) withObject:self];
  [_lm enumerateTextLayoutFragmentsFromLocation:nil options:0 usingBlock:^BOOL(NSTextLayoutFragment *f) {
    if (NSIntersectsRect(f->_frame, _vb) || NSEqualRects(_vb, NSZeroRect)) {
      NSInteger a = LI([[f rangeInElement] location]), e = LI([[f rangeInElement] endLocation]); lo = lo < 0 ? a : MIN(lo, a); hi = MAX(hi, e);
      if ([_delegate respondsToSelector:@selector(textViewportLayoutController:configureRenderingSurfaceForTextLayoutFragment:)]) [_delegate performSelector:@selector(textViewportLayoutController:configureRenderingSurfaceForTextLayoutFragment:) withObject:self withObject:f]; }
    return YES; }];
  [_vr release]; _vr = lo >= 0 ? [MR(lo, hi) retain] : nil;
  if ([_delegate respondsToSelector:@selector(textViewportLayoutControllerDidLayout:)]) [_delegate performSelector:@selector(textViewportLayoutControllerDidLayout:) withObject:self]; }
- (void)relocateViewportToTextLocation:(id)l { NSTextLayoutFragment *f = [_lm textLayoutFragmentForLocation:l]; if (f) _vb.origin.y = f->_frame.origin.y; }
- (CGFloat)adjustViewportByVerticalOffset:(CGFloat)o { _vb.origin.y += o; return o; }
@end
