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
  _layout = [[XEFTextLayout alloc] initWithAttributedString:[self _xefDisplayString] ?: [[[NSAttributedString alloc] init] autorelease] width:w];
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
/* temporary attributes: a shadow attributed string of the storage's length holds them; layout and drawing use the storage with them applied */
- (NSMutableAttributedString *)_xefTemp {
  NSMutableAttributedString *t = objc_getAssociatedObject(self, "xef.temp"); NSUInteger n = [_storage length];
  if (!t) { t = [[[NSMutableAttributedString alloc] initWithString:@""] autorelease]; objc_setAssociatedObject(self, "xef.temp", t, OBJC_ASSOCIATION_RETAIN); }
  if ([t length] < n) [t replaceCharactersInRange:NSMakeRange([t length], 0) withString:[@"" stringByPaddingToLength:n - [t length] withString:@" " startingAtIndex:0]];
  else if ([t length] > n) [t deleteCharactersInRange:NSMakeRange(n, [t length] - n)];
  return t; }
- (NSAttributedString *)_xefDisplayString {
  if (!objc_getAssociatedObject(self, "xef.hasTemp") || !_storage) return _storage;
  NSMutableAttributedString *t = [self _xefTemp]; NSMutableAttributedString *r = [[[NSMutableAttributedString alloc] initWithAttributedString:_storage] autorelease];
  [t enumerateAttributesInRange:NSMakeRange(0, [t length]) options:0 usingBlock:^(NSDictionary *a, NSRange rg, BOOL *stop) { if ([a count]) [r addAttributes:a range:rg]; }];
  return r; }
- (void)_xefTempChanged { objc_setAssociatedObject(self, "xef.hasTemp", @YES, OBJC_ASSOCIATION_RETAIN); [self _xefInvalidate]; for (NSTextContainer *c in _containers) [[c textView] setNeedsDisplay:YES]; }
- (NSRange)_xefClip:(NSRange)r { NSUInteger n = [_storage length]; if (r.location > n) return NSMakeRange(n, 0); if (NSMaxRange(r) > n) r.length = n - r.location; return r; }
- (void)addTemporaryAttribute:(NSString *)n value:(id)v forCharacterRange:(NSRange)r { r = [self _xefClip:r]; if (!r.length || !n || !v) return; [[self _xefTemp] addAttribute:n value:v range:r]; [self _xefTempChanged]; }
- (void)addTemporaryAttributes:(NSDictionary *)a forCharacterRange:(NSRange)r { r = [self _xefClip:r]; if (!r.length) return; [[self _xefTemp] addAttributes:a range:r]; [self _xefTempChanged]; }
- (void)setTemporaryAttributes:(NSDictionary *)a forCharacterRange:(NSRange)r { r = [self _xefClip:r]; if (!r.length) return; [[self _xefTemp] setAttributes:a range:r]; [self _xefTempChanged]; }
- (void)removeTemporaryAttribute:(NSString *)n forCharacterRange:(NSRange)r { r = [self _xefClip:r]; if (!r.length) return; [[self _xefTemp] removeAttribute:n range:r]; [self _xefTempChanged]; }
- (NSDictionary *)temporaryAttributesAtCharacterIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r {
  NSMutableAttributedString *t = [self _xefTemp]; if (i >= [t length]) { if (r) *r = NSMakeRange([t length], 0); return nil; }
  return [t attributesAtIndex:i effectiveRange:r]; }
- (NSDictionary *)temporaryAttributesAtCharacterIndex:(NSUInteger)i longestEffectiveRange:(NSRangePointer)r inRange:(NSRange)rg {
  NSMutableAttributedString *t = [self _xefTemp]; if (i >= [t length]) { if (r) *r = NSMakeRange([t length], 0); return nil; }
  return [t attributesAtIndex:i longestEffectiveRange:r inRange:[self _xefClip:rg]]; }
- (id)temporaryAttribute:(NSString *)n atCharacterIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r {
  NSMutableAttributedString *t = [self _xefTemp]; if (i >= [t length]) return nil; return [t attribute:n atIndex:i effectiveRange:r]; }
- (id)temporaryAttribute:(NSString *)n atCharacterIndex:(NSUInteger)i longestEffectiveRange:(NSRangePointer)r inRange:(NSRange)rg {
  NSMutableAttributedString *t = [self _xefTemp]; if (i >= [t length]) return nil; return [t attribute:n atIndex:i longestEffectiveRange:r inRange:[self _xefClip:rg]]; }
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
/* a plain NSText is a class cluster front: like AppKit, instances are NSTextViews */
- (id)initWithFrame:(NSRect)f { if ([self class] == [NSText class]) { [self release]; return [[NSTextView alloc] initWithFrame:f]; } return [super initWithFrame:f]; }
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
  if ((self = [self initWithFrame:f textContainer:tc])) { _storage = [ts retain]; _ownsStorage = YES; _maxSize = NSMakeSize(f.size.width, 1e7); _usesFontPanel = YES; }
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
- (NSInteger)baseWritingDirection { NSNumber *n = objc_getAssociatedObject(self, "xef.bwd"); return n ? [n integerValue] : -1; } - (void)setBaseWritingDirection:(NSInteger)d { objc_setAssociatedObject(self, "xef.bwd", [NSNumber numberWithInteger:d], OBJC_ASSOCIATION_RETAIN); }
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
- (BOOL)smartInsertDeleteEnabled { NSNumber *n = objc_getAssociatedObject(self, "xef.smart"); return n ? [n boolValue] : YES; } - (void)setSmartInsertDeleteEnabled:(BOOL)f { objc_setAssociatedObject(self, "xef.smart", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
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
- (NSRange)markedRange { NSValue *v = objc_getAssociatedObject(self, "xef.marked"); return v ? [v rangeValue] : NSMakeRange(NSNotFound, 0); }
- (BOOL)hasMarkedText { return [self markedRange].location != NSNotFound; }
- (void)unmarkText { objc_setAssociatedObject(self, "xef.marked", nil, OBJC_ASSOCIATION_RETAIN); }
- (void)setMarkedText:(id)s selectedRange:(NSRange)sr replacementRange:(NSRange)rr {
  /* the text being composed replaces the previous composition (or the selection) and stays marked until committed */
  NSString *str = [s isKindOfClass:[NSAttributedString class]] ? [s string] : s;
  NSRange target = rr.location != NSNotFound ? rr : ([self hasMarkedText] ? [self markedRange] : _sel);
  [self insertText:str replacementRange:target];
  NSRange m = NSMakeRange(target.location, [str length]);
  objc_setAssociatedObject(self, "xef.marked", [str length] ? [NSValue valueWithRange:m] : nil, OBJC_ASSOCIATION_RETAIN);
  [self setSelectedRange:NSMakeRange(m.location + sr.location, sr.length)]; }
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
static NSFontPanel *g_font_panel;
+ (NSFontPanel *)sharedFontPanel { if (!g_font_panel) { g_font_panel = [[NSFontPanel alloc] init]; g_font_panel->_modal = YES; } return g_font_panel; }
+ (BOOL)sharedFontPanelExists { return g_font_panel != nil; }
- (void)setPanelFont:(NSFont *)f isMultiple:(BOOL)m { [f retain]; [_font release]; _font = f; }
- (NSFont *)panelConvertFont:(NSFont *)f { return _font ? [[NSFontManager sharedFontManager] convertFont:f toSize:[_font pointSize]] : f; }
- (id)accessoryView { return _accessory; } - (void)setAccessoryView:(id)v { [v retain]; [_accessory release]; _accessory = v; }
- (BOOL)worksWhenModal { return _modal; } - (void)setWorksWhenModal:(BOOL)f { _modal = f; }
- (BOOL)isEnabled { return YES; } - (void)setEnabled:(BOOL)f {} - (void)reloadDefaultFontFamilies {}
- (BOOL)isVisible { return _visible; } - (void)orderFront:(id)s { _visible = YES; } - (void)makeKeyAndOrderFront:(id)s { _visible = YES; } - (void)close { _visible = NO; } - (void)orderOut:(id)s { _visible = NO; }
@end
@implementation NSColorPanel
static NSColorPanel *g_color_panel;
+ (NSColorPanel *)sharedColorPanel { if (!g_color_panel) { g_color_panel = [[NSColorPanel alloc] init]; g_color_panel->_continuous = YES; g_color_panel->_alpha = YES; g_color_panel->_mode = 6; g_color_panel->_color = [[NSColor whiteColor] retain]; } return g_color_panel; }
+ (BOOL)sharedColorPanelExists { return g_color_panel != nil; }
+ (void)setPickerMask:(NSUInteger)m {} + (void)setPickerMode:(NSInteger)m {} + (BOOL)dragColor:(NSColor *)c withEvent:(NSEvent *)e fromView:(NSView *)v { return NO; }
- (NSColor *)color { return _color; }
- (void)setColor:(NSColor *)c { [c retain]; [_color release]; _color = c; if (_action) [NSApp sendAction:_action to:_target from:self]; }
- (CGFloat)alpha { return [_color alphaComponent]; }
- (BOOL)isContinuous { return _continuous; } - (void)setContinuous:(BOOL)f { _continuous = f; } - (BOOL)showsAlpha { return _alpha; } - (void)setShowsAlpha:(BOOL)f { _alpha = f; }
- (NSInteger)mode { return _mode; } - (void)setMode:(NSInteger)m {}   /* the real panel keeps its mode while it is not on screen */
- (id)accessoryView { return _accessory; } - (void)setAccessoryView:(id)v { [v retain]; [_accessory release]; _accessory = v; }
- (void)setTarget:(id)t { _target = t; } - (void)setAction:(SEL)a { _action = a; }
- (BOOL)isVisible { return _visible; } - (void)orderFront:(id)s { _visible = YES; } - (void)orderFrontRegardless { _visible = YES; } - (void)makeKeyAndOrderFront:(id)s { _visible = YES; } - (void)close { _visible = NO; } - (void)orderOut:(id)s { _visible = NO; }
- (void)attachColorList:(NSColorList *)l {} - (void)detachColorList:(NSColorList *)l {} - (CGFloat)maximumLinearExposure { return 1; } - (void)setMaximumLinearExposure:(CGFloat)e {}
@end
static NSMutableDictionary *g_color_lists;
@implementation NSColorList
+ (NSArray *)availableColorLists { NSMutableArray *a = [NSMutableArray array]; for (NSString *k in g_color_lists) [a addObject:g_color_lists[k]]; return a; }
+ (NSColorList *)colorListNamed:(NSString *)n { return g_color_lists[n]; }
- (id)initWithName:(NSString *)n { if ((self = [super init])) { _name = [n copy]; _keys = [[NSMutableArray alloc] init]; _colors = [[NSMutableDictionary alloc] init]; if (n) { if (!g_color_lists) g_color_lists = [[NSMutableDictionary alloc] init]; g_color_lists[n] = self; } } return self; }
- (id)initWithName:(NSString *)n fromFile:(NSString *)p { return [self initWithName:n]; }
- (void)dealloc { if (_name && g_color_lists[_name] == self) [g_color_lists removeObjectForKey:_name]; [_name release]; [_keys release]; [_colors release]; [super dealloc]; }
- (NSString *)name { return _name; } - (BOOL)isEditable { return YES; } - (NSArray *)allKeys { return [NSArray arrayWithArray:_keys]; }
- (void)setColor:(NSColor *)c forKey:(NSString *)k { if (![_keys containsObject:k]) [_keys addObject:k]; _colors[k] = c; }
- (void)insertColor:(NSColor *)c key:(NSString *)k atIndex:(NSUInteger)i { [_keys removeObject:k]; [_keys insertObject:k atIndex:MIN(i, [_keys count])]; _colors[k] = c; }
- (void)removeColorWithKey:(NSString *)k { [_keys removeObject:k]; [_colors removeObjectForKey:k]; } - (NSColor *)colorWithKey:(NSString *)k { return _colors[k]; }
- (BOOL)writeToURL:(NSURL *)u error:(NSError **)e { return NO; } - (BOOL)writeToFile:(NSString *)p { return NO; } - (void)removeFile {}
@end

/* ---- NSTextView: factories, completion, smart insert/delete, pasteboard type negotiation ---- */
@implementation NSTextView (XEFExtras)
+ (NSScrollView *)_xefScrollableWithRich:(BOOL)rich usesFontPanel:(BOOL)fp {
  NSScrollView *sv = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)] autorelease];
  [sv setHasVerticalScroller:YES]; [sv setHasHorizontalScroller:NO];
  NSTextView *tv = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)] autorelease];
  [tv setMinSize:NSMakeSize(0, 100)]; [tv setMaxSize:NSMakeSize(1e7, 1e7)];
  [tv setVerticallyResizable:YES]; [tv setHorizontallyResizable:NO]; [tv setAutoresizingMask:2];
  [[tv textContainer] setContainerSize:NSMakeSize(100, 1e7)]; [[tv textContainer] setWidthTracksTextView:YES];
  [tv setRichText:rich]; [tv setUsesFontPanel:fp]; [tv setImportsGraphics:NO];
  [sv setDocumentView:tv]; return sv; }
