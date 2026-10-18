/* AppKit-lite text system: NSTextStorage, NSLayoutManager, NSTextContainer, NSText / NSTextView and NSFontManager.
 *
 * Layout is done by the host (pango) for the whole storage at once through XEFTextLayout (AppKitGraphics.m); glyph
 * indices are character indices. The text view is flipped, draws background, selection, text and caret, resizes
 * vertically to fit its text, edits through the standard NSResponder action methods (with undo), and handles mouse
 * selection, the pasteboard and font traits. TextKit 2 is not provided (textLayoutManager is nil). MRC. */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitControls.h"
#import "AppKitText.h"
#include <objc/runtime.h>
#include <objc/message.h>
#include <math.h>

NSString *const NSTextDidBeginEditingNotification = @"NSTextDidBeginEditingNotification";
NSString *const NSTextDidEndEditingNotification = @"NSTextDidEndEditingNotification";
NSString *const NSTextDidChangeNotification = @"NSTextDidChangeNotification";
NSString *const NSTextViewDidChangeSelectionNotification = @"NSTextViewDidChangeSelectionNotification";
NSString *const NSTextViewDidChangeTypingAttributesNotification = @"NSTextViewDidChangeTypingAttributesNotification";
NSString *const NSTextViewWillChangeNotifyingTextViewNotification = @"NSTextViewWillChangeNotifyingTextViewNotification";
NSString *const NSTextStorageWillProcessEditingNotification = @"NSTextStorageWillProcessEditingNotification";
NSString *const NSTextStorageDidProcessEditingNotification = @"NSTextStorageDidProcessEditingNotification";
NSString *const NSTextMovementUserInfoKey = @"NSTextMovement";
NSString *const NSOldSelectedCharacterRange = @"NSOldSelectedCharacterRange";
NSString *const NSFontPanelModesMaskKey = @"NSFontPanelModesMask";

enum { kEditedAttributes = 1, kEditedCharacters = 2 };

/* ================================================================== NSTextStorage */
@implementation NSTextStorage
+ (BOOL)supportsSecureCoding { return YES; }
- (id)init { return [self initWithString:@"" attributes:nil]; }
- (id)initWithString:(NSString *)s { return [self initWithString:s attributes:nil]; }
/* the class-cluster initializers of Darling's (CF-bridged) NSMutableAttributedString return a new concrete object:
 * the subclass keeps its own storage and never calls them */
- (id)initWithString:(NSString *)s attributes:(NSDictionary *)a {
  _s = [[NSMutableAttributedString alloc] initWithString:s ?: @"" attributes:a]; _lms = [[NSMutableArray alloc] init];
  return self; }
- (id)initWithAttributedString:(NSAttributedString *)a {
  _s = a ? [a mutableCopy] : [[NSMutableAttributedString alloc] init]; _lms = [[NSMutableArray alloc] init];
  return self; }
/* nib: NSString plus either one attribute dictionary or an array of them with run lengths in NSAttributeInfo */
- (id)initWithCoder:(NSCoder *)c {
  id str = [c decodeObjectForKey:@"NSString"];
  NSString *s = [str isKindOfClass:[NSString class]] ? str : ([str respondsToSelector:@selector(string)] ? [str string] : @"");
  if (!(self = [self initWithString:s attributes:nil])) return nil;
  id attrs = [c decodeObjectForKey:@"NSAttributes"];
  if ([attrs isKindOfClass:[NSDictionary class]]) [_s setAttributes:attrs range:NSMakeRange(0, [_s length])];
  else if ([attrs isKindOfClass:[NSArray class]]) {
    NSUInteger len = 0; const uint8_t *info = [c decodeBytesForKey:@"NSAttributeInfo" returnedLength:&len];
    id infoObj = info ? nil : [c decodeObjectForKey:@"NSAttributeInfo"];
    if (!info && [infoObj isKindOfClass:[NSData class]]) { info = [infoObj bytes]; len = [infoObj length]; }
    NSUInteger pos = 0, p = 0;
    while (info && p < len && pos < [_s length]) {
      uint64_t runLen = 0, idx = 0; int sh = 0;
      while (p < len) { uint8_t b = info[p++]; runLen |= (uint64_t)(b & 0x7f) << sh; sh += 7; if (!(b & 0x80)) break; }
      sh = 0;
      while (p < len) { uint8_t b = info[p++]; idx |= (uint64_t)(b & 0x7f) << sh; sh += 7; if (!(b & 0x80)) break; }
      NSRange r = NSMakeRange(pos, MIN((NSUInteger)runLen, [_s length] - pos));
      if (idx < [attrs count] && [[attrs objectAtIndex:idx] isKindOfClass:[NSDictionary class]]) [_s setAttributes:[attrs objectAtIndex:idx] range:r];
      pos += r.length; }
    if (!info && [attrs count]) [_s setAttributes:[attrs objectAtIndex:0] range:NSMakeRange(0, [_s length])]; }
  _delegate = [c decodeObjectForKey:@"NSDelegate"];
  return self; }
- (void)encodeWithCoder:(NSCoder *)c { [c encodeObject:[_s string] forKey:@"NSString"]; }
- (void)dealloc { [_s release]; [_lms release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [[NSAttributedString allocWithZone:z] initWithAttributedString:_s]; }
- (id)mutableCopyWithZone:(NSZone *)z { return [[NSMutableAttributedString allocWithZone:z] initWithAttributedString:_s]; }
/* primitives */
- (NSString *)string { return [_s string]; }
- (NSUInteger)length { return [_s length]; }
- (NSDictionary *)attributesAtIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r { return [_s attributesAtIndex:i effectiveRange:r]; }
- (id)attribute:(NSString *)n atIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r { return [_s attribute:n atIndex:i effectiveRange:r]; }
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s {
  NSUInteger before = [_s length];
  [_s replaceCharactersInRange:r withString:s ?: @""];
  [self edited:kEditedCharacters | kEditedAttributes range:r changeInLength:(NSInteger)[_s length] - (NSInteger)before]; }
- (void)setAttributes:(NSDictionary *)a range:(NSRange)r { [_s setAttributes:a range:r]; [self edited:kEditedAttributes range:r changeInLength:0]; }
- (void)addAttribute:(NSString *)n value:(id)v range:(NSRange)r { [_s addAttribute:n value:v range:r]; [self edited:kEditedAttributes range:r changeInLength:0]; }
- (void)addAttributes:(NSDictionary *)a range:(NSRange)r { [_s addAttributes:a range:r]; [self edited:kEditedAttributes range:r changeInLength:0]; }
- (void)removeAttribute:(NSString *)n range:(NSRange)r { [_s removeAttribute:n range:r]; [self edited:kEditedAttributes range:r changeInLength:0]; }
- (void)replaceCharactersInRange:(NSRange)r withAttributedString:(NSAttributedString *)a {
  NSUInteger before = [_s length];
  [_s replaceCharactersInRange:r withAttributedString:a ?: [[[NSAttributedString alloc] init] autorelease]];
  [self edited:kEditedCharacters | kEditedAttributes range:r changeInLength:(NSInteger)[_s length] - (NSInteger)before]; }
- (void)setAttributedString:(NSAttributedString *)a { [self replaceCharactersInRange:NSMakeRange(0, [_s length]) withAttributedString:a]; }
- (void)insertAttributedString:(NSAttributedString *)a atIndex:(NSUInteger)i { [self replaceCharactersInRange:NSMakeRange(i, 0) withAttributedString:a]; }
- (void)appendAttributedString:(NSAttributedString *)a { [self replaceCharactersInRange:NSMakeRange([_s length], 0) withAttributedString:a]; }
- (void)deleteCharactersInRange:(NSRange)r { [self replaceCharactersInRange:r withString:@""]; }
- (NSMutableString *)mutableString { return [_s mutableString]; }
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)r { return [_s attributedSubstringFromRange:r]; }
/* editing */
- (void)beginEditing { _nest++; }
- (void)endEditing { if (_nest > 0 && --_nest == 0 && _editedMask) [self processEditing]; }
- (void)edited:(NSUInteger)mask range:(NSRange)r changeInLength:(NSInteger)d {
  if (!_editedMask) { _editedRange = NSMakeRange(r.location, (NSUInteger)MAX(0, (NSInteger)r.length + d)); _delta = d; }
  else { _editedRange = NSUnionRange(_editedRange, NSMakeRange(r.location, (NSUInteger)MAX(0, (NSInteger)r.length + d))); _delta += d; }
  _editedMask |= mask;
  if (!_nest) [self processEditing]; }
- (void)processEditing {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  if ([_delegate respondsToSelector:@selector(textStorageWillProcessEditing:)]) [_delegate textStorageWillProcessEditing:[NSNotification notificationWithName:NSTextStorageWillProcessEditingNotification object:self]];
  [nc postNotificationName:NSTextStorageWillProcessEditingNotification object:self];
  if ([_delegate respondsToSelector:@selector(textStorageDidProcessEditing:)]) [_delegate textStorageDidProcessEditing:[NSNotification notificationWithName:NSTextStorageDidProcessEditingNotification object:self]];
  [nc postNotificationName:NSTextStorageDidProcessEditingNotification object:self];
  NSUInteger mask = _editedMask; NSRange r = _editedRange; NSInteger d = _delta;
  _editedMask = 0; _delta = 0;
  for (NSLayoutManager *lm in [[_lms copy] autorelease])
    [lm processEditingForTextStorage:self edited:mask range:r changeInLength:d invalidatedRange:r]; }
- (NSUInteger)editedMask { return _editedMask; } - (NSRange)editedRange { return _editedRange; } - (NSInteger)changeInLength { return _delta; }
- (BOOL)fixesAttributesLazily { return NO; }
- (void)invalidateAttributesInRange:(NSRange)r {} - (void)ensureAttributesAreFixedInRange:(NSRange)r {}
- (NSArray *)layoutManagers { return [[_lms copy] autorelease]; }
- (void)addLayoutManager:(NSLayoutManager *)lm { if (lm && ![_lms containsObject:lm]) { [_lms addObject:lm]; [lm setTextStorage:self]; } }
- (void)removeLayoutManager:(NSLayoutManager *)lm { [[lm retain] autorelease]; [_lms removeObjectIdenticalTo:lm]; if ([lm textStorage] == self) [lm setTextStorage:nil]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
/* scripting conveniences */
- (NSFont *)font { return [_s length] ? [_s attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] : nil; }
- (void)setFont:(NSFont *)f { if (f) [self addAttribute:NSFontAttributeName value:f range:NSMakeRange(0, [_s length])]; }
- (NSColor *)foregroundColor { return [_s length] ? [_s attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] : nil; }
- (void)setForegroundColor:(NSColor *)c { if (c) [self addAttribute:NSForegroundColorAttributeName value:c range:NSMakeRange(0, [_s length])]; }
- (NSArray *)paragraphs { return @[]; } - (NSArray *)words { return @[]; } - (NSArray *)characters { return @[]; } - (NSArray *)attributeRuns { return @[]; }
- (id)textStorageObserver { return nil; } - (void)setTextStorageObserver:(id)o {}
@end

/* ================================================================== NSTextContainer */
@implementation NSTextContainer
+ (BOOL)supportsSecureCoding { return YES; }
- (id)initWithContainerSize:(NSSize)s { if ((self = [super init])) { _size = s; _padding = 5; _widthTracks = NO; } return self; }
- (id)initWithSize:(NSSize)s { return [self initWithContainerSize:s]; }
- (id)init { return [self initWithContainerSize:NSMakeSize(1e7, 1e7)]; }
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [self initWithContainerSize:NSMakeSize(1e7, 1e7)])) return nil;
  if ([c containsValueForKey:@"NSWidth"]) _size.width = [c decodeDoubleForKey:@"NSWidth"];
  uint32_t f = (uint32_t)[c decodeIntForKey:@"NSTCFlags"];
  _widthTracks = (f & 1) != 0; _heightTracks = (f & 2) != 0;
  _lm = [c decodeObjectForKey:@"NSLayoutManager"];   /* weak */
  _tv = [c decodeObjectForKey:@"NSTextView"];
  return self; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc { [_exclusion release]; [super dealloc]; }
