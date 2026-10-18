/* AppKit-lite controls: NSCell / NSControl and the common controls (buttons, text fields with in-place editing, pop-up
 * buttons, scroll views, boxes), drawn with the 2D layer of AppKitGraphics.m in a light Aqua-like style, plus action
 * dispatch through the responder chain (-[NSApplication sendAction:to:from:]) and mouse tracking loops. Controls are
 * flipped views like in AppKit. Nib decoding follows the keyed-archive keys Interface Builder writes. */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitControls.h"
#include <objc/runtime.h>
#include <objc/message.h>
#include <math.h>

NSString *const NSControlTextDidBeginEditingNotification = @"NSControlTextDidBeginEditingNotification";
NSString *const NSControlTextDidChangeNotification = @"NSControlTextDidChangeNotification";
NSString *const NSControlTextDidEndEditingNotification = @"NSControlTextDidEndEditingNotification";
NSString *const NSPopUpButtonWillPopUpNotification = @"NSPopUpButtonWillPopUpNotification";
NSString *const NSPopUpButtonCellWillPopUpNotification = @"NSPopUpButtonCellWillPopUpNotification";
NSString *const NSViewFrameDidChangeNotification = @"NSViewFrameDidChangeNotification";
NSString *const NSViewBoundsDidChangeNotification = @"NSViewBoundsDidChangeNotification";
NSString *const NSScrollViewWillStartLiveScrollNotification = @"NSScrollViewWillStartLiveScrollNotification";
NSString *const NSScrollViewDidLiveScrollNotification = @"NSScrollViewDidLiveScrollNotification";
NSString *const NSScrollViewDidEndLiveScrollNotification = @"NSScrollViewDidEndLiveScrollNotification";

/* ---- helpers ------------------------------------------------------------------------------------------------------------ */
#define MOUSE_TRACK_MASK ((1ULL << NSEventTypeLeftMouseUp) | (1ULL << NSEventTypeLeftMouseDragged) | (1ULL << NSEventTypeMouseMoved))
NSEvent *XEFNextTrackingEvent(void) {
  return [NSApp nextEventMatchingMask:(NSUInteger)MOUSE_TRACK_MASK untilDate:[NSDate distantFuture] inMode:@"NSEventTrackingRunLoopMode" dequeue:YES]; }
void XEFRedrawWindowNow(NSWindow *w) { if ([w _xef2D]) [w _xefRedraw]; }

static NSDictionary *text_attrs(NSFont *f, NSColor *c, NSInteger align, NSInteger lineBreak) {
  NSMutableParagraphStyle *p = [[[NSMutableParagraphStyle alloc] init] autorelease];
  [p setAlignment:align]; [p setLineBreakMode:lineBreak];
  return @{ NSFontAttributeName: f ?: [NSFont systemFontOfSize:13], NSForegroundColorAttributeName: c ?: [NSColor controlTextColor], NSParagraphStyleAttributeName: p }; }

/* rounded bezel: fill + 1 px border */
static void draw_bezel(NSRect r, CGFloat radius, NSColor *fill, NSColor *border) {
  NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 0.5, 0.5) xRadius:radius yRadius:radius];
  [fill setFill]; [p fill];
  if (border) { [border setStroke]; [p setLineWidth:1]; [p stroke]; } }

/* ================================================================== NSCell */
@implementation NSCell
+ (BOOL)prefersTrackingUntilMouseUp { return NO; }
+ (NSMenu *)defaultMenu { return nil; }
- (id)init { return [self initTextCell:@""]; }
- (id)initTextCell:(NSString *)s {
  if ((self = [super init])) { _type = 1 /*NSTextCellType*/; _contents = [s copy]; _enabled = YES; _wraps = YES; _font = [[NSFont systemFontOfSize:13] retain]; _align = 4; _sendMask = 4 /*mouse up*/; }
  return self; }
- (id)initImageCell:(NSImage *)i {
  if ((self = [self initTextCell:@""])) { _type = 2; _image = [i retain]; } return self; }
- (void)dealloc { [_contents release]; [_font release]; [_image release]; [_formatter release]; [_rep release]; [_placeholder release]; [_attrTitle release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z {
  NSCell *c = (NSCell *)NSCopyObject(self, 0, z);
  [c->_contents retain]; [c->_font retain]; [c->_image retain]; [c->_formatter retain]; [c->_rep retain]; [c->_placeholder retain]; [c->_attrTitle retain];
  return c; }
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [self initTextCell:@""])) return nil;
  uint32_t f1 = (uint32_t)[c decodeIntForKey:@"NSCellFlags"], f2 = (uint32_t)[c decodeIntForKey:@"NSCellFlags2"];
  _state = (f1 & 0x80000000u) ? 1 : 0;
  _highlighted = (f1 & 0x40000000u) != 0;
  _enabled = !(f1 & 0x20000000u);
  _editable = (f1 & 0x10000000u) != 0;
  _bordered = (f1 & 0x00800000u) != 0;
  _bezeled = (f1 & 0x00400000u) != 0;
  _selectable = (f1 & 0x00200000u) != 0;
  _scrollable = (f1 & 0x00100000u) != 0;
  _wraps = !_scrollable && !(f1 & 0x40);   /* NSLineBreakByClipping / single line */
  _continuous = (f1 & 0x00080000u) != 0;
  _align = (f2 >> 26) & 7;
  _controlSize = (f2 >> 17) & 7;
  _lineBreak = (f1 >> 9) & 7;
  _allowsMixed = (f2 & 0x1000000u) != 0;
  id contents = [c decodeObjectForKey:@"NSContents"];
  if ([contents isKindOfClass:[NSString class]]) { [_contents release]; _contents = [contents copy]; }
  else if ([contents isKindOfClass:[NSImage class]]) { [_image release]; _image = [contents retain]; }
  else if (contents) { [_contents release]; _contents = [contents retain]; }
  NSFont *f = [c decodeObjectForKey:@"NSSupport"];
  if ([f isKindOfClass:[NSFont class]]) { [_font release]; _font = [f retain]; }
  _tag = [c decodeIntegerForKey:@"NSTag"];
  id fmt = [c decodeObjectForKey:@"NSFormatter"]; if (fmt) _formatter = [fmt retain];
  return self; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (NSInteger)type { return _type; } - (void)setType:(NSInteger)t { _type = t; }
- (id)objectValue { return _contents; }
- (void)setObjectValue:(id)v { if (v == _contents) return; id o = _contents; _contents = [v copy]; [o release]; [_attrTitle release]; _attrTitle = nil; [self _changed]; }
- (BOOL)hasValidObjectValue { return YES; }
- (NSString *)stringValue {
  if ([_contents isKindOfClass:[NSString class]]) return _contents;
  if ([_contents isKindOfClass:[NSAttributedString class]]) return [_contents string];
  if (_formatter && _contents) return [_formatter stringForObjectValue:_contents];
  if ([_contents respondsToSelector:@selector(stringValue)]) return [_contents stringValue];
  return _contents ? [_contents description] : @""; }
- (void)setStringValue:(NSString *)s { [self setObjectValue:s ?: @""]; }
- (int)intValue { return [[self stringValue] intValue]; } - (void)setIntValue:(int)v { [self setObjectValue:@(v)]; }
- (NSInteger)integerValue { return [[self stringValue] integerValue]; } - (void)setIntegerValue:(NSInteger)v { [self setObjectValue:@(v)]; }
- (float)floatValue { return [[self stringValue] floatValue]; } - (void)setFloatValue:(float)v { [self setObjectValue:@(v)]; }
- (double)doubleValue { return [[self stringValue] doubleValue]; } - (void)setDoubleValue:(double)v { [self setObjectValue:@(v)]; }
- (NSAttributedString *)attributedStringValue {
  if ([_contents isKindOfClass:[NSAttributedString class]]) return _contents;
  return [[[NSAttributedString alloc] initWithString:[self stringValue] attributes:text_attrs(_font, [self _textColor], _align, _lineBreak)] autorelease]; }
- (void)setAttributedStringValue:(NSAttributedString *)s { [self setObjectValue:s]; }
- (void)takeObjectValueFrom:(id)s { [self setObjectValue:[s objectValue]]; }
- (void)takeStringValueFrom:(id)s { [self setStringValue:[s stringValue]]; }
- (void)takeIntValueFrom:(id)s { [self setIntValue:[s intValue]]; }
- (void)takeDoubleValueFrom:(id)s { [self setDoubleValue:[s doubleValue]]; }
- (NSString *)title { return [self stringValue]; } - (void)setTitle:(NSString *)t { [self setStringValue:t]; }
- (NSFont *)font { return _font; } - (void)setFont:(NSFont *)f { [f retain]; [_font release]; _font = f; [self _changed]; }
- (NSInteger)alignment { return _align; } - (void)setAlignment:(NSInteger)a { _align = a; [self _changed]; }
- (NSInteger)lineBreakMode { return _lineBreak; } - (void)setLineBreakMode:(NSInteger)m { _lineBreak = m; }
- (BOOL)truncatesLastVisibleLine { return NO; } - (void)setTruncatesLastVisibleLine:(BOOL)f {}
- (NSInteger)baseWritingDirection { return 0; } - (void)setBaseWritingDirection:(NSInteger)d {}
- (NSInteger)state { return _state; } - (void)setState:(NSInteger)s { _state = s; [self _changed]; }
- (NSInteger)nextState { return _state == 1 ? 0 : 1; } - (void)setNextState { [self setState:[self nextState]]; }
- (BOOL)allowsMixedState { return _allowsMixed; } - (void)setAllowsMixedState:(BOOL)f { _allowsMixed = f; }
- (BOOL)isEnabled { return _enabled; } - (void)setEnabled:(BOOL)f { _enabled = f; [self _changed]; }
- (BOOL)isEditable { return _editable; } - (void)setEditable:(BOOL)f { _editable = f; if (f) _selectable = YES; }
- (BOOL)isSelectable { return _selectable || _editable; } - (void)setSelectable:(BOOL)f { _selectable = f; }
- (BOOL)isBezeled { return _bezeled; } - (void)setBezeled:(BOOL)f { _bezeled = f; [self _changed]; }
- (BOOL)isBordered { return _bordered; } - (void)setBordered:(BOOL)f { _bordered = f; [self _changed]; }
- (BOOL)isScrollable { return _scrollable; } - (void)setScrollable:(BOOL)f { _scrollable = f; if (f) _wraps = NO; }
- (BOOL)wraps { return _wraps; } - (void)setWraps:(BOOL)f { _wraps = f; if (f) _scrollable = NO; }
- (BOOL)isHighlighted { return _highlighted; } - (void)setHighlighted:(BOOL)f { _highlighted = f; [self _changed]; }
- (BOOL)isContinuous { return _continuous; } - (void)setContinuous:(BOOL)f { _continuous = f; }
- (NSInteger)sendActionOn:(NSInteger)mask { NSInteger o = _sendMask; _sendMask = mask; return o; }
- (BOOL)usesSingleLineMode { return !_wraps; } - (void)setUsesSingleLineMode:(BOOL)f { _wraps = !f; }
- (NSView *)controlView { return _controlView; } - (void)setControlView:(NSView *)v { _controlView = v; }
- (id)target { return nil; } - (void)setTarget:(id)t {}
- (SEL)action { return NULL; } - (void)setAction:(SEL)a {}
- (NSInteger)tag { return _tag; } - (void)setTag:(NSInteger)t { _tag = t; }
- (NSImage *)image { return _image; } - (void)setImage:(NSImage *)i { [i retain]; [_image release]; _image = i; [self _changed]; }
- (id)formatter { return _formatter; } - (void)setFormatter:(id)f { [f retain]; [_formatter release]; _formatter = f; }
- (id)representedObject { return _rep; } - (void)setRepresentedObject:(id)o { [o retain]; [_rep release]; _rep = o; }
- (NSUInteger)controlSize { return _controlSize; } - (void)setControlSize:(NSUInteger)s { _controlSize = s; }
- (NSInteger)focusRingType { return 0; } - (void)setFocusRingType:(NSInteger)t {}
- (BOOL)showsFirstResponder { return NO; } - (void)setShowsFirstResponder:(BOOL)f {}
- (BOOL)acceptsFirstResponder { return _enabled && (_selectable || _editable); }
- (BOOL)refusesFirstResponder { return NO; } - (void)setRefusesFirstResponder:(BOOL)f {}
- (NSInteger)backgroundStyle { return 0; } - (void)setBackgroundStyle:(NSInteger)s {}
- (NSInteger)interiorBackgroundStyle { return 0; }
- (BOOL)allowsUndo { return YES; } - (void)setAllowsUndo:(BOOL)f {}
- (BOOL)importsGraphics { return NO; } - (void)setImportsGraphics:(BOOL)f {}
- (BOOL)allowsEditingTextAttributes { return NO; } - (void)setAllowsEditingTextAttributes:(BOOL)f {}
- (NSString *)keyEquivalent { return @""; } - (void)setKeyEquivalent:(NSString *)k {}
- (NSMenu *)menu { return nil; } - (void)setMenu:(NSMenu *)m {}
- (BOOL)isOpaque { return NO; }
- (NSString *)placeholderString { return _placeholder; } - (void)setPlaceholderString:(NSString *)s { [_placeholder release]; _placeholder = [s copy]; }
- (NSAttributedString *)placeholderAttributedString { return nil; }
- (void)_changed { if (_controlView) [_controlView setNeedsDisplay:YES]; }
- (NSColor *)_textColor { return _enabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]; }
- (NSSize)cellSize {
  NSSize s = [[self attributedStringValue] size];
  if (_image) { NSSize i = [_image size]; s.width += i.width + (s.width > 0 ? 4 : 0); s.height = fmax(s.height, i.height); }
  s.width += _bezeled || _bordered ? 8 : 4; s.height += _bezeled || _bordered ? 6 : 0;
  return s; }