+ (NSScrollView *)scrollableTextView { NSScrollView *sv = [self _xefScrollableWithRich:NO usesFontPanel:YES]; [[sv documentView] setAutoresizingMask:18]; return sv; }
+ (NSScrollView *)scrollableDocumentContentTextView { return [self _xefScrollableWithRich:YES usesFontPanel:YES]; }
+ (NSScrollView *)scrollablePlainDocumentContentTextView { return [self _xefScrollableWithRich:NO usesFontPanel:YES]; }
+ (NSTextView *)fieldEditor { NSTextView *t = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)] autorelease]; [t setFieldEditor:YES]; return t; }
- (void)setConstrainedFrameSize:(NSSize)s { [self setFrameSize:s]; }
- (void)setBaseWritingDirection:(NSInteger)d range:(NSRange)r {
  NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init]; [p setBaseWritingDirection:d];
  [_storage addAttribute:NSParagraphStyleAttributeName value:p range:[[_storage string] paragraphRangeForRange:r]]; [p release]; }
- (void)toggleBaseWritingDirection:(id)s { [self setBaseWritingDirection:[self baseWritingDirection] == 1 ? 0 : 1]; }
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)r { return [_storage attributedSubstringFromRange:r]; }
- (NSRect)firstRectForCharacterRange:(NSRange)r { NSRect b = [self convertRect:[(NSLayoutManager *)_lm boundingRectForGlyphRange:r inTextContainer:_tc] toView:nil]; return b; }
- (void)setMarkedText:(id)t selectedRange:(NSRange)sel { [self setMarkedText:t selectedRange:sel replacementRange:NSMakeRange(NSNotFound, 0)]; }
- (NSArray *)rangesForUserCharacterAttributeChange { return nil; } - (NSArray *)rangesForUserParagraphAttributeChange { return nil; }
- (NSRange)rangeForUserCompletion {
  NSString *s = [_storage string]; NSUInteger e = _sel.location, b = e;
  while (b > 0 && [[NSCharacterSet alphanumericCharacterSet] characterIsMember:[s characterAtIndex:b - 1]]) b--;
  return NSMakeRange(b, e - b); }
- (NSArray *)completionsForPartialWordRange:(NSRange)r indexOfSelectedItem:(NSInteger *)i { if (i) *i = -1; return @[]; }
- (void)insertCompletion:(NSString *)w forPartialWordRange:(NSRange)r movement:(NSInteger)m isFinal:(BOOL)f { if (f) [self insertText:w replacementRange:r]; }
- (void)complete:(id)s {}
- (BOOL)performValidatedReplacementInRange:(NSRange)r withAttributedString:(NSAttributedString *)a { if (![self shouldChangeTextInRange:r replacementString:[a string]]) return NO; [_storage replaceCharactersInRange:r withAttributedString:a]; [self didChangeText]; return YES; }
- (NSRange)smartDeleteRangeForProposedRange:(NSRange)r {
  if (![self smartInsertDeleteEnabled]) return r;
  NSString *s = [_storage string]; NSUInteger e = NSMaxRange(r);
  if (r.location > 0 && [s characterAtIndex:r.location - 1] == ' ' && (e >= [s length] || ![[NSCharacterSet alphanumericCharacterSet] characterIsMember:[s characterAtIndex:e]])) { r.location--; r.length++; }
  return r; }
- (void)smartInsertForString:(NSString *)str replacingRange:(NSRange)r beforeString:(NSString **)b afterString:(NSString **)a {
  if (b) *b = nil; if (a) *a = nil; if (![self smartInsertDeleteEnabled] || ![str length]) return;
  NSString *s = [_storage string]; NSCharacterSet *w = [NSCharacterSet alphanumericCharacterSet];
  BOOL firstW = [w characterIsMember:[str characterAtIndex:0]], lastW = [w characterIsMember:[str characterAtIndex:[str length] - 1]];
  if (b && r.location > 0 && firstW && [w characterIsMember:[s characterAtIndex:r.location - 1]]) *b = @" ";
  if (a && NSMaxRange(r) < [s length] && lastW && [w characterIsMember:[s characterAtIndex:NSMaxRange(r)]]) *a = @" "; }