- (NSSize)containerSize { return _size; } - (NSSize)size { return _size; }
- (void)setContainerSize:(NSSize)s { if (NSEqualSizes(s, _size)) return; _size = s; [_lm textContainerChangedGeometry:self]; }
- (void)setSize:(NSSize)s { [self setContainerSize:s]; }
- (CGFloat)lineFragmentPadding { return _padding; } - (void)setLineFragmentPadding:(CGFloat)p { _padding = p; [_lm textContainerChangedGeometry:self]; }
- (BOOL)widthTracksTextView { return _widthTracks; } - (void)setWidthTracksTextView:(BOOL)f { _widthTracks = f; }
- (BOOL)heightTracksTextView { return _heightTracks; } - (void)setHeightTracksTextView:(BOOL)f { _heightTracks = f; }
- (NSTextView *)textView { return _tv; }
- (void)setTextView:(NSTextView *)tv { _tv = tv; if (tv && [tv textContainer] != self) [tv setTextContainer:self]; }
- (NSLayoutManager *)layoutManager { return _lm; } - (void)setLayoutManager:(NSLayoutManager *)lm { _lm = lm; }
- (void)replaceLayoutManager:(NSLayoutManager *)lm { [[_lm textStorage] addLayoutManager:lm]; _lm = lm; }
- (NSUInteger)maximumNumberOfLines { return _maxLines; } - (void)setMaximumNumberOfLines:(NSUInteger)n { _maxLines = n; }
- (NSInteger)lineBreakMode { return _lineBreak; } - (void)setLineBreakMode:(NSInteger)m { _lineBreak = m; }
- (NSArray *)exclusionPaths { return _exclusion ?: @[]; } - (void)setExclusionPaths:(NSArray *)p { [_exclusion release]; _exclusion = [p copy]; }
- (BOOL)isSimpleRectangularTextContainer { return YES; }
- (BOOL)containsPoint:(NSPoint)p { return p.x >= 0 && p.y >= 0 && p.x <= _size.width && p.y <= _size.height; }
- (id)textLayoutManager { return nil; }
@end

/* ================================================================== NSLayoutManager */
@implementation NSLayoutManager
+ (BOOL)supportsSecureCoding { return YES; }
- (id)init { if ((self = [super init])) { _containers = [[NSMutableArray alloc] init]; _usesFontLeading = YES; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [self init])) return nil;
  for (id tc in [c decodeObjectForKey:@"NSTextContainers"]) if ([tc isKindOfClass:[NSTextContainer class]]) [self addTextContainer:tc];
  NSTextStorage *ts = [c decodeObjectForKey:@"NSTextStorage"];
  if ([ts isKindOfClass:[NSTextStorage class]]) [ts addLayoutManager:self];
  _delegate = [c decodeObjectForKey:@"NSDelegate"];
  return self; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc { [_containers release]; [_layout release]; [_tempAttrs release]; [super dealloc]; }
- (NSTextStorage *)textStorage { return _storage; }
- (void)setTextStorage:(NSTextStorage *)s { _storage = s; [self _xefInvalidate]; }
- (void)replaceTextStorage:(NSTextStorage *)s { NSTextStorage *old = _storage; [[self retain] autorelease]; [old removeLayoutManager:self]; [s addLayoutManager:self]; }
- (NSArray *)textContainers { return [[_containers copy] autorelease]; }
- (void)addTextContainer:(NSTextContainer *)c { [self insertTextContainer:c atIndex:[_containers count]]; }
- (void)insertTextContainer:(NSTextContainer *)c atIndex:(NSUInteger)i { if (!c) return; [_containers insertObject:c atIndex:MIN(i, [_containers count])]; [c setLayoutManager:self]; [self _xefInvalidate]; }
- (void)removeTextContainerAtIndex:(NSUInteger)i { if (i < [_containers count]) { [[_containers objectAtIndex:i] setLayoutManager:nil]; [_containers removeObjectAtIndex:i]; } }
- (void)textContainerChangedGeometry:(NSTextContainer *)c { [self _xefInvalidate]; [[c textView] _xefLayoutChanged]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSTextView *)firstTextView { for (NSTextContainer *c in _containers) if ([c textView]) return [c textView]; return nil; }
- (NSTextView *)textViewForBeginningOfSelection { return [self firstTextView]; }
- (BOOL)allowsNonContiguousLayout { return _nonContiguous; } - (void)setAllowsNonContiguousLayout:(BOOL)f { _nonContiguous = f; }
- (BOOL)hasNonContiguousLayout { return NO; }
- (BOOL)backgroundLayoutEnabled { return _bgLayout; } - (void)setBackgroundLayoutEnabled:(BOOL)f { _bgLayout = f; }
- (BOOL)showsInvisibleCharacters { return _showInvisibles; } - (void)setShowsInvisibleCharacters:(BOOL)f { _showInvisibles = f; }
- (BOOL)showsControlCharacters { return NO; } - (void)setShowsControlCharacters:(BOOL)f {}
- (BOOL)usesFontLeading { return _usesFontLeading; } - (void)setUsesFontLeading:(BOOL)f { _usesFontLeading = f; }
- (BOOL)usesScreenFonts { return NO; } - (void)setUsesScreenFonts:(BOOL)f {}
- (NSInteger)typesetterBehavior { return 0; } - (void)setTypesetterBehavior:(NSInteger)b {}
- (CGFloat)hyphenationFactor { return 0; } - (void)setHyphenationFactor:(CGFloat)f {}
- (NSInteger)defaultAttachmentScaling { return 0; } - (void)setDefaultAttachmentScaling:(NSInteger)s {}
- (BOOL)limitsLayoutForSuspiciousContents { return NO; } - (void)setLimitsLayoutForSuspiciousContents:(BOOL)f {}
- (id)typesetter { return nil; } - (void)setTypesetter:(id)t {}
- (id)glyphGenerator { return nil; } - (void)setGlyphGenerator:(id)g {}
/* layout cache */
- (void)_xefInvalidate { [_layout release]; _layout = nil; }
- (CGFloat)_xefWidth { NSTextContainer *c = [_containers firstObject]; if (!c) return -1; CGFloat w = c->_size.width - 2 * c->_padding; return w > 0 && w < 1e6 ? w : -1; }
- (XEFTextLayout *)_xefLayout {
  CGFloat w = [self _xefWidth];
  if (_layout && _layoutWidth == w) return _layout;
  [_layout release];
  _layout = [[XEFTextLayout alloc] initWithAttributedString:_storage ?: [[[NSAttributedString alloc] init] autorelease] width:w];
  _layoutWidth = w;
  return _layout; }
- (void)processEditingForTextStorage:(NSTextStorage *)ts edited:(NSUInteger)mask range:(NSRange)r changeInLength:(NSInteger)d invalidatedRange:(NSRange)ir {
  [self _xefInvalidate];
  for (NSTextContainer *c in _containers) [[c textView] _xefLayoutChanged];
  if ([_delegate respondsToSelector:@selector(layoutManager:didCompleteLayoutForTextContainer:atEnd:)])
    ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(_delegate, @selector(layoutManager:didCompleteLayoutForTextContainer:atEnd:), self, [_containers firstObject], YES); }
- (void)invalidateLayoutForCharacterRange:(NSRange)r actualCharacterRange:(NSRangePointer)a { [self _xefInvalidate]; if (a) *a = r; }
- (void)invalidateLayoutForCharacterRange:(NSRange)r isSoft:(BOOL)s actualCharacterRange:(NSRangePointer)a { [self invalidateLayoutForCharacterRange:r actualCharacterRange:a]; }
- (void)invalidateGlyphsForCharacterRange:(NSRange)r changeInLength:(NSInteger)d actualCharacterRange:(NSRangePointer)a { [self _xefInvalidate]; if (a) *a = r; }
- (void)invalidateDisplayForCharacterRange:(NSRange)r { for (NSTextContainer *c in _containers) [[c textView] setNeedsDisplay:YES]; }
- (void)invalidateDisplayForGlyphRange:(NSRange)r { [self invalidateDisplayForCharacterRange:r]; }
- (void)ensureLayoutForTextContainer:(NSTextContainer *)c { [self _xefLayout]; }
- (void)ensureLayoutForGlyphRange:(NSRange)r { [self _xefLayout]; } - (void)ensureLayoutForCharacterRange:(NSRange)r { [self _xefLayout]; }
- (void)ensureLayoutForBoundingRect:(NSRect)b inTextContainer:(NSTextContainer *)c { [self _xefLayout]; }
- (void)ensureGlyphsForCharacterRange:(NSRange)r {} - (void)ensureGlyphsForGlyphRange:(NSRange)r {}
/* glyphs == characters */
- (NSUInteger)numberOfGlyphs { return [_storage length]; }
- (NSGlyph)glyphAtIndex:(NSUInteger)i { return i < [_storage length] ? [[_storage string] characterAtIndex:i] : 0; }
- (NSGlyph)glyphAtIndex:(NSUInteger)i isValidIndex:(BOOL *)v { if (v) *v = i < [_storage length]; return [self glyphAtIndex:i]; }
- (CGGlyph)CGGlyphAtIndex:(NSUInteger)i { return (CGGlyph)[self glyphAtIndex:i]; }
- (NSUInteger)characterIndexForGlyphAtIndex:(NSUInteger)i { return i; }
- (NSUInteger)glyphIndexForCharacterAtIndex:(NSUInteger)i { return i; }
- (NSRange)glyphRangeForCharacterRange:(NSRange)r actualCharacterRange:(NSRangePointer)a { if (a) *a = r; return r; }
- (NSRange)characterRangeForGlyphRange:(NSRange)r actualGlyphRange:(NSRangePointer)a { if (a) *a = r; return r; }
- (NSRange)glyphRangeForTextContainer:(NSTextContainer *)c { return NSMakeRange(0, [_storage length]); }
- (NSRange)glyphRangeForBoundingRect:(NSRect)b inTextContainer:(NSTextContainer *)c { return NSMakeRange(0, [_storage length]); }
- (NSRange)glyphRangeForBoundingRectWithoutAdditionalLayout:(NSRect)b inTextContainer:(NSTextContainer *)c { return NSMakeRange(0, [_storage length]); }
- (NSTextContainer *)textContainerForGlyphAtIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r { if (r) *r = NSMakeRange(0, [_storage length]); return [_containers firstObject]; }
- (NSTextContainer *)textContainerForGlyphAtIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r withoutAdditionalLayout:(BOOL)f { return [self textContainerForGlyphAtIndex:i effectiveRange:r]; }
- (BOOL)isValidGlyphIndex:(NSUInteger)i { return i < [_storage length]; }
- (NSUInteger)getGlyphs:(NSGlyph *)g range:(NSRange)r { for (NSUInteger i = 0; i < r.length; i++) g[i] = [self glyphAtIndex:r.location + i]; return r.length; }
/* geometry: container coordinates (origin top-left of the container, padding included in x) */
- (CGFloat)_xefPad { NSTextContainer *c = [_containers firstObject]; return c ? c->_padding : 0; }
- (NSRect)usedRectForTextContainer:(NSTextContainer *)c {
  XEFTextLayout *l = [self _xefLayout]; NSSize s = [l size];
  CGFloat w = [self _xefWidth] > 0 ? [self _xefWidth] : s.width;
  return NSMakeRect([self _xefPad], 0, w, s.height); }
- (NSRect)extraLineFragmentRect { return NSZeroRect; }
- (NSRect)extraLineFragmentUsedRect { return NSZeroRect; }
- (NSTextContainer *)extraLineFragmentTextContainer { return nil; }
- (NSUInteger)_xefLines:(XEFLineInfo **)out {
  XEFTextLayout *l = [self _xefLayout]; NSUInteger max = [l lineCount] + 1;
  XEFLineInfo *li = malloc(max * sizeof *li); NSUInteger n = [l getLines:li max:max];
  *out = li; return n; }
- (NSRect)lineFragmentRectForGlyphAtIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r {
  XEFLineInfo *li; NSUInteger n = [self _xefLines:&li], k = 0;
  while (k + 1 < n && li[k + 1].start <= i) k++;
  NSRect fr = n ? NSMakeRect(0, li[k].top, [self _xefWidth] > 0 ? [self _xefWidth] + 2 * [self _xefPad] : [[self _xefLayout] size].width, li[k].height) : NSZeroRect;
  if (r) { NSUInteger end = k + 1 < n ? li[k + 1].start : [_storage length]; *r = n ? NSMakeRange(li[k].start, end - li[k].start) : NSMakeRange(0, 0); }
  free(li); return fr; }