- (NSSize)cellSizeForBounds:(NSRect)r {
  if (_wraps && r.size.width > 0) {
    NSSize s = [[XEFTextLayout layoutWithAttributedString:[self attributedStringValue] width:r.size.width - 4] size];
    return NSMakeSize(fmin(s.width + 4, r.size.width), s.height + (_bezeled ? 6 : 0)); }
  return [self cellSize]; }
- (NSRect)drawingRectForBounds:(NSRect)r { return _bezeled ? NSInsetRect(r, 3, 3) : NSInsetRect(r, 2, 0); }
- (NSRect)titleRectForBounds:(NSRect)r { return [self drawingRectForBounds:r]; }
- (NSRect)imageRectForBounds:(NSRect)r { return r; }
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v { [self drawInteriorWithFrame:r inView:v]; }
- (void)drawInteriorWithFrame:(NSRect)r inView:(NSView *)v {
  if (_image && _type == 2) { NSSize s = [_image size]; [_image drawInRect:NSMakeRect(NSMidX(r) - s.width / 2, NSMidY(r) - s.height / 2, s.width, s.height)]; return; }
  NSAttributedString *s = [self attributedStringValue];
  NSRect tr = [self titleRectForBounds:r];
  [s drawInRect:tr]; }
- (void)highlight:(BOOL)f withFrame:(NSRect)r inView:(NSView *)v { _highlighted = f; [v setNeedsDisplay:YES]; }
- (BOOL)startTrackingAt:(NSPoint)p inView:(NSView *)v { return YES; }
- (BOOL)continueTracking:(NSPoint)last at:(NSPoint)cur inView:(NSView *)v { return YES; }
- (void)stopTracking:(NSPoint)last at:(NSPoint)stop inView:(NSView *)v mouseIsUp:(BOOL)up {}
/* modal mouse loop: highlight while inside, YES when released inside */
- (BOOL)trackMouse:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v untilMouseUp:(BOOL)untilUp {
  NSPoint p = [v convertPoint:[e locationInWindow] fromView:nil];
  if (![self startTrackingAt:p inView:v]) return NO;
  BOOL inside = NSPointInRect(p, r);
  [self highlight:inside withFrame:r inView:v]; XEFRedrawWindowNow([v window]);
  for (;;) {
    NSEvent *n = XEFNextTrackingEvent();
    if (!n) continue;
    NSPoint q = [v convertPoint:[n locationInWindow] fromView:nil];
    BOOL in = NSPointInRect(q, r);
    if ([n type] == NSEventTypeLeftMouseUp) {
      [self highlight:NO withFrame:r inView:v];
      [self stopTracking:p at:q inView:v mouseIsUp:YES];
      XEFRedrawWindowNow([v window]);
      return in; }
    if (in != inside) { inside = in; [self highlight:in withFrame:r inView:v]; XEFRedrawWindowNow([v window]); }
    if (_continuous && in && [v isKindOfClass:[NSControl class]]) [(NSControl *)v sendAction:[(NSControl *)v action] to:[(NSControl *)v target]];
    [self continueTracking:p at:q inView:v]; p = q; } }
- (void)performClick:(id)s { NSControl *c = (NSControl *)_controlView; if ([c respondsToSelector:@selector(sendAction:to:)]) [c sendAction:[c action] to:[c target]]; }
- (void)editWithFrame:(NSRect)r inView:(NSView *)v editor:(NSText *)t delegate:(id)d event:(NSEvent *)e {}
- (void)selectWithFrame:(NSRect)r inView:(NSView *)v editor:(NSText *)t delegate:(id)d start:(NSInteger)s length:(NSInteger)l {}
- (void)endEditing:(NSText *)t {}
- (void)resetCursorRect:(NSRect)r inView:(NSView *)v {}
- (NSInteger)hitTestForEvent:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v { return NSPointInRect([v convertPoint:[e locationInWindow] fromView:nil], r) ? 1 : 0; }
- (NSRect)expansionFrameWithFrame:(NSRect)r inView:(NSView *)v { return NSZeroRect; }
- (void)setUserInterfaceLayoutDirection:(NSInteger)d {} - (NSInteger)userInterfaceLayoutDirection { return 0; }
- (void)calcDrawInfo:(NSRect)r {}
- (id)accessibilityLabel { return nil; } - (void)setAccessibilityLabel:(id)l {}
@end

@implementation NSActionCell
- (id)target { return _target; } - (void)setTarget:(id)t { _target = t; }
- (SEL)action { return _action; } - (void)setAction:(SEL)a { _action = a; }
@end

/* ================================================================== NSControl */
@implementation NSControl
+ (Class)cellClass { return [NSActionCell class]; }
+ (void)setCellClass:(Class)c {}
- (id)initWithFrame:(NSRect)f {
  if ((self = [super initWithFrame:f])) {
    Class cc = [[self class] cellClass];
    if (cc) { _cell = [[cc alloc] init]; [_cell setControlView:self]; } }
  return self; }
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [super initWithCoder:c])) return nil;
  id cell = [c decodeObjectForKey:@"NSCell"];
  if ([cell isKindOfClass:[NSCell class]]) { [_cell release]; _cell = [cell retain]; [_cell setControlView:self]; }
  else if (!_cell && [[self class] cellClass]) { _cell = [[[[self class] cellClass] alloc] init]; [_cell setControlView:self]; }
  if ([c containsValueForKey:@"NSEnabled"] && _cell) [_cell setEnabled:[c decodeBoolForKey:@"NSEnabled"]];
  _tag = [c decodeIntegerForKey:@"NSTag"];
  return self; }