- (NSString *)smartInsertBeforeStringForString:(NSString *)str replacingRange:(NSRange)r { NSString *b = nil; [self smartInsertForString:str replacingRange:r beforeString:&b afterString:NULL]; return b; }
- (NSString *)smartInsertAfterStringForString:(NSString *)str replacingRange:(NSRange)r { NSString *a = nil; [self smartInsertForString:str replacingRange:r beforeString:NULL afterString:&a]; return a; }
- (NSString *)contentType { return objc_getAssociatedObject(self, "xef.contentType"); } - (void)setContentType:(NSString *)t { objc_setAssociatedObject(self, "xef.contentType", t, OBJC_ASSOCIATION_COPY); }
- (NSArray *)acceptableDragTypes { return @[@"NeXT Rich Text Format v1.0 pasteboard type", @"NSStringPboardType", @"NSFilenamesPboardType"]; }
- (NSString *)preferredPasteboardTypeFromArray:(NSArray *)a restrictedToTypesFromArray:(NSArray *)r {
  NSArray *ok = [self acceptableDragTypes]; for (NSString *t in a) if ([ok containsObject:t] && (!r || [r containsObject:t])) return t; return nil; }
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pb types:(NSArray *)types { BOOL any = NO; for (NSString *t in types) any |= [self writeSelectionToPasteboard:pb type:t]; return any; }
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pb type:(NSString *)t { NSString *s = [pb stringForType:t]; if (!s) return NO; [self insertText:s replacementRange:_sel]; return YES; }
- (NSDictionary *)textHighlightAttributes { return objc_getAssociatedObject(self, "xef.highlight") ?: @{ NSBackgroundColorAttributeName: [NSColor selectedTextBackgroundColor] }; }
- (void)setTextHighlightAttributes:(NSDictionary *)d { objc_setAssociatedObject(self, "xef.highlight", d, OBJC_ASSOCIATION_COPY); }
- (void)highlight:(id)s {} - (void)showFindIndicatorForRange:(NSRange)r {} - (void)updateCandidates {} - (void)updateTouchBarItemIdentifiers {} - (void)updateTextTouchBarItems {}
- (NSInteger)spellCheckerDocumentTag { return 1; } - (BOOL)usesRolloverButtonForSelection { return NO; } - (void)setUsesRolloverButtonForSelection:(BOOL)f {}
- (void)checkTextInRange:(NSRange)r types:(NSUInteger)t options:(NSDictionary *)o {} - (BOOL)isWritingToolsActive { return NO; }
- (void)cleanUpAfterDragOperation {} - (NSArray *)allowedInputSourceLocales { return nil; } - (void)setAllowedInputSourceLocales:(NSArray *)a {}
- (void)toggleAutomaticTextCompletion:(id)s {} - (void)toggleQuickLookPreviewPanel:(id)s {} - (void)updateQuickLookPreviewPanel {}
- (void)outline:(id)s {} - (void)changeLayoutOrientation:(id)s {}
@end

/* ================================================================== NSSpellChecker */
static NSSet *g_words; static BOOL g_words_tried;
static NSSet *XEFDictionary(void) {
  if (!g_words_tried) {
    g_words_tried = YES;
    NSString *t = [NSString stringWithContentsOfFile:@"/usr/share/dict/words" encoding:NSUTF8StringEncoding error:NULL];
    if (t) { NSMutableSet *s = [NSMutableSet set]; for (NSString *w in [t componentsSeparatedByString:@"\n"]) if ([w length]) [s addObject:[w lowercaseString]]; g_words = [s retain]; } }
  return g_words; }
/* the next word of s at or after `from`: letters with inner apostrophes */
static BOOL XEFNextWord(NSString *s, NSUInteger from, NSUInteger limit, NSRange *out) {
  NSCharacterSet *letters = [NSCharacterSet letterCharacterSet]; NSUInteger i = from, n = MIN(limit, [s length]);
  while (i < n) {
    while (i < n && ![letters characterIsMember:[s characterAtIndex:i]]) i++;
    if (i >= n) return NO;
    NSUInteger b = i;
    while (i < n && ([letters characterIsMember:[s characterAtIndex:i]] || ([s characterAtIndex:i] == '\'' && i + 1 < [s length] && [letters characterIsMember:[s characterAtIndex:i + 1]]))) i++;
    *out = NSMakeRange(b, i - b); return YES; }
  return NO; }
@implementation NSSpellChecker
+ (NSSpellChecker *)sharedSpellChecker { static NSSpellChecker *s; if (!s) s = [[NSSpellChecker alloc] init]; return s; }
+ (BOOL)sharedSpellCheckerExists { return YES; }
+ (NSInteger)uniqueSpellDocumentTag { static NSInteger n = 0; return ++n; }
- (id)init { if ((self = [super init])) { _ignored = [[NSMutableDictionary alloc] init]; _learned = [[NSMutableSet alloc] init]; _language = @"en"; } return self; }
- (BOOL)_xefIsCorrect:(NSString *)w tag:(NSInteger)tag {
  NSSet *d = XEFDictionary(); if (!d) return YES;
  NSString *lw = [w lowercaseString];
  if ([d containsObject:lw] || [_learned containsObject:lw] || [[_ignored objectForKey:@(tag)] containsObject:lw]) return YES;
  if ([lw hasSuffix:@"'s"] && [d containsObject:[lw substringToIndex:[lw length] - 2]]) return YES;
  /* inflections the plain word list lacks: plurals, -ed, -ing, -ly, -er, -est (with restored e or undoubled consonant) */
  static NSArray *suffixes; if (!suffixes) suffixes = [@[@"s", @"es", @"ies", @"ed", @"d", @"ing", @"ly", @"er", @"ers", @"est", @"ness"] retain];
  for (NSString *suf in suffixes) {
    if (![lw hasSuffix:suf] || [lw length] <= [suf length] + 1) continue;
    NSString *stem = [lw substringToIndex:[lw length] - [suf length]];
    if ([suf isEqualToString:@"ies"]) stem = [stem stringByAppendingString:@"y"];
    if ([d containsObject:stem] || [d containsObject:[stem stringByAppendingString:@"e"]]) return YES;
    NSUInteger n = [stem length]; if (n > 2 && [stem characterAtIndex:n - 1] == [stem characterAtIndex:n - 2] && [d containsObject:[stem substringToIndex:n - 1]]) return YES; }
  return NO; }
- (NSRange)checkSpellingOfString:(NSString *)s startingAt:(NSInteger)off language:(NSString *)lang wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)tag wordCount:(NSInteger *)wc {
  NSInteger count = 0; NSRange w; NSUInteger len = [s length]; if (off < 0) off = 0; if ((NSUInteger)off > len) off = len;
  for (int pass = 0; pass < (wrap ? 2 : 1); pass++) {
    NSUInteger from = pass == 0 ? off : 0, limit = pass == 0 ? len : MIN(len, (NSUInteger)off + 0);
    NSUInteger at = from;
    NSCharacterSet *ls = [NSCharacterSet letterCharacterSet];
    if (pass == 0 && at > 0 && at < len && [ls characterIsMember:[s characterAtIndex:at - 1]] && [ls characterIsMember:[s characterAtIndex:at]]) { while (at < len && [ls characterIsMember:[s characterAtIndex:at]]) at++; }   /* a word already begun is skipped */
    while (XEFNextWord(s, at, len, &w)) {
      if (pass == 1 && w.location >= (NSUInteger)off) break;
      at = NSMaxRange(w); count++;
      if (![self _xefIsCorrect:[s substringWithRange:w] tag:tag]) { if (wc) *wc = count; return w; } }
    (void)limit; }
  if (wc) *wc = count; return NSMakeRange(NSNotFound, 0); }
- (NSRange)checkSpellingOfString:(NSString *)s startingAt:(NSInteger)off { return [self checkSpellingOfString:s startingAt:off language:nil wrap:YES inSpellDocumentWithTag:0 wordCount:NULL]; }
- (NSInteger)countWordsInString:(NSString *)s language:(NSString *)l { NSInteger n = 0; NSRange w; NSUInteger at = 0; while (XEFNextWord(s, at, [s length], &w)) { n++; at = NSMaxRange(w); } return n; }
- (void)ignoreWord:(NSString *)w inSpellDocumentWithTag:(NSInteger)tag { NSMutableSet *set = [_ignored objectForKey:@(tag)]; if (!set) { set = [NSMutableSet set]; _ignored[@(tag)] = set; } [set addObject:[w lowercaseString]]; }
- (NSArray *)ignoredWordsInSpellDocumentWithTag:(NSInteger)tag { return [[[_ignored objectForKey:@(tag)] allObjects] ?: @[] sortedArrayUsingSelector:@selector(compare:)]; }
- (void)setIgnoredWords:(NSArray *)w inSpellDocumentWithTag:(NSInteger)tag { NSMutableSet *s = [NSMutableSet set]; for (NSString *x in w) [s addObject:[x lowercaseString]]; _ignored[@(tag)] = s; }
- (void)closeSpellDocumentWithTag:(NSInteger)tag { [_ignored removeObjectForKey:@(tag)]; }
- (void)learnWord:(NSString *)w { [_learned addObject:[w lowercaseString]]; } - (void)unlearnWord:(NSString *)w { [_learned removeObject:[w lowercaseString]]; } - (BOOL)hasLearnedWord:(NSString *)w { return [_learned containsObject:[w lowercaseString]]; }
- (NSArray *)guessesForWordRange:(NSRange)r inString:(NSString *)s language:(NSString *)l inSpellDocumentWithTag:(NSInteger)tag {
  NSSet *d = XEFDictionary(); if (!d || NSMaxRange(r) > [s length]) return @[];
  NSString *w = [[s substringWithRange:r] lowercaseString]; NSMutableSet *out = [NSMutableSet set]; NSUInteger n = [w length];
  NSString *alpha = @"abcdefghijklmnopqrstuvwxyz";
  for (NSUInteger i = 0; i <= n; i++) {
    if (i < n) { [out addObject:[w stringByReplacingCharactersInRange:NSMakeRange(i, 1) withString:@""]];
      if (i + 1 < n) { unichar a = [w characterAtIndex:i], b = [w characterAtIndex:i + 1]; NSMutableString *t = [NSMutableString stringWithString:w]; [t replaceCharactersInRange:NSMakeRange(i, 2) withString:[NSString stringWithFormat:@"%C%C", b, a]]; [out addObject:t]; } }
    for (NSUInteger k = 0; k < 26; k++) { NSString *c = [alpha substringWithRange:NSMakeRange(k, 1)];
      if (i < n) [out addObject:[w stringByReplacingCharactersInRange:NSMakeRange(i, 1) withString:c]];
      [out addObject:[w stringByReplacingCharactersInRange:NSMakeRange(i, 0) withString:c]]; } }
  NSMutableArray *r2 = [NSMutableArray array]; for (NSString *c in out) if ([c length] && ![c isEqualToString:w] && [d containsObject:c]) [r2 addObject:c];
  return [r2 sortedArrayUsingSelector:@selector(compare:)]; }