- (NSRect)lineFragmentRectForGlyphAtIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r withoutAdditionalLayout:(BOOL)f { return [self lineFragmentRectForGlyphAtIndex:i effectiveRange:r]; }
- (NSRect)lineFragmentUsedRectForGlyphAtIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r { return [self lineFragmentRectForGlyphAtIndex:i effectiveRange:r]; }
- (void)enumerateLineFragmentsForGlyphRange:(NSRange)gr usingBlock:(void (^)(NSRect, NSRect, NSTextContainer *, NSRange, BOOL *))b {
  XEFLineInfo *li; NSUInteger n = [self _xefLines:&li]; BOOL stop = NO;
  CGFloat w = [self _xefWidth] > 0 ? [self _xefWidth] + 2 * [self _xefPad] : [[self _xefLayout] size].width;
  for (NSUInteger k = 0; k < n && !stop; k++) {
    NSUInteger end = k + 1 < n ? li[k + 1].start : [_storage length];
    NSRange lr = NSMakeRange(li[k].start, end - li[k].start);
    if (NSMaxRange(lr) < gr.location || lr.location > NSMaxRange(gr)) continue;
    NSRect r = NSMakeRect(0, li[k].top, w, li[k].height);
    b(r, r, [_containers firstObject], lr, &stop); }
  free(li); }
- (NSPoint)locationForGlyphAtIndex:(NSUInteger)i { NSRect c = [[self _xefLayout] caretRectAtIndex:i]; return NSMakePoint(c.origin.x, c.origin.y + [[self _xefLayout] baseline]); }
- (NSRect)boundingRectForGlyphRange:(NSRange)r inTextContainer:(NSTextContainer *)c {
  XEFTextLayout *l = [self _xefLayout]; CGFloat pad = [self _xefPad];
  NSRect a = [l caretRectAtIndex:r.location], b = [l caretRectAtIndex:NSMaxRange(r)];
  if (a.origin.y == b.origin.y) return NSMakeRect(pad + fmin(a.origin.x, b.origin.x), a.origin.y, fmax(1, fabs(b.origin.x - a.origin.x)), a.size.height);
  CGFloat w = [self _xefWidth] > 0 ? [self _xefWidth] : [l size].width;
  return NSMakeRect(pad, a.origin.y, w, NSMaxY(b) - a.origin.y); }
/* selection rectangles in container coordinates (one per line touched) */
- (NSUInteger)_xefRects:(NSRect *)out max:(NSUInteger)max forRange:(NSRange)r {
  XEFTextLayout *l = [self _xefLayout]; CGFloat pad = [self _xefPad];
  CGFloat w = ([self _xefWidth] > 0 ? [self _xefWidth] : [l size].width);
  NSRect a = [l caretRectAtIndex:r.location], b = [l caretRectAtIndex:NSMaxRange(r)];
  if (fabs(a.origin.y - b.origin.y) < 0.5) { out[0] = NSMakeRect(pad + a.origin.x, a.origin.y, fmax(1, b.origin.x - a.origin.x), a.size.height); return 1; }
  NSUInteger n = 0;
  out[n++] = NSMakeRect(pad + a.origin.x, a.origin.y, fmax(1, w - a.origin.x), a.size.height);
  if (NSMaxY(a) < b.origin.y - 0.5 && n < max) out[n++] = NSMakeRect(pad, NSMaxY(a), w, b.origin.y - NSMaxY(a));
  if (n < max && b.origin.x > 0) out[n++] = NSMakeRect(pad, b.origin.y, b.origin.x, b.size.height);
  return n; }
- (NSRectArray)rectArrayForCharacterRange:(NSRange)cr withinSelectedCharacterRange:(NSRange)sr inTextContainer:(NSTextContainer *)c rectCount:(NSUInteger *)n {
  static NSRect rects[3]; NSUInteger k = [self _xefRects:rects max:3 forRange:cr]; if (n) *n = k; return rects; }
- (NSRectArray)rectArrayForGlyphRange:(NSRange)gr withinSelectedGlyphRange:(NSRange)sr inTextContainer:(NSTextContainer *)c rectCount:(NSUInteger *)n {
  return [self rectArrayForCharacterRange:gr withinSelectedCharacterRange:sr inTextContainer:c rectCount:n]; }
- (void)enumerateEnclosingRectsForGlyphRange:(NSRange)gr withinSelectedGlyphRange:(NSRange)sr inTextContainer:(NSTextContainer *)c usingBlock:(void (^)(NSRect, BOOL *))b {
  NSRect rects[3]; NSUInteger k = [self _xefRects:rects max:3 forRange:gr]; BOOL stop = NO;
  for (NSUInteger i = 0; i < k && !stop; i++) b(rects[i], &stop); }
- (NSUInteger)characterIndexForPoint:(NSPoint)p inTextContainer:(NSTextContainer *)c fractionOfDistanceBetweenInsertionPoints:(CGFloat *)f {
  if (f) *f = 0;
  return [[self _xefLayout] characterIndexAtPoint:NSMakePoint(p.x - [self _xefPad], p.y)]; }
- (NSUInteger)glyphIndexForPoint:(NSPoint)p inTextContainer:(NSTextContainer *)c fractionOfDistanceThroughGlyph:(CGFloat *)f {
  NSUInteger i = [self characterIndexForPoint:p inTextContainer:c fractionOfDistanceBetweenInsertionPoints:f];
  return i > 0 && i >= [_storage length] ? [_storage length] - 1 : i; }
- (NSUInteger)glyphIndexForPoint:(NSPoint)p inTextContainer:(NSTextContainer *)c { return [self glyphIndexForPoint:p inTextContainer:c fractionOfDistanceThroughGlyph:NULL]; }
- (CGFloat)fractionOfDistanceThroughGlyphForPoint:(NSPoint)p inTextContainer:(NSTextContainer *)c { return 0; }
- (CGFloat)defaultLineHeightForFont:(NSFont *)f { return ceil([f _xefLineHeight]); }
- (CGFloat)defaultBaselineOffsetForFont:(NSFont *)f { return ceil([f ascender]); }
/* drawing at the container origin p (in the flipped text view) */
- (void)drawBackgroundForGlyphRange:(NSRange)r atPoint:(NSPoint)p {}
- (void)drawGlyphsForGlyphRange:(NSRange)r atPoint:(NSPoint)p { [[self _xefLayout] drawAtTopLeft:NSMakePoint(p.x + [self _xefPad], p.y)]; }
- (void)drawUnderlineForGlyphRange:(NSRange)g underlineType:(NSInteger)t baselineOffset:(CGFloat)b lineFragmentRect:(NSRect)l lineFragmentGlyphRange:(NSRange)lg containerOrigin:(NSPoint)o {}
- (void)showCGGlyphs:(const CGGlyph *)g positions:(const CGPoint *)p count:(NSInteger)n font:(NSFont *)f textMatrix:(CGAffineTransform)m attributes:(NSDictionary *)a inContext:(CGContextRef)c {}
/* temporary attributes: kept, not drawn */
- (void)addTemporaryAttribute:(NSString *)n value:(id)v forCharacterRange:(NSRange)r {}
- (void)addTemporaryAttributes:(NSDictionary *)a forCharacterRange:(NSRange)r {}
- (void)setTemporaryAttributes:(NSDictionary *)a forCharacterRange:(NSRange)r {}
- (void)removeTemporaryAttribute:(NSString *)n forCharacterRange:(NSRange)r {}
- (NSDictionary *)temporaryAttributesAtCharacterIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r { if (r) *r = NSMakeRange(0, [_storage length]); return @{}; }
- (id)temporaryAttribute:(NSString *)n atCharacterIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r { return nil; }
- (NSUInteger)layoutOptions { return 0; }
- (NSUInteger)firstUnlaidCharacterIndex { return [_storage length]; } - (NSUInteger)firstUnlaidGlyphIndex { return [_storage length]; }
@end

/* ================================================================== NSTextView */
@interface NSTextViewSharedData : NSObject <NSCoding> {
@public
  NSColor *_bg, *_insertion; NSDictionary *_selAttrs, *_linkAttrs; NSParagraphStyle *_para; uint32_t _flags;
}
@end
@implementation NSTextViewSharedData
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super init])) {
    _flags = (uint32_t)[c decodeIntForKey:@"NSFlags"];
    _bg = [[c decodeObjectForKey:@"NSBackgroundColor"] retain];
    _insertion = [[c decodeObjectForKey:@"NSInsertionColor"] retain];
    _selAttrs = [[c decodeObjectForKey:@"NSSelectedAttributes"] retain];
    _linkAttrs = [[c decodeObjectForKey:@"NSLinkAttributes"] retain];
    _para = [[c decodeObjectForKey:@"NSDefaultParagraphStyle"] retain]; }
  return self; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc { [_bg release]; [_insertion release]; [_selAttrs release]; [_linkAttrs release]; [_para release]; [super dealloc]; }
@end

@implementation NSText
- (BOOL)isFlipped { return YES; }
@end

static BOOL is_word_char(unichar c) { return [[NSCharacterSet alphanumericCharacterSet] characterIsMember:c] || c == '_'; }

@implementation NSTextView
+ (NSMenu *)defaultMenu { return nil; }
+ (void)registerForServices {}
+ (BOOL)stronglyReferencesTextStorage { return NO; }
- (void)_xefCommonInit {
  _editable = _selectable = _rich = _drawsBg = _vResizable = _allowsUndo = YES;
  _bgColor = [[NSColor textBackgroundColor] retain]; _insertionColor = [[NSColor textColor] retain];
  _maxSize = NSMakeSize(1e7, 1e7); _goalX = -1;
  _typing = [@{ NSFontAttributeName: [NSFont userFontOfSize:12], NSForegroundColorAttributeName: [NSColor textColor] } retain]; }
- (id)initWithFrame:(NSRect)f textContainer:(NSTextContainer *)c {
  if (!(self = [super initWithFrame:f])) return nil;
  [self _xefCommonInit];
  _minSize = f.size;
  if (c) [self setTextContainer:c];
  return self; }
- (id)initWithFrame:(NSRect)f {
  NSTextStorage *ts = [[[NSTextStorage alloc] init] autorelease];
  NSLayoutManager *lm = [[[NSLayoutManager alloc] init] autorelease];
  NSTextContainer *tc = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(f.size.width, 1e7)] autorelease];
  [tc setWidthTracksTextView:YES];
  [lm addTextContainer:tc]; [ts addLayoutManager:lm];
  if ((self = [self initWithFrame:f textContainer:tc])) { _storage = [ts retain]; _ownsStorage = YES; }
  return self; }
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [super initWithCoder:c])) return nil;
  [self _xefCommonInit];
  NSTextViewSharedData *sd = [c decodeObjectForKey:@"NSSharedData"];
  if (getenv("XEF_APPKIT_DEBUG")) NSLog(@"xef: textview %p shared data %@ (%s) flags %#x", self, sd, sd ? class_getName([sd class]) : "-", [sd isKindOfClass:[NSTextViewSharedData class]] ? sd->_flags : 0);
  if ([sd isKindOfClass:[NSTextViewSharedData class]]) {
    uint32_t f = sd->_flags;
    _selectable = (f & 0x1) != 0; _editable = (f & 0x2) != 0; _rich = (f & 0x4) != 0; _imports = (f & 0x8) != 0;
    _fieldEditor = (f & 0x10) != 0; _usesFontPanel = (f & 0x20) != 0; _usesRuler = (f & 0x100) != 0;
    _allowsUndo = (f & 0x400) != 0; _drawsBg = (f & 0x800) != 0;
    if (sd->_bg) { [_bgColor release]; _bgColor = [sd->_bg retain]; }
    if (sd->_insertion) { [_insertionColor release]; _insertionColor = [sd->_insertion retain]; }
    _selAttrs = [sd->_selAttrs retain]; _linkAttrs = [sd->_linkAttrs retain]; _defaultPara = [sd->_para retain]; }
  uint32_t tv = (uint32_t)[c decodeIntForKey:@"NSTVFlags"];
  _hResizable = (tv & 1) != 0; _vResizable = (tv & 2) != 0;
  if ([c containsValueForKey:@"NSMaxSize"]) _maxSize = [c decodeSizeForKey:@"NSMaxSize"];
  if ([c containsValueForKey:@"NSMinize"]) _minSize = [c decodeSizeForKey:@"NSMinize"];
  else _minSize = _frame.size;
  if ([c containsValueForKey:@"NSTextContainerInset"]) _inset = [c decodeSizeForKey:@"NSTextContainerInset"];
  _tvDelegate = [c decodeObjectForKey:@"NSDelegate"];
  NSTextContainer *tc = [c decodeObjectForKey:@"NSTextContainer"];
  if ([tc isKindOfClass:[NSTextContainer class]]) {
    /* -[NSView initWithCoder:] went through -initWithFrame:, which built a private text network: replace it with the
     * archived one, which the text view owns (nothing else retains an archived text storage) */
    if (_ownsStorage) { [_storage release]; _storage = nil; _ownsStorage = NO; }
    _tc = nil; _lm = nil;
    [self setTextContainer:tc];
    if (_storage) { [_storage retain]; _ownsStorage = YES; } }
  if (!_storage) {   /* a text view archived without storage still edits */
    NSTextStorage *ts = [[[NSTextStorage alloc] init] autorelease]; NSLayoutManager *lm = [[[NSLayoutManager alloc] init] autorelease];
    NSTextContainer *ntc = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(_frame.size.width, 1e7)] autorelease];
    [ntc setWidthTracksTextView:YES]; [lm addTextContainer:ntc]; [ts addLayoutManager:lm];
    [self setTextContainer:ntc]; _storage = [ts retain]; _ownsStorage = YES; }
  if ([_storage length]) { NSDictionary *a = [_storage attributesAtIndex:0 effectiveRange:NULL]; if ([a count]) { [_typing release]; _typing = [a copy]; } }
  return self; }