- (void)dealloc { [_cell setControlView:nil]; [_cell release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (id)cell { return _cell; }
- (void)setCell:(NSCell *)c { [c retain]; [_cell setControlView:nil]; [_cell release]; _cell = c; [_cell setControlView:self]; [self setNeedsDisplay:YES]; }
- (id)selectedCell { return _cell; }
- (NSInteger)selectedTag { return [_cell tag]; }
- (id)target { return [_cell target]; } - (void)setTarget:(id)t { [_cell setTarget:t]; }
- (SEL)action { return [_cell action]; } - (void)setAction:(SEL)a { [_cell setAction:a]; }
- (NSInteger)tag { return _tag; } - (void)setTag:(NSInteger)t { _tag = t; }
- (id)objectValue { return [_cell objectValue]; } - (void)setObjectValue:(id)v { [self _xefAbortEditing]; [_cell setObjectValue:v]; [self setNeedsDisplay:YES]; }
- (NSString *)stringValue { return [_cell stringValue]; } - (void)setStringValue:(NSString *)s { [self _xefAbortEditing]; [_cell setStringValue:s]; [self setNeedsDisplay:YES]; }
- (NSAttributedString *)attributedStringValue { return [_cell attributedStringValue]; }
- (void)setAttributedStringValue:(NSAttributedString *)s { [self _xefAbortEditing]; [_cell setAttributedStringValue:s]; [self setNeedsDisplay:YES]; }
- (int)intValue { return [_cell intValue]; } - (void)setIntValue:(int)v { [_cell setIntValue:v]; [self setNeedsDisplay:YES]; }
- (NSInteger)integerValue { return [_cell integerValue]; } - (void)setIntegerValue:(NSInteger)v { [_cell setIntegerValue:v]; [self setNeedsDisplay:YES]; }
- (float)floatValue { return [_cell floatValue]; } - (void)setFloatValue:(float)v { [_cell setFloatValue:v]; [self setNeedsDisplay:YES]; }
- (double)doubleValue { return [_cell doubleValue]; } - (void)setDoubleValue:(double)v { [_cell setDoubleValue:v]; [self setNeedsDisplay:YES]; }
- (void)takeObjectValueFrom:(id)s { [self setObjectValue:[s objectValue]]; }
- (void)takeStringValueFrom:(id)s { [self setStringValue:[s stringValue]]; }
- (void)takeIntValueFrom:(id)s { [self setIntValue:[s intValue]]; }
- (void)takeDoubleValueFrom:(id)s { [self setDoubleValue:[s doubleValue]]; }
- (NSFont *)font { return [_cell font]; } - (void)setFont:(NSFont *)f { [_cell setFont:f]; [self setNeedsDisplay:YES]; }
- (NSInteger)alignment { return [_cell alignment]; } - (void)setAlignment:(NSInteger)a { [_cell setAlignment:a]; }
- (NSInteger)lineBreakMode { return [_cell lineBreakMode]; } - (void)setLineBreakMode:(NSInteger)m { [_cell setLineBreakMode:m]; }
- (BOOL)isEnabled { return [_cell isEnabled]; } - (void)setEnabled:(BOOL)f { [_cell setEnabled:f]; [self setNeedsDisplay:YES]; }
- (BOOL)isContinuous { return [_cell isContinuous]; } - (void)setContinuous:(BOOL)f { [_cell setContinuous:f]; }
- (BOOL)isHighlighted { return [_cell isHighlighted]; } - (void)setHighlighted:(BOOL)f { [_cell setHighlighted:f]; }
- (id)formatter { return [_cell formatter]; } - (void)setFormatter:(id)f { [_cell setFormatter:f]; }
- (NSUInteger)controlSize { return [_cell controlSize]; } - (void)setControlSize:(NSUInteger)s { [_cell setControlSize:s]; }
- (NSInteger)sendActionOn:(NSInteger)m { return [_cell sendActionOn:m]; }
- (BOOL)usesSingleLineMode { return [_cell usesSingleLineMode]; } - (void)setUsesSingleLineMode:(BOOL)f { [_cell setUsesSingleLineMode:f]; }
- (BOOL)refusesFirstResponder { return NO; } - (void)setRefusesFirstResponder:(BOOL)f {}
- (BOOL)ignoresMultiClick { return NO; } - (void)setIgnoresMultiClick:(BOOL)f {}
- (BOOL)allowsExpansionToolTips { return NO; } - (void)setAllowsExpansionToolTips:(BOOL)f {}
- (NSSize)sizeThatFits:(NSSize)s { return [_cell cellSize]; }
- (void)sizeToFit { NSSize s = [_cell cellSize]; [self setFrameSize:NSMakeSize(ceil(s.width), ceil(s.height))]; }
- (NSSize)intrinsicContentSize { return [_cell cellSize]; }
- (void)updateCell:(NSCell *)c { [self setNeedsDisplay:YES]; }
- (void)updateCellInside:(NSCell *)c { [self setNeedsDisplay:YES]; }
- (void)drawCell:(NSCell *)c { [self setNeedsDisplay:YES]; }
- (void)drawCellInside:(NSCell *)c { [self setNeedsDisplay:YES]; }
- (void)selectCell:(NSCell *)c {}
- (void)calcSize {}
- (void)validateEditing {}
- (BOOL)abortEditing { [self _xefAbortEditing]; return NO; }
- (NSText *)currentEditor { return nil; }
- (void)_xefAbortEditing {}
- (BOOL)sendAction:(SEL)a to:(id)t { return a ? [NSApp sendAction:a to:t from:self] : NO; }
- (void)performClick:(id)s { [_cell setHighlighted:YES]; XEFRedrawWindowNow(_window); [_cell setHighlighted:NO]; [self sendAction:[self action] to:[self target]]; }
- (void)drawRect:(NSRect)r { [_cell drawWithFrame:_bounds inView:self]; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (BOOL)acceptsFirstResponder { return [_cell acceptsFirstResponder]; }
- (void)mouseDown:(NSEvent *)e {
  if (![self isEnabled]) return;
  if ([_cell trackMouse:e inRect:_bounds ofView:self untilMouseUp:YES]) {
    if ([_cell respondsToSelector:@selector(_xefClicked)]) [(id)_cell _xefClicked];
    [self sendAction:[self action] to:[self target]]; } }
- (BOOL)performKeyEquivalent:(NSEvent *)e { return NO; }
- (id)accessibilityLabel { return nil; } - (void)setAccessibilityLabel:(id)l {}
@end

/* ================================================================== buttons */
@implementation NSButtonImageSource
- (id)initWithCoder:(NSCoder *)c { if ((self = [super init])) _name = [[c decodeObjectForKey:@"NSImageName"] copy]; return self; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (NSString *)imageName { return _name; }
- (void)dealloc { [_name release]; [super dealloc]; }
@end

enum { kPush = 0, kSwitch = 3, kRadio = 4, kToggle = 2, kMomentaryChange = 5, kOnOff = 6, kMomentaryPushIn = 7 };
@implementation NSButtonCell
- (id)initTextCell:(NSString *)s {
  if ((self = [super initTextCell:s])) { _bezelStyle = 1; _bordered = YES; _buttonType = kMomentaryPushIn; _align = 1; _key = @""; _altTitle = @""; }
  return self; }
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [super initWithCoder:c])) return nil;
  uint32_t bf = (uint32_t)[c decodeIntForKey:@"NSButtonFlags"], bf2 = (uint32_t)[c decodeIntForKey:@"NSButtonFlags2"];
  _bezelStyle = (bf2 & 7) | ((bf2 & 0x20) >> 2);
  _bordered = (bf & 0x00800000u) != 0;
  _transparent = (bf & 0x00008000u) != 0;
  _imagePosition = (bf & 0x00400000u) ? ((bf & 0x00200000u) ? 3 /*right?*/ : 2) : ((bf & 0x00080000u) ? 1 : 0);
  _key = [[c decodeObjectForKey:@"NSKeyEquivalent"] copy] ?: @"";
  _keyMask = (NSUInteger)[c decodeIntegerForKey:@"NSKeyEquivModMask"];
  id alt = [c decodeObjectForKey:@"NSAlternateContents"]; _altTitle = [alt isKindOfClass:[NSString class]] ? [alt copy] : @"";
  id normal = [c decodeObjectForKey:@"NSNormalImage"];
  _buttonType = kMomentaryPushIn;
  if ([normal isKindOfClass:[NSButtonImageSource class]]) {
    NSString *n = [normal imageName];
    if ([n isEqualToString:@"NSSwitch"]) _buttonType = kSwitch;
    else if ([n isEqualToString:@"NSRadioButton"]) _buttonType = kRadio; }
  else if ([normal isKindOfClass:[NSImage class]]) { [_image release]; _image = [normal retain]; }
  if ((bf & 0x4000) && _buttonType == kMomentaryPushIn) _buttonType = kToggle;   /* "changes state" */
  if (_buttonType == kSwitch || _buttonType == kRadio) _align = 0; else if (![c decodeIntForKey:@"NSCellFlags2"]) _align = 1;
  return self; }
- (void)dealloc { [_key release]; [_altTitle release]; [_altImage release]; [super dealloc]; }
- (id)target { return _target; } - (void)setTarget:(id)t { _target = t; }
- (SEL)action { return _action; } - (void)setAction:(SEL)a { _action = a; }
- (NSString *)title { return [self stringValue]; }
- (void)setTitle:(NSString *)t { [self setStringValue:t]; }
- (NSAttributedString *)attributedTitle { return [self attributedStringValue]; }
- (void)setAttributedTitle:(NSAttributedString *)t { [self setObjectValue:t]; }
- (NSString *)alternateTitle { return _altTitle; } - (void)setAlternateTitle:(NSString *)t { [_altTitle release]; _altTitle = [t copy]; }
- (NSImage *)alternateImage { return _altImage; } - (void)setAlternateImage:(NSImage *)i { [i retain]; [_altImage release]; _altImage = i; }
- (NSString *)keyEquivalent { return _key; } - (void)setKeyEquivalent:(NSString *)k { [_key release]; _key = [k copy] ?: @""; }
- (NSUInteger)keyEquivalentModifierMask { return _keyMask; } - (void)setKeyEquivalentModifierMask:(NSUInteger)m { _keyMask = m; }
- (NSInteger)bezelStyle { return _bezelStyle; } - (void)setBezelStyle:(NSInteger)s { _bezelStyle = s; [self _changed]; }
- (void)setButtonType:(NSInteger)t { _buttonType = t; if (t == kSwitch || t == kRadio) { _align = 0; } [self _changed]; }
- (NSInteger)_xefButtonType { return _buttonType; }
- (BOOL)isTransparent { return _transparent; } - (void)setTransparent:(BOOL)f { _transparent = f; }
- (NSInteger)imagePosition { return _imagePosition; } - (void)setImagePosition:(NSInteger)p { _imagePosition = p; }
- (NSInteger)imageScaling { return 0; } - (void)setImageScaling:(NSInteger)s {}
- (BOOL)imageDimsWhenDisabled { return YES; } - (void)setImageDimsWhenDisabled:(BOOL)f {}
- (BOOL)showsBorderOnlyWhileMouseInside { return NO; } - (void)setShowsBorderOnlyWhileMouseInside:(BOOL)f {}
- (NSInteger)highlightsBy { return 0; } - (void)setHighlightsBy:(NSInteger)h {} - (NSInteger)showsStateBy { return 0; } - (void)setShowsStateBy:(NSInteger)s {}
- (NSColor *)backgroundColor { return nil; } - (void)setBackgroundColor:(NSColor *)c {}
- (NSColor *)bezelColor { return nil; } - (void)setBezelColor:(NSColor *)c {}
- (void)setPeriodicDelay:(float)d interval:(float)i {}
- (BOOL)acceptsFirstResponder { return _enabled; }
- (BOOL)_xefIsDefault { return [_key isEqualToString:@"\r"]; }
- (void)_xefClicked { if (_buttonType == kSwitch || _buttonType == kToggle || _buttonType == kOnOff || _buttonType == kMomentaryChange) [self setNextState]; else if (_buttonType == kRadio) [self setState:1]; }
- (void)performClick:(id)s { [self _xefClicked]; [super performClick:s]; }
- (NSSize)cellSize {
  NSSize t = [[self attributedStringValue] size];
  if (_buttonType == kSwitch || _buttonType == kRadio) return NSMakeSize(t.width + 22, fmax(t.height, 16) + 2);
  if (!_bordered) return NSMakeSize(t.width + 4, t.height);
  return NSMakeSize(fmax(t.width + 28, 60), 32); }
- (NSRect)_xefBezelRect:(NSRect)r {
  /* rounded push buttons in nibs are 32 pt tall around a 21 pt bezel */
  if (_bezelStyle == 1 && r.size.height >= 26) return NSMakeRect(r.origin.x + 6, r.origin.y + floor((r.size.height - 21) / 2) - 1, r.size.width - 12, 21);
  return NSInsetRect(r, 1, 1); }
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v {
  if (_transparent) return;
  BOOL on = _state == 1, dis = !_enabled;
  NSString *title = (on && [_altTitle length] && _buttonType != kSwitch && _buttonType != kRadio) ? _altTitle : [self stringValue];
  NSColor *tc = dis ? [NSColor disabledControlTextColor] : [NSColor controlTextColor];
  if (_buttonType == kSwitch || _buttonType == kRadio) {
    NSRect box = NSMakeRect(r.origin.x + 2, r.origin.y + floor((r.size.height - 14) / 2), 14, 14);
    BOOL filled = on || _state == -1;
    NSColor *fill = filled ? (dis ? [NSColor colorWithCalibratedRed:0.6 green:0.75 blue:1 alpha:1] : [NSColor controlAccentColor]) : [NSColor whiteColor];
    if (_highlighted) fill = [fill shadowWithLevel:0.15];
    draw_bezel(box, _buttonType == kRadio ? 7 : 3, fill, filled ? nil : [NSColor colorWithCalibratedWhite:0.7 alpha:1]);
    [[NSColor whiteColor] setStroke];
    if (on && _buttonType == kSwitch) {
      NSBezierPath *ck = [NSBezierPath bezierPath]; [ck setLineWidth:2];
      [ck moveToPoint:NSMakePoint(box.origin.x + 3.5, box.origin.y + 7.5)]; [ck lineToPoint:NSMakePoint(box.origin.x + 6, box.origin.y + 10.5)];
      [ck lineToPoint:NSMakePoint(box.origin.x + 10.5, box.origin.y + 3.5)]; [ck stroke]; }
    else if (_state == -1 && _buttonType == kSwitch) { [[NSColor whiteColor] setFill]; NSRectFill(NSMakeRect(box.origin.x + 3, box.origin.y + 6, 8, 2)); }
    else if (on) { [[NSColor whiteColor] setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(box, 4.5, 4.5)] fill]; }
    NSDictionary *a = text_attrs(_font, tc, 0, 4);
    NSSize ts = [title sizeWithAttributes:a];
    [title drawInRect:NSMakeRect(box.origin.x + 20, r.origin.y + floor((r.size.height - ts.height) / 2), r.size.width - 22, ts.height) withAttributes:a];
    return; }
  NSRect bz = [self _xefBezelRect:r];
  BOOL isDefault = [self _xefIsDefault] && _enabled;
  if (_bordered) {
    NSColor *fill = [NSColor whiteColor];
    if (isDefault) fill = [NSColor controlAccentColor];
    if ((_buttonType == kToggle || _buttonType == kOnOff || _buttonType == kMomentaryChange) && on) fill = [NSColor colorWithCalibratedWhite:0.82 alpha:1];
    if (_highlighted) fill = isDefault ? [fill shadowWithLevel:0.2] : [NSColor colorWithCalibratedWhite:0.78 alpha:1];
    CGFloat radius = _bezelStyle == 1 || _bezelStyle == 13 ? 5 : _bezelStyle == 12 || _bezelStyle == 7 ? bz.size.height / 2 : _bezelStyle == 9 ? bz.size.width / 2 : 3;
    if (_bezelStyle == 9) { CGFloat d = fmin(bz.size.width, bz.size.height); bz = NSMakeRect(NSMidX(bz) - d / 2, NSMidY(bz) - d / 2, d, d); radius = d / 2; }
    draw_bezel(bz, radius, fill, isDefault && !_highlighted ? nil : [NSColor colorWithCalibratedWhite:0.72 alpha:1]);
    if (isDefault) tc = [NSColor whiteColor]; }
  else if (_highlighted) { [[NSColor colorWithCalibratedWhite:0 alpha:0.1] setFill]; NSRectFillUsingOperation(bz, 2); }
  if (_bezelStyle == 9 && [title length] == 0) title = @"?";
  NSImage *img = (on && _altImage) ? _altImage : _image;
  CGFloat iw = 0;
  if (img) {
    NSSize is = [img size]; iw = is.width;
    CGFloat ix = [title length] ? bz.origin.x + 6 : NSMidX(bz) - is.width / 2;
    [img drawInRect:NSMakeRect(ix, NSMidY(bz) - is.height / 2, is.width, is.height)]; }
  if ([title length]) {
    NSDictionary *a = text_attrs(_font, tc, 1, 4);
    NSSize ts = [title sizeWithAttributes:a];
    NSRect tr = NSMakeRect(bz.origin.x + (iw ? iw + 8 : 2), NSMidY(bz) - ts.height / 2, bz.size.width - (iw ? iw + 10 : 4), ts.height);
    [title drawInRect:tr withAttributes:a]; } }
@end

@implementation NSButton
+ (Class)cellClass { return [NSButtonCell class]; }
+ (NSButton *)buttonWithTitle:(NSString *)t target:(id)tg action:(SEL)a {
  NSButton *b = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 80, 32)] autorelease]; [b setTitle:t]; [b setTarget:tg]; [b setAction:a]; [b sizeToFit]; return b; }
+ (NSButton *)checkboxWithTitle:(NSString *)t target:(id)tg action:(SEL)a {
  NSButton *b = [self buttonWithTitle:t target:tg action:a]; [b setButtonType:kSwitch]; [b sizeToFit]; return b; }
+ (NSButton *)radioButtonWithTitle:(NSString *)t target:(id)tg action:(SEL)a {
  NSButton *b = [self buttonWithTitle:t target:tg action:a]; [b setButtonType:kRadio]; [b sizeToFit]; return b; }
+ (NSButton *)buttonWithImage:(NSImage *)i target:(id)tg action:(SEL)a {
  NSButton *b = [self buttonWithTitle:@"" target:tg action:a]; [b setImage:i]; return b; }
- (NSString *)title { return [_cell title]; } - (void)setTitle:(NSString *)t { [_cell setTitle:t]; [self setNeedsDisplay:YES]; }
- (NSAttributedString *)attributedTitle { return [_cell attributedTitle]; } - (void)setAttributedTitle:(NSAttributedString *)t { [_cell setAttributedTitle:t]; [self setNeedsDisplay:YES]; }
- (NSString *)alternateTitle { return [_cell alternateTitle]; } - (void)setAlternateTitle:(NSString *)t { [_cell setAlternateTitle:t]; }
- (NSImage *)image { return [_cell image]; } - (void)setImage:(NSImage *)i { [_cell setImage:i]; [self setNeedsDisplay:YES]; }
- (NSImage *)alternateImage { return [_cell alternateImage]; } - (void)setAlternateImage:(NSImage *)i { [_cell setAlternateImage:i]; }
- (NSInteger)state { return [_cell state]; } - (void)setState:(NSInteger)s { [_cell setState:s]; [self setNeedsDisplay:YES]; }
- (BOOL)allowsMixedState { return [_cell allowsMixedState]; } - (void)setAllowsMixedState:(BOOL)f { [_cell setAllowsMixedState:f]; }
- (void)setNextState { [_cell setNextState]; [self setNeedsDisplay:YES]; }
- (NSString *)keyEquivalent { return [_cell keyEquivalent]; } - (void)setKeyEquivalent:(NSString *)k { [_cell setKeyEquivalent:k]; }
- (NSUInteger)keyEquivalentModifierMask { return [_cell keyEquivalentModifierMask]; } - (void)setKeyEquivalentModifierMask:(NSUInteger)m { [_cell setKeyEquivalentModifierMask:m]; }
- (NSInteger)bezelStyle { return [_cell bezelStyle]; } - (void)setBezelStyle:(NSInteger)s { [_cell setBezelStyle:s]; }
- (void)setButtonType:(NSInteger)t { [_cell setButtonType:t]; }
- (BOOL)isBordered { return [_cell isBordered]; } - (void)setBordered:(BOOL)f { [_cell setBordered:f]; [self setNeedsDisplay:YES]; }
- (BOOL)isTransparent { return [_cell isTransparent]; } - (void)setTransparent:(BOOL)f { [_cell setTransparent:f]; }
- (NSInteger)imagePosition { return [_cell imagePosition]; } - (void)setImagePosition:(NSInteger)p { [_cell setImagePosition:p]; }
- (NSInteger)imageScaling { return 0; } - (void)setImageScaling:(NSInteger)s {}
- (BOOL)showsBorderOnlyWhileMouseInside { return NO; } - (void)setShowsBorderOnlyWhileMouseInside:(BOOL)f {}
- (NSColor *)bezelColor { return nil; } - (void)setBezelColor:(NSColor *)c {}
- (NSColor *)contentTintColor { return nil; } - (void)setContentTintColor:(NSColor *)c {}
- (BOOL)hasDestructiveAction { return NO; } - (void)setHasDestructiveAction:(BOOL)f {}
- (void)setPeriodicDelay:(float)d interval:(float)i {}
- (void)highlight:(BOOL)f { [_cell setHighlighted:f]; [self setNeedsDisplay:YES]; }
- (void)setSound:(id)s {} - (id)sound { return nil; }
- (BOOL)performKeyEquivalent:(NSEvent *)e {
  NSString *k = [_cell keyEquivalent];
  if (![self isEnabled] || ![k length]) return NO;
  NSUInteger want = [_cell keyEquivalentModifierMask] & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl);
  NSUInteger have = [e modifierFlags] & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl);
  NSString *c = [e charactersIgnoringModifiers];
  BOOL match = [k isEqualToString:c] || ([k isEqualToString:@"\r"] && ([e keyCode] == 36 || [e keyCode] == 76)) || ([k isEqualToString:@"\e"] && [e keyCode] == 53);
  if (!match || want != have) return NO;
  [self performClick:self]; return YES; }