- (NSString *)correctionForWordRange:(NSRange)r inString:(NSString *)s language:(NSString *)l inSpellDocumentWithTag:(NSInteger)tag { return nil; }
- (NSArray *)completionsForPartialWordRange:(NSRange)r inString:(NSString *)s language:(NSString *)l inSpellDocumentWithTag:(NSInteger)tag {
  NSSet *d = XEFDictionary(); if (!d || NSMaxRange(r) > [s length]) return @[];
  NSString *p = [[s substringWithRange:r] lowercaseString]; NSMutableArray *a = [NSMutableArray array];
  for (NSString *w in d) if ([w hasPrefix:p] && ![w isEqualToString:p]) [a addObject:w];
  [a sortUsingSelector:@selector(compare:)]; return [a count] > 20 ? [a subarrayWithRange:NSMakeRange(0, 20)] : a; }
- (NSArray *)availableLanguages { return @[@"en"]; } - (NSArray *)userPreferredLanguages { return @[@"en"]; }
- (NSString *)language { return _language; } - (BOOL)setLanguage:(NSString *)l { if (![l isEqualToString:@"en"]) return NO; return YES; }
- (BOOL)automaticallyIdentifiesLanguages { return _autoLang; } - (void)setAutomaticallyIdentifiesLanguages:(BOOL)f { _autoLang = f; }
- (NSString *)languageForWordRange:(NSRange)r inString:(NSString *)s orthography:(id)o { return @"en"; }
- (NSArray *)checkString:(NSString *)s range:(NSRange)r types:(unsigned long long)t options:(NSDictionary *)o inSpellDocumentWithTag:(NSInteger)tag orthography:(id *)orth wordCount:(NSInteger *)wc { if (wc) *wc = [self countWordsInString:[s substringWithRange:r] language:nil]; return @[]; }
- (NSInteger)requestCheckingOfString:(NSString *)s range:(NSRange)r types:(unsigned long long)t options:(NSDictionary *)o inSpellDocumentWithTag:(NSInteger)tag completionHandler:(void (^)(NSInteger, NSArray *, NSArray *, NSInteger))h {
  NSInteger seq = [NSSpellChecker uniqueSpellDocumentTag]; if (h) h(seq, @[], @[], 0); return seq; }
- (void)requestCandidatesForSelectedRange:(NSRange)r inString:(NSString *)s types:(unsigned long long)t options:(NSDictionary *)o inSpellDocumentWithTag:(NSInteger)tag completionHandler:(void (^)(NSInteger, NSArray *))h { if (h) h(0, @[]); }
- (NSRange)checkGrammarOfString:(NSString *)s startingAt:(NSInteger)off language:(NSString *)l wrap:(BOOL)w inSpellDocumentWithTag:(NSInteger)tag details:(NSArray **)d { if (d) *d = @[]; return NSMakeRange(NSNotFound, 0); }
- (NSArray *)userQuotesArrayForLanguage:(NSString *)l { return @[@"“", @"”", @"‘", @"’"]; } - (NSDictionary *)userReplacementsDictionary { return @{}; }
- (void)updateSpellingPanelWithMisspelledWord:(NSString *)w {} - (void)updateSpellingPanelWithGrammarString:(NSString *)s detail:(NSDictionary *)d {} - (void)updatePanels {}
- (id)accessoryView { return _accessory; } - (void)setAccessoryView:(id)v { _accessory = v; }
- (BOOL)preventsAutocorrectionBeforeString:(NSString *)s language:(NSString *)l { return NO; } - (BOOL)deletesAutospaceBetweenString:(NSString *)a andString:(NSString *)b language:(NSString *)l { return NO; }
- (void)recordResponse:(NSInteger)r toCorrection:(NSString *)c forWord:(NSString *)w language:(NSString *)l inSpellDocumentWithTag:(NSInteger)t {}
- (void)dismissCorrectionIndicatorForView:(NSView *)v {}
@end