- (void)dealloc { [_bgColor release]; [_insertionColor release]; [_selAttrs release]; [_linkAttrs release]; [_defaultPara release]; [_typing release]; if (_ownsStorage) [_storage release]; [super dealloc]; }
/* components */
- (NSTextContainer *)textContainer { return _tc; }
- (void)setTextContainer:(NSTextContainer *)c {
  if (c == _tc) return;
  _tc = c; [c setTextView:self];
  _lm = [c layoutManager]; _storage = [_lm textStorage];
  [self _xefTrackWidth]; [self _xefLayoutChanged]; }
- (void)replaceTextContainer:(NSTextContainer *)c { [self setTextContainer:c]; }
- (NSLayoutManager *)layoutManager { if (!_lm) _lm = [_tc layoutManager]; return _lm; }
- (NSTextStorage *)textStorage { if (!_storage) _storage = [[self layoutManager] textStorage]; return _storage; }
- (id)textLayoutManager { return nil; } - (id)textContentStorage { return nil; }
- (NSSize)textContainerInset { return _inset; } - (void)setTextContainerInset:(NSSize)s { _inset = s; [self _xefTrackWidth]; [self _xefLayoutChanged]; }
- (NSPoint)textContainerOrigin { return NSMakePoint(_inset.width, _inset.height); }
- (void)invalidateTextContainerOrigin {}
- (void)_xefTrackWidth {
  if (_tc && [_tc widthTracksTextView]) { NSSize s = [_tc containerSize]; s.width = fmax(0, _bounds.size.width - 2 * _inset.width); [_tc setContainerSize:s]; }
  if (_tc && [_tc heightTracksTextView]) { NSSize s = [_tc containerSize]; s.height = fmax(0, _bounds.size.height - 2 * _inset.height); [_tc setContainerSize:s]; } }
- (void)setFrame:(NSRect)f {
  BOOL widthChanged = f.size.width != _frame.size.width;
  [super setFrame:f];
  if (widthChanged && !_inLayout) { [self _xefTrackWidth]; [self _xefLayoutChanged]; } }
- (void)setFrameSize:(NSSize)s { NSRect f = _frame; f.size = s; [self setFrame:f]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self _xefLayoutChanged]; }
/* resizing to the text */
- (void)_xefLayoutChanged {
  [self setNeedsDisplay:YES];
  if (_inLayout || !_lm) return;
  _inLayout = YES;
  [self sizeToFit];
  _inLayout = NO; }
- (void)sizeToFit {
  if (!_lm || !_tc) return;
  NSRect used = [_lm usedRectForTextContainer:_tc];
  NSSize s = _frame.size;
  if (_vResizable) {
    CGFloat h = ceil(used.size.height + 2 * _inset.height);
    NSView *sv = [self superview];
    if ([sv isKindOfClass:[NSClipView class]]) h = fmax(h, sv->_bounds.size.height);
    s.height = fmin(fmax(h, _minSize.height), _maxSize.height); }
  if (_hResizable) s.width = fmin(fmax(ceil(NSMaxX(used) + 2 * _inset.width), _minSize.width), _maxSize.width);
  if (!NSEqualSizes(s, _frame.size)) {
    NSRect f = _frame; f.size = s;
    [super setFrame:f];
    id sv = [self superview]; if ([sv isKindOfClass:[NSClipView class]]) { [sv scrollToPoint:[sv bounds].origin]; id sc = [sv superview]; if ([sc respondsToSelector:@selector(reflectScrolledClipView:)]) [sc reflectScrolledClipView:sv]; } } }
- (NSSize)minSize { return _minSize; } - (void)setMinSize:(NSSize)s { _minSize = s; }
- (NSSize)maxSize { return _maxSize; } - (void)setMaxSize:(NSSize)s { _maxSize = s; }
- (BOOL)isVerticallyResizable { return _vResizable; } - (void)setVerticallyResizable:(BOOL)f { _vResizable = f; }
- (BOOL)isHorizontallyResizable { return _hResizable; } - (void)setHorizontallyResizable:(BOOL)f { _hResizable = f; }
/* properties */
- (id)delegate { return _tvDelegate; } - (void)setDelegate:(id)d { _tvDelegate = d; }
- (BOOL)isEditable { return _editable; } - (void)setEditable:(BOOL)f { _editable = f; if (f) _selectable = YES; [self setNeedsDisplay:YES]; }
- (BOOL)isSelectable { return _selectable; } - (void)setSelectable:(BOOL)f { _selectable = f; }
- (BOOL)isRichText { return _rich; } - (void)setRichText:(BOOL)f { _rich = f; }
- (BOOL)importsGraphics { return _imports; } - (void)setImportsGraphics:(BOOL)f { _imports = f; }
- (BOOL)isFieldEditor { return _fieldEditor; } - (void)setFieldEditor:(BOOL)f { _fieldEditor = f; }
- (BOOL)allowsUndo { return _allowsUndo; } - (void)setAllowsUndo:(BOOL)f { _allowsUndo = f; }
- (BOOL)usesFontPanel { return _usesFontPanel; } - (void)setUsesFontPanel:(BOOL)f { _usesFontPanel = f; }
- (BOOL)usesRuler { return _usesRuler; } - (void)setUsesRuler:(BOOL)f { _usesRuler = f; }
- (BOOL)isRulerVisible { return NO; } - (void)setRulerVisible:(BOOL)f {} - (void)toggleRuler:(id)s {}
- (BOOL)drawsBackground { return _drawsBg; } - (void)setDrawsBackground:(BOOL)f { if (getenv("XEF_APPKIT_DEBUG")) NSLog(@"xef: textview %p setDrawsBackground %d", self, f); _drawsBg = f; [self setNeedsDisplay:YES]; }
- (NSColor *)backgroundColor { return _bgColor; } - (void)setBackgroundColor:(NSColor *)c { if (getenv("XEF_APPKIT_DEBUG")) NSLog(@"xef: textview %p setBackgroundColor %@", self, c); [c retain]; [_bgColor release]; _bgColor = c; [self setNeedsDisplay:YES]; }
- (NSColor *)insertionPointColor { return _insertionColor; } - (void)setInsertionPointColor:(NSColor *)c { [c retain]; [_insertionColor release]; _insertionColor = c; }
- (NSDictionary *)selectedTextAttributes { return _selAttrs ?: @{ NSBackgroundColorAttributeName: [NSColor selectedTextBackgroundColor] }; }
- (void)setSelectedTextAttributes:(NSDictionary *)a { [_selAttrs release]; _selAttrs = [a copy]; }
- (NSDictionary *)linkTextAttributes { return _linkAttrs; } - (void)setLinkTextAttributes:(NSDictionary *)a { [_linkAttrs release]; _linkAttrs = [a copy]; }
- (NSDictionary *)markedTextAttributes { return @{}; } - (void)setMarkedTextAttributes:(NSDictionary *)a {}
- (NSParagraphStyle *)defaultParagraphStyle { return _defaultPara; } - (void)setDefaultParagraphStyle:(NSParagraphStyle *)p { [_defaultPara release]; _defaultPara = [p copy]; }
- (NSDictionary *)typingAttributes { return _typing; }
- (void)setTypingAttributes:(NSDictionary *)a {
  if ([_typing isEqual:a]) return;
  [_typing release]; _typing = [a copy] ?: [@{} retain];
  [[NSNotificationCenter defaultCenter] postNotificationName:NSTextViewDidChangeTypingAttributesNotification object:self]; }
- (NSFont *)font { return [self _xefAttr:NSFontAttributeName] ?: [NSFont userFontOfSize:12]; }
- (void)setFont:(NSFont *)f { if (!f) return; [[self textStorage] addAttribute:NSFontAttributeName value:f range:NSMakeRange(0, [[self textStorage] length])]; [self _xefSetTyping:NSFontAttributeName value:f]; }
- (void)setFont:(NSFont *)f range:(NSRange)r { if (f) [[self textStorage] addAttribute:NSFontAttributeName value:f range:r]; }
- (NSColor *)textColor { return [self _xefAttr:NSForegroundColorAttributeName]; }
- (void)setTextColor:(NSColor *)c { NSRange all = NSMakeRange(0, [[self textStorage] length]);
  if (c) [[self textStorage] addAttribute:NSForegroundColorAttributeName value:c range:all]; else [[self textStorage] removeAttribute:NSForegroundColorAttributeName range:all];
  [self _xefSetTyping:NSForegroundColorAttributeName value:c]; }
- (void)setTextColor:(NSColor *)c range:(NSRange)r { if (c) [[self textStorage] addAttribute:NSForegroundColorAttributeName value:c range:r]; }
- (NSInteger)alignment { NSParagraphStyle *p = [self _xefAttr:NSParagraphStyleAttributeName]; return p ? [p alignment] : 4; }
- (void)setAlignment:(NSInteger)a { [self setAlignment:a range:NSMakeRange(0, [[self textStorage] length])]; }
- (void)setAlignment:(NSInteger)a range:(NSRange)r {
  NSMutableParagraphStyle *p = [[([self _xefAttr:NSParagraphStyleAttributeName] ?: [NSParagraphStyle defaultParagraphStyle]) mutableCopy] autorelease];
  [p setAlignment:a];
  if (r.length) [[self textStorage] addAttribute:NSParagraphStyleAttributeName value:p range:r];
  [self _xefSetTyping:NSParagraphStyleAttributeName value:p]; }