@end

/* ================================================================== text fields */
@implementation NSTextFieldCell
- (id)initTextCell:(NSString *)s {
  if ((self = [super initTextCell:s])) { _drawsBg = NO; _bg = [[NSColor textBackgroundColor] retain]; _tc = [[NSColor controlTextColor] retain]; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [super initWithCoder:c])) return nil;
  NSColor *bg = [c decodeObjectForKey:@"NSBackgroundColor"], *tc = [c decodeObjectForKey:@"NSTextColor"];
  if ([bg isKindOfClass:[NSColor class]]) { [_bg release]; _bg = [bg retain]; }
  if ([tc isKindOfClass:[NSColor class]]) { [_tc release]; _tc = [tc retain]; }
  _drawsBg = [c decodeBoolForKey:@"NSDrawsBackground"];
  id ph = [c decodeObjectForKey:@"NSPlaceholderString"];
  if ([ph isKindOfClass:[NSString class]]) [self setPlaceholderString:ph];
  else if ([ph isKindOfClass:[NSAttributedString class]]) [self setPlaceholderString:[ph string]];
  _bezelStyle = [c decodeIntegerForKey:@"NSTextBezelStyle"];
  return self; }
- (void)dealloc { [_bg release]; [_tc release]; [super dealloc]; }
- (NSColor *)backgroundColor { return _bg; } - (void)setBackgroundColor:(NSColor *)c { [c retain]; [_bg release]; _bg = c; [self _changed]; }
- (NSColor *)textColor { return _tc; } - (void)setTextColor:(NSColor *)c { [c retain]; [_tc release]; _tc = c; [self _changed]; }
- (BOOL)drawsBackground { return _drawsBg; } - (void)setDrawsBackground:(BOOL)f { _drawsBg = f; [self _changed]; }
- (NSInteger)bezelStyle { return _bezelStyle; } - (void)setBezelStyle:(NSInteger)s { _bezelStyle = s; }
- (NSColor *)_textColor { return _enabled ? (_tc ?: [NSColor controlTextColor]) : [NSColor disabledControlTextColor]; }
- (NSRect)drawingRectForBounds:(NSRect)r { return (_bezeled || _bordered) ? NSInsetRect(r, 4, 3) : NSInsetRect(r, 2, 0); }
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v {
  if (_bezeled) {
    [(_drawsBg || _editable ? (_bg ?: [NSColor whiteColor]) : [NSColor whiteColor]) setFill]; NSRectFill(r);
    [[NSColor colorWithCalibratedWhite:0.75 alpha:1] setFill]; NSFrameRect(r);
    if (_bezelStyle == 1) { [[NSColor colorWithCalibratedWhite:0.6 alpha:1] setStroke];
      [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 0.5, 0.5) xRadius:r.size.height / 2 yRadius:r.size.height / 2] stroke]; } }
  else {
    if (_drawsBg && _bg) { [_bg setFill]; NSRectFill(r); }
    if (_bordered) { [[NSColor blackColor] setFill]; NSFrameRect(r); } }
  [self drawInteriorWithFrame:r inView:v]; }
- (void)drawInteriorWithFrame:(NSRect)r inView:(NSView *)v {
  NSRect tr = [self drawingRectForBounds:r];
  NSString *s = [self stringValue];
  if (![s length] && [_placeholder length] && ![v respondsToSelector:@selector(_xefIsEditing)] ) {}
  BOOL editing = [v respondsToSelector:@selector(_xefIsEditing)] && [(id)v _xefIsEditing];
  if (![s length] && [_placeholder length] && !editing) {
    [_placeholder drawInRect:tr withAttributes:text_attrs(_font, [NSColor placeholderTextColor], _align, _lineBreak)]; return; }
  NSAttributedString *as = [self attributedStringValue];
  if (!_wraps) {   /* single line: vertically centred in bezeled fields */
    XEFTextLayout *l = [XEFTextLayout layoutWithAttributedString:as width:-1];
    CGFloat y = (_bezeled || _bordered) ? NSMidY(r) - [l size].height / 2 : tr.origin.y;
    CGContextRef c = XEFCurrentCGContext(); CGContextSaveGState(c); CGContextClipToRect(c, tr);
    CGFloat x = tr.origin.x;
    if (_align == 1) x = NSMidX(tr) - [l size].width / 2; else if (_align == 2) x = NSMaxX(tr) - [l size].width;
    [l drawAtTopLeft:NSMakePoint(x, y)];
    CGContextRestoreGState(c); return; }
  [as drawInRect:tr]; }
- (NSSize)cellSize {
  NSSize s = [[self attributedStringValue] size];
  if (![[self stringValue] length] && [_placeholder length]) s = [_placeholder sizeWithAttributes:text_attrs(_font, nil, 0, 0)];
  if (s.height < 1) s.height = [_font _xefLineHeight];
  return NSMakeSize(ceil(s.width) + ((_bezeled || _bordered) ? 8 : 4), ceil(s.height) + ((_bezeled || _bordered) ? 6 : 0)); }
@end

@implementation NSTextField
+ (Class)cellClass { return [NSTextFieldCell class]; }
+ (NSTextField *)labelWithString:(NSString *)s {
  NSTextField *t = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
  [t setStringValue:s]; [t setBezeled:NO]; [t setDrawsBackground:NO]; [t setEditable:NO]; [t setSelectable:NO]; [t sizeToFit]; return t; }
+ (NSTextField *)wrappingLabelWithString:(NSString *)s { NSTextField *t = [self labelWithString:s]; [[t cell] setWraps:YES]; return t; }
+ (NSTextField *)textFieldWithString:(NSString *)s {
  NSTextField *t = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 96, 22)] autorelease]; [t setStringValue:s]; return t; }
- (id)initWithFrame:(NSRect)f {
  if ((self = [super initWithFrame:f])) { [_cell setBezeled:YES]; [_cell setEditable:YES]; [_cell setDrawsBackground:YES]; [_cell setWraps:NO]; [_cell setScrollable:YES]; } return self; }
- (void)dealloc { [_editString release]; [super dealloc]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)isEditable { return [_cell isEditable]; } - (void)setEditable:(BOOL)f { [_cell setEditable:f]; }
- (BOOL)isSelectable { return [_cell isSelectable]; } - (void)setSelectable:(BOOL)f { [_cell setSelectable:f]; }
- (BOOL)isBezeled { return [_cell isBezeled]; } - (void)setBezeled:(BOOL)f { [_cell setBezeled:f]; }
- (BOOL)isBordered { return [_cell isBordered]; } - (void)setBordered:(BOOL)f { [_cell setBordered:f]; }
- (BOOL)drawsBackground { return [_cell drawsBackground]; } - (void)setDrawsBackground:(BOOL)f { [_cell setDrawsBackground:f]; }
- (NSColor *)backgroundColor { return [_cell backgroundColor]; } - (void)setBackgroundColor:(NSColor *)c { [_cell setBackgroundColor:c]; }
- (NSColor *)textColor { return [_cell textColor]; } - (void)setTextColor:(NSColor *)c { [_cell setTextColor:c]; [self setNeedsDisplay:YES]; }
- (NSString *)placeholderString { return [_cell placeholderString]; } - (void)setPlaceholderString:(NSString *)s { [_cell setPlaceholderString:s]; }
- (NSAttributedString *)placeholderAttributedString { return nil; } - (void)setPlaceholderAttributedString:(NSAttributedString *)s { [_cell setPlaceholderString:[s string]]; }
- (NSInteger)bezelStyle { return [_cell bezelStyle]; } - (void)setBezelStyle:(NSInteger)s { [_cell setBezelStyle:s]; }
- (CGFloat)preferredMaxLayoutWidth { return 0; } - (void)setPreferredMaxLayoutWidth:(CGFloat)w {}
- (NSInteger)maximumNumberOfLines { return 0; } - (void)setMaximumNumberOfLines:(NSInteger)n {}
- (BOOL)allowsEditingTextAttributes { return NO; } - (void)setAllowsEditingTextAttributes:(BOOL)f {}
- (BOOL)importsGraphics { return NO; } - (void)setImportsGraphics:(BOOL)f {}
- (BOOL)allowsDefaultTighteningForTruncation { return NO; } - (void)setAllowsDefaultTighteningForTruncation:(BOOL)f {}
- (BOOL)isAutomaticTextCompletionEnabled { return NO; } - (void)setAutomaticTextCompletionEnabled:(BOOL)f {}
- (void)setTextFieldStyle:(NSInteger)s {}
- (BOOL)acceptsFirstResponder { return [_cell isEnabled] && [_cell isSelectable]; }
- (BOOL)_xefIsEditing { return _editing; }
- (BOOL)becomeFirstResponder {
  if (![_cell isEditable]) return [_cell isSelectable];
  _editing = YES; [_editString release]; _editString = [[_cell stringValue] mutableCopy];
  _sel = NSMakeRange(0, [_editString length]);
  [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidBeginEditingNotification object:self];
  [self setNeedsDisplay:YES]; return YES; }
- (BOOL)resignFirstResponder { [self _xefEndEditing:0]; return YES; }
- (void)_xefAbortEditing { if (_editing) { _editing = NO; [_editString release]; _editString = nil; [self setNeedsDisplay:YES]; } }
- (void)_xefEndEditing:(NSInteger)movement {
  if (!_editing) return;
  _editing = NO;
  [_cell setStringValue:_editString];
  [_editString release]; _editString = nil;
  NSDictionary *ui = @{ @"NSTextMovement": @(movement) };
  NSNotification *n = [NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:self userInfo:ui];
  if ([_delegate respondsToSelector:@selector(controlTextDidEndEditing:)]) [_delegate controlTextDidEndEditing:n];
  [[NSNotificationCenter defaultCenter] postNotification:n];
  [self setNeedsDisplay:YES]; }
- (NSString *)stringValue { return _editing ? [[_editString copy] autorelease] : [super stringValue]; }
- (NSText *)currentEditor { return nil; }
- (void)selectText:(id)s { if ([_window makeFirstResponder:self]) { _sel = NSMakeRange(0, [_editString length]); [self setNeedsDisplay:YES]; } }
- (void)_xefChanged {
  NSNotification *n = [NSNotification notificationWithName:NSControlTextDidChangeNotification object:self userInfo:nil];
  if ([_delegate respondsToSelector:@selector(controlTextDidChange:)]) [_delegate controlTextDidChange:n];
  [[NSNotificationCenter defaultCenter] postNotification:n];
  if ([_cell isContinuous]) [self sendAction:[self action] to:[self target]];
  [self setNeedsDisplay:YES]; }
- (void)_xefReplaceSelection:(NSString *)s {
  if (_sel.location > [_editString length]) _sel = NSMakeRange([_editString length], 0);
  if (NSMaxRange(_sel) > [_editString length]) _sel.length = [_editString length] - _sel.location;
  [_editString replaceCharactersInRange:_sel withString:s];
  _sel = NSMakeRange(_sel.location + [s length], 0);
  [self _xefChanged]; }
- (void)keyDown:(NSEvent *)e {
  if (!_editing) { [super keyDown:e]; return; }
  [self interpretKeyEvents:@[e]]; }
- (void)insertText:(id)s replacementRange:(NSRange)r { [self _xefReplaceSelection:[s isKindOfClass:[NSAttributedString class]] ? [s string] : s]; }
- (void)insertText:(id)s { [self insertText:s replacementRange:NSMakeRange(NSNotFound, 0)]; }
- (void)doCommandBySelector:(SEL)sel {
  if ([_delegate respondsToSelector:@selector(control:textView:doCommandBySelector:)] &&
      ((BOOL (*)(id, SEL, id, id, SEL))objc_msgSend)(_delegate, @selector(control:textView:doCommandBySelector:), self, nil, sel)) return;
  if ([self respondsToSelector:sel]) [self performSelector:sel withObject:nil]; }