/* ---- NSLayoutManager: glyph helpers (glyphs are the characters here), hyphenation, drawing helpers ---- */
@implementation NSLayoutManager (XEFMore)
- (BOOL)usesDefaultHyphenation { return [objc_getAssociatedObject(self, "xef.hyph") boolValue]; } - (void)setUsesDefaultHyphenation:(BOOL)f { objc_setAssociatedObject(self, "xef.hyph", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (NSAttributedString *)attributedString { return _storage; }
- (CGGlyph)CGGlyphAtIndex:(NSUInteger)i isValidIndex:(BOOL *)ok { BOOL v = i < [_storage length]; if (ok) *ok = v; return v ? (CGGlyph)([[_storage string] characterAtIndex:i]) : 0; }
- (NSInteger)propertyForGlyphAtIndex:(NSUInteger)i { return 0; }
- (NSUInteger)getGlyphsInRange:(NSRange)r glyphs:(CGGlyph *)g properties:(NSInteger *)p characterIndexes:(NSUInteger *)ci bidiLevels:(unsigned char *)b {
  NSUInteger n = 0; for (NSUInteger i = r.location; i < NSMaxRange(r) && i < [_storage length]; i++, n++) { if (g) g[n] = [[_storage string] characterAtIndex:i]; if (p) p[n] = 0; if (ci) ci[n] = i; if (b) b[n] = 0; } return n; }
- (BOOL)notShownAttributeForGlyphAtIndex:(NSUInteger)i { if (i >= [_storage length]) return NO; unichar c = [[_storage string] characterAtIndex:i]; return c == '\\n' || c == '\\r' || c == 0x2028 || c == 0x2029; }
- (void)setNotShownAttribute:(BOOL)f forGlyphAtIndex:(NSUInteger)i {}
- (BOOL)drawsOutsideLineFragmentForGlyphAtIndex:(NSUInteger)i { return NO; } - (void)setDrawsOutsideLineFragment:(BOOL)f forGlyphAtIndex:(NSUInteger)i {}
- (NSSize)attachmentSizeForGlyphAtIndex:(NSUInteger)i { id a = i < [_storage length] ? [_storage attribute:@"NSAttachment" atIndex:i effectiveRange:NULL] : nil; return a && [a respondsToSelector:@selector(bounds)] ? [a bounds].size : NSMakeSize(-1, -1); }
- (void)setAttachmentSize:(NSSize)s forGlyphRange:(NSRange)r {}
- (NSRange)truncatedGlyphRangeInLineFragmentForGlyphAtIndex:(NSUInteger)i { return NSMakeRange(NSNotFound, 0); }
- (NSRange)rangeOfNominallySpacedGlyphsContainingIndex:(NSUInteger)i { NSRange r; [self lineFragmentRectForGlyphAtIndex:i effectiveRange:&r]; return r; }
- (NSRect)lineFragmentUsedRectForGlyphAtIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r withoutAdditionalLayout:(BOOL)f { return [self lineFragmentUsedRectForGlyphAtIndex:i effectiveRange:r]; }
- (void)getFirstUnlaidCharacterIndex:(NSUInteger *)c glyphIndex:(NSUInteger *)g { if (c) *c = [_storage length]; if (g) *g = [_storage length]; }
- (void)textContainerChangedTextView:(NSTextContainer *)c { [self _xefInvalidate]; }
- (void)setTextContainer:(NSTextContainer *)c forGlyphRange:(NSRange)r {} - (void)setLineFragmentRect:(NSRect)f forGlyphRange:(NSRange)r usedRect:(NSRect)u {}
- (void)setExtraLineFragmentRect:(NSRect)f usedRect:(NSRect)u textContainer:(NSTextContainer *)c {} - (void)setLocation:(NSPoint)p forStartOfGlyphRange:(NSRange)r {}
- (void)setGlyphs:(const CGGlyph *)g properties:(const NSInteger *)p characterIndexes:(const NSUInteger *)ci font:(NSFont *)f forGlyphRange:(NSRange)r {}
- (void)fillBackgroundRectArray:(const NSRect *)rects count:(NSUInteger)n forCharacterRange:(NSRange)r color:(NSColor *)c { [c set]; for (NSUInteger i = 0; i < n; i++) NSRectFill(rects[i]); }
- (void)underlineGlyphRange:(NSRange)g underlineType:(NSInteger)t lineFragmentRect:(NSRect)l lineFragmentGlyphRange:(NSRange)lg containerOrigin:(NSPoint)o {
  NSRect b = [self boundingRectForGlyphRange:g inTextContainer:[_containers firstObject]]; b.origin.x += o.x; b.origin.y += o.y; NSRectFill(NSMakeRect(b.origin.x, NSMaxY(b) - 1, b.size.width, 1)); }
- (void)strikethroughGlyphRange:(NSRange)g strikethroughType:(NSInteger)t lineFragmentRect:(NSRect)l lineFragmentGlyphRange:(NSRange)lg containerOrigin:(NSPoint)o {
  NSRect b = [self boundingRectForGlyphRange:g inTextContainer:[_containers firstObject]]; b.origin.x += o.x; b.origin.y += o.y; NSRectFill(NSMakeRect(b.origin.x, NSMidY(b), b.size.width, 1)); }
- (void)drawStrikethroughForGlyphRange:(NSRange)g strikethroughType:(NSInteger)t baselineOffset:(CGFloat)b lineFragmentRect:(NSRect)l lineFragmentGlyphRange:(NSRange)lg containerOrigin:(NSPoint)o { [self strikethroughGlyphRange:g strikethroughType:t lineFragmentRect:l lineFragmentGlyphRange:lg containerOrigin:o]; }
- (void)showAttachmentCell:(id)cell inRect:(NSRect)r characterIndex:(NSUInteger)i { [cell drawWithFrame:r inView:[self firstTextView]]; }
- (void)setLayoutRect:(NSRect)r forTextBlock:(id)b glyphRange:(NSRange)g {} - (void)setBoundsRect:(NSRect)r forTextBlock:(id)b glyphRange:(NSRange)g {}
- (NSRect)layoutRectForTextBlock:(id)b glyphRange:(NSRange)g { return NSZeroRect; } - (NSRect)boundsRectForTextBlock:(id)b glyphRange:(NSRange)g { return NSZeroRect; }
- (NSRect)layoutRectForTextBlock:(id)b atIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r { return NSZeroRect; } - (NSRect)boundsRectForTextBlock:(id)b atIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r { return NSZeroRect; }
- (NSArray *)rulerMarkersForTextView:(NSTextView *)tv paragraphStyle:(NSParagraphStyle *)p ruler:(id)r { return @[]; }
- (NSView *)rulerAccessoryViewForTextView:(NSTextView *)tv paragraphStyle:(NSParagraphStyle *)p ruler:(id)r enabled:(BOOL)e { return nil; }
- (BOOL)layoutManagerOwnsFirstResponderInWindow:(NSWindow *)w { id fr = [w firstResponder]; for (NSTextContainer *c in _containers) if ([c textView] == fr) return YES; return NO; }
@end

/* ================================================================== NSTypesetter */
@implementation NSTypesetter
+ (id)sharedSystemTypesetter { static NSATSTypesetter *t; if (!t) t = [[NSATSTypesetter alloc] init]; return t; }
+ (id)sharedSystemTypesetterForBehavior:(NSInteger)b { return [self sharedSystemTypesetter]; }
+ (NSInteger)defaultTypesetterBehavior { return 4; }
- (id)init { if ((self = [super init])) { _leading = YES; _bidi = YES; _behavior = 4; } return self; }
- (void)dealloc { [_attr release]; [super dealloc]; }
- (BOOL)usesFontLeading { return _leading; } - (void)setUsesFontLeading:(BOOL)f { _leading = f; }
- (NSInteger)typesetterBehavior { return _behavior; } - (void)setTypesetterBehavior:(NSInteger)b { _behavior = b == -1 ? 15 : b; }
- (float)hyphenationFactor { return _hyph; } - (void)setHyphenationFactor:(float)f { _hyph = f; }
- (CGFloat)lineFragmentPadding { return _padding; } - (void)setLineFragmentPadding:(CGFloat)p { _padding = p; }
- (BOOL)bidiProcessingEnabled { return _bidi; } - (void)setBidiProcessingEnabled:(BOOL)f { _bidi = f; }
- (NSAttributedString *)attributedString { return _attr; } - (void)setAttributedString:(NSAttributedString *)a { [a retain]; [_attr release]; _attr = a; }
- (void)setParagraphGlyphRange:(NSRange)r separatorGlyphRange:(NSRange)s { _pgr = r; _sepr = s; }
- (NSRange)paragraphGlyphRange { NSRange r = _pgr; r.length = r.length >= _sepr.length ? r.length - _sepr.length : r.length; return r; }
- (NSRange)paragraphSeparatorGlyphRange { return _sepr; }
- (NSRange)paragraphCharacterRange { return NSMakeRange(0, 0); } - (NSRange)paragraphSeparatorCharacterRange { return NSMakeRange(0, 0); }
- (NSLayoutManager *)layoutManager { return nil; } - (NSArray *)textContainers { return @[]; } - (NSTextContainer *)currentTextContainer { return nil; } - (NSParagraphStyle *)currentParagraphStyle { return nil; }
- (NSFont *)substituteFontForFont:(NSFont *)f { return f; }
- (id)textTabForGlyphLocation:(CGFloat)loc writingDirection:(NSInteger)d maxLocation:(CGFloat)max { return nil; }
- (NSUInteger)actionForControlCharacterAtIndex:(NSUInteger)i {
  if (!_attr || i >= [_attr length]) return 1;
  unichar c = [[_attr string] characterAtIndex:i];
  if (c == '\n' || c == 0x2028 || c == 0x2029) return 24; if (c == '\t') return 4; if (c == 0x0C) return 32; return 1; }
- (BOOL)shouldBreakLineByWordBeforeCharacterAtIndex:(NSUInteger)i { return YES; }
- (BOOL)shouldBreakLineByHyphenatingBeforeCharacterAtIndex:(NSUInteger)i { return YES; }
- (float)hyphenationFactorForGlyphAtIndex:(NSUInteger)i { return _hyph; }
- (unichar)hyphenCharacterForGlyphAtIndex:(NSUInteger)i { return 0x2010; }
- (CGFloat)lineSpacingAfterGlyphAtIndex:(NSUInteger)i withProposedLineFragmentRect:(NSRect)r { return 0; }
- (CGFloat)paragraphSpacingBeforeGlyphAtIndex:(NSUInteger)i withProposedLineFragmentRect:(NSRect)r { return 0; }
- (CGFloat)paragraphSpacingAfterGlyphAtIndex:(NSUInteger)i withProposedLineFragmentRect:(NSRect)r { return 0; }
- (CGFloat)baselineOffsetInLayoutManager:(NSLayoutManager *)lm glyphIndex:(NSUInteger)i { return 0; }
- (NSDictionary *)attributesForExtraLineFragment { return @{}; }
- (void)beginParagraph {} - (void)endParagraph {} - (void)beginLineWithGlyphAtIndex:(NSUInteger)i {} - (void)endLineWithGlyphRange:(NSRange)r {}
- (NSInteger)layoutParagraphAtPoint:(NSPointPointer)p { return 0; }
- (NSUInteger)layoutGlyphsInLayoutManager:(NSLayoutManager *)lm startingAtGlyphIndex:(NSUInteger)i maxNumberOfLineFragments:(NSUInteger)n nextGlyphIndex:(NSUInteger *)next { if (next) *next = i; return 0; }
- (void)layoutCharactersInRange:(NSRange)r forLayoutManager:(NSLayoutManager *)lm maximumNumberOfLineFragments:(NSUInteger)n {}
- (void)setHardInvalidation:(BOOL)f forGlyphRange:(NSRange)r {}
+ (CGFloat)printingAdjustmentInLayoutManager:(NSLayoutManager *)lm forNominallySpacedGlyphRange:(NSRange)r packedGlyphs:(const unsigned char *)g count:(NSUInteger)n { return 0; }
- (void)willSetLineFragmentRect:(NSRectPointer)f forGlyphRange:(NSRange)r usedRect:(NSRectPointer)u baselineOffset:(CGFloat *)b {}
- (NSRect)boundingBoxForControlGlyphAtIndex:(NSUInteger)i forTextContainer:(NSTextContainer *)c proposedLineFragment:(NSRect)f glyphPosition:(NSPoint)p characterIndex:(NSUInteger)ci { return NSZeroRect; }
- (void)getLineFragmentRect:(NSRectPointer)f usedRect:(NSRectPointer)u forParagraphSeparatorGlyphRange:(NSRange)r atProposedOrigin:(NSPoint)o { if (f) *f = NSMakeRect(o.x, o.y, 0, 0); if (u) *u = NSMakeRect(o.x, o.y, 0, 0); }
- (NSUInteger)getLineFragmentRect:(NSRectPointer)f usedRect:(NSRectPointer)u remainingRect:(NSRectPointer)rem forStartingGlyphAtIndex:(NSUInteger)i proposedRect:(NSRect)p lineSpacing:(CGFloat)ls paragraphSpacingBefore:(CGFloat)pb paragraphSpacingAfter:(CGFloat)pa { if (f) *f = p; if (u) *u = p; if (rem) *rem = NSZeroRect; return 0; }
- (void)setLineFragmentRect:(NSRect)f forGlyphRange:(NSRange)r usedRect:(NSRect)u baselineOffset:(CGFloat)b {}
- (void)setNotShownAttribute:(BOOL)f forGlyphRange:(NSRange)r {} - (void)setDrawsOutsideLineFragment:(BOOL)f forGlyphRange:(NSRange)r {}
- (void)setLocation:(NSPoint)p withAdvancements:(const CGFloat *)a forStartOfGlyphRange:(NSRange)r {} - (void)setAttachmentSize:(NSSize)s forGlyphRange:(NSRange)r {} - (void)setBidiLevels:(const unsigned char *)l forGlyphRange:(NSRange)r {}
- (NSRange)characterRangeForGlyphRange:(NSRange)g actualGlyphRange:(NSRangePointer)a { return NSMakeRange(0, 0); }
- (NSRange)glyphRangeForCharacterRange:(NSRange)c actualCharacterRange:(NSRangePointer)a { return NSMakeRange(0, 0); }
@end
@implementation NSATSTypesetter
+ (id)sharedTypesetter { return [NSTypesetter sharedSystemTypesetter]; }
- (NSRect)lineFragmentRectForProposedRect:(NSRect)p remainingRect:(NSRectPointer)r { if (r) *r = NSZeroRect; return p; }
- (NSUInteger)getGlyphsInRange:(NSRange)r glyphs:(NSGlyph *)g characterIndexes:(NSUInteger *)ci glyphInscriptions:(int *)gi elasticBits:(BOOL *)eb {
  NSUInteger n = 0; for (NSUInteger i = r.location; i < NSMaxRange(r) && i < [_attr length]; i++, n++) { if (g) g[n] = [[_attr string] characterAtIndex:i]; if (ci) ci[n] = i; if (gi) gi[n] = 0; if (eb) eb[n] = NO; } return n; }
@end


/* AppKit text-document attribute / option / type names (values read from macOS) */
NSString *const NSAppearanceDocumentAttribute = @"NSAppearanceDocumentAttribute";
NSString *const NSAuthorDocumentAttribute = @"NSAuthorDocumentAttribute";
NSString *const NSBackgroundColorDocumentAttribute = @"BackgroundColor";
NSString *const NSBaseURLDocumentOption = @"BaseURL";
NSString *const NSBottomMarginDocumentAttribute = @"BottomMargin";
NSString *const NSCategoryDocumentAttribute = @"NSCategoryDocumentAttribute";
NSString *const NSCharacterEncodingDocumentAttribute = @"CharacterEncoding";
NSString *const NSCharacterEncodingDocumentOption = @"CharacterEncoding";
NSString *const NSCocoaVersionDocumentAttribute = @"CocoaRTFVersion";
NSString *const NSCommentDocumentAttribute = @"NSCommentDocumentAttribute";
NSString *const NSCompanyDocumentAttribute = @"NSCompanyDocumentAttribute";
NSString *const NSConvertedDocumentAttribute = @"Converted";
NSString *const NSCopyrightDocumentAttribute = @"NSCopyrightDocumentAttribute";
NSString *const NSCreationTimeDocumentAttribute = @"NSCreationTimeDocumentAttribute";
NSString *const NSDefaultAttributesDocumentAttribute = @"DefaultAttributes";
NSString *const NSDefaultAttributesDocumentOption = @"DefaultAttributes";
NSString *const NSDefaultFontExcludedDocumentAttribute = @"NoDefaultFonts";
NSString *const NSDefaultTabIntervalDocumentAttribute = @"DefaultTabInterval";
NSString *const NSDocFormatTextDocumentType = @"NSDocFormat";
NSString *const NSDocumentTypeDocumentAttribute = @"DocumentType";
NSString *const NSDocumentTypeDocumentOption = @"DocumentType";
NSString *const NSEditorDocumentAttribute = @"NSEditorDocumentAttribute";
NSString *const NSExcludedElementsDocumentAttribute = @"ExcludedElements";
NSString *const NSFileTypeDocumentAttribute = @"UTI";
NSString *const NSFileTypeDocumentOption = @"UTI";
NSString *const NSHTMLTextDocumentType = @"NSHTML";
NSString *const NSHyphenationFactorDocumentAttribute = @"HyphenationFactor";
NSString *const NSKeywordsDocumentAttribute = @"NSKeywordsDocumentAttribute";
NSString *const NSLeftMarginDocumentAttribute = @"LeftMargin";
NSString *const NSMacSimpleTextDocumentType = @"NSMacSimpleText";
NSString *const NSManagerDocumentAttribute = @"NSManagerDocumentAttribute";
NSString *const NSModificationTimeDocumentAttribute = @"NSModificationTimeDocumentAttribute";
NSString *const NSOfficeOpenXMLTextDocumentType = @"NSOfficeOpenXML";
NSString *const NSOpenDocumentTextDocumentType = @"NSOpenDocument";
NSString *const NSPaperSizeDocumentAttribute = @"PaperSize";
NSString *const NSPlainTextDocumentType = @"NSPlainText";
NSString *const NSPrefixSpacesDocumentAttribute = @"PrefixSpaces";
NSString *const NSRTFDTextDocumentType = @"NSRTFD";
NSString *const NSRTFTextDocumentType = @"NSRTF";
NSString *const NSReadOnlyDocumentAttribute = @"ReadOnly";
NSString *const NSRightMarginDocumentAttribute = @"RightMargin";
NSString *const NSSourceTextScalingDocumentAttribute = @"SourceTextScaling";
NSString *const NSSourceTextScalingDocumentOption = @"SourceTextScaling";
NSString *const NSSubjectDocumentAttribute = @"NSSubjectDocumentAttribute";
NSString *const NSTargetTextScalingDocumentOption = @"TargetTextScaling";
NSString *const NSTextEncodingNameDocumentAttribute = @"TextEncodingName";
NSString *const NSTextEncodingNameDocumentOption = @"TextEncodingName";
NSString *const NSTextScalingDocumentAttribute = @"TextScaling";
NSString *const NSTextSizeMultiplierDocumentOption = @"TextSizeMultiplier";
NSString *const NSTimeoutDocumentOption = @"Timeout";
NSString *const NSTitleDocumentAttribute = @"NSTitleDocumentAttribute";
NSString *const NSTopMarginDocumentAttribute = @"TopMargin";
NSString *const NSUsesScreenFontsDocumentAttribute = @"UsesScreenFonts";
NSString *const NSViewModeDocumentAttribute = @"ViewMode";
NSString *const NSViewSizeDocumentAttribute = @"ViewSize";
NSString *const NSViewZoomDocumentAttribute = @"ViewZoom";
NSString *const NSWebArchiveTextDocumentType = @"NSWebArchive";
NSString *const NSWebPreferencesDocumentOption = @"WebPreferences";
NSString *const NSWebResourceLoadDelegateDocumentOption = @"WebResourceLoadDelegate";
NSString *const NSWordMLTextDocumentType = @"NSWordML";
NSString *const NSAttributedStringDocumentAttribute = @"AttributedString";


/* more AppKit string constants that were not exported (values read from macOS) */
NSString *const NSTextHighlightColorSchemeBlue = @"NSTextHighlightColorSchemeBlue";
NSString *const NSTextHighlightColorSchemeDefault = @"NSTextHighlightColorSchemeDefault";
NSString *const NSTextHighlightColorSchemeMint = @"NSTextHighlightColorSchemeMint";
NSString *const NSTextHighlightColorSchemeOrange = @"NSTextHighlightColorSchemeOrange";
NSString *const NSTextHighlightColorSchemePink = @"NSTextHighlightColorSchemePink";
NSString *const NSTextHighlightColorSchemePurple = @"NSTextHighlightColorSchemePurple";
NSString *const NSTextHighlightStyleDefault = @"NSTextHighlightStyleDefault";
NSString *const NSTextKit1ListMarkerFormatDocumentOption = @"TextKit1ListMarkerFormat";
NSString *const NSTextListMarkerBox = @"{box}";
NSString *const NSTextListMarkerCheck = @"{check}";
NSString *const NSTextListMarkerCircle = @"{circle}";
NSString *const NSTextListMarkerDecimal = @"{decimal}";
NSString *const NSTextListMarkerDiamond = @"{diamond}";
NSString *const NSTextListMarkerDisc = @"{disc}";
NSString *const NSTextListMarkerHyphen = @"{hyphen}";
NSString *const NSTextListMarkerLowercaseAlpha = @"{lower-alpha}";
NSString *const NSTextListMarkerLowercaseHexadecimal = @"{lower-hexadecimal}";
NSString *const NSTextListMarkerLowercaseLatin = @"{lower-latin}";
NSString *const NSTextListMarkerLowercaseRoman = @"{lower-roman}";
NSString *const NSTextListMarkerOctal = @"{octal}";
NSString *const NSTextListMarkerSquare = @"{square}";
NSString *const NSTextListMarkerUppercaseAlpha = @"{upper-alpha}";
NSString *const NSTextListMarkerUppercaseHexadecimal = @"{upper-hexadecimal}";
NSString *const NSTextListMarkerUppercaseLatin = @"{upper-latin}";
NSString *const NSTextListMarkerUppercaseRoman = @"{upper-roman}";

/* ---- NSAttributedString: document readers (plain, RTF, HTML), attachments, line breaks ---- */
static NSString *XEFHTMLEntity(NSString *e) {
  if ([e isEqualToString:@"amp"]) return @"&"; if ([e isEqualToString:@"lt"]) return @"<"; if ([e isEqualToString:@"gt"]) return @">"; if ([e isEqualToString:@"quot"]) return @"\""; if ([e isEqualToString:@"apos"]) return @"'"; if ([e isEqualToString:@"nbsp"]) return @" ";
  if ([e hasPrefix:@"#"]) { unsigned long v = [e hasPrefix:@"#x"] ? strtoul([[e substringFromIndex:2] UTF8String], NULL, 16) : strtoul([[e substringFromIndex:1] UTF8String], NULL, 10); if (v) return [NSString stringWithFormat:@"%C", (unichar)v]; }
  return nil; }
static NSAttributedString *XEFParseHTML(NSString *h) {
  NSMutableAttributedString *out = [[[NSMutableAttributedString alloc] init] autorelease]; NSUInteger i = 0, n = [h length]; int bold = 0, ital = 0, und = 0;
  NSFontManager *fm = [NSFontManager sharedFontManager]; NSFont *base = [NSFont systemFontOfSize:12];
  while (i < n) {
    unichar c = [h characterAtIndex:i]; NSString *piece = nil;
    if (c == '<') {
      NSRange close = [h rangeOfString:@">" options:0 range:NSMakeRange(i, n - i)]; if (close.location == NSNotFound) break;
      NSString *tag = [[h substringWithRange:NSMakeRange(i + 1, close.location - i - 1)] lowercaseString]; i = NSMaxRange(close);
      BOOL end = [tag hasPrefix:@"/"]; if (end) tag = [tag substringFromIndex:1]; NSString *name = [[tag componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] firstObject];
      if ([name isEqualToString:@"b"] || [name isEqualToString:@"strong"]) bold += end ? -1 : 1; else if ([name isEqualToString:@"i"] || [name isEqualToString:@"em"]) ital += end ? -1 : 1; else if ([name isEqualToString:@"u"]) und += end ? -1 : 1;
      else if ([name isEqualToString:@"br"]) piece = @"\n";
      else if (end && ([@[@"p", @"div", @"h1", @"h2", @"h3", @"h4", @"h5", @"h6", @"li", @"tr"] containsObject:name])) piece = @"\n";
      else if ([@[@"script", @"style", @"head"] containsObject:name] && !end) { NSRange e = [h rangeOfString:[NSString stringWithFormat:@"</%@", name] options:NSCaseInsensitiveSearch range:NSMakeRange(i, n - i)]; if (e.location == NSNotFound) break; i = e.location; }
    } else if (c == '&') {
      NSRange semi = [h rangeOfString:@";" options:0 range:NSMakeRange(i, MIN((NSUInteger)10, n - i))]; NSString *rep = semi.location != NSNotFound ? XEFHTMLEntity([h substringWithRange:NSMakeRange(i + 1, semi.location - i - 1)]) : nil;
      if (rep) { piece = rep; i = NSMaxRange(semi); } else { piece = @"&"; i++; }
    } else { NSUInteger j = i; while (j < n && [h characterAtIndex:j] != '<' && [h characterAtIndex:j] != '&') j++; piece = [[h substringWithRange:NSMakeRange(i, j - i)] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]; i = j;
      piece = [piece stringByReplacingOccurrencesOfString:@"  " withString:@" "]; }
    if (!piece || ![piece length]) continue;
    NSFont *f = base; if (bold > 0) f = [fm convertFont:f toHaveTrait:2]; if (ital > 0) f = [fm convertFont:f toHaveTrait:1];
    NSMutableDictionary *at = [NSMutableDictionary dictionaryWithObject:f forKey:NSFontAttributeName]; if (und > 0) at[NSUnderlineStyleAttributeName] = @1;
    [out appendAttributedString:[[[NSAttributedString alloc] initWithString:piece attributes:at] autorelease]]; }
  return out; }
static NSAttributedString *XEFParseRTF(NSString *r) {
  if (![r hasPrefix:@"{\\rtf"]) return nil;
  NSMutableAttributedString *out = [[[NSMutableAttributedString alloc] init] autorelease]; NSFontManager *fm = [NSFontManager sharedFontManager]; NSFont *base = [NSFont systemFontOfSize:12];
  NSUInteger i = 0, n = [r length]; int depth = 0; BOOL boldStack[64] = {0}, italStack[64] = {0}, skipStack[64] = {0}; BOOL bold = NO, ital = NO, skip = NO;
  while (i < n) {
    unichar c = [r characterAtIndex:i];
    if (c == '{') { if (depth < 63) { boldStack[depth] = bold; italStack[depth] = ital; skipStack[depth] = skip; depth++; }
      if (i + 2 < n && [r characterAtIndex:i + 1] == '\\' && [r characterAtIndex:i + 2] == '*') skip = YES; i++; continue; }
    if (c == '}') { if (depth > 0) { depth--; bold = boldStack[depth]; ital = italStack[depth]; skip = skipStack[depth]; } i++; continue; }
    if (c == '\\') {
      i++; if (i >= n) break; unichar d = [r characterAtIndex:i];
      if (d == '\\' || d == '{' || d == '}') { if (!skip) { NSString *s = [NSString stringWithFormat:@"%C", d]; [out appendAttributedString:[[[NSAttributedString alloc] initWithString:s attributes:@{ NSFontAttributeName: base }] autorelease]]; } i++; continue; }
      if (d == '\'') { if (i + 2 < n) { unsigned v = (unsigned)strtoul([[r substringWithRange:NSMakeRange(i + 1, 2)] UTF8String], NULL, 16); if (!skip) [out appendAttributedString:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%C", (unichar)v]] autorelease]]; i += 3; } continue; }
      NSUInteger j = i; while (j < n && [[NSCharacterSet letterCharacterSet] characterIsMember:[r characterAtIndex:j]]) j++;
      NSString *word = [r substringWithRange:NSMakeRange(i, j - i)]; NSUInteger k = j; if (k < n && ([r characterAtIndex:k] == '-')) k++; while (k < n && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[r characterAtIndex:k]]) k++;
      NSInteger param = k > j ? [[r substringWithRange:NSMakeRange(j, k - j)] integerValue] : -1; BOOL hasParam = k > j; i = k; if (i < n && [r characterAtIndex:i] == ' ') i++;
      if ([word isEqualToString:@"b"]) bold = !hasParam || param != 0; else if ([word isEqualToString:@"i"]) ital = !hasParam || param != 0;
      else if ([word isEqualToString:@"par"] || [word isEqualToString:@"line"]) { if (!skip) [out appendAttributedString:[[[NSAttributedString alloc] initWithString:@"\n"] autorelease]]; }
      else if ([word isEqualToString:@"tab"]) { if (!skip) [out appendAttributedString:[[[NSAttributedString alloc] initWithString:@"\t"] autorelease]]; }
      else if ([word isEqualToString:@"u"]) { if (!skip && hasParam) [out appendAttributedString:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%C", (unichar)param]] autorelease]]; if (i < n) i++; }
      else if ([@[@"fonttbl", @"colortbl", @"stylesheet", @"info", @"pict", @"header", @"footer"] containsObject:word]) skip = YES;
      continue; }
    if (c == '\n' || c == '\r') { i++; continue; }
    NSUInteger j = i; while (j < n) { unichar x = [r characterAtIndex:j]; if (x == '\\' || x == '{' || x == '}' || x == '\n' || x == '\r') break; j++; }
    if (!skip && j > i) { NSFont *f = base; if (bold) f = [fm convertFont:f toHaveTrait:2]; if (ital) f = [fm convertFont:f toHaveTrait:1];
      [out appendAttributedString:[[[NSAttributedString alloc] initWithString:[r substringWithRange:NSMakeRange(i, j - i)] attributes:@{ NSFontAttributeName: f }] autorelease]]; }
    i = j; }
  return out; }
@implementation NSAttributedString (XEFDocuments)
- (id)initWithData:(NSData *)data options:(NSDictionary *)o documentAttributes:(NSDictionary **)da error:(NSError **)e {
  NSString *type = [o objectForKey:@"DocumentType"] ?: [o objectForKey:@"NSDocumentTypeDocumentAttribute"];
  if ([type isEqualToString:@"NSRTFTextDocumentType"]) type = @"NSRTF"; else if ([type isEqualToString:@"NSHTMLTextDocumentType"]) type = @"NSHTML"; else if ([type isEqualToString:@"NSPlainTextDocumentType"]) type = @"NSPlainText"; NSString *s = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
  if (!s) s = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
  NSAttributedString *r = nil;
  if ([type isEqualToString:@"NSRTF"] || (!type && [s hasPrefix:@"{\\rtf"])) r = XEFParseRTF(s);
  else if ([type isEqualToString:@"NSHTML"] || (!type && [s rangeOfString:@"<"].location != NSNotFound && [s rangeOfString:@">"].location != NSNotFound)) r = XEFParseHTML(s);
  else if (!type || [type isEqualToString:@"NSPlainText"]) r = s ? [[[NSAttributedString alloc] initWithString:s attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:12] }] autorelease] : nil;
  if (!r) { if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:259 userInfo:nil]; [self release]; return nil; }
  if (da) *da = type ? @{ @"DocumentType": type } : @{};
  [self release]; return [r retain]; }
- (id)initWithURL:(NSURL *)u options:(NSDictionary *)o documentAttributes:(NSDictionary **)da error:(NSError **)e { NSData *d = [NSData dataWithContentsOfURL:u]; if (!d) { if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:260 userInfo:nil]; [self release]; return nil; } return [self initWithData:d options:o documentAttributes:da error:e]; }
- (id)initWithRTF:(NSData *)d documentAttributes:(NSDictionary **)da { return [self initWithData:d options:@{ @"DocumentType": @"NSRTF" } documentAttributes:da error:NULL]; }
- (id)initWithRTFD:(NSData *)d documentAttributes:(NSDictionary **)da { return [self initWithRTF:d documentAttributes:da]; }
- (id)initWithHTML:(NSData *)d documentAttributes:(NSDictionary **)da { return [self initWithData:d options:@{ @"DocumentType": @"NSHTML" } documentAttributes:da error:NULL]; }
- (id)initWithHTML:(NSData *)d baseURL:(NSURL *)b documentAttributes:(NSDictionary **)da { return [self initWithHTML:d documentAttributes:da]; }
- (id)initWithHTML:(NSData *)d options:(NSDictionary *)o documentAttributes:(NSDictionary **)da { return [self initWithHTML:d documentAttributes:da]; }
- (id)initWithDocFormat:(NSData *)d documentAttributes:(NSDictionary **)da { [self release]; return nil; }
- (id)initWithRTFDFileWrapper:(NSFileWrapper *)w documentAttributes:(NSDictionary **)da { return [self initWithRTF:[w regularFileContents] documentAttributes:da]; }
- (id)initWithURL:(NSURL *)u documentAttributes:(NSDictionary **)da { return [self initWithURL:u options:@{} documentAttributes:da error:NULL]; }
- (id)initWithPath:(NSString *)p documentAttributes:(NSDictionary **)da { return [self initWithURL:[NSURL fileURLWithPath:p] documentAttributes:da]; }
+ (NSAttributedString *)attributedStringWithAttachment:(id)a { return [self attributedStringWithAttachment:a attributes:@{}]; }
+ (NSAttributedString *)attributedStringWithAttachment:(id)a attributes:(NSDictionary *)at {
  NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:at]; d[@"NSAttachment"] = a; return [[[NSAttributedString alloc] initWithString:@"￼" attributes:d] autorelease]; }
- (NSUInteger)lineBreakBeforeIndex:(NSUInteger)i withinRange:(NSRange)r {
  NSString *s = [self string]; if (i > NSMaxRange(r)) i = NSMaxRange(r); NSUInteger k = i;
  while (k > r.location) { if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[s characterAtIndex:k - 1]]) return k; k--; }
  return r.location; }