- (NSInteger)baseWritingDirection { return 0; } - (void)setBaseWritingDirection:(NSInteger)d {}
- (id)_xefAttr:(NSString *)n { NSTextStorage *s = [self textStorage]; return [s length] ? [s attribute:n atIndex:MIN(_sel.location, [s length] - 1) effectiveRange:NULL] : [_typing objectForKey:n]; }
- (void)_xefSetTyping:(NSString *)n value:(id)v { NSMutableDictionary *t = [[_typing mutableCopy] autorelease]; if (v) [t setObject:v forKey:n]; else [t removeObjectForKey:n]; [self setTypingAttributes:t]; }
/* no-op feature switches */
- (BOOL)isContinuousSpellCheckingEnabled { return NO; } - (void)setContinuousSpellCheckingEnabled:(BOOL)f {}
- (BOOL)isGrammarCheckingEnabled { return NO; } - (void)setGrammarCheckingEnabled:(BOOL)f {}
- (BOOL)isAutomaticSpellingCorrectionEnabled { return NO; } - (void)setAutomaticSpellingCorrectionEnabled:(BOOL)f {}
- (BOOL)isAutomaticQuoteSubstitutionEnabled { return NO; } - (void)setAutomaticQuoteSubstitutionEnabled:(BOOL)f {}
- (BOOL)isAutomaticDashSubstitutionEnabled { return NO; } - (void)setAutomaticDashSubstitutionEnabled:(BOOL)f {}
- (BOOL)isAutomaticLinkDetectionEnabled { return NO; } - (void)setAutomaticLinkDetectionEnabled:(BOOL)f {}
- (BOOL)isAutomaticDataDetectionEnabled { return NO; } - (void)setAutomaticDataDetectionEnabled:(BOOL)f {}
- (BOOL)isAutomaticTextReplacementEnabled { return NO; } - (void)setAutomaticTextReplacementEnabled:(BOOL)f {}
- (BOOL)isAutomaticTextCompletionEnabled { return NO; } - (void)setAutomaticTextCompletionEnabled:(BOOL)f {}
- (BOOL)smartInsertDeleteEnabled { return NO; } - (void)setSmartInsertDeleteEnabled:(BOOL)f {}
- (NSUInteger)enabledTextCheckingTypes { return 0; } - (void)setEnabledTextCheckingTypes:(NSUInteger)t {}
- (BOOL)allowsImageEditing { return NO; } - (void)setAllowsImageEditing:(BOOL)f {}
- (BOOL)allowsDocumentBackgroundColorChange { return NO; } - (void)setAllowsDocumentBackgroundColorChange:(BOOL)f {}
- (BOOL)usesInspectorBar { return NO; } - (void)setUsesInspectorBar:(BOOL)f {}
- (BOOL)usesFindBar { return NO; } - (void)setUsesFindBar:(BOOL)f {}
- (BOOL)usesFindPanel { return NO; } - (void)setUsesFindPanel:(BOOL)f {}
- (BOOL)isIncrementalSearchingEnabled { return NO; } - (void)setIncrementalSearchingEnabled:(BOOL)f {}
- (BOOL)usesAdaptiveColorMappingForDarkAppearance { return NO; } - (void)setUsesAdaptiveColorMappingForDarkAppearance:(BOOL)f {}
- (BOOL)displaysLinkToolTips { return NO; } - (void)setDisplaysLinkToolTips:(BOOL)f {}
- (BOOL)acceptsGlyphInfo { return NO; } - (void)setAcceptsGlyphInfo:(BOOL)f {}
- (BOOL)allowsCharacterPickerTouchBarItem { return NO; } - (void)setAllowsCharacterPickerTouchBarItem:(BOOL)f {}
- (void)setWritingToolsBehavior:(NSInteger)b {} - (NSInteger)writingToolsBehavior { return 0; }
- (void)setInlinePredictionType:(NSInteger)t {} - (void)setMathExpressionCompletionType:(NSInteger)t {}
- (void)setAllowedWritingToolsResultOptions:(NSUInteger)o {}
- (void)setLayoutOrientation:(NSInteger)o {} - (NSInteger)layoutOrientation { return 0; }
- (NSArray *)readablePasteboardTypes { return @[NSPasteboardTypeString]; } - (NSArray *)writablePasteboardTypes { return @[NSPasteboardTypeString]; }
- (void)breakUndoCoalescing {} - (BOOL)isCoalescingUndo { return NO; }
- (void)updateInsertionPointStateAndRestartTimer:(BOOL)f { [self setNeedsDisplay:YES]; }
- (void)setNeedsDisplayInRect:(NSRect)r avoidAdditionalLayout:(BOOL)f { [self setNeedsDisplay:YES]; }
- (void)updateRuler {} - (void)updateFontPanel {} - (void)updateDragTypeRegistration {}
- (void)setSpellingState:(NSInteger)s range:(NSRange)r {}
- (void)checkTextInDocument:(id)s {} - (void)checkTextInSelection:(id)s {}
- (void)performFindPanelAction:(id)s {} - (void)performTextFinderAction:(id)s {}
- (void)complete:(id)s {} - (void)orderFrontSharingServicePicker:(id)s {}
- (void)toggleContinuousSpellChecking:(id)s {} - (void)toggleGrammarChecking:(id)s {} - (void)toggleAutomaticSpellingCorrection:(id)s {}
- (void)toggleSmartInsertDelete:(id)s {} - (void)toggleAutomaticQuoteSubstitution:(id)s {} - (void)toggleAutomaticDashSubstitution:(id)s {}
- (void)toggleAutomaticLinkDetection:(id)s {} - (void)toggleAutomaticTextReplacement:(id)s {} - (void)toggleAutomaticDataDetection:(id)s {}
- (void)showGuessPanel:(id)s {} - (void)checkSpelling:(id)s {} - (void)startSpeaking:(id)s {} - (void)stopSpeaking:(id)s {}
/* text access */
- (NSString *)string { return [[[[self textStorage] string] copy] autorelease] ?: @""; }
- (void)setString:(NSString *)s {
  NSTextStorage *ts = [self textStorage];
  [ts replaceCharactersInRange:NSMakeRange(0, [ts length]) withAttributedString:[[[NSAttributedString alloc] initWithString:s ?: @"" attributes:_typing] autorelease]];
  [self setSelectedRange:NSMakeRange([ts length], 0)]; }
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s { [[self textStorage] replaceCharactersInRange:r withString:s]; }
- (void)replaceCharactersInRange:(NSRange)r withRTF:(NSData *)d { [self replaceCharactersInRange:r withString:[[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease]]; }
- (void)insertText:(id)s { [self insertText:s replacementRange:NSMakeRange(NSNotFound, 0)]; }
- (NSData *)RTFFromRange:(NSRange)r { return [[[self string] substringWithRange:r] dataUsingEncoding:NSUTF8StringEncoding]; }
- (NSData *)RTFDFromRange:(NSRange)r { return [self RTFFromRange:r]; }
- (BOOL)readRTFDFromFile:(NSString *)p { return NO; } - (BOOL)writeRTFDToFile:(NSString *)p atomically:(BOOL)f { return NO; }
- (NSRange)rangeForUserTextChange { return _editable ? _sel : NSMakeRange(NSNotFound, 0); }
- (NSRange)rangeForUserCharacterAttributeChange { return _editable ? (_sel.length || !_rich ? _sel : NSMakeRange(NSNotFound, 0)) : NSMakeRange(NSNotFound, 0); }
- (NSRange)rangeForUserParagraphAttributeChange { return _editable ? [[self string] paragraphRangeForRange:_sel] : NSMakeRange(NSNotFound, 0); }
- (NSArray *)rangesForUserTextChange { return @[[NSValue valueWithRange:[self rangeForUserTextChange]]]; }
/* selection */
- (NSRange)selectedRange { return _sel; }
- (NSArray *)selectedRanges { return @[[NSValue valueWithRange:_sel]]; }
- (void)setSelectedRanges:(NSArray *)r { if ([r count]) [self setSelectedRange:[[r objectAtIndex:0] rangeValue]]; }
- (void)setSelectedRanges:(NSArray *)r affinity:(NSInteger)a stillSelecting:(BOOL)s { [self setSelectedRanges:r]; }
- (NSInteger)selectionAffinity { return 0; } - (NSInteger)selectionGranularity { return 0; } - (void)setSelectionGranularity:(NSInteger)g {}
- (void)setSelectedRange:(NSRange)r affinity:(NSInteger)a stillSelecting:(BOOL)still { [self _xefSelect:r notify:!still]; }
- (void)setSelectedRange:(NSRange)r { [self _xefSelect:r notify:YES]; }
- (void)_xefSelect:(NSRange)r notify:(BOOL)notify {
  NSUInteger len = [[self textStorage] length];
  if (r.location > len) r = NSMakeRange(len, 0);
  if (NSMaxRange(r) > len) r.length = len - r.location;
  if ([_tvDelegate respondsToSelector:@selector(textView:willChangeSelectionFromCharacterRange:toCharacterRange:)])
    r = ((NSRange (*)(id, SEL, id, NSRange, NSRange))objc_msgSend)(_tvDelegate, @selector(textView:willChangeSelectionFromCharacterRange:toCharacterRange:), self, _sel, r);
  NSRange old = _sel; _sel = r;
  if (len && !r.length) {   /* typing attributes follow the character before the caret */
    NSDictionary *a = [[self textStorage] attributesAtIndex:r.location ? r.location - 1 : 0 effectiveRange:NULL];
    if ([a count]) { NSMutableDictionary *t = [[a mutableCopy] autorelease]; [t removeObjectForKey:NSLinkAttributeName]; [self setTypingAttributes:t]; } }
  [self setNeedsDisplay:YES];
  if (notify && !NSEqualRanges(old, r)) {
    NSNotification *n = [NSNotification notificationWithName:NSTextViewDidChangeSelectionNotification object:self userInfo:@{ NSOldSelectedCharacterRange: [NSValue valueWithRange:old] }];
    if ([_tvDelegate respondsToSelector:@selector(textViewDidChangeSelection:)]) [_tvDelegate textViewDidChangeSelection:n];
    [[NSNotificationCenter defaultCenter] postNotification:n]; } }
- (void)selectAll:(id)s { _anchor = 0; [self setSelectedRange:NSMakeRange(0, [[self textStorage] length])]; }
- (void)selectLine:(id)s { [self setSelectedRange:[[self string] lineRangeForRange:_sel]]; }
- (void)selectParagraph:(id)s { [self setSelectedRange:[[self string] paragraphRangeForRange:_sel]]; }
- (void)selectWord:(id)s { [self setSelectedRange:[[self textStorage] doubleClickAtIndex:_sel.location]]; }
- (NSRange)selectionRangeForProposedRange:(NSRange)r granularity:(NSInteger)g { return r; }
- (void)scrollRangeToVisible:(NSRange)r {
  if (!_lm) return;
  NSRect c = [[_lm _xefLayout] caretRectAtIndex:NSMaxRange(r)];
  NSPoint o = [self textContainerOrigin];
  [self scrollRectToVisible:NSMakeRect(o.x + c.origin.x, o.y + c.origin.y, 2, c.size.height)]; }
/* editing primitives */
- (BOOL)shouldChangeTextInRange:(NSRange)r replacementString:(NSString *)s {
  if (!_editable) return NO;
  if ([_tvDelegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementString:)])
    return ((BOOL (*)(id, SEL, id, NSRange, id))objc_msgSend)(_tvDelegate, @selector(textView:shouldChangeTextInRange:replacementString:), self, r, s);
  return YES; }
- (BOOL)shouldChangeTextInRanges:(NSArray *)rs replacementStrings:(NSArray *)ss {
  return [self shouldChangeTextInRange:[[rs firstObject] rangeValue] replacementString:[ss firstObject]]; }
- (void)didChangeText {
  NSNotification *n = [NSNotification notificationWithName:NSTextDidChangeNotification object:self];
  if ([_tvDelegate respondsToSelector:@selector(textDidChange:)]) [_tvDelegate textDidChange:n];
  [[NSNotificationCenter defaultCenter] postNotification:n]; }
- (void)_xefTextChanged { [self didChangeText]; }
- (NSUndoManager *)undoManager {
  if ([_tvDelegate respondsToSelector:@selector(undoManagerForTextView:)]) return [_tvDelegate undoManagerForTextView:self];
  return [_window undoManager]; }
/* replaces a range with attributed text, registering the inverse with the undo manager */
- (void)_xefReplace:(NSRange)r with:(NSAttributedString *)as actionName:(NSString *)name {
  NSTextStorage *ts = [self textStorage];
  NSAttributedString *old = [[[ts attributedSubstringFromRange:r] copy] autorelease];
  NSRange oldSel = _sel;
  NSUndoManager *um = _allowsUndo ? [self undoManager] : nil;
  if (um) {
    BOOL group = [um groupingLevel] == 0;
    if (group) [um beginUndoGrouping];
    /* registerUndoWithTarget: (invocation-based undo needs -forwardInvocation:, unavailable here) */
    [um registerUndoWithTarget:self selector:@selector(_xefUndoWithInfo:) object:@{
      @"range": [NSValue valueWithRange:NSMakeRange(r.location, [as length])], @"text": old,
      @"selection": [NSValue valueWithRange:oldSel], @"name": name ?: @"" }];
    if (name) [um setActionName:name];
    if (group) [um endUndoGrouping]; }
  [ts replaceCharactersInRange:r withAttributedString:as];
  [self _xefSelect:NSMakeRange(r.location + [as length], 0) notify:YES];
  [self didChangeText];
  [self scrollRangeToVisible:_sel]; }