- (void)deleteBackward:(id)s { if (_sel.length == 0 && _sel.location > 0) _sel = NSMakeRange(_sel.location - 1, 1); if (_sel.length) [self _xefReplaceSelection:@""]; }
- (void)deleteForward:(id)s { if (_sel.length == 0 && _sel.location < [_editString length]) _sel.length = 1; if (_sel.length) [self _xefReplaceSelection:@""]; }
- (void)moveLeft:(id)s { _sel = NSMakeRange(_sel.length ? _sel.location : (_sel.location ? _sel.location - 1 : 0), 0); [self setNeedsDisplay:YES]; }
- (void)moveRight:(id)s { NSUInteger e = NSMaxRange(_sel); _sel = NSMakeRange(_sel.length ? e : MIN(e + 1, [_editString length]), 0); [self setNeedsDisplay:YES]; }
- (void)moveToBeginningOfLine:(id)s { _sel = NSMakeRange(0, 0); [self setNeedsDisplay:YES]; }
- (void)moveToEndOfLine:(id)s { _sel = NSMakeRange([_editString length], 0); [self setNeedsDisplay:YES]; }
- (void)moveUp:(id)s { [self moveToBeginningOfLine:s]; } - (void)moveDown:(id)s { [self moveToEndOfLine:s]; }
- (void)selectAll:(id)s { if (_editing) { _sel = NSMakeRange(0, [_editString length]); [self setNeedsDisplay:YES]; } }
- (void)insertNewline:(id)s { [self _xefEndEditing:0x10 /*NSReturnTextMovement*/]; [self sendAction:[self action] to:[self target]]; if (_window) [_window makeFirstResponder:self]; }
- (void)insertTab:(id)s { [self _xefEndEditing:0x11]; [_window selectNextKeyView:self]; }
- (void)insertBacktab:(id)s { [self _xefEndEditing:0x12]; [_window selectPreviousKeyView:self]; }
- (void)cancelOperation:(id)s { [self _xefAbortEditing]; }
- (void)copy:(id)s { if (_editing && _sel.length) { NSPasteboard *p = [NSPasteboard generalPasteboard]; [p clearContents]; [p setString:[_editString substringWithRange:_sel] forType:NSPasteboardTypeString]; } }
- (void)cut:(id)s { [self copy:s]; if (_editing && _sel.length) [self _xefReplaceSelection:@""]; }
- (void)paste:(id)s { NSString *t = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]; if (_editing && t) [self _xefReplaceSelection:t]; }
- (void)mouseDown:(NSEvent *)e {
  if (![_cell isEnabled]) return;
  if (![_cell isSelectable]) { [super mouseDown:e]; return; }
  if (!_editing) { [_window makeFirstResponder:self]; if (!_editing) return; }
  NSUInteger i = [self _xefIndexAtEvent:e];
  _sel = NSMakeRange(i, 0);
  if ([e clickCount] >= 2) _sel = NSMakeRange(0, [_editString length]);
  [self setNeedsDisplay:YES]; XEFRedrawWindowNow(_window);
  NSUInteger anchor = i;
  for (;;) {
    NSEvent *n = XEFNextTrackingEvent(); if (!n) continue;
    if ([n type] == NSEventTypeLeftMouseUp) break;
    NSUInteger j = [self _xefIndexAtEvent:n];
    _sel = j < anchor ? NSMakeRange(j, anchor - j) : NSMakeRange(anchor, j - anchor);
    [self setNeedsDisplay:YES]; XEFRedrawWindowNow(_window); } }
- (XEFTextLayout *)_xefEditLayout {
  NSTextFieldCell *c = _cell;
  return [XEFTextLayout layoutWithString:_editString ?: @"" attributes:text_attrs([c font], [c _textColor], 0, 0) width:[c wraps] ? [c drawingRectForBounds:_bounds].size.width : -1]; }
- (NSPoint)_xefTextOrigin:(XEFTextLayout *)l {
  NSTextFieldCell *c = _cell; NSRect tr = [c drawingRectForBounds:_bounds];
  CGFloat y = ([c isBezeled] || [c isBordered]) && ![c wraps] ? NSMidY(_bounds) - [l size].height / 2 : tr.origin.y;
  CGFloat x = tr.origin.x - _scrollX;
  return NSMakePoint(x, y); }
- (NSUInteger)_xefIndexAtEvent:(NSEvent *)e {
  XEFTextLayout *l = [self _xefEditLayout]; NSPoint o = [self _xefTextOrigin:l];
  NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
  return [l characterIndexAtPoint:NSMakePoint(p.x - o.x, p.y - o.y)]; }
- (void)drawRect:(NSRect)r {
  if (!_editing) { _scrollX = 0; [super drawRect:r]; return; }
  NSTextFieldCell *c = _cell;
  /* bezel/background from the cell, then the edited text with selection and caret */
  id saved = [[c objectValue] retain]; [c setObjectValue:@""];
  NSString *ph = [[c placeholderString] retain]; [c setPlaceholderString:nil];
  [c drawWithFrame:_bounds inView:self];
  [c setObjectValue:saved]; [saved release]; [c setPlaceholderString:ph]; [ph release];
  XEFTextLayout *l = [self _xefEditLayout];
  NSRect tr = [c drawingRectForBounds:_bounds];
  NSRect caret = [l caretRectAtIndex:NSMaxRange(_sel)];
  if (caret.origin.x - _scrollX > tr.size.width - 2) _scrollX = caret.origin.x - tr.size.width + 2;
  if (caret.origin.x - _scrollX < 0) _scrollX = caret.origin.x;
  NSPoint o = [self _xefTextOrigin:l];
  CGContextRef cg = XEFCurrentCGContext(); CGContextSaveGState(cg); CGContextClipToRect(cg, NSInsetRect(_bounds, 1, 1));
  if (_sel.length) {
    NSRect a = [l caretRectAtIndex:_sel.location], b = [l caretRectAtIndex:NSMaxRange(_sel)];
    [[NSColor selectedTextBackgroundColor] setFill];
    NSRectFillUsingOperation(NSMakeRect(o.x + fmin(a.origin.x, b.origin.x), o.y + a.origin.y, fabs(b.origin.x - a.origin.x), a.size.height), 2); }
  [l drawAtTopLeft:o];
  if (!_sel.length && [_window isKeyWindow]) { [[NSColor controlTextColor] setFill]; NSRectFill(NSMakeRect(o.x + caret.origin.x, o.y + caret.origin.y, 1, caret.size.height)); }
  CGContextRestoreGState(cg);
  if ([c isBezeled]) { [[NSColor keyboardFocusIndicatorColor] setStroke]; NSBezierPath *f = [NSBezierPath bezierPathWithRect:NSInsetRect(_bounds, 1, 1)]; [f setLineWidth:2]; [f stroke]; } }
@end

@implementation NSSecureTextField
- (void)drawRect:(NSRect)r { [super drawRect:r]; }
@end
@implementation NSSecureTextFieldCell
- (NSAttributedString *)attributedStringValue {
  NSUInteger n = [[self stringValue] length]; NSMutableString *s = [NSMutableString string]; for (NSUInteger i = 0; i < n; i++) [s appendString:@"•"];
  return [[[NSAttributedString alloc] initWithString:s attributes:text_attrs(_font, [self _textColor], _align, 0)] autorelease]; }
@end
@implementation NSSearchField
@end
@implementation NSSearchFieldCell
@end
@implementation NSTokenField
@end
@implementation NSTokenFieldCell
@end

/* ================================================================== pop-up buttons */
@implementation NSPopUpButtonCell
- (id)initTextCell:(NSString *)s pullsDown:(BOOL)p {
  if ((self = [super initTextCell:s])) { _pullsDown = p; _menu = [[NSMenu alloc] initWithTitle:@""]; _selected = -1; _bezelStyle = 1; _align = 0; } return self; }
- (id)initTextCell:(NSString *)s { return [self initTextCell:s pullsDown:NO]; }
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [super initWithCoder:c])) return nil;
  NSMenu *m = [c decodeObjectForKey:@"NSMenu"];
  if ([m isKindOfClass:[NSMenu class]]) { [_menu release]; _menu = [m retain]; }
  _pullsDown = [c decodeBoolForKey:@"NSPullDown"];
  _selected = [c containsValueForKey:@"NSSelectedIndex"] ? [c decodeIntegerForKey:@"NSSelectedIndex"] : ([[_menu itemArray] count] ? 0 : -1);
  _arrowPosition = [c decodeIntegerForKey:@"NSArrowPosition"];
  _preferredEdge = [c decodeIntegerForKey:@"NSPreferredEdge"];
  _align = 0;
  return self; }
- (void)dealloc { [_menu release]; [super dealloc]; }
- (NSMenu *)menu { return _menu; } - (void)setMenu:(NSMenu *)m { [m retain]; [_menu release]; _menu = m; [self _changed]; }
- (BOOL)pullsDown { return _pullsDown; } - (void)setPullsDown:(BOOL)f { _pullsDown = f; }
- (BOOL)autoenablesItems { return YES; } - (void)setAutoenablesItems:(BOOL)f {}
- (NSInteger)preferredEdge { return _preferredEdge; } - (void)setPreferredEdge:(NSInteger)e { _preferredEdge = e; }
- (BOOL)usesItemFromMenu { return YES; } - (void)setUsesItemFromMenu:(BOOL)f {}
- (BOOL)altersStateOfSelectedItem { return YES; } - (void)setAltersStateOfSelectedItem:(BOOL)f {}
- (NSInteger)arrowPosition { return _arrowPosition; } - (void)setArrowPosition:(NSInteger)p { _arrowPosition = p; }
- (NSArray *)itemArray { return [_menu itemArray]; }
- (NSInteger)numberOfItems { return [[_menu itemArray] count]; }
- (NSMenuItem *)itemAtIndex:(NSInteger)i { NSArray *a = [_menu itemArray]; return i >= 0 && i < (NSInteger)[a count] ? [a objectAtIndex:i] : nil; }
- (NSString *)itemTitleAtIndex:(NSInteger)i { return [[self itemAtIndex:i] title] ?: @""; }
- (NSArray *)itemTitles { NSMutableArray *a = [NSMutableArray array]; for (NSMenuItem *i in [_menu itemArray]) [a addObject:[i title] ?: @""]; return a; }
- (NSInteger)indexOfItem:(NSMenuItem *)i { NSUInteger x = [[_menu itemArray] indexOfObjectIdenticalTo:i]; return x == NSNotFound ? -1 : (NSInteger)x; }
- (NSInteger)indexOfItemWithTitle:(NSString *)t { NSInteger k = 0; for (NSMenuItem *i in [_menu itemArray]) { if ([[i title] isEqualToString:t]) return k; k++; } return -1; }
- (NSInteger)indexOfItemWithTag:(NSInteger)t { NSInteger k = 0; for (NSMenuItem *i in [_menu itemArray]) { if ([i tag] == t) return k; k++; } return -1; }
- (NSInteger)indexOfItemWithRepresentedObject:(id)o { NSInteger k = 0; for (NSMenuItem *i in [_menu itemArray]) { if ([[i representedObject] isEqual:o]) return k; k++; } return -1; }
- (NSMenuItem *)itemWithTitle:(NSString *)t { return [self itemAtIndex:[self indexOfItemWithTitle:t]]; }
- (NSMenuItem *)lastItem { return [[_menu itemArray] lastObject]; }
- (void)addItemWithTitle:(NSString *)t { [_menu addItemWithTitle:t action:NULL keyEquivalent:@""]; if (_selected < 0) _selected = 0; [self _changed]; }
- (void)addItemsWithTitles:(NSArray *)ts { for (NSString *t in ts) [self addItemWithTitle:t]; }
- (void)insertItemWithTitle:(NSString *)t atIndex:(NSInteger)i { [_menu insertItemWithTitle:t action:NULL keyEquivalent:@"" atIndex:i]; if (_selected < 0) _selected = 0; [self _changed]; }
- (void)removeItemWithTitle:(NSString *)t { NSInteger i = [self indexOfItemWithTitle:t]; if (i >= 0) [self removeItemAtIndex:i]; }
- (void)removeItemAtIndex:(NSInteger)i { [_menu removeItemAtIndex:i]; if (_selected >= [self numberOfItems]) _selected = [self numberOfItems] - 1; [self _changed]; }
- (void)removeAllItems { [_menu removeAllItems]; _selected = -1; [self _changed]; }
- (NSMenuItem *)selectedItem { return [self itemAtIndex:_selected]; }
- (NSInteger)indexOfSelectedItem { return _selected; }
- (void)selectItem:(NSMenuItem *)i { [self selectItemAtIndex:[self indexOfItem:i]]; }
- (void)selectItemAtIndex:(NSInteger)i {
  if (!_pullsDown) for (NSMenuItem *m in [_menu itemArray]) [m setState:0];
  _selected = i; if (!_pullsDown) [[self selectedItem] setState:1]; [self _changed]; }