- (NSUInteger)lineBreakByHyphenatingBeforeIndex:(NSUInteger)i withinRange:(NSRange)r { return [self lineBreakBeforeIndex:i withinRange:r]; }
- (NSRange)rangeOfTextBlock:(id)b atIndex:(NSUInteger)i { return NSMakeRange(NSNotFound, 0); } - (NSRange)rangeOfTextTable:(id)t atIndex:(NSUInteger)i { return NSMakeRange(NSNotFound, 0); } - (NSRange)rangeOfTextList:(id)l atIndex:(NSUInteger)i { return NSMakeRange(NSNotFound, 0); }
- (NSInteger)itemNumberInTextList:(id)l atIndex:(NSUInteger)i { return 0; }
- (BOOL)prefersRTFDInRange:(NSRange)r { return NO; }
- (NSURL *)URLAtIndex:(NSUInteger)i effectiveRange:(NSRangePointer)r { id l = [self attribute:@"NSLink" atIndex:i effectiveRange:r]; return [l isKindOfClass:[NSURL class]] ? l : nil; }
+ (NSArray *)textTypes { return @[@"public.rtf", @"public.html", @"public.plain-text", @"com.apple.rtfd"]; } + (NSArray *)textUnfilteredTypes { return [self textTypes]; }
+ (NSArray *)textFileTypes { return @[@"rtf", @"html", @"htm", @"txt", @"rtfd"]; } + (NSArray *)textUnfilteredFileTypes { return [self textFileTypes]; }
+ (NSArray *)textPasteboardTypes { return @[]; } + (NSArray *)textUnfilteredPasteboardTypes { return @[]; }
@end