- (void)_xefUndoWithInfo:(NSDictionary *)i {
  NSString *name = [i objectForKey:@"name"];
  [self _xefReplace:[[i objectForKey:@"range"] rangeValue] with:[i objectForKey:@"text"] actionName:[name length] ? name : nil];
  [self setSelectedRange:[[i objectForKey:@"selection"] rangeValue]]; }
- (void)_xefInsertString:(NSString *)s {
  if (!_editable) return;
  NSRange r = _sel;
  if (![self shouldChangeTextInRange:r replacementString:s]) return;
  NSMutableDictionary *attrs = [[_typing mutableCopy] autorelease] ?: [NSMutableDictionary dictionary];
  if (![attrs objectForKey:NSFontAttributeName]) [attrs setObject:[NSFont userFontOfSize:12] forKey:NSFontAttributeName];
  if (_defaultPara && ![attrs objectForKey:NSParagraphStyleAttributeName]) [attrs setObject:_defaultPara forKey:NSParagraphStyleAttributeName];
  [self _xefReplace:r with:[[[NSAttributedString alloc] initWithString:s attributes:attrs] autorelease] actionName:@"Typing"];
  _goalX = -1; }
- (void)_xefDelete:(NSRange)r {
  if (!_editable || !r.length) return;
  if (![self shouldChangeTextInRange:r replacementString:@""]) return;
  [self _xefReplace:r with:[[[NSAttributedString alloc] init] autorelease] actionName:@"Delete"];
  _goalX = -1; }
/* NSTextInputClient */
- (void)insertText:(id)s replacementRange:(NSRange)rr {
  if (rr.location != NSNotFound) _sel = rr;
  [self _xefInsertString:[s isKindOfClass:[NSAttributedString class]] ? [s string] : s]; }
- (BOOL)hasMarkedText { return NO; } - (NSRange)markedRange { return NSMakeRange(NSNotFound, 0); } - (void)unmarkText {}
- (void)setMarkedText:(id)s selectedRange:(NSRange)sr replacementRange:(NSRange)rr { [self insertText:s replacementRange:rr]; }
- (NSArray *)validAttributesForMarkedText { return @[]; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)r actualRange:(NSRangePointer)a {
  NSUInteger len = [[self textStorage] length]; if (r.location > len) return nil; if (NSMaxRange(r) > len) r.length = len - r.location;
  if (a) *a = r; return [[self textStorage] attributedSubstringFromRange:r]; }
- (NSUInteger)characterIndexForPoint:(NSPoint)p { return [self _xefIndexAtPoint:[self convertPoint:[[self window] convertPointFromScreen:p] fromView:nil]]; }
- (NSUInteger)characterIndexForInsertionAtPoint:(NSPoint)p { return [self _xefIndexAtPoint:p]; }
- (NSRect)firstRectForCharacterRange:(NSRange)r actualRange:(NSRangePointer)a { if (a) *a = r; return NSZeroRect; }
- (NSAttributedString *)attributedString { return [self textStorage]; }
- (CGFloat)baselineDeltaForCharacterAtIndex:(NSUInteger)i { return 0; }
- (NSInteger)windowLevel { return 0; }
- (BOOL)drawsVerticallyForCharacterAtIndex:(NSUInteger)i { return NO; }
/* key handling: modifier-aware movement on top of -interpretKeyEvents: */
- (BOOL)acceptsFirstResponder { return _selectable; }
- (BOOL)becomeFirstResponder {
  [self setNeedsDisplay:YES];
  if (_editable) [[NSNotificationCenter defaultCenter] postNotificationName:NSTextDidBeginEditingNotification object:self];
  return YES; }
- (BOOL)resignFirstResponder {
  if ([_tvDelegate respondsToSelector:@selector(textShouldEndEditing:)] && ![_tvDelegate textShouldEndEditing:self]) return NO;
  [self setNeedsDisplay:YES];
  NSNotification *n = [NSNotification notificationWithName:NSTextDidEndEditingNotification object:self];
  if ([_tvDelegate respondsToSelector:@selector(textDidEndEditing:)]) [_tvDelegate textDidEndEditing:n];
  [[NSNotificationCenter defaultCenter] postNotification:n];
  return YES; }
- (void)keyDown:(NSEvent *)e {
  NSUInteger f = [e modifierFlags]; unsigned short k = [e keyCode];
  BOOL shift = (f & NSEventModifierFlagShift) != 0, word = (f & (NSEventModifierFlagOption | NSEventModifierFlagControl)) != 0, cmd = (f & NSEventModifierFlagCommand) != 0;
  SEL s = NULL;
  switch (k) {
  case 123: s = cmd ? (shift ? @selector(moveToBeginningOfLineAndModifySelection:) : @selector(moveToBeginningOfLine:)) : word ? (shift ? @selector(moveWordLeftAndModifySelection:) : @selector(moveWordLeft:)) : (shift ? @selector(moveLeftAndModifySelection:) : @selector(moveLeft:)); break;
  case 124: s = cmd ? (shift ? @selector(moveToEndOfLineAndModifySelection:) : @selector(moveToEndOfLine:)) : word ? (shift ? @selector(moveWordRightAndModifySelection:) : @selector(moveWordRight:)) : (shift ? @selector(moveRightAndModifySelection:) : @selector(moveRight:)); break;
  case 126: s = (cmd || word) ? (shift ? @selector(moveToBeginningOfDocumentAndModifySelection:) : @selector(moveToBeginningOfDocument:)) : (shift ? @selector(moveUpAndModifySelection:) : @selector(moveUp:)); break;
  case 125: s = (cmd || word) ? (shift ? @selector(moveToEndOfDocumentAndModifySelection:) : @selector(moveToEndOfDocument:)) : (shift ? @selector(moveDownAndModifySelection:) : @selector(moveDown:)); break;
  case 115: s = shift ? @selector(moveToBeginningOfLineAndModifySelection:) : @selector(moveToBeginningOfLine:); break;
  case 119: s = shift ? @selector(moveToEndOfLineAndModifySelection:) : @selector(moveToEndOfLine:); break;
  case 51: s = word ? @selector(deleteWordBackward:) : @selector(deleteBackward:); break;
  case 117: s = word ? @selector(deleteWordForward:) : @selector(deleteForward:); break;
  default: break; }
  if (s) { [self doCommandBySelector:s]; return; }
  if (cmd || ((f & NSEventModifierFlagControl) && ![[e characters] length])) { [super keyDown:e]; return; }
  [self interpretKeyEvents:@[e]]; }
- (void)doCommandBySelector:(SEL)s {
  if ([_tvDelegate respondsToSelector:@selector(textView:doCommandBySelector:)] &&
      ((BOOL (*)(id, SEL, id, SEL))objc_msgSend)(_tvDelegate, @selector(textView:doCommandBySelector:), self, s)) return;
  if ([self respondsToSelector:s]) ((void (*)(id, SEL, id))objc_msgSend)(self, s, nil);
  else [super doCommandBySelector:s]; }
- (void)insertNewline:(id)s { if (_fieldEditor) { [_window makeFirstResponder:_window]; return; } [self _xefInsertString:@"\n"]; }
- (void)insertNewlineIgnoringFieldEditor:(id)s { [self _xefInsertString:@"\n"]; }
- (void)insertLineBreak:(id)s { [self _xefInsertString:@" "]; }
- (void)insertParagraphSeparator:(id)s { [self insertNewline:s]; }
- (void)insertTab:(id)s { if (_fieldEditor) [_window selectNextKeyView:self]; else [self _xefInsertString:@"\t"]; }
- (void)insertTabIgnoringFieldEditor:(id)s { [self _xefInsertString:@"\t"]; }
- (void)insertBacktab:(id)s { [_window selectPreviousKeyView:self]; }
- (void)cancelOperation:(id)s {}
- (void)deleteBackward:(id)s { if (_sel.length) [self _xefDelete:_sel]; else if (_sel.location) { NSRange r = [[self string] rangeOfComposedCharacterSequenceAtIndex:_sel.location - 1]; [self _xefDelete:r]; } }
- (void)deleteForward:(id)s { if (_sel.length) [self _xefDelete:_sel]; else if (_sel.location < [[self textStorage] length]) [self _xefDelete:[[self string] rangeOfComposedCharacterSequenceAtIndex:_sel.location]]; }
- (void)deleteWordBackward:(id)s { if (_sel.length) { [self _xefDelete:_sel]; return; } NSUInteger a = [[self textStorage] nextWordFromIndex:_sel.location forward:NO]; [self _xefDelete:NSMakeRange(a, _sel.location - a)]; }
- (void)deleteWordForward:(id)s { if (_sel.length) { [self _xefDelete:_sel]; return; } NSUInteger b = [[self textStorage] nextWordFromIndex:_sel.location forward:YES]; [self _xefDelete:NSMakeRange(_sel.location, b - _sel.location)]; }
- (void)deleteToBeginningOfLine:(id)s { NSRange l = [[self string] lineRangeForRange:NSMakeRange(_sel.location, 0)]; [self _xefDelete:NSMakeRange(l.location, _sel.location - l.location)]; }
- (void)deleteToEndOfLine:(id)s { NSUInteger e = [self _xefLineEnd:_sel.location]; [self _xefDelete:NSMakeRange(_sel.location, e - _sel.location)]; }
- (void)deleteToEndOfParagraph:(id)s { [self deleteToEndOfLine:s]; }
- (void)delete:(id)s { [self _xefDelete:_sel]; }
/* movement */
- (NSUInteger)_xefLineEnd:(NSUInteger)i {
  NSString *str = [self string]; NSRange l = [str lineRangeForRange:NSMakeRange(i, 0)];
  NSUInteger e = NSMaxRange(l); if (e > l.location && e <= [str length] && [str characterAtIndex:e - 1] == '\n') e--; return e; }
- (void)_xefMoveTo:(NSUInteger)i extend:(BOOL)ext {
  NSUInteger len = [[self textStorage] length]; if (i > len) i = len;
  if (!ext) { _anchor = i; [self setSelectedRange:NSMakeRange(i, 0)]; }
  else [self setSelectedRange:i < _anchor ? NSMakeRange(i, _anchor - i) : NSMakeRange(_anchor, i - _anchor)];
  [self scrollRangeToVisible:NSMakeRange(i, 0)]; }
- (NSUInteger)_xefFocus { return _sel.location == _anchor ? NSMaxRange(_sel) : _sel.location; }
- (void)moveLeft:(id)s { if (_sel.length) [self _xefMoveTo:_sel.location extend:NO]; else [self _xefMoveTo:_sel.location ? _sel.location - 1 : 0 extend:NO]; _goalX = -1; }
- (void)moveRight:(id)s { if (_sel.length) [self _xefMoveTo:NSMaxRange(_sel) extend:NO]; else [self _xefMoveTo:_sel.location + 1 extend:NO]; _goalX = -1; }
- (void)moveBackward:(id)s { [self moveLeft:s]; } - (void)moveForward:(id)s { [self moveRight:s]; }
- (void)moveLeftAndModifySelection:(id)s { NSUInteger f = [self _xefFocus]; [self _xefMoveTo:f ? f - 1 : 0 extend:YES]; }
- (void)moveRightAndModifySelection:(id)s { [self _xefMoveTo:[self _xefFocus] + 1 extend:YES]; }
- (void)moveWordLeft:(id)s { [self _xefMoveTo:[[self textStorage] nextWordFromIndex:_sel.location forward:NO] extend:NO]; }
- (void)moveWordRight:(id)s { [self _xefMoveTo:[[self textStorage] nextWordFromIndex:NSMaxRange(_sel) forward:YES] extend:NO]; }
- (void)moveWordLeftAndModifySelection:(id)s { [self _xefMoveTo:[[self textStorage] nextWordFromIndex:[self _xefFocus] forward:NO] extend:YES]; }
- (void)moveWordRightAndModifySelection:(id)s { [self _xefMoveTo:[[self textStorage] nextWordFromIndex:[self _xefFocus] forward:YES] extend:YES]; }
- (void)moveWordBackward:(id)s { [self moveWordLeft:s]; } - (void)moveWordForward:(id)s { [self moveWordRight:s]; }
- (NSUInteger)_xefVertical:(NSInteger)dir from:(NSUInteger)i {
  XEFTextLayout *l = [_lm _xefLayout]; NSRect c = [l caretRectAtIndex:i];
  if (_goalX < 0) _goalX = c.origin.x;
  CGFloat y = dir < 0 ? c.origin.y - 1 : NSMaxY(c) + 1;
  if (y < 0) return 0;
  if (y >= [l size].height) return [[self textStorage] length];
  return [l characterIndexAtPoint:NSMakePoint(_goalX, y)]; }