- (void)selectItemWithTitle:(NSString *)t { [self selectItemAtIndex:[self indexOfItemWithTitle:t]]; }
- (BOOL)selectItemWithTag:(NSInteger)t { NSInteger i = [self indexOfItemWithTag:t]; if (i < 0) return NO; [self selectItemAtIndex:i]; return YES; }
- (NSString *)titleOfSelectedItem { return [[self selectedItem] title]; }
- (NSInteger)selectedTag { return [[self selectedItem] tag]; }
- (id)objectValue { return @(_selected); } - (void)setObjectValue:(id)v { [self selectItemAtIndex:[v integerValue]]; }
- (NSString *)stringValue { return _pullsDown ? [self itemTitleAtIndex:0] : ([self titleOfSelectedItem] ?: @""); }
- (void)synchronizeTitleAndSelectedItem {}
- (void)setTitle:(NSString *)t { if (_pullsDown) { if ([self numberOfItems]) [[self itemAtIndex:0] setTitle:t]; else [self addItemWithTitle:t]; } else [self selectItemWithTitle:t]; }
- (NSSize)cellSize {
  CGFloat w = 0; NSDictionary *a = text_attrs(_font, nil, 0, 0);
  for (NSMenuItem *i in [_menu itemArray]) w = fmax(w, [[i title] sizeWithAttributes:a].width);
  return NSMakeSize(w + 40, 25); }
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v {
  NSRect bz = r.size.height >= 24 ? NSMakeRect(r.origin.x + 3, r.origin.y + floor((r.size.height - 21) / 2), r.size.width - 6, 21) : NSInsetRect(r, 1, 1);
  if (_bordered || _bezelStyle) draw_bezel(bz, 5, _highlighted ? [NSColor colorWithCalibratedWhite:0.85 alpha:1] : [NSColor whiteColor], [NSColor colorWithCalibratedWhite:0.72 alpha:1]);
  NSRect arrow = NSMakeRect(NSMaxX(bz) - 18, bz.origin.y + 2, 16, bz.size.height - 4);
  draw_bezel(arrow, 4, _enabled ? [NSColor controlAccentColor] : [NSColor colorWithCalibratedWhite:0.75 alpha:1], nil);
  [[NSColor whiteColor] setStroke];
  NSBezierPath *p = [NSBezierPath bezierPath]; [p setLineWidth:1.5];
  CGFloat cx = NSMidX(arrow), cy = NSMidY(arrow);
  if (_pullsDown) { [p moveToPoint:NSMakePoint(cx - 3.5, cy - 1.5)]; [p lineToPoint:NSMakePoint(cx, cy + 2)]; [p lineToPoint:NSMakePoint(cx + 3.5, cy - 1.5)]; }
  else { [p moveToPoint:NSMakePoint(cx - 3, cy - 2)]; [p lineToPoint:NSMakePoint(cx, cy - 5)]; [p lineToPoint:NSMakePoint(cx + 3, cy - 2)];
         [p moveToPoint:NSMakePoint(cx - 3, cy + 2)]; [p lineToPoint:NSMakePoint(cx, cy + 5)]; [p lineToPoint:NSMakePoint(cx + 3, cy + 2)]; }
  [p stroke];
  NSString *t = [self stringValue];
  NSDictionary *a = text_attrs(_font, _enabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor], 0, 4);
  NSSize ts = [t sizeWithAttributes:a];
  [t drawInRect:NSMakeRect(bz.origin.x + 8, NSMidY(bz) - ts.height / 2, bz.size.width - 30, ts.height) withAttributes:a]; }
/* pops the menu up at the control (AppKitMenu.m) and selects the chosen item */
- (BOOL)trackMouse:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v untilMouseUp:(BOOL)u {
  [[NSNotificationCenter defaultCenter] postNotificationName:NSPopUpButtonWillPopUpNotification object:v];
  [self setHighlighted:YES]; XEFRedrawWindowNow([v window]);
  NSMenuItem *pos = _pullsDown ? nil : [self selectedItem];
  NSMenuItem *chosen = [_menu _xefPopUpPositioningItem:pos atLocation:NSMakePoint(r.origin.x, _pullsDown ? NSMaxY(r) : r.origin.y) inView:v minWidth:r.size.width];
  [self setHighlighted:NO];
  if (!chosen) { XEFRedrawWindowNow([v window]); return NO; }
  NSInteger idx = [self indexOfItem:chosen];
  if (!_pullsDown && idx >= 0) [self selectItemAtIndex:idx];
  XEFRedrawWindowNow([v window]);
  if ([chosen action]) { [NSApp sendAction:[chosen action] to:[chosen target] from:chosen]; return _pullsDown ? NO : YES; }
  return YES; }
- (void)performClickWithFrame:(NSRect)r inView:(NSView *)v { [self trackMouse:nil inRect:r ofView:v untilMouseUp:YES]; }
- (void)attachPopUpWithFrame:(NSRect)r inView:(NSView *)v {} - (void)dismissPopUp {}
@end

@implementation NSPopUpButton
+ (Class)cellClass { return [NSPopUpButtonCell class]; }
- (id)initWithFrame:(NSRect)f pullsDown:(BOOL)p { if ((self = [super initWithFrame:f])) [_cell setPullsDown:p]; return self; }
- (NSMenu *)menu { return [_cell menu]; } - (void)setMenu:(NSMenu *)m { [_cell setMenu:m]; }
- (BOOL)pullsDown { return [_cell pullsDown]; } - (void)setPullsDown:(BOOL)f { [_cell setPullsDown:f]; }
- (BOOL)autoenablesItems { return YES; } - (void)setAutoenablesItems:(BOOL)f {}
- (NSInteger)preferredEdge { return [_cell preferredEdge]; } - (void)setPreferredEdge:(NSInteger)e { [_cell setPreferredEdge:e]; }
- (NSArray *)itemArray { return [_cell itemArray]; } - (NSInteger)numberOfItems { return [_cell numberOfItems]; }
- (NSMenuItem *)itemAtIndex:(NSInteger)i { return [_cell itemAtIndex:i]; } - (NSString *)itemTitleAtIndex:(NSInteger)i { return [_cell itemTitleAtIndex:i]; }
- (NSArray *)itemTitles { return [_cell itemTitles]; } - (NSMenuItem *)itemWithTitle:(NSString *)t { return [_cell itemWithTitle:t]; }
- (NSMenuItem *)lastItem { return [_cell lastItem]; }
- (NSInteger)indexOfItem:(NSMenuItem *)i { return [_cell indexOfItem:i]; } - (NSInteger)indexOfItemWithTitle:(NSString *)t { return [_cell indexOfItemWithTitle:t]; }
- (NSInteger)indexOfItemWithTag:(NSInteger)t { return [_cell indexOfItemWithTag:t]; }
- (NSInteger)indexOfItemWithRepresentedObject:(id)o { return [_cell indexOfItemWithRepresentedObject:o]; }
- (void)addItemWithTitle:(NSString *)t { [_cell addItemWithTitle:t]; } - (void)addItemsWithTitles:(NSArray *)a { [_cell addItemsWithTitles:a]; }
- (void)insertItemWithTitle:(NSString *)t atIndex:(NSInteger)i { [_cell insertItemWithTitle:t atIndex:i]; }
- (void)removeItemWithTitle:(NSString *)t { [_cell removeItemWithTitle:t]; } - (void)removeItemAtIndex:(NSInteger)i { [_cell removeItemAtIndex:i]; }
- (void)removeAllItems { [_cell removeAllItems]; }
- (NSMenuItem *)selectedItem { return [_cell selectedItem]; } - (NSInteger)indexOfSelectedItem { return [_cell indexOfSelectedItem]; }
- (NSInteger)selectedTag { return [_cell selectedTag]; } - (NSString *)titleOfSelectedItem { return [_cell titleOfSelectedItem]; }
- (void)selectItem:(NSMenuItem *)i { [_cell selectItem:i]; [self setNeedsDisplay:YES]; }
- (void)selectItemAtIndex:(NSInteger)i { [_cell selectItemAtIndex:i]; [self setNeedsDisplay:YES]; }
- (void)selectItemWithTitle:(NSString *)t { [_cell selectItemWithTitle:t]; [self setNeedsDisplay:YES]; }
- (BOOL)selectItemWithTag:(NSInteger)t { BOOL r = [_cell selectItemWithTag:t]; [self setNeedsDisplay:YES]; return r; }
- (void)setTitle:(NSString *)t { [_cell setTitle:t]; [self setNeedsDisplay:YES]; }
- (void)synchronizeTitleAndSelectedItem {}
- (void)mouseDown:(NSEvent *)e { if ([self isEnabled] && [_cell trackMouse:e inRect:_bounds ofView:self untilMouseUp:YES]) [self sendAction:[self action] to:[self target]]; }
@end

/* ================================================================== scroll views */
@implementation NSScroller
+ (CGFloat)scrollerWidth { return 15; }
+ (CGFloat)scrollerWidthForControlSize:(NSUInteger)s scrollerStyle:(NSInteger)st { return st == 1 ? 0 : 15; }
+ (NSInteger)preferredScrollerStyle { return 1; /* overlay */ }
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { _knobProportion = 1; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) { _value = [c decodeDoubleForKey:@"NSCurValue"]; _knobProportion = [c containsValueForKey:@"NSPercent"] ? [c decodeDoubleForKey:@"NSPercent"] : 1; } return self; }
- (BOOL)isFlipped { return YES; }
- (double)doubleValue { return _value; } - (void)setDoubleValue:(double)v { _value = fmax(0, fmin(1, v)); [self setNeedsDisplay:YES]; }
- (CGFloat)knobProportion { return _knobProportion; } - (void)setKnobProportion:(CGFloat)p { _knobProportion = fmax(0, fmin(1, p)); [self setNeedsDisplay:YES]; }
- (NSInteger)scrollerStyle { return 1; } - (void)setScrollerStyle:(NSInteger)s {}
- (NSInteger)knobStyle { return 0; } - (void)setKnobStyle:(NSInteger)s {}
- (NSInteger)hitPart { return _hitPart; }
- (BOOL)_xefVertical { return _frame.size.height >= _frame.size.width; }
- (NSRect)rectForPart:(NSInteger)part {
  if (part != 2 /*knob*/) return _bounds;
  BOOL v = [self _xefVertical];
  CGFloat len = v ? _bounds.size.height : _bounds.size.width, k = fmax(20, len * _knobProportion), pos = (len - k) * _value;
  return v ? NSMakeRect(2, pos, _bounds.size.width - 4, k) : NSMakeRect(pos, 2, k, _bounds.size.height - 4); }
- (void)drawRect:(NSRect)r {
  if (_knobProportion >= 1 || ![self isEnabled]) return;
  NSRect k = NSInsetRect([self rectForPart:2], 1, 1);
  CGFloat rad = fmin(k.size.width, k.size.height) / 2;
  [[NSColor colorWithCalibratedWhite:0 alpha:0.35] setFill];
  [[NSBezierPath bezierPathWithRoundedRect:k xRadius:rad yRadius:rad] fill]; }
- (void)drawKnob {} - (void)drawKnobSlotInRect:(NSRect)r highlight:(BOOL)h {}
- (BOOL)isEnabled { return _knobProportion < 1; }
- (void)mouseDown:(NSEvent *)e {
  BOOL v = [self _xefVertical];
  NSRect k = [self rectForPart:2];
  CGFloat len = v ? _bounds.size.height : _bounds.size.width, kl = v ? k.size.height : k.size.width;
  NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
  CGFloat start = v ? p.y : p.x, startVal = _value;
  if (!NSPointInRect(p, k)) { _value = fmax(0, fmin(1, (start - kl / 2) / fmax(1, len - kl))); startVal = _value; _hitPart = 2; [self sendAction:[self action] to:[self target]]; }
  _hitPart = 2;
  for (;;) {
    NSEvent *n = XEFNextTrackingEvent(); if (!n) continue;
    if ([n type] == NSEventTypeLeftMouseUp) break;
    NSPoint q = [self convertPoint:[n locationInWindow] fromView:nil];
    _value = fmax(0, fmin(1, startVal + ((v ? q.y : q.x) - start) / fmax(1, len - kl)));
    [self sendAction:[self action] to:[self target]];
    XEFRedrawWindowNow(_window); } }
@end

@implementation NSClipView
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { _drawsBg = YES; _bg = [[NSColor controlBackgroundColor] retain]; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [super initWithCoder:c])) return nil;
  NSColor *bg = [c decodeObjectForKey:@"NSBGColor"];
  _bg = [bg isKindOfClass:[NSColor class]] ? [bg retain] : [[NSColor controlBackgroundColor] retain];
  _drawsBg = ([c decodeIntForKey:@"NScvFlags"] & 4) != 0;
  id doc = [c decodeObjectForKey:@"NSDocView"];
  if ([doc isKindOfClass:[NSView class]]) _doc = doc;   /* a subview, retained by _subviews */
  [self _xefPropagateBackground];
  return self; }
/* a clip view that draws no background makes its text view transparent too (AppKit does the same) */
- (void)_xefPropagateBackground {
  if (!_drawsBg && [_doc respondsToSelector:@selector(setDrawsBackground:)] && [_doc isKindOfClass:NSClassFromString(@"NSTextView")]) [(id)_doc setDrawsBackground:NO]; }
- (void)dealloc { [_bg release]; [super dealloc]; }
- (BOOL)isFlipped { return _doc ? [_doc isFlipped] : NO; }
- (id)documentView { return _doc; }
- (void)setDocumentView:(NSView *)v {
  if (v == _doc) return;
  if (_doc) [_doc removeFromSuperview];
  _doc = v;
  if (v) { [self addSubview:v]; [v setFrameOrigin:NSZeroPoint]; }
  _bounds.origin = NSZeroPoint;
  [[self superview] respondsToSelector:@selector(tile)] ? [(id)[self superview] tile] : (void)0;
  [self setNeedsDisplay:YES]; }