/* ================================================================== NSTextAttachment */
@implementation NSTextAttachment
+ (BOOL)supportsSecureCoding { return YES; }
- (id)init { if ((self = [super init])) _allowsView = YES; return self; }
- (id)initWithData:(NSData *)d ofType:(NSString *)t {
  if ((self = [self init])) { _contents = [d copy]; _fileType = [t copy]; if (d) _wrapper = [[NSFileWrapper alloc] initRegularFileWithContents:d]; } return self; }
- (id)initWithFileWrapper:(NSFileWrapper *)w { if ((self = [self init])) _wrapper = [w retain]; return self; }
- (id)initWithCoder:(NSCoder *)c { return [self init]; } - (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc { [_contents release]; [_fileType release]; [_image release]; [_wrapper release]; [_cell release]; [super dealloc]; }
- (NSData *)contents { return _contents; } - (void)setContents:(NSData *)d { [d retain]; [_contents release]; _contents = d; }
- (NSString *)fileType { return _fileType; } - (void)setFileType:(NSString *)t { [t retain]; [_fileType release]; _fileType = t; }
- (NSImage *)image { return _image; } - (void)setImage:(NSImage *)i { [i retain]; [_image release]; _image = i; }
- (NSRect)bounds { return _bounds; } - (void)setBounds:(NSRect)b { _bounds = b; }
- (NSFileWrapper *)fileWrapper { return _wrapper; } - (void)setFileWrapper:(NSFileWrapper *)w { [w retain]; [_wrapper release]; _wrapper = w; }
- (CGFloat)lineLayoutPadding { return _padding; } - (void)setLineLayoutPadding:(CGFloat)p { _padding = p; }
- (id)attachmentCell { return _cell; } - (void)setAttachmentCell:(id)c { [c retain]; [_cell release]; _cell = c; }
- (BOOL)allowsTextAttachmentView { return _allowsView; } - (void)setAllowsTextAttachmentView:(BOOL)f { _allowsView = f; } - (BOOL)usesTextAttachmentView { return NO; }
+ (Class)textAttachmentViewProviderClassForFileType:(NSString *)t { return nil; } + (void)registerTextAttachmentViewProviderClass:(Class)c forFileType:(NSString *)t {}
- (id)viewProviderForParentView:(NSView *)v location:(id)l textContainer:(NSTextContainer *)c { return nil; }
- (NSImage *)imageForBounds:(NSRect)b textContainer:(NSTextContainer *)c characterIndex:(NSUInteger)i { return _image; }
- (NSImage *)imageForBounds:(NSRect)b attributes:(NSDictionary *)a location:(id)l textContainer:(NSTextContainer *)c { return _image; }
- (NSRect)attachmentBoundsForAttributes:(NSDictionary *)a location:(id)l textContainer:(NSTextContainer *)c proposedLineFragment:(NSRect)f position:(NSPoint)p {
  if (!NSEqualRects(_bounds, NSZeroRect)) return _bounds; NSSize s = _image ? [_image size] : NSZeroSize; return NSMakeRect(0, 0, s.width, s.height); }
- (NSRect)attachmentBoundsForTextContainer:(NSTextContainer *)c proposedLineFragment:(NSRect)f glyphPosition:(NSPoint)p characterIndex:(NSUInteger)i { return [self attachmentBoundsForAttributes:@{} location:nil textContainer:c proposedLineFragment:f position:p]; }
@end