- (void)moveUp:(id)s { CGFloat g = _goalX; NSUInteger i = [self _xefVertical:-1 from:_sel.location]; [self _xefMoveTo:i extend:NO]; _goalX = g < 0 ? _goalX : g; }
- (void)moveDown:(id)s { CGFloat g = _goalX; NSUInteger i = [self _xefVertical:1 from:NSMaxRange(_sel)]; [self _xefMoveTo:i extend:NO]; _goalX = g < 0 ? _goalX : g; }
- (void)moveUpAndModifySelection:(id)s { [self _xefMoveTo:[self _xefVertical:-1 from:[self _xefFocus]] extend:YES]; }
- (void)moveDownAndModifySelection:(id)s { [self _xefMoveTo:[self _xefVertical:1 from:[self _xefFocus]] extend:YES]; }
- (void)moveToBeginningOfLine:(id)s { [self _xefMoveTo:[[self string] lineRangeForRange:NSMakeRange(_sel.location, 0)].location extend:NO]; _goalX = -1; }
- (void)moveToEndOfLine:(id)s { [self _xefMoveTo:[self _xefLineEnd:NSMaxRange(_sel)] extend:NO]; _goalX = -1; }
- (void)moveToBeginningOfLineAndModifySelection:(id)s { [self _xefMoveTo:[[self string] lineRangeForRange:NSMakeRange([self _xefFocus], 0)].location extend:YES]; }
- (void)moveToEndOfLineAndModifySelection:(id)s { [self _xefMoveTo:[self _xefLineEnd:[self _xefFocus]] extend:YES]; }
- (void)moveToLeftEndOfLine:(id)s { [self moveToBeginningOfLine:s]; } - (void)moveToRightEndOfLine:(id)s { [self moveToEndOfLine:s]; }
- (void)moveToBeginningOfParagraph:(id)s { [self moveToBeginningOfLine:s]; } - (void)moveToEndOfParagraph:(id)s { [self moveToEndOfLine:s]; }
- (void)moveToBeginningOfDocument:(id)s { [self _xefMoveTo:0 extend:NO]; }
- (void)moveToEndOfDocument:(id)s { [self _xefMoveTo:[[self textStorage] length] extend:NO]; }
- (void)moveToBeginningOfDocumentAndModifySelection:(id)s { [self _xefMoveTo:0 extend:YES]; }
- (void)moveToEndOfDocumentAndModifySelection:(id)s { [self _xefMoveTo:[[self textStorage] length] extend:YES]; }
- (void)pageUp:(id)s { [self moveToBeginningOfDocument:s]; } - (void)pageDown:(id)s { [self moveToEndOfDocument:s]; }
- (void)scrollPageUp:(id)s { [self pageUp:s]; } - (void)scrollPageDown:(id)s { [self pageDown:s]; }
- (void)scrollToBeginningOfDocument:(id)s { [self scrollRangeToVisible:NSMakeRange(0, 0)]; }
- (void)scrollToEndOfDocument:(id)s { [self scrollRangeToVisible:NSMakeRange([[self textStorage] length], 0)]; }
- (void)centerSelectionInVisibleArea:(id)s { [self scrollRangeToVisible:_sel]; }
- (void)transpose:(id)s {}
- (void)capitalizeWord:(id)s {} - (void)uppercaseWord:(id)s {} - (void)lowercaseWord:(id)s {}
/* pasteboard */
- (void)copy:(id)s {
  if (!_sel.length) return;
  NSPasteboard *p = [NSPasteboard generalPasteboard]; [p clearContents];
  [p setString:[[self string] substringWithRange:_sel] forType:NSPasteboardTypeString];
  NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:[[self textStorage] attributedSubstringFromRange:_sel] requiringSecureCoding:NO error:NULL];
  if (archived) [p setData:archived forType:@"com.apple.xef.attributed-string"]; }
- (void)cut:(id)s { if (_editable && _sel.length) { [self copy:s]; [self _xefDelete:_sel]; } }
- (void)paste:(id)s {
  if (!_editable) return;
  NSPasteboard *p = [NSPasteboard generalPasteboard];
  NSData *d = _rich ? [p dataForType:@"com.apple.xef.attributed-string"] : nil;
  NSAttributedString *as = d ? [NSKeyedUnarchiver unarchiveObjectWithData:d] : nil;
  if ([as isKindOfClass:[NSAttributedString class]] && [as length]) {
    if ([self shouldChangeTextInRange:_sel replacementString:[as string]]) [self _xefReplace:_sel with:as actionName:@"Paste"];
    return; }
  NSString *t = [p stringForType:NSPasteboardTypeString];
  if (t) [self _xefInsertString:t]; }
- (void)pasteAsPlainText:(id)s { NSString *t = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]; if (t) [self _xefInsertString:t]; }
- (void)pasteAsRichText:(id)s { [self paste:s]; }
- (void)copyFont:(id)s {} - (void)pasteFont:(id)s {} - (void)copyRuler:(id)s {} - (void)pasteRuler:(id)s {}
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)p type:(NSString *)t { if (!_sel.length) return NO; return [p setString:[[self string] substringWithRange:_sel] forType:t]; }
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)p { NSString *t = [p stringForType:NSPasteboardTypeString]; if (!t) return NO; [self _xefInsertString:t]; return YES; }
- (void)undo:(id)s { [[self undoManager] undo]; } - (void)redo:(id)s { [[self undoManager] redo]; }
/* attribute actions (Format menu) */
- (void)_xefApply:(NSString *)n value:(id)v {
  NSRange r = [self rangeForUserCharacterAttributeChange];
  if (r.location == NSNotFound) return;
  if (r.length) {
    NSTextStorage *ts = [self textStorage];
    NSAttributedString *old = [[[ts attributedSubstringFromRange:r] copy] autorelease];
    NSMutableAttributedString *nw = [[old mutableCopy] autorelease];
    if (v) [nw addAttribute:n value:v range:NSMakeRange(0, [nw length])]; else [nw removeAttribute:n range:NSMakeRange(0, [nw length])];
    NSRange sel = _sel;
    [self _xefReplace:r with:nw actionName:@"Format"];
    [self setSelectedRange:sel]; }
  [self _xefSetTyping:n value:v]; }
- (void)underline:(id)s { NSNumber *u = [self _xefAttr:NSUnderlineStyleAttributeName]; [self _xefApply:NSUnderlineStyleAttributeName value:[u integerValue] ? nil : @1]; }
- (void)alignLeft:(id)s { [self _xefAlign:0]; } - (void)alignCenter:(id)s { [self _xefAlign:1]; }
- (void)alignRight:(id)s { [self _xefAlign:2]; } - (void)alignJustified:(id)s { [self _xefAlign:3]; } - (void)alignNatural:(id)s { [self _xefAlign:4]; }
- (void)_xefAlign:(NSInteger)a {
  NSRange r = [self rangeForUserParagraphAttributeChange]; if (r.location == NSNotFound) return;
  NSMutableParagraphStyle *p = [[([self _xefAttr:NSParagraphStyleAttributeName] ?: [NSParagraphStyle defaultParagraphStyle]) mutableCopy] autorelease];
  [p setAlignment:a];
  NSRange sel = _sel; NSRange osel = _sel; _sel = r;
  [self _xefApply:NSParagraphStyleAttributeName value:p];
  _sel = osel; [self setSelectedRange:sel]; }
- (void)changeFont:(id)sender {
  NSFontManager *fm = [sender isKindOfClass:[NSFontManager class]] ? sender : [NSFontManager sharedFontManager];
  NSRange r = [self rangeForUserCharacterAttributeChange];
  if (r.location == NSNotFound) return;
  if (!r.length) { [self _xefSetTyping:NSFontAttributeName value:[fm convertFont:[self _xefAttr:NSFontAttributeName] ?: [NSFont userFontOfSize:12]]]; return; }
  NSTextStorage *ts = [self textStorage];
  NSMutableAttributedString *nw = [[[ts attributedSubstringFromRange:r] mutableCopy] autorelease];
  [nw enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, [nw length]) options:0 usingBlock:^(id f, NSRange rr, BOOL *stop) {
    [nw addAttribute:NSFontAttributeName value:[fm convertFont:f ?: [NSFont userFontOfSize:12]] range:rr]; }];
  NSRange sel = _sel;
  [self _xefReplace:r with:nw actionName:@"Font"];
  [self setSelectedRange:sel]; }
- (void)changeColor:(id)sender { if ([sender respondsToSelector:@selector(color)]) [self _xefApply:NSForegroundColorAttributeName value:[sender color]]; }
- (void)changeAttributes:(id)s {} - (void)changeDocumentBackgroundColor:(id)s {}
- (void)useStandardKerning:(id)s {} - (void)turnOffKerning:(id)s {} - (void)loosenKerning:(id)s {} - (void)tightenKerning:(id)s {}
- (void)useStandardLigatures:(id)s {} - (void)turnOffLigatures:(id)s {} - (void)useAllLigatures:(id)s {}
- (void)raiseBaseline:(id)s {} - (void)lowerBaseline:(id)s {} - (void)superscript:(id)s {} - (void)subscript:(id)s {} - (void)unscript:(id)s {}
- (void)makeBaseWritingDirectionNatural:(id)s {} - (void)makeBaseWritingDirectionLeftToRight:(id)s {} - (void)makeBaseWritingDirectionRightToLeft:(id)s {}
- (void)makeTextWritingDirectionNatural:(id)s {} - (void)makeTextWritingDirectionLeftToRight:(id)s {} - (void)makeTextWritingDirectionRightToLeft:(id)s {}
- (void)orderFrontSpacingPanel:(id)s {} - (void)orderFrontLinkPanel:(id)s {} - (void)orderFrontListPanel:(id)s {} - (void)orderFrontTablePanel:(id)s {}
- (void)orderFrontSubstitutionsPanel:(id)s {}
- (BOOL)validateMenuItem:(NSMenuItem *)i { return [self validateUserInterfaceItem:(id)i]; }
- (BOOL)validateUserInterfaceItem:(id)i {
  SEL a = [i action];
  if (a == @selector(copy:)) return _sel.length > 0;
  if (a == @selector(cut:) || a == @selector(delete:)) return _editable && _sel.length > 0;
  if (a == @selector(paste:) || a == @selector(pasteAsPlainText:)) return _editable && [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] != nil;
  if (a == @selector(undo:)) return [[self undoManager] canUndo];
  if (a == @selector(redo:)) return [[self undoManager] canRedo];
  if (a == @selector(underline:) || a == @selector(changeFont:) || a == @selector(alignLeft:) || a == @selector(alignCenter:) || a == @selector(alignRight:) || a == @selector(alignJustified:)) return _editable;
  return [self respondsToSelector:a]; }
/* mouse */
- (NSUInteger)_xefIndexAtPoint:(NSPoint)p {
  NSPoint o = [self textContainerOrigin];
  return [_lm characterIndexForPoint:NSMakePoint(p.x - o.x, p.y - o.y) inTextContainer:_tc fractionOfDistanceBetweenInsertionPoints:NULL]; }