- (NSColor *)backgroundColor { return _bg; } - (void)setBackgroundColor:(NSColor *)c { [c retain]; [_bg release]; _bg = c; [self setNeedsDisplay:YES]; }
- (BOOL)drawsBackground { return _drawsBg; } - (void)setDrawsBackground:(BOOL)f { _drawsBg = f; [self _xefPropagateBackground]; [self setNeedsDisplay:YES]; }
- (NSRect)documentRect { return _doc ? [_doc frame] : _bounds; }
- (NSRect)documentVisibleRect { return _doc ? [self convertRect:_bounds toView:_doc] : NSZeroRect; }
- (BOOL)copiesOnScroll { return YES; } - (void)setCopiesOnScroll:(BOOL)f {}
- (NSEdgeInsets)contentInsets { NSEdgeInsets e = {0, 0, 0, 0}; return e; } - (void)setContentInsets:(NSEdgeInsets)e {}
- (BOOL)automaticallyAdjustsContentInsets { return NO; } - (void)setAutomaticallyAdjustsContentInsets:(BOOL)f {}
- (NSPoint)constrainScrollPoint:(NSPoint)p {
  NSRect d = [self documentRect];
  CGFloat maxX = fmax(d.origin.x, NSMaxX(d) - _bounds.size.width), maxY = fmax(d.origin.y, NSMaxY(d) - _bounds.size.height);
  p.x = fmax(d.origin.x, fmin(p.x, maxX));
  if ([self isFlipped]) p.y = fmax(d.origin.y, fmin(p.y, maxY));
  else p.y = fmax(fmin(d.origin.y, maxY), fmin(p.y, maxY));
  return p; }
- (NSRect)constrainBoundsRect:(NSRect)r { r.origin = [self constrainScrollPoint:r.origin]; return r; }
- (void)scrollToPoint:(NSPoint)p {
  p = [self constrainScrollPoint:p];
  if (NSEqualPoints(p, _bounds.origin)) return;
  _bounds.origin = p;
  [[NSNotificationCenter defaultCenter] postNotificationName:NSViewBoundsDidChangeNotification object:self];
  id sv = [self superview]; if ([sv respondsToSelector:@selector(reflectScrolledClipView:)]) [sv reflectScrolledClipView:self];
  [self setNeedsDisplay:YES]; }
- (void)setBoundsOrigin:(NSPoint)p { [self scrollToPoint:p]; }
- (BOOL)autoscroll:(NSEvent *)e { return NO; }
- (void)viewFrameChanged:(NSNotification *)n { [self scrollToPoint:_bounds.origin]; }
- (void)drawRect:(NSRect)r { if (_drawsBg && _bg) { [_bg setFill]; NSRectFill(_bounds); } }
- (void)scrollWheel:(NSEvent *)e { [[self superview] scrollWheel:e]; }
@end

@implementation NSScrollView
+ (NSSize)frameSizeForContentSize:(NSSize)s hasHorizontalScroller:(BOOL)h hasVerticalScroller:(BOOL)v borderType:(NSInteger)b { return s; }
+ (NSSize)contentSizeForFrameSize:(NSSize)s hasHorizontalScroller:(BOOL)h hasVerticalScroller:(BOOL)v borderType:(NSInteger)b { return s; }
+ (NSSize)frameSizeForContentSize:(NSSize)s horizontalScrollerClass:(Class)h verticalScrollerClass:(Class)v borderType:(NSInteger)b controlSize:(NSUInteger)c scrollerStyle:(NSInteger)st { return s; }
+ (NSSize)contentSizeForFrameSize:(NSSize)s horizontalScrollerClass:(Class)h verticalScrollerClass:(Class)v borderType:(NSInteger)b controlSize:(NSUInteger)c scrollerStyle:(NSInteger)st { return s; }
- (id)initWithFrame:(NSRect)f {
  if ((self = [super initWithFrame:f])) {
    _clip = [[NSClipView alloc] initWithFrame:NSMakeRect(0, 0, f.size.width, f.size.height)];
    [self addSubview:_clip]; [_clip release];
    _drawsBg = YES; _lineScroll = 10; [self tile]; }
  return self; }
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [super initWithCoder:c])) return nil;
  for (NSView *s in _subviews) {
    if ([s isKindOfClass:[NSClipView class]] && !_clip) _clip = (NSClipView *)s;
    else if ([s isKindOfClass:[NSScroller class]]) { if (s->_frame.size.height >= s->_frame.size.width) _vs = (NSScroller *)s; else _hs = (NSScroller *)s; } }
  id cv = [c decodeObjectForKey:@"NSContentView"]; if ([cv isKindOfClass:[NSClipView class]]) _clip = cv;
  uint32_t fl = (uint32_t)[c decodeIntForKey:@"NSsFlags"];
  _hasV = (fl & 0x10) != 0; _hasH = (fl & 0x20) != 0; _border = fl & 3; _autohides = (fl & 0x200) != 0;
  _drawsBg = YES; _lineScroll = 10;
  [_vs setTarget:self]; [_vs setAction:@selector(_xefScrollerMoved:)];
  [_hs setTarget:self]; [_hs setAction:@selector(_xefScrollerMoved:)];
  [self tile];
  return self; }
- (BOOL)isFlipped { return YES; }
- (NSClipView *)contentView { return _clip; }
- (void)setContentView:(NSClipView *)c { if (c == _clip) return; NSView *doc = [[[_clip documentView] retain] autorelease]; [_clip removeFromSuperview]; _clip = c; [self addSubview:c]; if (doc && ![c documentView]) [c setDocumentView:doc]; [self tile]; }
- (id)documentView { return [_clip documentView]; }
- (void)setDocumentView:(NSView *)v { [_clip setDocumentView:v]; [self tile]; }
- (NSSize)contentSize { return [_clip frame].size; }
- (NSRect)documentVisibleRect { return [_clip documentVisibleRect]; }
- (BOOL)hasVerticalScroller { return _hasV; }
- (void)setHasVerticalScroller:(BOOL)f { _hasV = f; if (f && !_vs) { _vs = [[NSScroller alloc] initWithFrame:NSMakeRect(0, 0, 15, 100)]; [_vs setTarget:self]; [_vs setAction:@selector(_xefScrollerMoved:)]; [self addSubview:_vs]; [_vs release]; } [self tile]; }
- (BOOL)hasHorizontalScroller { return _hasH; }
- (void)setHasHorizontalScroller:(BOOL)f { _hasH = f; if (f && !_hs) { _hs = [[NSScroller alloc] initWithFrame:NSMakeRect(0, 0, 100, 15)]; [_hs setTarget:self]; [_hs setAction:@selector(_xefScrollerMoved:)]; [self addSubview:_hs]; [_hs release]; } [self tile]; }
- (NSScroller *)verticalScroller { return _vs; } - (void)setVerticalScroller:(NSScroller *)s { [_vs removeFromSuperview]; _vs = s; if (s) { [self addSubview:s]; [s setTarget:self]; [s setAction:@selector(_xefScrollerMoved:)]; } [self tile]; }
- (NSScroller *)horizontalScroller { return _hs; } - (void)setHorizontalScroller:(NSScroller *)s { [_hs removeFromSuperview]; _hs = s; if (s) { [self addSubview:s]; [s setTarget:self]; [s setAction:@selector(_xefScrollerMoved:)]; } [self tile]; }
- (BOOL)autohidesScrollers { return _autohides; } - (void)setAutohidesScrollers:(BOOL)f { _autohides = f; }
- (NSInteger)borderType { return _border; } - (void)setBorderType:(NSInteger)b { _border = b; [self tile]; }
- (NSColor *)backgroundColor { return [_clip backgroundColor]; } - (void)setBackgroundColor:(NSColor *)c { [_clip setBackgroundColor:c]; }
- (BOOL)drawsBackground { return [_clip drawsBackground]; } - (void)setDrawsBackground:(BOOL)f { [_clip setDrawsBackground:f]; }
- (NSInteger)scrollerStyle { return 1; } - (void)setScrollerStyle:(NSInteger)s {}
- (NSInteger)scrollerKnobStyle { return 0; } - (void)setScrollerKnobStyle:(NSInteger)s {}
- (CGFloat)lineScroll { return _lineScroll; } - (void)setLineScroll:(CGFloat)l { _lineScroll = l; }
- (CGFloat)verticalLineScroll { return _lineScroll; } - (void)setVerticalLineScroll:(CGFloat)l { _lineScroll = l; }
- (CGFloat)horizontalLineScroll { return _lineScroll; } - (void)setHorizontalLineScroll:(CGFloat)l {}
- (CGFloat)pageScroll { return 10; } - (void)setPageScroll:(CGFloat)p {} - (void)setVerticalPageScroll:(CGFloat)p {} - (void)setHorizontalPageScroll:(CGFloat)p {}
- (BOOL)scrollsDynamically { return YES; } - (void)setScrollsDynamically:(BOOL)f {}
- (BOOL)usesPredominantAxisScrolling { return YES; } - (void)setUsesPredominantAxisScrolling:(BOOL)f {}
- (NSInteger)horizontalScrollElasticity { return 0; } - (void)setHorizontalScrollElasticity:(NSInteger)e {}
- (NSInteger)verticalScrollElasticity { return 0; } - (void)setVerticalScrollElasticity:(NSInteger)e {}
- (BOOL)allowsMagnification { return NO; } - (void)setAllowsMagnification:(BOOL)f {}
- (CGFloat)magnification { return 1; } - (void)setMagnification:(CGFloat)m {}
- (BOOL)hasVerticalRuler { return NO; } - (void)setHasVerticalRuler:(BOOL)f {} - (BOOL)hasHorizontalRuler { return NO; } - (void)setHasHorizontalRuler:(BOOL)f {}
- (BOOL)rulersVisible { return NO; } - (void)setRulersVisible:(BOOL)f {}
- (NSEdgeInsets)contentInsets { NSEdgeInsets e = {0, 0, 0, 0}; return e; } - (void)setContentInsets:(NSEdgeInsets)e {}
- (NSEdgeInsets)scrollerInsets { NSEdgeInsets e = {0, 0, 0, 0}; return e; } - (void)setScrollerInsets:(NSEdgeInsets)e {}
- (BOOL)automaticallyAdjustsContentInsets { return NO; } - (void)setAutomaticallyAdjustsContentInsets:(BOOL)f {}
- (BOOL)findBarVisible { return NO; } - (void)setFindBarVisible:(BOOL)f {} - (id)findBarView { return nil; }
- (void)flashScrollers {}
/* overlay scrollers: the clip view fills the scroll view (inside the border), scrollers float over its edges */
- (void)tile {
  CGFloat b = _border ? 1 : 0;
  NSRect inner = NSInsetRect(_bounds, b, b);
  if (_clip) [_clip setFrame:inner];
  if (_vs) { [_vs setFrame:NSMakeRect(NSMaxX(inner) - 11, inner.origin.y, 11, inner.size.height - (_hasH ? 11 : 0))]; [_vs setHidden:!_hasV]; }
  if (_hs) { [_hs setFrame:NSMakeRect(inner.origin.x, NSMaxY(inner) - 11, inner.size.width - (_hasV ? 11 : 0), 11)]; [_hs setHidden:!_hasH]; }
  if (_vs) { [_subviews removeObjectIdenticalTo:_vs]; [_subviews addObject:_vs]; }   /* scrollers draw last */
  if (_hs) { [_subviews removeObjectIdenticalTo:_hs]; [_subviews addObject:_hs]; }
  [self reflectScrolledClipView:_clip]; }
- (void)setFrame:(NSRect)f { [super setFrame:f]; [self tile]; }
- (void)setFrameSize:(NSSize)s { NSRect f = _frame; f.size = s; [self setFrame:f]; }
- (void)resizeSubviewsWithOldSize:(NSSize)s { [self tile]; }
- (void)reflectScrolledClipView:(NSClipView *)c {
  if (c != _clip || !_clip) return;
  NSRect d = [_clip documentRect], v = [_clip bounds];
  if (_vs) {
    CGFloat over = d.size.height - v.size.height;
    [_vs setKnobProportion:d.size.height > 0 ? fmin(1, v.size.height / d.size.height) : 1];
    CGFloat pos = [_clip isFlipped] ? v.origin.y - d.origin.y : NSMaxY(d) - NSMaxY(v);
    [_vs setDoubleValue:over > 0 ? pos / over : 0]; }
  if (_hs) {
    CGFloat over = d.size.width - v.size.width;
    [_hs setKnobProportion:d.size.width > 0 ? fmin(1, v.size.width / d.size.width) : 1];
    [_hs setDoubleValue:over > 0 ? (v.origin.x - d.origin.x) / over : 0]; } }
- (void)_xefScrollerMoved:(NSScroller *)s {
  NSRect d = [_clip documentRect], v = [_clip bounds]; NSPoint o = v.origin;
  if (s == _vs) { CGFloat over = fmax(0, d.size.height - v.size.height); o.y = [_clip isFlipped] ? d.origin.y + over * [s doubleValue] : d.origin.y + over * (1 - [s doubleValue]); }
  else { CGFloat over = fmax(0, d.size.width - v.size.width); o.x = d.origin.x + over * [s doubleValue]; }
  [_clip scrollToPoint:o]; }
- (void)scrollWheel:(NSEvent *)e {
  CGFloat dy = [e deltaY] * _lineScroll * 3, dx = [e deltaX] * _lineScroll * 3;
  NSPoint o = [_clip bounds].origin;
  o.y += [_clip isFlipped] ? -dy : dy; o.x -= dx;
  [_clip scrollToPoint:o]; }
- (void)drawRect:(NSRect)r {
  if (_border) { [[NSColor colorWithCalibratedWhite:0.75 alpha:1] setFill]; NSFrameRect(_bounds); } }
@end

/* ================================================================== boxes, custom views, misc */
@implementation NSBox
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [super initWithCoder:c])) return nil;
  _boxType = [c decodeIntegerForKey:@"NSBoxType"]; _titlePos = [c decodeIntegerForKey:@"NSTitlePosition"];
  _transparent = [c decodeBoolForKey:@"NSTransparent"]; _borderType = [c decodeIntegerForKey:@"NSBorderType"];
  id t = [c decodeObjectForKey:@"NSTitleCell"]; if ([t respondsToSelector:@selector(stringValue)]) _title = [[t stringValue] copy];
  NSColor *fc = [c decodeObjectForKey:@"NSFillColor2"]; if ([fc isKindOfClass:[NSColor class]]) _fill = [fc retain];
  return self; }
- (void)dealloc { [_title release]; [_fill release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (NSString *)title { return _title ?: @""; } - (void)setTitle:(NSString *)t { [_title release]; _title = [t copy]; [self setNeedsDisplay:YES]; }
- (NSInteger)boxType { return _boxType; } - (void)setBoxType:(NSInteger)t { _boxType = t; }
- (NSInteger)titlePosition { return _titlePos; } - (void)setTitlePosition:(NSInteger)p { _titlePos = p; }
- (BOOL)isTransparent { return _transparent; } - (void)setTransparent:(BOOL)f { _transparent = f; }
- (NSColor *)fillColor { return _fill; } - (void)setFillColor:(NSColor *)c { [c retain]; [_fill release]; _fill = c; }
- (NSView *)contentView { return [_subviews firstObject]; } - (void)setContentView:(NSView *)v { for (NSView *s in [[_subviews copy] autorelease]) [s removeFromSuperview]; if (v) [self addSubview:v]; }
- (NSSize)contentViewMargins { return NSMakeSize(5, 5); } - (void)setContentViewMargins:(NSSize)s {}
- (void)drawRect:(NSRect)r {
  if (_transparent) return;
  if (_boxType == 2 /*separator*/) { [[NSColor separatorColor] setFill]; NSRectFill(_bounds.size.width > _bounds.size.height ? NSMakeRect(0, NSMidY(_bounds), _bounds.size.width, 1) : NSMakeRect(NSMidX(_bounds), 0, 1, _bounds.size.height)); return; }
  NSRect b = NSInsetRect(_bounds, 1, 1);
  if (_title && _titlePos) b.origin.y += 8, b.size.height -= 8;
  if (_boxType == 4 && _fill) { [_fill setFill]; NSRectFill(b); }
  else { [[NSColor colorWithCalibratedWhite:0 alpha:0.05] setFill]; [[NSBezierPath bezierPathWithRoundedRect:b xRadius:5 yRadius:5] fill]; }
  [[NSColor colorWithCalibratedWhite:0 alpha:0.15] setStroke]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.5, 0.5) xRadius:5 yRadius:5] stroke];
  if ([_title length] && _titlePos) [_title drawAtPoint:NSMakePoint(8, 0) withAttributes:text_attrs([NSFont systemFontOfSize:11], [NSColor secondaryLabelColor], 0, 0)]; }
@end

@implementation NSCustomView
/* nib placeholder for a custom NSView subclass: becomes an instance of NSClassName */
- (id)initWithCoder:(NSCoder *)c {
  NSString *cn = [c decodeObjectForKey:@"NSClassName"];
  Class cls = NSClassFromString(cn);
  if (!cls || ![cls isSubclassOfClass:[NSView class]]) { if (cn) NSLog(@"xef: nib custom view class %@ not found", cn); cls = [NSView class]; }
  NSRect f = [c containsValueForKey:@"NSFrame"] ? [c decodeRectForKey:@"NSFrame"] : NSMakeRect(0, 0, [c decodeSizeForKey:@"NSFrameSize"].width, [c decodeSizeForKey:@"NSFrameSize"].height);
  [self release];
  NSView *v = [[cls alloc] initWithFrame:f];
  NSUInteger flags = (NSUInteger)[c decodeIntegerForKey:@"NSvFlags"];
  v->_autoresizingMask = flags & 0x3f; v->_autoresizesSubviews = (flags & 0x100) != 0;
  for (id s in [c decodeObjectForKey:@"NSSubviews"]) if ([s isKindOfClass:[NSView class]]) [v addSubview:s];
  return v; }
@end

@implementation NSLayoutConstraint (XEFNib)
- (id)initWithCoder:(NSCoder *)c { return [self init]; }   /* Auto Layout is not evaluated: frames come from the nib */
- (void)encodeWithCoder:(NSCoder *)c {}
@end

@implementation NSAppearance
+ (NSAppearance *)appearanceNamed:(NSString *)n { NSAppearance *a = [[[self alloc] init] autorelease]; a->_name = [n copy]; return a; }
+ (NSAppearance *)currentAppearance { return [self appearanceNamed:@"NSAppearanceNameAqua"]; }
+ (NSAppearance *)currentDrawingAppearance { return [self currentAppearance]; }
+ (void)setCurrentAppearance:(NSAppearance *)a {}
- (id)initWithCoder:(NSCoder *)c { if ((self = [super init])) _name = [[c decodeObjectForKey:@"NSAppearanceName"] copy] ?: @"NSAppearanceNameAqua"; return self; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (NSString *)name { return _name ?: @"NSAppearanceNameAqua"; }
- (NSString *)bestMatchFromAppearancesWithNames:(NSArray *)names { for (NSString *n in names) if ([n rangeOfString:@"Aqua"].location != NSNotFound && [n rangeOfString:@"Dark"].location == NSNotFound) return n; return [names firstObject]; }
- (void)performAsCurrentDrawingAppearance:(void (^)(void))b { if (b) b(); }
- (BOOL)allowsVibrancy { return NO; }
- (void)dealloc { [_name release]; [super dealloc]; }
@end
NSString *const NSAppearanceNameAqua = @"NSAppearanceNameAqua";
NSString *const NSAppearanceNameDarkAqua = @"NSAppearanceNameDarkAqua";
NSString *const NSAppearanceNameVibrantLight = @"NSAppearanceNameVibrantLight";
NSString *const NSAppearanceNameVibrantDark = @"NSAppearanceNameVibrantDark";
NSString *const NSAppearanceNameAccessibilityHighContrastAqua = @"NSAppearanceNameAccessibilityHighContrastAqua";

/* ================================================================== action dispatch */
@implementation NSApplication (XEFActions)
BOOL XEFRespondsForReal(id o, SEL a);
static BOOL responds(id o, SEL a) { return XEFRespondsForReal(o, a); }
- (id)targetForAction:(SEL)a to:(id)t from:(id)s {
  if (!a) return nil;
  if (t) return responds(t, a) ? t : nil;
  NSWindow *key = [self keyWindow], *main = [self mainWindow];
  for (NSResponder *r = [key firstResponder]; r; r = [r nextResponder]) if (responds(r, a)) return r;
  if (key) {
    if (responds(key, a)) return key; if (responds([key delegate], a)) return [key delegate];
    id wc = [key respondsToSelector:@selector(windowController)] ? [(id)key windowController] : nil;
    if (responds(wc, a)) return wc;
    id doc = [wc respondsToSelector:@selector(document)] ? [wc document] : nil;
    if (responds(doc, a)) return doc; }
  if (main && main != key) {
    for (NSResponder *r = [main firstResponder]; r; r = [r nextResponder]) if (responds(r, a)) return r;
    if (responds(main, a)) return main; if (responds([main delegate], a)) return [main delegate]; }
  if (responds(self, a)) return self;
  if (responds([self delegate], a)) return [self delegate];
  Class dc = NSClassFromString(@"NSDocumentController");
  if (dc) { id d = [dc sharedDocumentController]; if (responds(d, a)) return d; }
  return nil; }
- (id)targetForAction:(SEL)a { return [self targetForAction:a to:nil from:nil]; }
- (BOOL)sendAction:(SEL)a to:(id)t from:(id)s {
  id target = [self targetForAction:a to:t from:s];
  if (!target) return NO;
  ((void (*)(id, SEL, id))objc_msgSend)(target, a, s);
  return YES; }
- (BOOL)tryToPerform:(SEL)a with:(id)o { if (responds(self, a)) { ((void (*)(id, SEL, id))objc_msgSend)(self, a, o); return YES; } if (responds([self delegate], a)) { ((void (*)(id, SEL, id))objc_msgSend)([self delegate], a, o); return YES; } return NO; }
@end

@implementation NSResponder (XEFActions)
- (BOOL)tryToPerform:(SEL)a with:(id)o {
  for (NSResponder *r = self; r; r = [r nextResponder]) if ([r respondsToSelector:a]) { ((void (*)(id, SEL, id))objc_msgSend)(r, a, o); return YES; }
  return NO; }
- (BOOL)performKeyEquivalent:(NSEvent *)e { return NO; }
- (id)validRequestorForSendType:(NSString *)s returnType:(NSString *)r { return nil; }
- (NSUndoManager *)undoManager { return [_nextResponder undoManager]; }
- (void)noResponderFor:(SEL)s {}
- (BOOL)presentError:(NSError *)e { NSLog(@"%@", e); return NO; }
- (NSMenu *)menu { return objc_getAssociatedObject(self, "xef.menu"); }
- (void)setMenu:(NSMenu *)m { objc_setAssociatedObject(self, "xef.menu", m, OBJC_ASSOCIATION_RETAIN); }
@end

@implementation NSView (XEFKeyEquivalents)
- (BOOL)performKeyEquivalent:(NSEvent *)e {
  if (_hidden) return NO;
  for (NSView *s in [[_subviews copy] autorelease]) if ([s performKeyEquivalent:e]) return YES;
  return NO; }
- (NSView *)nextKeyView { return objc_getAssociatedObject(self, "xef.nextKeyView"); }
- (void)setNextKeyView:(NSView *)v { objc_setAssociatedObject(self, "xef.nextKeyView", v, OBJC_ASSOCIATION_ASSIGN); }
- (NSView *)nextValidKeyView { for (NSView *v = [self nextKeyView]; v && v != self; v = [v nextKeyView]) if ([v acceptsFirstResponder] && ![v isHiddenOrHasHiddenAncestor]) return v; return nil; }
- (NSView *)previousKeyView { return nil; } - (NSView *)previousValidKeyView { return nil; }
@end

@implementation NSWindow (XEFKeyViews)
- (void)selectNextKeyView:(id)s {
  NSView *from = [s isKindOfClass:[NSView class]] ? s : ([_first isKindOfClass:[NSView class]] ? (NSView *)_first : nil);
  NSView *n = [from nextValidKeyView];
  if (!n) {   /* no key-view loop: next focusable view in tree order */
    NSMutableArray *all = [NSMutableArray array];
    void (^__block walk)(NSView *) = nil;
    void (^w)(NSView *) = ^(NSView *v) { if ([v acceptsFirstResponder] && ![v isHidden]) [all addObject:v]; for (NSView *c in v->_subviews) walk(c); };
    walk = w; walk(_content); walk = nil;
    NSUInteger i = from ? [all indexOfObjectIdenticalTo:from] : NSNotFound;
    if ([all count]) n = [all objectAtIndex:i == NSNotFound ? 0 : (i + 1) % [all count]]; }
  if (n) [self makeFirstResponder:n]; }
- (void)selectPreviousKeyView:(id)s { [self selectNextKeyView:s]; }
- (void)selectKeyViewFollowingView:(NSView *)v { [self selectNextKeyView:v]; }
- (void)selectKeyViewPrecedingView:(NSView *)v { [self selectNextKeyView:v]; }
- (NSView *)initialFirstResponder { return (NSView *)_initialFirst; }
- (void)setInitialFirstResponder:(NSView *)v { _initialFirst = v; }
- (NSButtonCell *)defaultButtonCell { return _defaultButtonCell; }
- (void)setDefaultButtonCell:(NSButtonCell *)c { _defaultButtonCell = c; }
- (BOOL)performKeyEquivalent:(NSEvent *)e { return [_content performKeyEquivalent:e]; }
/* end of the responder chain: Return / Escape press the window's default / cancel button, Tab moves the focus */
static NSButton *find_button(NSView *v, NSString *key) {
  if ([v isKindOfClass:[NSButton class]] && [[(NSButton *)v keyEquivalent] isEqualToString:key] && [(NSButton *)v isEnabled] && ![v isHiddenOrHasHiddenAncestor]) return (NSButton *)v;
  for (NSView *s in v->_subviews) { NSButton *b = find_button(s, key); if (b) return b; }
  return nil; }
- (void)keyDown:(NSEvent *)e {
  unsigned short k = [e keyCode];
  NSButton *b = (k == 36 || k == 76) ? find_button(_content, @"\r") : k == 53 ? find_button(_content, @"\e") : nil;
  if (b) { [b performClick:self]; return; }
  if (k == 48) { if ([e modifierFlags] & NSEventModifierFlagShift) [self selectPreviousKeyView:nil]; else [self selectNextKeyView:nil]; return; }
  if (k == 53 && [_delegate respondsToSelector:@selector(cancelOperation:)]) [_delegate cancelOperation:self]; }
- (NSUndoManager *)undoManager {
  if ([_delegate respondsToSelector:@selector(windowWillReturnUndoManager:)]) return [_delegate windowWillReturnUndoManager:self];
  id wc = [self respondsToSelector:@selector(windowController)] ? [(id)self windowController] : nil;
  id doc = [wc respondsToSelector:@selector(document)] ? [wc document] : nil;
  if ([doc respondsToSelector:@selector(undoManager)]) return [doc undoManager];
  NSUndoManager *u = objc_getAssociatedObject(self, "xef.undo");
  if (!u) { u = [[[NSUndoManager alloc] init] autorelease]; objc_setAssociatedObject(self, "xef.undo", u, OBJC_ASSOCIATION_RETAIN); }
  return u; }
@end