- (void)mouseDown:(NSEvent *)e {
  if (!_selectable) { [super mouseDown:e]; return; }
  if ([_window firstResponder] != self) [_window makeFirstResponder:self];
  NSUInteger i = [self _xefIndexAtPoint:[self convertPoint:[e locationInWindow] fromView:nil]];
  NSInteger clicks = [e clickCount];
  NSRange base;
  if (clicks >= 3) base = [[self string] paragraphRangeForRange:NSMakeRange(i, 0)];
  else if (clicks == 2) base = [[self textStorage] doubleClickAtIndex:i];
  else if ([e modifierFlags] & NSEventModifierFlagShift) { NSUInteger a = _anchor; base = i < a ? NSMakeRange(i, a - i) : NSMakeRange(a, i - a); [self setSelectedRange:base]; XEFRedrawWindowNow(_window); return; }
  else base = NSMakeRange(i, 0);
  _anchor = base.location; _goalX = -1;
  [self setSelectedRange:base affinity:0 stillSelecting:YES];
  XEFRedrawWindowNow(_window);
  for (;;) {
    NSEvent *n = XEFNextTrackingEvent(); if (!n) continue;
    if ([n type] == NSEventTypeLeftMouseUp) break;
    NSUInteger j = [self _xefIndexAtPoint:[self convertPoint:[n locationInWindow] fromView:nil]];
    NSRange r = j < base.location ? NSMakeRange(j, NSMaxRange(base) - j) : NSMakeRange(base.location, MAX(j, NSMaxRange(base)) - base.location);
    [self setSelectedRange:r affinity:0 stillSelecting:YES];
    [self scrollRangeToVisible:NSMakeRange(j, 0)];
    XEFRedrawWindowNow(_window); }
  NSRange fin = _sel; _sel = NSMakeRange(NSNotFound, 0);
  [self setSelectedRange:fin];
  if ([_tvDelegate respondsToSelector:@selector(textView:clickedOnLink:atIndex:)] && !fin.length && fin.location < [[self textStorage] length]) {
    id link = [[self textStorage] attribute:NSLinkAttributeName atIndex:fin.location effectiveRange:NULL];
    if (link) ((BOOL (*)(id, SEL, id, id, NSUInteger))objc_msgSend)(_tvDelegate, @selector(textView:clickedOnLink:atIndex:), self, link, fin.location); } }
- (void)clickedOnLink:(id)l atIndex:(NSUInteger)i {}
/* drawing */
- (BOOL)isOpaque { return _drawsBg; }
- (void)drawViewBackgroundInRect:(NSRect)r { if (_drawsBg && _bgColor) { [_bgColor setFill]; NSRectFillUsingOperation(r, 2); } }
- (void)drawInsertionPointInRect:(NSRect)r color:(NSColor *)c turnedOn:(BOOL)on { if (on) { [c setFill]; NSRectFill(r); } }
- (BOOL)shouldDrawInsertionPoint { return _editable && [_window firstResponder] == self && [_window isKeyWindow]; }
- (void)drawRect:(NSRect)r {
  [self drawViewBackgroundInRect:_bounds];
  if (!_lm) return;
  NSPoint o = [self textContainerOrigin];
  if (_sel.length && _sel.location != NSNotFound) {
    NSColor *hl = [[self selectedTextAttributes] objectForKey:NSBackgroundColorAttributeName] ?: [NSColor selectedTextBackgroundColor];
    if ([_window firstResponder] != self) hl = [NSColor unemphasizedSelectedTextBackgroundColor];
    NSRect rects[3]; NSUInteger n = [_lm _xefRects:rects max:3 forRange:_sel];
    [hl setFill];
    for (NSUInteger k = 0; k < n; k++) NSRectFillUsingOperation(NSOffsetRect(rects[k], o.x, o.y), 2); }
  [_lm drawBackgroundForGlyphRange:NSMakeRange(0, [[self textStorage] length]) atPoint:o];
  [_lm drawGlyphsForGlyphRange:NSMakeRange(0, [[self textStorage] length]) atPoint:o];
  if (!_sel.length && _sel.location != NSNotFound && [self shouldDrawInsertionPoint]) {
    NSRect c = [[_lm _xefLayout] caretRectAtIndex:_sel.location];
    if (c.size.height <= 0) c.size.height = [_lm defaultLineHeightForFont:[_typing objectForKey:NSFontAttributeName] ?: [NSFont userFontOfSize:12]];
    [self drawInsertionPointInRect:NSMakeRect(o.x + [_tc lineFragmentPadding] + c.origin.x, o.y + c.origin.y, 1, c.size.height) color:_insertionColor ?: [NSColor textColor] turnedOn:YES]; } }
- (NSMenu *)menuForEvent:(NSEvent *)e { return [self menu]; }
@end

/* ================================================================== NSFontManager */
enum { kItalic = 1, kBold = 2, kUnbold = 4, kNonStandard = 8, kNarrow = 0x10, kExpanded = 0x20, kCondensed = 0x40, kSmallCaps = 0x80,
       kPoster = 0x100, kCompressed = 0x200, kFixedPitch = 0x400, kUnitalic = 0x01000000 };
static NSString *font_with_style(NSFont *f, BOOL bold, BOOL italic) {
  NSString *base = [[[f fontName] componentsSeparatedByString:@"-"] objectAtIndex:0];
  if ([base hasPrefix:@".AppleSystemUIFont"]) base = @".AppleSystemUIFont";
  if ([base hasPrefix:@"."]) return bold ? (italic ? @".AppleSystemUIFontBoldItalic" : @".AppleSystemUIFontBold") : (italic ? @".AppleSystemUIFontItalic" : @".AppleSystemUIFont");
  if (!bold && !italic) return base;
  return [NSString stringWithFormat:@"%@-%@%@", base, bold ? @"Bold" : @"", italic ? @"Italic" : @""]; }

@implementation NSFontManager
+ (NSFontManager *)sharedFontManager { static NSFontManager *m; if (!m) m = [[NSFontManager alloc] init]; return m; }
+ (void)setFontManagerFactory:(Class)c {} + (void)setFontPanelFactory:(Class)c {}
- (id)init { if ((self = [super init])) _action = @selector(changeFont:); return self; }
- (id)target { return _target; } - (void)setTarget:(id)t { _target = t; }
- (SEL)action { return _action; } - (void)setAction:(SEL)a { _action = a; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSFont *)selectedFont { return _selected; }
- (void)setSelectedFont:(NSFont *)f isMultiple:(BOOL)m { [f retain]; [_selected release]; _selected = f; }
- (BOOL)isMultiple { return NO; }
- (void)setSelectedAttributes:(NSDictionary *)a isMultiple:(BOOL)m {}
- (NSUInteger)traitsOfFont:(NSFont *)f { NSUInteger t = 0; if ([f _xefWeight] >= 600) t |= kBold; if ([f _xefItalic]) t |= kItalic; if ([f isFixedPitch]) t |= kFixedPitch; return t; }
- (NSInteger)weightOfFont:(NSFont *)f { return [f _xefWeight] >= 600 ? 9 : 5; }
- (BOOL)fontNamed:(NSString *)n hasTraits:(NSUInteger)t { return ([self traitsOfFont:[NSFont fontWithName:n size:12]] & t) == t; }
- (NSFont *)convertFont:(NSFont *)f toHaveTrait:(NSUInteger)t {
  if (!f) return nil;
  NSUInteger cur = [self traitsOfFont:f];
  BOOL bold = (cur & kBold) != 0, italic = (cur & kItalic) != 0;
  if (t & kBold) bold = YES; if (t & kUnbold) bold = NO; if (t & kItalic) italic = YES; if (t & kUnitalic) italic = NO;
  return [NSFont fontWithName:font_with_style(f, bold, italic) size:[f pointSize]]; }
- (NSFont *)convertFont:(NSFont *)f toNotHaveTrait:(NSUInteger)t {
  NSUInteger m = 0; if (t & kBold) m |= kUnbold; if (t & kItalic) m |= kUnitalic; return [self convertFont:f toHaveTrait:m]; }
- (NSFont *)convertFont:(NSFont *)f toSize:(CGFloat)s { return f ? [NSFont fontWithName:[f fontName] size:s] : nil; }
- (NSFont *)convertFont:(NSFont *)f toFamily:(NSString *)fam {
  NSUInteger t = [self traitsOfFont:f]; NSFont *b = [NSFont fontWithName:fam size:[f pointSize]];
  return [self convertFont:b toHaveTrait:t & (kBold | kItalic)]; }
- (NSFont *)convertFont:(NSFont *)f toFace:(NSString *)face { return [NSFont fontWithName:face size:[f pointSize]] ?: f; }
- (NSFont *)convertWeight:(BOOL)up ofFont:(NSFont *)f { return [self convertFont:f toHaveTrait:up ? kBold : kUnbold]; }
/* conversion requested by the last font action */
- (NSFont *)convertFont:(NSFont *)f {
  if (_pendingAction == 1) return [self convertFont:f toHaveTrait:_pendingTrait];
  if (_pendingAction == 2) return [self convertFont:f toNotHaveTrait:_pendingTrait];
  if (_pendingAction == 3) return [self convertFont:f toSize:[f pointSize] + 1];
  if (_pendingAction == 4) return [self convertFont:f toSize:fmax(1, [f pointSize] - 1)];
  if (_pendingAction == 7 && _selected) return [self convertFont:f toSize:[_selected pointSize]];
  return _selected ?: f; }
- (void)_xefSend { [NSApp sendAction:_action to:_target from:self]; _pendingAction = 0; }
- (void)addFontTrait:(id)s {
  NSInteger tag = [s respondsToSelector:@selector(tag)] ? [s tag] : 0;
  NSFont *cur = [[[NSApp keyWindow] firstResponder] respondsToSelector:@selector(font)] ? [(id)[[NSApp keyWindow] firstResponder] font] : nil;
  _pendingTrait = tag;
  /* toggles like the Format > Font > Bold/Italic items: remove a trait the selection already has */
  _pendingAction = (cur && ([self traitsOfFont:cur] & tag) == (NSUInteger)tag && (tag & (kBold | kItalic))) ? 2 : 1;
  [self _xefSend]; }
- (void)removeFontTrait:(id)s { _pendingTrait = [s respondsToSelector:@selector(tag)] ? [s tag] : 0; _pendingAction = 2; [self _xefSend]; }
- (void)modifyFont:(id)s { NSInteger tag = [s respondsToSelector:@selector(tag)] ? [s tag] : 0; _pendingAction = tag == 3 ? 3 : tag == 4 ? 4 : tag == 5 ? 1 : tag == 6 ? 2 : 0; _pendingTrait = kBold; [self _xefSend]; }
- (void)modifyFontViaPanel:(id)s { _pendingAction = 0; [self _xefSend]; }
- (void)orderFrontFontPanel:(id)s { NSLog(@"xef: the font panel is not available"); }
- (void)orderFrontStylesPanel:(id)s {}
- (id)fontPanel:(BOOL)create { return nil; }
- (NSArray *)availableFonts { return @[@"Helvetica", @"Helvetica-Bold", @"Times-Roman", @"Courier", @"Menlo-Regular", @"MarkerFelt-Thin"]; }
- (NSArray *)availableFontFamilies { return @[@"Helvetica", @"Times", @"Courier", @"Menlo", @"Marker Felt"]; }
- (NSArray *)availableMembersOfFontFamily:(NSString *)f { return @[@[f, @"Regular", @5, @0], @[[f stringByAppendingString:@"-Bold"], @"Bold", @9, @2]]; }
- (NSArray *)availableFontNamesWithTraits:(NSUInteger)t { return [self availableFonts]; }
- (NSFont *)fontWithFamily:(NSString *)fam traits:(NSUInteger)t weight:(NSInteger)w size:(CGFloat)s {
  return [self convertFont:[NSFont fontWithName:fam size:s] toHaveTrait:(t & (kBold | kItalic)) | (w >= 8 ? kBold : 0)]; }
- (NSString *)localizedNameForFamily:(NSString *)f face:(NSString *)face { return face ? [NSString stringWithFormat:@"%@ %@", f, face] : f; }
- (BOOL)sendAction { [self _xefSend]; return YES; }
- (NSInteger)currentFontAction { return _pendingAction; }
- (NSMenu *)fontMenu:(BOOL)create { return nil; } - (void)setFontMenu:(NSMenu *)m {}
- (BOOL)isEnabled { return YES; } - (void)setEnabled:(BOOL)f {}
@end

@implementation NSFontPanel
+ (NSFontPanel *)sharedFontPanel { return nil; }
+ (BOOL)sharedFontPanelExists { return NO; }
@end
@implementation NSColorPanel
+ (NSColorPanel *)sharedColorPanel { return nil; }
+ (BOOL)sharedColorPanelExists { return NO; }
+ (void)setPickerMask:(NSUInteger)m {} + (void)setPickerMode:(NSInteger)m {}
@end
