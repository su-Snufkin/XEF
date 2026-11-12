/* AppKit-lite: sliders, steppers, progress indicators, segmented controls, image views, level indicators, colour wells,
 * switches, combo boxes, date pickers, tab views, split views, stack views, panels, gradients and animation contexts.
 * Behaviour (defaults, clamping, selection rules, delegate call order) follows real AppKit as recorded by
 * tests/darwin/mac/appkit_controls.m; drawing is the light Aqua-like style of AppKitControls.m. */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitControls.h"
#import "AppKitControls2.h"
#include <objc/runtime.h>
#include <math.h>

NSString *const NSComboBoxSelectionDidChangeNotification = @"NSComboBoxSelectionDidChangeNotification";
NSString *const NSComboBoxSelectionIsChangingNotification = @"NSComboBoxSelectionIsChangingNotification";
NSString *const NSComboBoxWillPopUpNotification = @"NSComboBoxWillPopUpNotification";
NSString *const NSComboBoxWillDismissNotification = @"NSComboBoxWillDismissNotification";
NSString *const NSSplitViewWillResizeSubviewsNotification = @"NSSplitViewWillResizeSubviewsNotification";
NSString *const NSSplitViewDidResizeSubviewsNotification = @"NSSplitViewDidResizeSubviewsNotification";
const CGFloat NSStackViewSpacingUseDefault = 3.40282347e+38F;

static double clampd(double v, double lo, double hi) { return v < lo ? lo : v > hi ? hi : v; }
static NSDictionary *attrs2(NSFont *f, NSColor *c, NSInteger align) {
  NSMutableParagraphStyle *p = [[[NSMutableParagraphStyle alloc] init] autorelease];
  [p setAlignment:align]; [p setLineBreakMode:4];
  return @{ NSFontAttributeName: f ?: [NSFont systemFontOfSize:13], NSForegroundColorAttributeName: c ?: [NSColor controlTextColor], NSParagraphStyleAttributeName: p }; }
static void fill_round(NSRect r, CGFloat rad, NSColor *fill, NSColor *border) {
  NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:border ? NSInsetRect(r, 0.5, 0.5) : r xRadius:rad yRadius:rad];
  if (fill) { [fill setFill]; [p fill]; }
  if (border) { [border setStroke]; [p setLineWidth:1]; [p stroke]; } }
static NSColor *gray(CGFloat w) { return [NSColor colorWithCalibratedWhite:w alpha:1]; }
static NSPoint local_point(NSView *v, NSEvent *e) { return [v convertPoint:[e locationInWindow] fromView:nil]; }
static void draw_centered(NSString *s, NSRect r, NSDictionary *a) {
  NSSize ts = [s sizeWithAttributes:a];
  [s drawInRect:NSMakeRect(r.origin.x, NSMidY(r) - ts.height / 2, r.size.width, ts.height) withAttributes:a]; }
static void draw_image_fit(NSImage *img, NSRect r, NSInteger scaling, NSInteger align) {
  NSSize s = [img size]; if (s.width <= 0 || s.height <= 0) return;
  NSSize d = s;
  if (scaling == 1) d = r.size;
  else if (scaling != 2) {
    CGFloat k = fmin(r.size.width / s.width, r.size.height / s.height);
    if (scaling == 0 && k > 1) k = 1;
    d = NSMakeSize(s.width * k, s.height * k); }
  CGFloat x = NSMidX(r) - d.width / 2, y = NSMidY(r) - d.height / 2;
  /* NSImageAlignment: 0 center, 1 top, 2 topLeft, 3 topRight, 4 left, 5 bottom, 6 bottomLeft, 7 bottomRight, 8 right (flipped view: top = minY) */
  if (align == 2 || align == 4 || align == 6) x = r.origin.x;
  if (align == 3 || align == 7 || align == 8) x = NSMaxX(r) - d.width;
  if (align == 1 || align == 2 || align == 3) y = r.origin.y;
  if (align == 5 || align == 6 || align == 7) y = NSMaxY(r) - d.height;
  [img drawInRect:NSMakeRect(x, y, d.width, d.height)]; }

/* ================================================================== NSSlider */
@implementation NSSliderCell
- (id)initTextCell:(NSString *)s { if ((self = [super initTextCell:s])) { _max = 1; _vertical = -1; _continuous = YES; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    _min = [c decodeDoubleForKey:@"NSMinValue"]; _max = [c containsValueForKey:@"NSMaxValue"] ? [c decodeDoubleForKey:@"NSMaxValue"] : 1;
    _value = [c decodeDoubleForKey:@"NSValue"]; _alt = [c decodeDoubleForKey:@"NSAltIncValue"];
    _ticks = [c decodeIntegerForKey:@"NSNumberOfTickMarks"]; _tickPos = [c decodeIntegerForKey:@"NSTickMarkPosition"];
    _ticksOnly = [c decodeBoolForKey:@"NSAllowsTickMarkValuesOnly"]; _sliderType = [c decodeIntegerForKey:@"NSSliderType"];
    _vertical = [c containsValueForKey:@"NSVertical"] ? [c decodeBoolForKey:@"NSVertical"] : -1; _continuous = YES; }
  return self; }
- (void)dealloc { [_trackFill release]; [super dealloc]; }
+ (BOOL)prefersTrackingUntilMouseUp { return YES; }
- (double)_fit:(double)v {
  v = clampd(v, _min, _max >= _min ? _max : _min);
  return _ticksOnly && _ticks > 1 ? [self closestTickMarkValueToValue:v] : v; }
- (double)minValue { return _min; } - (void)setMinValue:(double)v { _min = v; _value = [self _fit:_value]; [self _changed]; }
- (double)maxValue { return _max; } - (void)setMaxValue:(double)v { _max = v; _value = [self _fit:_value]; [self _changed]; }
- (double)altIncrementValue { return _alt; } - (void)setAltIncrementValue:(double)v { _alt = v; }
- (double)neutralValue { return _min; } - (void)setNeutralValue:(double)v {}
- (NSInteger)sliderType { return _sliderType; } - (void)setSliderType:(NSInteger)t { _sliderType = t; [self _changed]; }
- (NSInteger)numberOfTickMarks { return _ticks; } - (void)setNumberOfTickMarks:(NSInteger)n { _ticks = n < 0 ? 0 : n; _value = [self _fit:_value]; [self _changed]; }
- (NSInteger)tickMarkPosition { return _tickPos; } - (void)setTickMarkPosition:(NSInteger)p { _tickPos = p; [self _changed]; }
- (BOOL)allowsTickMarkValuesOnly { return _ticksOnly; } - (void)setAllowsTickMarkValuesOnly:(BOOL)f { _ticksOnly = f; _value = [self _fit:_value]; [self _changed]; }
- (double)tickMarkValueAtIndex:(NSInteger)i { return _ticks > 1 ? _min + (_max - _min) * i / (_ticks - 1) : _min; }
- (double)closestTickMarkValueToValue:(double)v {
  if (_ticks < 2 || _max == _min) return _ticks == 1 ? _min : v;
  double step = (_max - _min) / (_ticks - 1);
  return _min + round(clampd((v - _min) / step, 0, _ticks - 1)) * step; }
- (BOOL)isVertical { NSRect f = _controlView ? [_controlView bounds] : NSZeroRect; return _vertical >= 0 ? _vertical : f.size.height > f.size.width; }
- (void)setVertical:(BOOL)f { _vertical = f; [self _changed]; }
- (NSColor *)trackFillColor { return _trackFill; } - (void)setTrackFillColor:(NSColor *)c { [c retain]; [_trackFill release]; _trackFill = c; [self _changed]; }
- (CGFloat)knobThickness { return 0; } - (void)setKnobThickness:(CGFloat)t {}
- (NSInteger)trackRect { return 0; }
- (id)objectValue { return @(_value); }
- (void)setObjectValue:(id)v { _value = [self _fit:[v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0]; [self _changed]; }
- (double)doubleValue { return _value; } - (void)setDoubleValue:(double)v { _value = [self _fit:v]; [self _changed]; }
- (float)floatValue { return (float)_value; } - (void)setFloatValue:(float)v { [self setDoubleValue:v]; }
- (int)intValue { return (int)_value; } - (void)setIntValue:(int)v { [self setDoubleValue:v]; }
- (NSInteger)integerValue { return (NSInteger)_value; } - (void)setIntegerValue:(NSInteger)v { [self setDoubleValue:v]; }
- (NSString *)stringValue { return [@(_value) stringValue]; } - (void)setStringValue:(NSString *)s { [self setDoubleValue:[s doubleValue]]; }
- (NSSize)cellSize { return [self isVertical] ? NSMakeSize(_ticks ? 28 : 21, 96) : NSMakeSize(96, _ticks ? 28 : 21); }
- (CGFloat)_frac { return _max > _min ? (_value - _min) / (_max - _min) : 0; }
- (NSRect)_bounds { return _controlView ? [_controlView bounds] : NSZeroRect; }
- (NSRect)barRectFlipped:(BOOL)f {
  NSRect b = [self _bounds];
  if ([self isVertical]) return NSMakeRect(NSMidX(b) - 2, b.origin.y + 9, 4, b.size.height - 18);
  CGFloat y = _ticks ? b.origin.y + (_tickPos == 1 ? b.size.height - 12 : 10) : NSMidY(b);
  return NSMakeRect(b.origin.x + 9, y - 2, b.size.width - 18, 4); }
- (NSRect)knobRectFlipped:(BOOL)f {
  NSRect bar = [self barRectFlipped:f]; CGFloat t = [self _frac];
  if (_sliderType == 1) return NSInsetRect([self _bounds], 2, 2);
  if ([self isVertical]) return NSMakeRect(NSMidX(bar) - 9, NSMaxY(bar) - t * bar.size.height - 9, 18, 18);   /* flipped: maximum at the top */
  return NSMakeRect(bar.origin.x + t * bar.size.width - 9, NSMidY(bar) - 9, 18, 18); }
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)i {
  NSRect bar = [self barRectFlipped:YES]; CGFloat t = _ticks > 1 ? (CGFloat)i / (_ticks - 1) : 0;
  if ([self isVertical]) return NSMakeRect(NSMaxX(bar) + 5, NSMaxY(bar) - t * bar.size.height - 0.5, 6, 1);
  return NSMakeRect(bar.origin.x + t * bar.size.width - 0.5, _tickPos == 1 ? bar.origin.y - 11 : NSMaxY(bar) + 5, 1, 6); }
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v {
  NSColor *accent = _enabled ? (_trackFill ?: [NSColor controlAccentColor]) : gray(0.75);
  if (_sliderType == 1) {   /* circular */
    NSRect k = NSInsetRect(r, 2, 2); CGFloat d = fmin(k.size.width, k.size.height); k = NSMakeRect(NSMidX(r) - d / 2, NSMidY(r) - d / 2, d, d);
    [gray(0.97) setFill]; NSBezierPath *o = [NSBezierPath bezierPathWithOvalInRect:k]; [o fill]; [gray(0.7) setStroke]; [o stroke];
    double ang = [self _frac] * 2 * M_PI; NSPoint c = NSMakePoint(NSMidX(k), NSMidY(k));
    [accent setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x + sin(ang) * (d / 2 - 5) - 2.5, c.y - cos(ang) * (d / 2 - 5) - 2.5, 5, 5)] fill];
    return; }
  NSRect bar = [self barRectFlipped:YES], knob = [self knobRectFlipped:YES];
  fill_round(bar, 2, gray(0.82), nil);
  if (!_ticks) {
    NSRect fill = bar;
    if ([self isVertical]) { fill.origin.y = NSMidY(knob); fill.size.height = NSMaxY(bar) - NSMidY(knob); } else fill.size.width = NSMidX(knob) - bar.origin.x;
    fill_round(fill, 2, accent, nil); }
  [gray(0.55) setFill];
  for (NSInteger i = 0; i < _ticks; i++) NSRectFill([self rectOfTickMarkAtIndex:i]);
  NSRect k = NSInsetRect(knob, 1, 1);
  [[NSColor whiteColor] setFill]; NSBezierPath *o = [NSBezierPath bezierPathWithOvalInRect:k]; [o fill];
  [(_highlighted ? gray(0.45) : gray(0.65)) setStroke]; [o setLineWidth:1]; [o stroke]; }
- (double)_valueAtPoint:(NSPoint)p {
  NSRect bar = [self barRectFlipped:YES];
  if (_sliderType == 1) { NSRect b = [self _bounds]; double a = atan2(p.x - NSMidX(b), NSMidY(b) - p.y); if (a < 0) a += 2 * M_PI; return _min + (_max - _min) * a / (2 * M_PI); }
  CGFloat t = [self isVertical] ? (NSMaxY(bar) - p.y) / fmax(1, bar.size.height) : (p.x - bar.origin.x) / fmax(1, bar.size.width);
  return _min + (_max - _min) * clampd(t, 0, 1); }
- (BOOL)trackMouse:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v untilMouseUp:(BOOL)u {
  NSControl *ctl = [v isKindOfClass:[NSControl class]] ? (NSControl *)v : nil;
  _highlighted = YES;
  for (NSEvent *n = e;;) {
    if (n) {
      if ([n type] == NSEventTypeLeftMouseUp) break;
      double nv = [self _fit:[self _valueAtPoint:local_point(v, n)]];
      if (nv != _value) { _value = nv; if (_continuous) [ctl sendAction:[self action] to:[self target]]; }
      [v setNeedsDisplay:YES]; XEFRedrawWindowNow([v window]); }
    n = XEFNextTrackingEvent(); }
  _highlighted = NO; [v setNeedsDisplay:YES];
  return YES; }
@end

@implementation NSSlider
+ (Class)cellClass { return [NSSliderCell class]; }
+ (NSSlider *)sliderWithTarget:(id)t action:(SEL)a { NSSlider *s = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 96, 21)] autorelease]; [s setTarget:t]; [s setAction:a]; return s; }
+ (NSSlider *)sliderWithValue:(double)v minValue:(double)mn maxValue:(double)mx target:(id)t action:(SEL)a {
  NSSlider *s = [self sliderWithTarget:t action:a]; [s setMinValue:mn]; [s setMaxValue:mx]; [s setDoubleValue:v]; return s; }
#define SC ((NSSliderCell *)_cell)
- (double)minValue { return [SC minValue]; } - (void)setMinValue:(double)v { [SC setMinValue:v]; [self setNeedsDisplay:YES]; }
- (double)maxValue { return [SC maxValue]; } - (void)setMaxValue:(double)v { [SC setMaxValue:v]; [self setNeedsDisplay:YES]; }
- (double)altIncrementValue { return [SC altIncrementValue]; } - (void)setAltIncrementValue:(double)v { [SC setAltIncrementValue:v]; }
- (double)neutralValue { return [SC neutralValue]; } - (void)setNeutralValue:(double)v {}
- (NSInteger)sliderType { return [SC sliderType]; } - (void)setSliderType:(NSInteger)t { [SC setSliderType:t]; [self setNeedsDisplay:YES]; }
- (NSInteger)numberOfTickMarks { return [SC numberOfTickMarks]; } - (void)setNumberOfTickMarks:(NSInteger)n { [SC setNumberOfTickMarks:n]; [self setNeedsDisplay:YES]; }
- (NSInteger)tickMarkPosition { return [SC tickMarkPosition]; } - (void)setTickMarkPosition:(NSInteger)p { [SC setTickMarkPosition:p]; [self setNeedsDisplay:YES]; }
- (BOOL)allowsTickMarkValuesOnly { return [SC allowsTickMarkValuesOnly]; } - (void)setAllowsTickMarkValuesOnly:(BOOL)f { [SC setAllowsTickMarkValuesOnly:f]; [self setNeedsDisplay:YES]; }
- (double)tickMarkValueAtIndex:(NSInteger)i { return [SC tickMarkValueAtIndex:i]; }
- (double)closestTickMarkValueToValue:(double)v { return [SC closestTickMarkValueToValue:v]; }
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)i { return [SC rectOfTickMarkAtIndex:i]; }
- (NSInteger)indexOfTickMarkAtPoint:(NSPoint)p {
  for (NSInteger i = 0; i < [SC numberOfTickMarks]; i++) if (NSPointInRect(p, NSInsetRect([SC rectOfTickMarkAtIndex:i], -2, -2))) return i;
  return NSNotFound; }
- (BOOL)isVertical { return [SC isVertical]; } - (void)setVertical:(BOOL)f { [SC setVertical:f]; [self setNeedsDisplay:YES]; }
- (NSColor *)trackFillColor { return [SC trackFillColor]; } - (void)setTrackFillColor:(NSColor *)c { [SC setTrackFillColor:c]; [self setNeedsDisplay:YES]; }
- (CGFloat)knobThickness { return 0; } - (void)setKnobThickness:(CGFloat)t {}
- (NSInteger)tintProminence { return 0; } - (void)setTintProminence:(NSInteger)p {}
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (id)titleCell { return nil; } - (void)setTitleCell:(id)c {} - (id)titleColor { return nil; } - (void)setTitleColor:(id)c {}
- (id)titleFont { return nil; } - (void)setTitleFont:(id)f {} - (NSString *)title { return nil; } - (void)setTitle:(NSString *)t {}
- (NSImage *)image { return nil; } - (void)setImage:(NSImage *)i {}
- (void)mouseDown:(NSEvent *)e {
  if (![self isEnabled]) return;
  [_cell trackMouse:e inRect:_bounds ofView:self untilMouseUp:YES];
  if (![_cell isContinuous] || YES) [self sendAction:[self action] to:[self target]]; }
- (void)keyDown:(NSEvent *)e {
  unsigned short k = [e keyCode]; double step = [SC numberOfTickMarks] > 1 ? ([SC maxValue] - [SC minValue]) / ([SC numberOfTickMarks] - 1) : ([SC maxValue] - [SC minValue]) / 20;
  if (k == 123 || k == 125) [self setDoubleValue:[self doubleValue] - step]; else if (k == 124 || k == 126) [self setDoubleValue:[self doubleValue] + step]; else { [super keyDown:e]; return; }
  [self sendAction:[self action] to:[self target]]; }
#undef SC
@end

/* ================================================================== NSStepper */
@implementation NSStepperCell
- (id)initTextCell:(NSString *)s { if ((self = [super initTextCell:s])) { _max = 59; _inc = 1; _valueWraps = YES; _autorepeat = YES; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    _min = [c decodeDoubleForKey:@"NSMinValue"]; _max = [c containsValueForKey:@"NSMaxValue"] ? [c decodeDoubleForKey:@"NSMaxValue"] : 59;
    _inc = [c containsValueForKey:@"NSIncrement"] ? [c decodeDoubleForKey:@"NSIncrement"] : 1; _value = [c decodeDoubleForKey:@"NSValue"];
    _valueWraps = [c decodeBoolForKey:@"NSValueWraps"]; _autorepeat = [c decodeBoolForKey:@"NSAutorepeat"]; }
  return self; }
- (double)_fit:(double)v { return fmax(_min, fmin(v, _max)); }
- (double)minValue { return _min; } - (void)setMinValue:(double)v { _min = v; _value = [self _fit:_value]; }
- (double)maxValue { return _max; } - (void)setMaxValue:(double)v { _max = v; _value = [self _fit:_value]; }
- (double)increment { return _inc; } - (void)setIncrement:(double)v { _inc = v; }
- (BOOL)valueWraps { return _valueWraps; } - (void)setValueWraps:(BOOL)f { _valueWraps = f; }
- (BOOL)autorepeat { return _autorepeat; } - (void)setAutorepeat:(BOOL)f { _autorepeat = f; }
- (id)objectValue { return @(_value); }
- (void)setObjectValue:(id)v { _value = [self _fit:[v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0]; [self _changed]; }
- (double)doubleValue { return _value; } - (void)setDoubleValue:(double)v { _value = [self _fit:v]; [self _changed]; }
- (float)floatValue { return (float)_value; } - (void)setFloatValue:(float)v { [self setDoubleValue:v]; }
- (int)intValue { return (int)_value; } - (void)setIntValue:(int)v { [self setDoubleValue:v]; }
- (NSInteger)integerValue { return (NSInteger)_value; } - (void)setIntegerValue:(NSInteger)v { [self setDoubleValue:v]; }
- (NSString *)stringValue { return [@(_value) stringValue]; } - (void)setStringValue:(NSString *)s { [self setDoubleValue:[s doubleValue]]; }
- (NSSize)cellSize { return NSMakeSize(19, 27); }
- (void)_step:(int)dir {
  double v = _value + dir * _inc;
  if (v > _max) v = _valueWraps ? _min : _max;
  if (v < _min) v = _valueWraps ? _max : _min;
  _value = v; }
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v {
  NSRect b = NSMakeRect(NSMidX(r) - 7, r.origin.y + 2, 14, r.size.height - 4);
  fill_round(b, 5, [NSColor whiteColor], gray(0.7));
  if (_pressed) { [gray(0.85) setFill]; NSRectFill(_pressed > 0 ? NSMakeRect(b.origin.x + 1, b.origin.y + 1, 12, b.size.height / 2 - 1) : NSMakeRect(b.origin.x + 1, NSMidY(b), 12, b.size.height / 2 - 1)); }
  [(_enabled ? gray(0.25) : gray(0.65)) setStroke];
  NSBezierPath *p = [NSBezierPath bezierPath]; [p setLineWidth:1.5];
  CGFloat cx = NSMidX(b), uy = b.origin.y + b.size.height * 0.27, dy = b.origin.y + b.size.height * 0.73;
  [p moveToPoint:NSMakePoint(cx - 3, uy + 1.5)]; [p lineToPoint:NSMakePoint(cx, uy - 1.5)]; [p lineToPoint:NSMakePoint(cx + 3, uy + 1.5)];
  [p moveToPoint:NSMakePoint(cx - 3, dy - 1.5)]; [p lineToPoint:NSMakePoint(cx, dy + 1.5)]; [p lineToPoint:NSMakePoint(cx + 3, dy - 1.5)];
  [p stroke]; }
- (BOOL)trackMouse:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v untilMouseUp:(BOOL)u {
  NSPoint p = local_point(v, e);
  _pressed = p.y < NSMidY(r) ? 1 : -1;   /* flipped: the upper half increments */
  [self _step:_pressed]; [v setNeedsDisplay:YES]; XEFRedrawWindowNow([v window]);
  for (;;) { NSEvent *n = XEFNextTrackingEvent(); if (n && [n type] == NSEventTypeLeftMouseUp) break; }
  _pressed = 0; [v setNeedsDisplay:YES];
  return YES; }
@end

@implementation NSStepper
+ (Class)cellClass { return [NSStepperCell class]; }
#define SC ((NSStepperCell *)_cell)
- (double)minValue { return [SC minValue]; } - (void)setMinValue:(double)v { [SC setMinValue:v]; }
- (double)maxValue { return [SC maxValue]; } - (void)setMaxValue:(double)v { [SC setMaxValue:v]; }
- (double)increment { return [SC increment]; } - (void)setIncrement:(double)v { [SC setIncrement:v]; }
- (BOOL)valueWraps { return [SC valueWraps]; } - (void)setValueWraps:(BOOL)f { [SC setValueWraps:f]; }
- (BOOL)autorepeat { return [SC autorepeat]; } - (void)setAutorepeat:(BOOL)f { [SC setAutorepeat:f]; }
- (void)keyDown:(NSEvent *)e {
  unsigned short k = [e keyCode];
  if (k == 126) [SC _step:1]; else if (k == 125) [SC _step:-1]; else { [super keyDown:e]; return; }
  [self setNeedsDisplay:YES]; [self sendAction:[self action] to:[self target]]; }
#undef SC
@end

/* ================================================================== NSProgressIndicator */
@implementation NSProgressIndicator
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { _max = 100; _indeterminate = YES; _bezeled = YES; _displayedWhenStopped = YES; _threaded = YES; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    _min = [c decodeDoubleForKey:@"NSMinValue"]; _max = [c containsValueForKey:@"NSMaxValue"] ? [c decodeDoubleForKey:@"NSMaxValue"] : 100;
    uint32_t fl = (uint32_t)[c decodeIntForKey:@"NSpiFlags"];
    _indeterminate = (fl & 0x2) != 0; _style = (fl & 0x1000) ? 1 : 0; _displayedWhenStopped = !(fl & 0x2000); _bezeled = YES; _threaded = YES; }
  return self; }
- (void)dealloc { [_timer invalidate]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (double)minValue { return _min; } - (void)setMinValue:(double)v { _min = v; [self setNeedsDisplay:YES]; }
- (double)maxValue { return _max; } - (void)setMaxValue:(double)v { _max = v; [self setNeedsDisplay:YES]; }
- (double)doubleValue { return _value; }
- (void)setDoubleValue:(double)v { _value = v < _min ? _min : v > _max ? _max : v; [self setNeedsDisplay:YES]; }
- (void)incrementBy:(double)d { [self setDoubleValue:_value + d]; }
- (BOOL)isIndeterminate { return _indeterminate; } - (void)setIndeterminate:(BOOL)f { _indeterminate = f; [self setNeedsDisplay:YES]; }
- (NSInteger)style { return _style; } - (void)setStyle:(NSInteger)s { _style = s; [self setNeedsDisplay:YES]; }
- (BOOL)isBezeled { return _bezeled; } - (void)setBezeled:(BOOL)f { _bezeled = f; }
- (NSUInteger)controlSize { return _controlSize; } - (void)setControlSize:(NSUInteger)s { _controlSize = s; }
- (NSInteger)controlTint { return _tint; } - (void)setControlTint:(NSInteger)t { _tint = t; }
- (BOOL)isDisplayedWhenStopped { return _displayedWhenStopped; } - (void)setDisplayedWhenStopped:(BOOL)f { _displayedWhenStopped = f; [self setNeedsDisplay:YES]; }
- (BOOL)usesThreadedAnimation { return _threaded; } - (void)setUsesThreadedAnimation:(BOOL)f { _threaded = f; }
- (NSTimeInterval)animationDelay { return 1.0 / 30; } - (void)setAnimationDelay:(NSTimeInterval)d {}
- (id)observedProgress { return nil; } - (void)setObservedProgress:(id)p {}
- (void)_xefTick:(NSTimer *)t { _phase += 1.0 / 30; [self setNeedsDisplay:YES]; }
- (void)startAnimation:(id)s {
  if (_animating) return;
  _animating = YES;
  _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30 target:self selector:@selector(_xefTick:) userInfo:nil repeats:YES];
  [self setNeedsDisplay:YES]; }
- (void)stopAnimation:(id)s { _animating = NO; [_timer invalidate]; _timer = nil; [self setNeedsDisplay:YES]; }
- (void)animate:(id)s { _phase += 1.0 / 30; [self setNeedsDisplay:YES]; }
- (void)sizeToFit { [self setFrameSize:_style == 1 ? NSMakeSize(32, 32) : NSMakeSize(_frame.size.width, 20)]; }
- (NSSize)intrinsicContentSize { return _style == 1 ? NSMakeSize(32, 32) : NSMakeSize(-1, 20); }
- (void)drawRect:(NSRect)r {
  if (_style == 1) {   /* spinner: 12 fading spokes */
    if (!_animating && !_displayedWhenStopped) return;
    CGFloat d = fmin(_bounds.size.width, _bounds.size.height), cx = NSMidX(_bounds), cy = NSMidY(_bounds);
    int head = _animating ? (int)(_phase * 12) % 12 : 0;
    for (int i = 0; i < 12; i++) {
      double a = i * M_PI / 6; CGFloat alpha = _indeterminate ? 0.15 + 0.75 * (((i - head + 12) % 12) / 11.0) : (i / 12.0 < (_max > _min ? (_value - _min) / (_max - _min) : 0) ? 0.9 : 0.15);
      [[NSColor colorWithCalibratedWhite:0.3 alpha:alpha] setStroke];
      NSBezierPath *p = [NSBezierPath bezierPath]; [p setLineWidth:fmax(1.5, d / 12)];
      [p moveToPoint:NSMakePoint(cx + sin(a) * d * 0.25, cy - cos(a) * d * 0.25)]; [p lineToPoint:NSMakePoint(cx + sin(a) * d * 0.45, cy - cos(a) * d * 0.45)]; [p stroke]; }
    return; }
  NSRect bar = NSMakeRect(_bounds.origin.x, NSMidY(_bounds) - 3, _bounds.size.width, 6);
  fill_round(bar, 3, gray(0.85), nil);
  NSColor *accent = [NSColor controlAccentColor];
  if (_indeterminate) {
    if (!_animating) return;
    CGFloat w = bar.size.width * 0.3, x = fmod(_phase * 0.8, 1.0) * (bar.size.width + w) - w;
    NSRect seg = NSIntersectionRect(NSMakeRect(bar.origin.x + x, bar.origin.y, w, bar.size.height), bar);
    if (seg.size.width > 0) fill_round(seg, 3, accent, nil);
  } else {
    CGFloat t = _max > _min ? clampd((_value - _min) / (_max - _min), 0, 1) : 0;
    if (t > 0) fill_round(NSMakeRect(bar.origin.x, bar.origin.y, fmax(6, bar.size.width * t), bar.size.height), 3, accent, nil); } }
@end

/* ================================================================== NSSegmentedControl */
@implementation XEFSegment
- (id)init { if ((self = [super init])) { _enabled = YES; _label = @""; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [self init])) {
    _label = [[c decodeObjectForKey:@"NSSegmentItemLabel"] copy] ?: @""; _image = [[c decodeObjectForKey:@"NSSegmentItemImage"] retain];
    _width = [c decodeDoubleForKey:@"NSSegmentItemWidth"]; _selected = [c decodeBoolForKey:@"NSSegmentItemSelected"];
    _enabled = ![c decodeBoolForKey:@"NSSegmentItemDisabled"]; _tag = [c decodeIntegerForKey:@"NSSegmentItemTag"]; }
  return self; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc { [_label release]; [_toolTip release]; [_image release]; [_menu release]; [super dealloc]; }
@end

@implementation NSSegmentedCell
- (id)initTextCell:(NSString *)s { if ((self = [super initTextCell:s])) { _segments = [[NSMutableArray alloc] init]; _last = -1; _pressed = -1; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    _segments = [[NSMutableArray alloc] init]; _last = -1; _pressed = -1;
    for (id s in [c decodeObjectForKey:@"NSSegmentImages"]) if ([s isKindOfClass:[XEFSegment class]]) [_segments addObject:s];
    _mode = [c decodeIntegerForKey:@"NSTrackingMode"]; _style = [c decodeIntegerForKey:@"NSSegmentStyle"];
    if ([c containsValueForKey:@"NSSelectedSegment"]) _last = [c decodeIntegerForKey:@"NSSelectedSegment"];
    else for (NSUInteger i = 0; i < [_segments count]; i++) if (((XEFSegment *)_segments[i])->_selected) _last = i; }
  return self; }
- (void)dealloc { [_segments release]; [super dealloc]; }
- (XEFSegment *)_seg:(NSInteger)i { return i >= 0 && i < (NSInteger)[_segments count] ? _segments[i] : nil; }
- (NSInteger)segmentCount { return [_segments count]; }
- (void)setSegmentCount:(NSInteger)n {
  while ((NSInteger)[_segments count] > n && n >= 0) [_segments removeLastObject];
  while ((NSInteger)[_segments count] < n) [_segments addObject:[[[XEFSegment alloc] init] autorelease]];
  if (_last >= n) _last = -1;
  [self _changed]; }
- (NSInteger)trackingMode { return _mode; } - (void)setTrackingMode:(NSInteger)m { _mode = m; }
- (NSInteger)segmentStyle { return _style; } - (void)setSegmentStyle:(NSInteger)s { _style = s; [self _changed]; }
- (NSInteger)selectedSegment { return _last; }
- (void)setSelectedSegment:(NSInteger)i {
  if (_mode == 2 /* momentary */) return;
  if (i < 0 || i >= (NSInteger)[_segments count]) { if (i == -1) { for (XEFSegment *s in _segments) s->_selected = NO; _last = -1; [self _changed]; } return; }
  [self setSelected:YES forSegment:i]; }
- (BOOL)isSelectedForSegment:(NSInteger)i { XEFSegment *s = [self _seg:i]; return s ? s->_selected : NO; }
- (void)setSelected:(BOOL)f forSegment:(NSInteger)i {
  XEFSegment *s = [self _seg:i]; if (!s) return;
  if (_mode == 0 /* select one */) {
    if (!f) return;                                  /* the selected segment of a select-one control cannot be deselected */
    for (XEFSegment *o in _segments) o->_selected = NO; }
  s->_selected = f;
  if (f) _last = i;
  else if (_last == i) { _last = -1; for (NSInteger k = [_segments count] - 1; k >= 0; k--) if (((XEFSegment *)_segments[k])->_selected) { _last = k; break; } }
  [self _changed]; }
- (BOOL)selectSegmentWithTag:(NSInteger)t {
  for (NSUInteger i = 0; i < [_segments count]; i++) if (((XEFSegment *)_segments[i])->_tag == t) { [self setSelectedSegment:i]; return YES; }
  return NO; }
- (void)makeNextSegmentKey {} - (void)makePreviousSegmentKey {}
- (NSString *)labelForSegment:(NSInteger)i { return [self _seg:i]->_label; }
- (void)setLabel:(NSString *)l forSegment:(NSInteger)i { XEFSegment *s = [self _seg:i]; if (s) { [s->_label release]; s->_label = [l copy] ?: @""; [self _changed]; } }
- (NSImage *)imageForSegment:(NSInteger)i { return [self _seg:i]->_image; }
- (void)setImage:(NSImage *)im forSegment:(NSInteger)i { XEFSegment *s = [self _seg:i]; if (s) { [im retain]; [s->_image release]; s->_image = im; [self _changed]; } }
- (NSInteger)imageScalingForSegment:(NSInteger)i { return [self _seg:i]->_scaling; } - (void)setImageScaling:(NSInteger)sc forSegment:(NSInteger)i { [self _seg:i]->_scaling = sc; }
- (CGFloat)widthForSegment:(NSInteger)i { XEFSegment *s = [self _seg:i]; return s ? s->_width : 0; }
- (void)setWidth:(CGFloat)w forSegment:(NSInteger)i { [self _seg:i]->_width = w; [self _changed]; }
- (BOOL)isEnabledForSegment:(NSInteger)i { XEFSegment *s = [self _seg:i]; return s ? s->_enabled : NO; }
- (void)setEnabled:(BOOL)f forSegment:(NSInteger)i { [self _seg:i]->_enabled = f; [self _changed]; }
- (NSInteger)tagForSegment:(NSInteger)i { XEFSegment *s = [self _seg:i]; return s ? s->_tag : 0; } - (void)setTag:(NSInteger)t forSegment:(NSInteger)i { [self _seg:i]->_tag = t; }
- (NSMenu *)menuForSegment:(NSInteger)i { return [self _seg:i]->_menu; }
- (void)setMenu:(NSMenu *)m forSegment:(NSInteger)i { XEFSegment *s = [self _seg:i]; if (s) { [m retain]; [s->_menu release]; s->_menu = m; } }
- (NSString *)toolTipForSegment:(NSInteger)i { return [self _seg:i]->_toolTip; }
- (void)setToolTip:(NSString *)t forSegment:(NSInteger)i { XEFSegment *s = [self _seg:i]; if (s) { [s->_toolTip release]; s->_toolTip = [t copy]; } }
- (NSInteger)alignmentForSegment:(NSInteger)i { return [self _seg:i]->_align; } - (void)setAlignment:(NSInteger)a forSegment:(NSInteger)i { [self _seg:i]->_align = a; }
- (BOOL)showsMenuIndicatorForSegment:(NSInteger)i { return NO; } - (void)setShowsMenuIndicator:(BOOL)f forSegment:(NSInteger)i {}
- (CGFloat)_natural:(XEFSegment *)s {
  if (s->_width > 0) return s->_width;
  CGFloat w = [s->_label length] ? [s->_label sizeWithAttributes:attrs2(_font, nil, 1)].width + 20 : 12;
  if (s->_image) w += [s->_image size].width + ([s->_label length] ? 4 : 8);
  return ceil(w); }
- (NSSize)cellSize { CGFloat w = 0; for (XEFSegment *s in _segments) w += [self _natural:s]; return NSMakeSize(w + 4, 24); }
/* segment rectangles: fixed widths where set, the rest shares what is left of the control */
- (NSRect)_rectOfSegment:(NSInteger)idx inFrame:(NSRect)r {
  CGFloat fixed = 0; NSInteger flexible = 0; NSInteger n = [_segments count];
  for (XEFSegment *s in _segments) { if (s->_width > 0) fixed += s->_width; else flexible++; }
  CGFloat natural = 0; for (XEFSegment *s in _segments) natural += [self _natural:s];
  BOOL fill = r.size.width - 4 < natural || natural <= 0;
  CGFloat each = flexible ? (r.size.width - 4 - fixed) / flexible : 0, x = r.origin.x + (fill ? 2 : NSMidX(r) - r.origin.x - natural / 2);
  for (NSInteger i = 0; i < n; i++) {
    XEFSegment *s = _segments[i]; CGFloat w = fill ? (s->_width > 0 ? s->_width : each) : [self _natural:s];
    if (i == idx) return NSMakeRect(x, r.origin.y + 1, w, r.size.height - 2);
    x += w; }
  return NSZeroRect; }
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v {
  NSInteger n = [_segments count]; if (!n) return;
  NSRect first = [self _rectOfSegment:0 inFrame:r], last = [self _rectOfSegment:n - 1 inFrame:r];
  NSRect all = NSMakeRect(first.origin.x, r.origin.y + 1, NSMaxX(last) - first.origin.x, r.size.height - 2);
  fill_round(all, 5, gray(0.93), gray(0.75));
  for (NSInteger i = 0; i < n; i++) {
    XEFSegment *s = _segments[i]; NSRect sr = [self _rectOfSegment:i inFrame:r];
    BOOL on = s->_selected || i == _pressed;
    if (on) fill_round(NSInsetRect(sr, 1.5, 1.5), 4, i == _pressed && !s->_selected ? gray(0.8) : (_mode == 2 ? gray(0.8) : [NSColor whiteColor]), gray(0.7));
    else if (i > 0 && !((XEFSegment *)_segments[i - 1])->_selected) { [gray(0.8) setFill]; NSRectFill(NSMakeRect(sr.origin.x, sr.origin.y + 5, 1, sr.size.height - 10)); }
    NSColor *tc = !_enabled || !s->_enabled ? [NSColor disabledControlTextColor] : [NSColor controlTextColor];
    NSRect content = NSInsetRect(sr, 4, 0);
    if (s->_image) {
      CGFloat iw = fmin([s->_image size].width, sr.size.height - 6);
      NSRect ir = [s->_label length] ? NSMakeRect(content.origin.x + 2, NSMidY(sr) - iw / 2, iw, iw) : NSMakeRect(NSMidX(sr) - iw / 2, NSMidY(sr) - iw / 2, iw, iw);
      draw_image_fit(s->_image, ir, 3, 0);
      content.origin.x += iw + 4; content.size.width -= iw + 4; }
    if ([s->_label length]) draw_centered(s->_label, content, attrs2(_font, tc, 1)); } }
- (NSInteger)_segmentAtPoint:(NSPoint)p inFrame:(NSRect)r {
  for (NSUInteger i = 0; i < [_segments count]; i++) if (NSPointInRect(p, [self _rectOfSegment:i inFrame:r])) return i;
  return -1; }
- (BOOL)trackMouse:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v untilMouseUp:(BOOL)u {
  NSInteger start = [self _segmentAtPoint:local_point(v, e) inFrame:r];
  XEFSegment *s = [self _seg:start]; if (!s || !s->_enabled) return NO;
  _pressed = start; [v setNeedsDisplay:YES]; XEFRedrawWindowNow([v window]);
  BOOL inside = YES;
  for (;;) {
    NSEvent *n = XEFNextTrackingEvent(); if (!n) continue;
    inside = [self _segmentAtPoint:local_point(v, n) inFrame:r] == start;
    if ([n type] == NSEventTypeLeftMouseUp) break;
    NSInteger p = inside ? start : -1; if (p != _pressed) { _pressed = p; [v setNeedsDisplay:YES]; XEFRedrawWindowNow([v window]); } }
  _pressed = -1; [v setNeedsDisplay:YES];
  if (!inside) return NO;
  if (_mode == 0) [self setSelected:YES forSegment:start];
  else if (_mode == 1) [self setSelected:!s->_selected forSegment:start];
  else _last = start;                                    /* momentary: selectedSegment names the clicked one during the action */
  return YES; }
- (void)_xefClicked {}
- (void)_xefAfterAction { if (_mode == 2) _last = -1; }
@end

@implementation NSSegmentedControl
+ (Class)cellClass { return [NSSegmentedCell class]; }
+ (NSSegmentedControl *)segmentedControlWithLabels:(NSArray *)labels trackingMode:(NSInteger)m target:(id)t action:(SEL)a {
  NSSegmentedControl *s = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
  [s setSegmentCount:[labels count]]; for (NSUInteger i = 0; i < [labels count]; i++) [s setLabel:labels[i] forSegment:i];
  [s setTrackingMode:m]; [s setTarget:t]; [s setAction:a]; [s sizeToFit]; return s; }
+ (NSSegmentedControl *)segmentedControlWithImages:(NSArray *)images trackingMode:(NSInteger)m target:(id)t action:(SEL)a {
  NSSegmentedControl *s = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
  [s setSegmentCount:[images count]]; for (NSUInteger i = 0; i < [images count]; i++) [s setImage:images[i] forSegment:i];
  [s setTrackingMode:m]; [s setTarget:t]; [s setAction:a]; [s sizeToFit]; return s; }
#define SC ((NSSegmentedCell *)_cell)
- (NSInteger)segmentCount { return [SC segmentCount]; } - (void)setSegmentCount:(NSInteger)n { [SC setSegmentCount:n]; [self setNeedsDisplay:YES]; }
- (NSInteger)selectedSegment { return [SC selectedSegment]; } - (void)setSelectedSegment:(NSInteger)i { [SC setSelectedSegment:i]; [self setNeedsDisplay:YES]; }
- (NSInteger)indexOfSelectedItem { return [SC selectedSegment]; }
- (BOOL)selectSegmentWithTag:(NSInteger)t { BOOL r = [SC selectSegmentWithTag:t]; [self setNeedsDisplay:YES]; return r; }
- (NSInteger)trackingMode { return [SC trackingMode]; } - (void)setTrackingMode:(NSInteger)m { [SC setTrackingMode:m]; }
- (NSInteger)segmentStyle { return [SC segmentStyle]; } - (void)setSegmentStyle:(NSInteger)s { [SC setSegmentStyle:s]; }
- (NSInteger)segmentDistribution { return 0; } - (void)setSegmentDistribution:(NSInteger)d {}
- (BOOL)isSpringLoaded { return NO; } - (void)setSpringLoaded:(BOOL)f {}
- (NSColor *)selectedSegmentBezelColor { return nil; } - (void)setSelectedSegmentBezelColor:(NSColor *)c {}
- (double)doubleValueForSelectedSegment { return 0; } - (NSInteger)activeCompressionOptions { return 0; }
- (NSInteger)borderShape { return 0; } - (void)setBorderShape:(NSInteger)s {}
- (BOOL)isSelectedForSegment:(NSInteger)i { return [SC isSelectedForSegment:i]; } - (void)setSelected:(BOOL)f forSegment:(NSInteger)i { [SC setSelected:f forSegment:i]; [self setNeedsDisplay:YES]; }
- (NSString *)labelForSegment:(NSInteger)i { return [SC labelForSegment:i]; } - (void)setLabel:(NSString *)l forSegment:(NSInteger)i { [SC setLabel:l forSegment:i]; [self setNeedsDisplay:YES]; }
- (NSImage *)imageForSegment:(NSInteger)i { return [SC imageForSegment:i]; } - (void)setImage:(NSImage *)im forSegment:(NSInteger)i { [SC setImage:im forSegment:i]; [self setNeedsDisplay:YES]; }
- (NSInteger)imageScalingForSegment:(NSInteger)i { return [SC imageScalingForSegment:i]; } - (void)setImageScaling:(NSInteger)s forSegment:(NSInteger)i { [SC setImageScaling:s forSegment:i]; }
- (CGFloat)widthForSegment:(NSInteger)i { return [SC widthForSegment:i]; } - (void)setWidth:(CGFloat)w forSegment:(NSInteger)i { [SC setWidth:w forSegment:i]; [self setNeedsDisplay:YES]; }
- (BOOL)isEnabledForSegment:(NSInteger)i { return [SC isEnabledForSegment:i]; } - (void)setEnabled:(BOOL)f forSegment:(NSInteger)i { [SC setEnabled:f forSegment:i]; [self setNeedsDisplay:YES]; }
- (NSInteger)tagForSegment:(NSInteger)i { return [SC tagForSegment:i]; } - (void)setTag:(NSInteger)t forSegment:(NSInteger)i { [SC setTag:t forSegment:i]; }
- (NSMenu *)menuForSegment:(NSInteger)i { return [SC menuForSegment:i]; } - (void)setMenu:(NSMenu *)m forSegment:(NSInteger)i { [SC setMenu:m forSegment:i]; }
- (NSString *)toolTipForSegment:(NSInteger)i { return [SC toolTipForSegment:i]; } - (void)setToolTip:(NSString *)t forSegment:(NSInteger)i { [SC setToolTip:t forSegment:i]; }
- (NSInteger)alignmentForSegment:(NSInteger)i { return [SC alignmentForSegment:i]; } - (void)setAlignment:(NSInteger)a forSegment:(NSInteger)i { [SC setAlignment:a forSegment:i]; }
- (BOOL)showsMenuIndicatorForSegment:(NSInteger)i { return NO; } - (void)setShowsMenuIndicator:(BOOL)f forSegment:(NSInteger)i {}
- (void)setImageScaling:(NSInteger)s { }
- (void)mouseDown:(NSEvent *)e {
  if (![self isEnabled]) return;
  if ([_cell trackMouse:e inRect:_bounds ofView:self untilMouseUp:YES]) { [self sendAction:[self action] to:[self target]]; [SC _xefAfterAction]; [self setNeedsDisplay:YES]; } }
#undef SC
@end

/* ================================================================== NSImageView */
@implementation NSImageCell
- (id)initTextCell:(NSString *)s { if ((self = [super initTextCell:s])) { _type = 2; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    _type = 2; _scaling = [c decodeIntegerForKey:@"NSScale"]; _imageAlign = [c decodeIntegerForKey:@"NSAlign"]; _frameStyle = [c decodeIntegerForKey:@"NSStyle"];
    id i = [c decodeObjectForKey:@"NSContents"]; if ([i isKindOfClass:[NSImage class]]) [self setImage:i]; }
  return self; }
- (id)objectValue { return _image; }
- (void)setObjectValue:(id)v { if (!v || [v isKindOfClass:[NSImage class]]) [self setImage:v]; }
- (NSInteger)imageScaling { return _scaling; } - (void)setImageScaling:(NSInteger)s { _scaling = s; [self _changed]; }
- (NSInteger)imageAlignment { return _imageAlign; } - (void)setImageAlignment:(NSInteger)a { _imageAlign = a; [self _changed]; }
- (NSInteger)imageFrameStyle { return _frameStyle; } - (void)setImageFrameStyle:(NSInteger)s { _frameStyle = s; [self _changed]; }
- (NSSize)cellSize { return _image ? [_image size] : NSZeroSize; }
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v {
  NSRect inner = r;
  if (_frameStyle) { fill_round(r, _frameStyle == 2 ? 0 : 3, _frameStyle >= 2 ? [NSColor whiteColor] : nil, gray(0.7)); inner = NSInsetRect(r, 3, 3); }
  if (_image) draw_image_fit(_image, inner, _scaling, _imageAlign); }
@end

@implementation NSImageView
+ (Class)cellClass { return [NSImageCell class]; }
+ (NSImageView *)imageViewWithImage:(NSImage *)i { NSImageView *v = [[[self alloc] initWithFrame:NSMakeRect(0, 0, [i size].width, [i size].height)] autorelease]; [v setImage:i]; return v; }
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { _animates = YES; } return self; }
- (id)initWithCoder:(NSCoder *)c { if ((self = [super initWithCoder:c])) { _animates = YES; _editableIV = [c decodeBoolForKey:@"NSEditable"]; } return self; }
- (void)dealloc { [_tint release]; [super dealloc]; }
- (NSImage *)image { return [_cell image]; } - (void)setImage:(NSImage *)i { [_cell setImage:i]; [self setNeedsDisplay:YES]; }
- (id)objectValue { return [_cell image]; } - (void)setObjectValue:(id)v { [_cell setObjectValue:v]; [self setNeedsDisplay:YES]; }
- (NSInteger)imageScaling { return [(NSImageCell *)_cell imageScaling]; } - (void)setImageScaling:(NSInteger)s { [(NSImageCell *)_cell setImageScaling:s]; [self setNeedsDisplay:YES]; }
- (NSInteger)imageAlignment { return [(NSImageCell *)_cell imageAlignment]; } - (void)setImageAlignment:(NSInteger)a { [(NSImageCell *)_cell setImageAlignment:a]; [self setNeedsDisplay:YES]; }
- (NSInteger)imageFrameStyle { return [(NSImageCell *)_cell imageFrameStyle]; } - (void)setImageFrameStyle:(NSInteger)s { [(NSImageCell *)_cell setImageFrameStyle:s]; [self setNeedsDisplay:YES]; }
- (BOOL)isEditable { return _editableIV; } - (void)setEditable:(BOOL)f { _editableIV = f; }
- (BOOL)animates { return _animates; } - (void)setAnimates:(BOOL)f { _animates = f; }
- (BOOL)allowsCutCopyPaste { return _allowsCut; } - (void)setAllowsCutCopyPaste:(BOOL)f { _allowsCut = f; }
- (NSColor *)contentTintColor { return _tint; } - (void)setContentTintColor:(NSColor *)c { [c retain]; [_tint release]; _tint = c; }
- (id)symbolConfiguration { return nil; } - (void)setSymbolConfiguration:(id)c {}
- (id)preferredImageDynamicRange { return nil; } - (void)setPreferredImageDynamicRange:(NSInteger)r {}
- (id)defaultPreferredImageDynamicRange { return nil; }
- (NSInteger)imageDynamicRange { return 0; }
- (void)addSymbolEffect:(id)e {} - (void)removeSymbolEffectOfType:(id)e {} - (void)removeAllSymbolEffects {}
- (NSSize)intrinsicContentSize { NSImage *i = [_cell image]; return i ? [i size] : NSMakeSize(-1, -1); }
- (BOOL)acceptsFirstResponder { return _editableIV; }
- (void)mouseDown:(NSEvent *)e { if ([self action]) [self sendAction:[self action] to:[self target]]; else [[self nextResponder] mouseDown:e]; }
@end

/* ================================================================== NSLevelIndicator */
@implementation NSLevelIndicatorCell
- (id)initTextCell:(NSString *)s { return [self initWithLevelIndicatorStyle:2]; }
- (id)initWithLevelIndicatorStyle:(NSInteger)st { if ((self = [super initTextCell:@""])) { _style = st; _max = 5; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    _min = [c decodeDoubleForKey:@"NSMinValue"]; _max = [c decodeDoubleForKey:@"NSMaxValue"]; _value = [c decodeDoubleForKey:@"NSValue"];
    _warn = [c decodeDoubleForKey:@"NSWarningValue"]; _crit = [c decodeDoubleForKey:@"NSCriticalValue"]; _style = [c decodeIntegerForKey:@"NSIndicatorStyle"];
    _ticks = [c decodeIntegerForKey:@"NSNumberOfTickMarks"]; _major = [c decodeIntegerForKey:@"NSNumberOfMajorTickMarks"]; }
  return self; }
- (double)minValue { return _min; } - (void)setMinValue:(double)v { _min = v; [self _changed]; }
- (double)maxValue { return _max; } - (void)setMaxValue:(double)v { _max = v; [self _changed]; }
- (double)warningValue { return _warn; } - (void)setWarningValue:(double)v { _warn = v; [self _changed]; }
- (double)criticalValue { return _crit; } - (void)setCriticalValue:(double)v { _crit = v; [self _changed]; }
- (NSInteger)levelIndicatorStyle { return _style; } - (void)setLevelIndicatorStyle:(NSInteger)s { _style = s; [self _changed]; }
- (NSInteger)numberOfTickMarks { return _ticks; } - (void)setNumberOfTickMarks:(NSInteger)n { _ticks = n; }
- (NSInteger)numberOfMajorTickMarks { return _major; } - (void)setNumberOfMajorTickMarks:(NSInteger)n { _major = n; }
- (NSInteger)tickMarkPosition { return _tickPos; } - (void)setTickMarkPosition:(NSInteger)p { _tickPos = p; }
- (double)tickMarkValueAtIndex:(NSInteger)i { return _ticks > 1 ? _min + (_max - _min) * i / (_ticks - 1) : _min; }
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)i { return NSZeroRect; }
- (id)objectValue { return @(_value); }
- (void)setObjectValue:(id)v { _value = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0; [self _changed]; }
- (double)doubleValue { return _value; } - (void)setDoubleValue:(double)v { _value = v; [self _changed]; }
- (float)floatValue { return (float)_value; } - (void)setFloatValue:(float)v { [self setDoubleValue:v]; }
- (int)intValue { return (int)_value; } - (void)setIntValue:(int)v { [self setDoubleValue:v]; }
- (NSInteger)integerValue { return (NSInteger)_value; } - (void)setIntegerValue:(NSInteger)v { [self setDoubleValue:v]; }
- (NSString *)stringValue { return [@(_value) stringValue]; }
- (NSSize)cellSize { return NSMakeSize(_style == 3 ? 13 * fmax(1, _max - _min) : 96, 16); }
- (NSColor *)_color {
  NSLevelIndicator *li = (NSLevelIndicator *)_controlView; BOOL custom = [li isKindOfClass:[NSLevelIndicator class]];
  BOOL rising = _crit >= _warn;
  if (_crit != 0 && (rising ? _value >= _crit : _value <= _crit)) return (custom && li->_critFill) ? li->_critFill : [NSColor colorWithCalibratedRed:1 green:0.23 blue:0.19 alpha:1];
  if (_warn != 0 && (rising ? _value >= _warn : _value <= _warn)) return (custom && li->_warnFill) ? li->_warnFill : [NSColor colorWithCalibratedRed:1 green:0.8 blue:0 alpha:1];
  return (custom && li->_fill) ? li->_fill : [NSColor colorWithCalibratedRed:0.2 green:0.78 blue:0.35 alpha:1]; }
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v {
  double range = _max - _min, t = range > 0 ? clampd((_value - _min) / range, 0, 1) : 0;
  NSRect bar = NSMakeRect(r.origin.x, NSMidY(r) - 6, r.size.width, 12);
  if (_style == 1) {            /* continuous capacity */
    fill_round(bar, 2, gray(0.9), gray(0.75));
    if (t > 0) { [[self _color] setFill]; NSRectFill(NSMakeRect(bar.origin.x + 1, bar.origin.y + 1, (bar.size.width - 2) * t, bar.size.height - 2)); }
  } else if (_style == 3) {     /* rating: one dot per unit */
    NSInteger n = (NSInteger)fmax(1, range); CGFloat w = fmin(13, r.size.width / n);
    for (NSInteger i = 0; i < n; i++) {
      NSBezierPath *star = [NSBezierPath bezierPath]; CGFloat cx = r.origin.x + w * i + w / 2, cy = NSMidY(r);
      for (int k = 0; k < 10; k++) { double a = k * M_PI / 5, rad = k % 2 ? 2.4 : 6; NSPoint p = NSMakePoint(cx + sin(a) * rad, cy - cos(a) * rad); if (k) [star lineToPoint:p]; else [star moveToPoint:p]; }
      [star closePath]; [(i < _value - _min ? gray(0.3) : gray(0.85)) setFill]; [star fill]; }
  } else if (_style == 0) {     /* relevancy: thin vertical bars */
    NSInteger n = (NSInteger)(bar.size.width / 3);
    for (NSInteger i = 0; i < n; i++) { [(i < t * n ? gray(0.4) : gray(0.88)) setFill]; NSRectFill(NSMakeRect(bar.origin.x + i * 3, bar.origin.y, 2, bar.size.height)); }
  } else {                      /* discrete capacity */
    NSInteger n = (NSInteger)fmax(1, range); CGFloat w = bar.size.width / n; NSColor *c = [self _color];
    for (NSInteger i = 0; i < n; i++) fill_round(NSMakeRect(bar.origin.x + i * w + 1, bar.origin.y, w - 2, bar.size.height), 2, i < _value - _min ? c : gray(0.9), gray(0.78)); } }
- (BOOL)trackMouse:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v untilMouseUp:(BOOL)u {
  for (NSEvent *n = e;;) {
    if (n) {
      double t = clampd((local_point(v, n).x - r.origin.x) / fmax(1, r.size.width), 0, 1), nv = _min + (_max - _min) * t;
      if (_style != 1) nv = ceil(nv - 1e-9);
      _value = nv; [v setNeedsDisplay:YES]; XEFRedrawWindowNow([v window]);
      if ([n type] == NSEventTypeLeftMouseUp) break; }
    n = XEFNextTrackingEvent(); }
  return YES; }
@end

@implementation NSLevelIndicator
+ (Class)cellClass { return [NSLevelIndicatorCell class]; }
- (void)dealloc { [_fill release]; [_warnFill release]; [_critFill release]; [super dealloc]; }
#define LC ((NSLevelIndicatorCell *)_cell)
- (double)minValue { return [LC minValue]; } - (void)setMinValue:(double)v { [LC setMinValue:v]; [self setNeedsDisplay:YES]; }
- (double)maxValue { return [LC maxValue]; } - (void)setMaxValue:(double)v { [LC setMaxValue:v]; [self setNeedsDisplay:YES]; }
- (double)warningValue { return [LC warningValue]; } - (void)setWarningValue:(double)v { [LC setWarningValue:v]; [self setNeedsDisplay:YES]; }
- (double)criticalValue { return [LC criticalValue]; } - (void)setCriticalValue:(double)v { [LC setCriticalValue:v]; [self setNeedsDisplay:YES]; }
- (NSInteger)levelIndicatorStyle { return [LC levelIndicatorStyle]; } - (void)setLevelIndicatorStyle:(NSInteger)s { [LC setLevelIndicatorStyle:s]; [self setNeedsDisplay:YES]; }
- (NSInteger)numberOfTickMarks { return [LC numberOfTickMarks]; } - (void)setNumberOfTickMarks:(NSInteger)n { [LC setNumberOfTickMarks:n]; }
- (NSInteger)numberOfMajorTickMarks { return [LC numberOfMajorTickMarks]; } - (void)setNumberOfMajorTickMarks:(NSInteger)n { [LC setNumberOfMajorTickMarks:n]; }
- (NSInteger)tickMarkPosition { return [LC tickMarkPosition]; } - (void)setTickMarkPosition:(NSInteger)p { [LC setTickMarkPosition:p]; }
- (double)tickMarkValueAtIndex:(NSInteger)i { return [LC tickMarkValueAtIndex:i]; } - (NSRect)rectOfTickMarkAtIndex:(NSInteger)i { return NSZeroRect; }
#undef LC
- (BOOL)isEditable { return _editableLI; } - (void)setEditable:(BOOL)f { _editableLI = f; }
- (NSColor *)fillColor { return _fill; } - (void)setFillColor:(NSColor *)c { [c retain]; [_fill release]; _fill = c; [self setNeedsDisplay:YES]; }
- (NSColor *)warningFillColor { return _warnFill; } - (void)setWarningFillColor:(NSColor *)c { [c retain]; [_warnFill release]; _warnFill = c; [self setNeedsDisplay:YES]; }
- (NSColor *)criticalFillColor { return _critFill; } - (void)setCriticalFillColor:(NSColor *)c { [c retain]; [_critFill release]; _critFill = c; [self setNeedsDisplay:YES]; }
- (BOOL)drawsTieredCapacityLevels { return NO; } - (void)setDrawsTieredCapacityLevels:(BOOL)f {}
- (NSInteger)placeholderVisibility { return 0; } - (void)setPlaceholderVisibility:(NSInteger)v {}
- (NSImage *)ratingImage { return nil; } - (void)setRatingImage:(NSImage *)i {} - (NSImage *)ratingPlaceholderImage { return nil; } - (void)setRatingPlaceholderImage:(NSImage *)i {}
- (void)mouseDown:(NSEvent *)e { if (_editableLI && [self isEnabled]) [super mouseDown:e]; }
@end

/* ================================================================== NSColorWell */
@implementation NSColorWell
+ (Class)cellClass { return [NSActionCell class]; }
+ (NSColorWell *)colorWellWithStyle:(NSInteger)s { NSColorWell *w = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 44, 23)] autorelease]; w->_wellStyle = s; return w; }
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { _color = [[NSColor whiteColor] retain]; _borderedCW = YES; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) { _color = [[c decodeObjectForKey:@"NSColor"] retain] ?: [[NSColor whiteColor] retain]; _borderedCW = [c containsValueForKey:@"NSIsBordered"] ? [c decodeBoolForKey:@"NSIsBordered"] : YES; }
  return self; }
- (void)dealloc { [_color release]; [super dealloc]; }
- (NSColor *)color { return _color; } - (void)setColor:(NSColor *)c { if (!c) return; [c retain]; [_color release]; _color = c; [self setNeedsDisplay:YES]; }
- (void)takeColorFrom:(id)s { if ([s respondsToSelector:@selector(color)]) [self setColor:[s color]]; }
- (BOOL)isActive { return _active; }
- (void)activate:(BOOL)exclusive { _active = YES; [self setNeedsDisplay:YES]; }
- (void)deactivate { _active = NO; [self setNeedsDisplay:YES]; }
- (BOOL)isBordered { return _borderedCW; } - (void)setBordered:(BOOL)f { _borderedCW = f; [self setNeedsDisplay:YES]; }
- (NSInteger)colorWellStyle { return _wellStyle; } - (void)setColorWellStyle:(NSInteger)s { _wellStyle = s; }
- (BOOL)supportsAlpha { return YES; } - (void)setSupportsAlpha:(BOOL)f {}
- (NSImage *)image { return nil; } - (void)setImage:(NSImage *)i {}
- (id)pulldownTarget { return nil; } - (void)setPulldownTarget:(id)t {} - (SEL)pulldownAction { return NULL; } - (void)setPulldownAction:(SEL)a {}
- (NSInteger)maximumLinearExposure { return 1; } - (void)setMaximumLinearExposure:(NSInteger)e {}
- (void)drawWellInside:(NSRect)r { [_color setFill]; NSRectFill(r); }
- (void)drawRect:(NSRect)r {
  if (_borderedCW) fill_round(_bounds, 4, _active ? gray(0.8) : gray(0.95), gray(0.7));
  [self drawWellInside:NSInsetRect(_bounds, _borderedCW ? 4 : 0, _borderedCW ? 4 : 0)];
  [gray(0.6) setFill]; NSFrameRect(NSInsetRect(_bounds, _borderedCW ? 4 : 0, _borderedCW ? 4 : 0)); }
- (void)mouseDown:(NSEvent *)e {
  if (![self isEnabled]) return;
  for (;;) { NSEvent *n = XEFNextTrackingEvent(); if (n && [n type] == NSEventTypeLeftMouseUp) break; }
  if (_active) [self deactivate]; else [self activate:YES]; }
@end

/* ================================================================== NSSwitch */
@implementation NSSwitch
+ (Class)cellClass { return [NSActionCell class]; }
- (NSInteger)state { return _stateSW; } - (void)setState:(NSInteger)s { _stateSW = s ? 1 : 0; [self setNeedsDisplay:YES]; }
- (id)objectValue { return @(_stateSW); } - (void)setObjectValue:(id)v { [self setState:[v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0]; }
- (int)intValue { return (int)_stateSW; } - (void)setIntValue:(int)v { [self setState:v]; } - (NSInteger)integerValue { return _stateSW; } - (void)setIntegerValue:(NSInteger)v { [self setState:v]; }
- (NSSize)intrinsicContentSize { return NSMakeSize(38, 22); } - (void)sizeToFit { [self setFrameSize:NSMakeSize(38, 22)]; }
- (void)drawRect:(NSRect)r {
  NSRect t = NSMakeRect(NSMidX(_bounds) - 19, NSMidY(_bounds) - 11, 38, 22);
  fill_round(t, 11, _stateSW ? ([self isEnabled] ? [NSColor controlAccentColor] : gray(0.7)) : gray(0.85), nil);
  NSRect k = NSMakeRect(_stateSW ? NSMaxX(t) - 21 : t.origin.x + 1, t.origin.y + 1, 20, 20);
  [[NSColor whiteColor] setFill]; NSBezierPath *o = [NSBezierPath bezierPathWithOvalInRect:k]; [o fill]; [gray(0.7) setStroke]; [o stroke]; }
- (void)performClick:(id)s { [self setState:!_stateSW]; [self sendAction:[self action] to:[self target]]; }
- (void)mouseDown:(NSEvent *)e {
  if (![self isEnabled]) return;
  BOOL inside = YES;
  for (;;) { NSEvent *n = XEFNextTrackingEvent(); if (!n) continue; if ([n type] == NSEventTypeLeftMouseUp) { inside = NSPointInRect(local_point(self, n), _bounds); break; } }
  if (inside) [self performClick:nil]; }
@end

/* ================================================================== NSComboBox */
@interface NSObject (XEFComboBoxInformal)
- (NSInteger)numberOfItemsInComboBox:(id)c; - (id)comboBox:(id)c objectValueForItemAtIndex:(NSInteger)i;
- (NSInteger)numberOfItemsInComboBoxCell:(id)c; - (id)comboBoxCell:(id)c objectValueForItemAtIndex:(NSInteger)i;
- (void)comboBoxSelectionDidChange:(NSNotification *)n; - (void)comboBoxWillPopUp:(NSNotification *)n; - (void)comboBoxWillDismiss:(NSNotification *)n;
@end

@implementation NSComboBoxCell
- (id)initTextCell:(NSString *)s {
  if ((self = [super initTextCell:s])) { _items = [[NSMutableArray alloc] init]; _selected = -1; _visibleItems = 5; _scroller = YES; _buttonBordered = YES; _itemHeight = 21; _spacing = NSMakeSize(3, 2); }
  return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    _items = [[NSMutableArray alloc] initWithArray:[c decodeObjectForKey:@"NSPopUpListData"] ?: @[]]; _selected = -1; _scroller = YES; _buttonBordered = YES; _itemHeight = 21; _spacing = NSMakeSize(3, 2);
    _visibleItems = [c containsValueForKey:@"NSVisibleItemCount"] ? [c decodeIntegerForKey:@"NSVisibleItemCount"] : 5;
    _usesDataSource = [c decodeBoolForKey:@"NSUsesDataSource"]; _completes = [c decodeBoolForKey:@"NSCompletes"]; }
  return self; }
- (void)dealloc { [_items release]; [super dealloc]; }
- (NSInteger)numberOfItems {
  if (!_usesDataSource) return [_items count];
  if ([_dataSource respondsToSelector:@selector(numberOfItemsInComboBox:)]) return [_dataSource numberOfItemsInComboBox:_controlView];
  if ([_dataSource respondsToSelector:@selector(numberOfItemsInComboBoxCell:)]) return [_dataSource numberOfItemsInComboBoxCell:self];
  return 0; }
- (id)itemObjectValueAtIndex:(NSInteger)i {
  if (i < 0 || i >= [self numberOfItems]) return nil;
  if (!_usesDataSource) return _items[i];
  if ([_dataSource respondsToSelector:@selector(comboBox:objectValueForItemAtIndex:)]) return [_dataSource comboBox:_controlView objectValueForItemAtIndex:i];
  if ([_dataSource respondsToSelector:@selector(comboBoxCell:objectValueForItemAtIndex:)]) return [_dataSource comboBoxCell:self objectValueForItemAtIndex:i];
  return nil; }
- (NSArray *)objectValues { return [[_items copy] autorelease]; }
- (void)addItemWithObjectValue:(id)o { if (o) [_items addObject:o]; } - (void)addItemsWithObjectValues:(NSArray *)a { [_items addObjectsFromArray:a]; }
- (void)insertItemWithObjectValue:(id)o atIndex:(NSInteger)i { if (o) [_items insertObject:o atIndex:i]; }
- (void)removeItemWithObjectValue:(id)o { [_items removeObject:o]; _selected = -1; }
- (void)removeItemAtIndex:(NSInteger)i { if (i >= 0 && i < (NSInteger)[_items count]) [_items removeObjectAtIndex:i]; _selected = -1; }
- (void)removeAllItems { [_items removeAllObjects]; _selected = -1; }
- (NSInteger)indexOfItemWithObjectValue:(id)o { return [_items indexOfObject:o]; }
- (NSInteger)indexOfSelectedItem { return _selected; }
- (id)objectValueOfSelectedItem { return [self itemObjectValueAtIndex:_selected]; }
- (void)_notify:(NSString *)name selector:(SEL)sel {
  NSNotification *n = [NSNotification notificationWithName:name object:_controlView ?: (id)self];
  id d = [_controlView respondsToSelector:@selector(delegate)] ? [(id)_controlView delegate] : nil;
  if ([d respondsToSelector:sel]) [d performSelector:sel withObject:n];
  [[NSNotificationCenter defaultCenter] postNotification:n]; }
- (void)selectItemAtIndex:(NSInteger)i {
  if (i < 0 || i >= [self numberOfItems]) return;
  _selected = i;
  id v = [self itemObjectValueAtIndex:i]; if (v) [self setObjectValue:v];
  [_controlView setNeedsDisplay:YES];
  [self _notify:NSComboBoxSelectionDidChangeNotification selector:@selector(comboBoxSelectionDidChange:)]; }
- (void)selectItemWithObjectValue:(id)o { NSUInteger i = [_items indexOfObject:o]; if (i != NSNotFound) [self selectItemAtIndex:i]; }
- (void)deselectItemAtIndex:(NSInteger)i {
  if (i < 0 || i != _selected) return;
  _selected = -1; [self _notify:NSComboBoxSelectionDidChangeNotification selector:@selector(comboBoxSelectionDidChange:)]; }
- (void)scrollItemAtIndexToTop:(NSInteger)i {} - (void)scrollItemAtIndexToVisible:(NSInteger)i {} - (void)noteNumberOfItemsChanged {} - (void)reloadData {}
- (NSInteger)numberOfVisibleItems { return _visibleItems; } - (void)setNumberOfVisibleItems:(NSInteger)n { _visibleItems = n; }
- (BOOL)usesDataSource { return _usesDataSource; } - (void)setUsesDataSource:(BOOL)f { _usesDataSource = f; }
- (id)dataSource { return _dataSource; } - (void)setDataSource:(id)d { _dataSource = d; }
- (BOOL)hasVerticalScroller { return _scroller; } - (void)setHasVerticalScroller:(BOOL)f { _scroller = f; }
- (BOOL)completes { return _completes; } - (void)setCompletes:(BOOL)f { _completes = f; }
- (BOOL)isButtonBordered { return _buttonBordered; } - (void)setButtonBordered:(BOOL)f { _buttonBordered = f; }
- (CGFloat)itemHeight { return _itemHeight; } - (void)setItemHeight:(CGFloat)h { _itemHeight = h; }
- (NSSize)intercellSpacing { return _spacing; } - (void)setIntercellSpacing:(NSSize)s { _spacing = s; }
- (NSString *)completedString:(NSString *)s {
  for (NSInteger i = 0; i < [self numberOfItems]; i++) { NSString *v = [[self itemObjectValueAtIndex:i] description]; if ([v hasPrefix:s]) return v; }
  return nil; }
- (NSRect)_buttonRect:(NSRect)r { return NSMakeRect(NSMaxX(r) - 20, r.origin.y + 2, 18, r.size.height - 4); }
- (NSRect)drawingRectForBounds:(NSRect)r { NSRect t = [super drawingRectForBounds:r]; t.size.width -= 20; return t; }
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v {
  [super drawWithFrame:r inView:v];
  NSRect b = [self _buttonRect:r];
  fill_round(b, 4, _enabled ? [NSColor controlAccentColor] : gray(0.8), nil);
  [[NSColor whiteColor] setStroke]; NSBezierPath *p = [NSBezierPath bezierPath]; [p setLineWidth:1.5];
  [p moveToPoint:NSMakePoint(NSMidX(b) - 3.5, NSMidY(b) - 1.5)]; [p lineToPoint:NSMakePoint(NSMidX(b), NSMidY(b) + 2)]; [p lineToPoint:NSMakePoint(NSMidX(b) + 3.5, NSMidY(b) - 1.5)]; [p stroke]; }
/* the list is shown as a menu under the field */
- (void)_popUpInView:(NSView *)v frame:(NSRect)r {
  [self _notify:NSComboBoxWillPopUpNotification selector:@selector(comboBoxWillPopUp:)];
  NSMenu *m = [[[NSMenu alloc] initWithTitle:@""] autorelease];
  for (NSInteger i = 0; i < [self numberOfItems]; i++) {
    NSMenuItem *it = [m addItemWithTitle:[[self itemObjectValueAtIndex:i] description] ?: @"" action:NULL keyEquivalent:@""]; [it setTag:i]; if (i == _selected) [it setState:1]; }
  NSMenuItem *chosen = [m numberOfItems] ? [m _xefPopUpPositioningItem:nil atLocation:NSMakePoint(r.origin.x, NSMaxY(r)) inView:v minWidth:r.size.width] : nil;
  [self _notify:NSComboBoxWillDismissNotification selector:@selector(comboBoxWillDismiss:)];
  if (chosen) {
    if ([v respondsToSelector:@selector(_xefAbortEditing)]) [(id)v _xefAbortEditing];
    [self selectItemAtIndex:[chosen tag]];
    if ([v isKindOfClass:[NSControl class]]) [(NSControl *)v sendAction:[self action] to:[self target]]; } }
@end

@implementation NSComboBox
+ (Class)cellClass { return [NSComboBoxCell class]; }
#define CC ((NSComboBoxCell *)_cell)
- (NSInteger)numberOfItems { return [CC numberOfItems]; } - (id)itemObjectValueAtIndex:(NSInteger)i { return [CC itemObjectValueAtIndex:i]; }
- (NSArray *)objectValues { return [CC objectValues]; }
- (void)addItemWithObjectValue:(id)o { [CC addItemWithObjectValue:o]; } - (void)addItemsWithObjectValues:(NSArray *)a { [CC addItemsWithObjectValues:a]; }
- (void)insertItemWithObjectValue:(id)o atIndex:(NSInteger)i { [CC insertItemWithObjectValue:o atIndex:i]; }
- (void)removeItemWithObjectValue:(id)o { [CC removeItemWithObjectValue:o]; } - (void)removeItemAtIndex:(NSInteger)i { [CC removeItemAtIndex:i]; } - (void)removeAllItems { [CC removeAllItems]; }
- (NSInteger)indexOfItemWithObjectValue:(id)o { return [CC indexOfItemWithObjectValue:o]; }
- (NSInteger)indexOfSelectedItem { return [CC indexOfSelectedItem]; } - (id)objectValueOfSelectedItem { return [CC objectValueOfSelectedItem]; }
- (void)selectItemAtIndex:(NSInteger)i { [self _xefAbortEditing]; [CC selectItemAtIndex:i]; } - (void)selectItemWithObjectValue:(id)o { [self _xefAbortEditing]; [CC selectItemWithObjectValue:o]; }
- (void)deselectItemAtIndex:(NSInteger)i { [CC deselectItemAtIndex:i]; }
- (void)scrollItemAtIndexToTop:(NSInteger)i {} - (void)scrollItemAtIndexToVisible:(NSInteger)i {} - (void)noteNumberOfItemsChanged {} - (void)reloadData { [self setNeedsDisplay:YES]; }
- (NSInteger)numberOfVisibleItems { return [CC numberOfVisibleItems]; } - (void)setNumberOfVisibleItems:(NSInteger)n { [CC setNumberOfVisibleItems:n]; }
- (BOOL)usesDataSource { return [CC usesDataSource]; } - (void)setUsesDataSource:(BOOL)f { [CC setUsesDataSource:f]; }
- (id)dataSource { return [CC dataSource]; } - (void)setDataSource:(id)d { [CC setDataSource:d]; }
- (BOOL)hasVerticalScroller { return [CC hasVerticalScroller]; } - (void)setHasVerticalScroller:(BOOL)f { [CC setHasVerticalScroller:f]; }
- (BOOL)completes { return [CC completes]; } - (void)setCompletes:(BOOL)f { [CC setCompletes:f]; }
- (BOOL)isButtonBordered { return [CC isButtonBordered]; } - (void)setButtonBordered:(BOOL)f { [CC setButtonBordered:f]; }
- (CGFloat)itemHeight { return [CC itemHeight]; } - (void)setItemHeight:(CGFloat)h { [CC setItemHeight:h]; }
- (NSSize)intercellSpacing { return [CC intercellSpacing]; } - (void)setIntercellSpacing:(NSSize)s { [CC setIntercellSpacing:s]; }
- (void)mouseDown:(NSEvent *)e {
  if (![self isEnabled]) return;
  if (NSPointInRect(local_point(self, e), [CC _buttonRect:_bounds])) { [CC _popUpInView:self frame:_bounds]; [self setNeedsDisplay:YES]; return; }
  [super mouseDown:e]; }
#undef CC
@end

/* ================================================================== NSDatePicker */
@implementation NSDatePickerCell
- (id)initTextCell:(NSString *)s {
  if ((self = [super initTextCell:s])) { _date = [[NSDate date] retain]; _elements = 0x00e0 | 0x000c /* year-month-day, hour-minute */; _calendar = [[NSCalendar currentCalendar] retain]; _drawsBg = YES; }
  return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    _date = [[c decodeObjectForKey:@"NSContents"] retain]; if (![_date isKindOfClass:[NSDate class]]) { [_date release]; _date = [[NSDate date] retain]; }
    _elements = [c containsValueForKey:@"NSDatePickerElements"] ? [c decodeIntegerForKey:@"NSDatePickerElements"] : 0x00ec; _dpStyle = [c decodeIntegerForKey:@"NSDatePickerType"];
    _minDate = [[c decodeObjectForKey:@"NSMinDate"] retain]; _maxDate = [[c decodeObjectForKey:@"NSMaxDate"] retain]; _calendar = [[NSCalendar currentCalendar] retain]; _drawsBg = YES; }
  return self; }
- (void)dealloc { [_date release]; [_minDate release]; [_maxDate release]; [_calendar release]; [_locale release]; [_tz release]; [_bg release]; [_tc release]; [super dealloc]; }
- (NSDate *)dateValue { return _date; }
- (void)setDateValue:(NSDate *)d {
  if (!d) return;
  if (_minDate && [d compare:_minDate] < 0) d = _minDate;
  if (_maxDate && [d compare:_maxDate] > 0) d = _maxDate;
  [d retain]; [_date release]; _date = d; [self _changed]; }
- (id)objectValue { return _date; } - (void)setObjectValue:(id)v { if ([v isKindOfClass:[NSDate class]]) [self setDateValue:v]; }
- (NSDate *)minDate { return _minDate; } - (void)setMinDate:(NSDate *)d { [d retain]; [_minDate release]; _minDate = d; [self setDateValue:_date]; }
- (NSDate *)maxDate { return _maxDate; } - (void)setMaxDate:(NSDate *)d { [d retain]; [_maxDate release]; _maxDate = d; [self setDateValue:_date]; }
- (NSTimeInterval)timeInterval { return _interval; } - (void)setTimeInterval:(NSTimeInterval)t { _interval = t; }
- (NSInteger)datePickerStyle { return _dpStyle; } - (void)setDatePickerStyle:(NSInteger)s { _dpStyle = s; [self _changed]; }
- (NSInteger)datePickerMode { return _mode; } - (void)setDatePickerMode:(NSInteger)m { _mode = m; }
- (NSUInteger)datePickerElements { return _elements; } - (void)setDatePickerElements:(NSUInteger)e { _elements = e; [self _changed]; }
- (NSCalendar *)calendar { return _calendar; } - (void)setCalendar:(NSCalendar *)c { [c retain]; [_calendar release]; _calendar = c; }
- (NSLocale *)locale { return _locale; } - (void)setLocale:(NSLocale *)l { [l retain]; [_locale release]; _locale = l; }
- (NSTimeZone *)timeZone { return _tz; } - (void)setTimeZone:(NSTimeZone *)t { [t retain]; [_tz release]; _tz = t; [self _changed]; }
- (NSColor *)backgroundColor { return _bg; } - (void)setBackgroundColor:(NSColor *)c { [c retain]; [_bg release]; _bg = c; }
- (NSColor *)textColor { return _tc; } - (void)setTextColor:(NSColor *)c { [c retain]; [_tc release]; _tc = c; }
- (BOOL)drawsBackground { return _drawsBg; } - (void)setDrawsBackground:(BOOL)f { _drawsBg = f; }
- (id)delegate { return _dpDelegate; } - (void)setDelegate:(id)d { _dpDelegate = d; }
- (NSString *)stringValue {
  NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
  NSMutableString *fmt = [NSMutableString string];
  if (_elements & 0x00e0) [fmt appendString:(_elements & 0x00e0) == 0x00c0 ? @"yyyy-MM" : @"yyyy-MM-dd"];
  if (_elements & 0x000e) { if ([fmt length]) [fmt appendString:@" "]; [fmt appendString:(_elements & 0x000e) == 0x000e ? @"HH:mm:ss" : @"HH:mm"]; }
  [f setDateFormat:fmt]; if (_tz) [f setTimeZone:_tz];
  return [f stringFromDate:_date] ?: @""; }
- (NSSize)cellSize { NSSize s = [[self stringValue] sizeWithAttributes:attrs2(_font, nil, 0)]; return NSMakeSize(ceil(s.width) + (_dpStyle == 0 ? 26 : 10), 22); }
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v {
  NSRect field = r; if (_dpStyle == 0) field.size.width -= 16;
  if (_bezeled || _bordered || _dpStyle != 2) fill_round(field, 3, _drawsBg ? (_bg ?: [NSColor whiteColor]) : nil, gray(0.7));
  draw_centered([self stringValue], NSInsetRect(field, 5, 0), attrs2(_font, _enabled ? (_tc ?: [NSColor controlTextColor]) : [NSColor disabledControlTextColor], 0));
  if (_dpStyle == 0) {
    NSRect st = NSMakeRect(NSMaxX(r) - 14, r.origin.y + 1, 13, r.size.height - 2);
    fill_round(st, 4, [NSColor whiteColor], gray(0.7)); [gray(0.3) setStroke];
    NSBezierPath *p = [NSBezierPath bezierPath]; CGFloat cx = NSMidX(st), uy = st.origin.y + st.size.height * 0.3, dy = st.origin.y + st.size.height * 0.7;
    [p moveToPoint:NSMakePoint(cx - 2.5, uy + 1)]; [p lineToPoint:NSMakePoint(cx, uy - 1.5)]; [p lineToPoint:NSMakePoint(cx + 2.5, uy + 1)];
    [p moveToPoint:NSMakePoint(cx - 2.5, dy - 1)]; [p lineToPoint:NSMakePoint(cx, dy + 1.5)]; [p lineToPoint:NSMakePoint(cx + 2.5, dy - 1)]; [p stroke]; } }
- (BOOL)trackMouse:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v untilMouseUp:(BOOL)u {
  NSPoint p = local_point(v, e); BOOL stepper = _dpStyle == 0 && p.x > NSMaxX(r) - 16;
  for (;;) { NSEvent *n = XEFNextTrackingEvent(); if (n && [n type] == NSEventTypeLeftMouseUp) break; }
  if (!stepper) return NO;
  [self setDateValue:[_date dateByAddingTimeInterval:(p.y < NSMidY(r) ? 1 : -1) * ((_elements & 0x000e) && !(_elements & 0x00e0) ? 60 : 86400)]];
  [v setNeedsDisplay:YES]; return YES; }
@end

@implementation NSDatePicker
+ (Class)cellClass { return [NSDatePickerCell class]; }
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { [_cell setBezeled:YES]; } return self; }
#define DC ((NSDatePickerCell *)_cell)
- (NSDate *)dateValue { return [DC dateValue]; } - (void)setDateValue:(NSDate *)d { [DC setDateValue:d]; [self setNeedsDisplay:YES]; }
- (NSDate *)minDate { return [DC minDate]; } - (void)setMinDate:(NSDate *)d { [DC setMinDate:d]; } - (NSDate *)maxDate { return [DC maxDate]; } - (void)setMaxDate:(NSDate *)d { [DC setMaxDate:d]; }
- (NSTimeInterval)timeInterval { return [DC timeInterval]; } - (void)setTimeInterval:(NSTimeInterval)t { [DC setTimeInterval:t]; }
- (NSInteger)datePickerStyle { return [DC datePickerStyle]; } - (void)setDatePickerStyle:(NSInteger)s { [DC setDatePickerStyle:s]; [self setNeedsDisplay:YES]; }
- (NSInteger)datePickerMode { return [DC datePickerMode]; } - (void)setDatePickerMode:(NSInteger)m { [DC setDatePickerMode:m]; }
- (NSUInteger)datePickerElements { return [DC datePickerElements]; } - (void)setDatePickerElements:(NSUInteger)e { [DC setDatePickerElements:e]; [self setNeedsDisplay:YES]; }
- (NSCalendar *)calendar { return [DC calendar]; } - (void)setCalendar:(NSCalendar *)c { [DC setCalendar:c]; }
- (NSLocale *)locale { return [DC locale]; } - (void)setLocale:(NSLocale *)l { [DC setLocale:l]; }
- (NSTimeZone *)timeZone { return [DC timeZone]; } - (void)setTimeZone:(NSTimeZone *)t { [DC setTimeZone:t]; [self setNeedsDisplay:YES]; }
- (NSColor *)backgroundColor { return [DC backgroundColor]; } - (void)setBackgroundColor:(NSColor *)c { [DC setBackgroundColor:c]; }
- (NSColor *)textColor { return [DC textColor]; } - (void)setTextColor:(NSColor *)c { [DC setTextColor:c]; }
- (BOOL)drawsBackground { return [DC drawsBackground]; } - (void)setDrawsBackground:(BOOL)f { [DC setDrawsBackground:f]; }
- (BOOL)isBezeled { return [DC isBezeled]; } - (void)setBezeled:(BOOL)f { [DC setBezeled:f]; } - (BOOL)isBordered { return [DC isBordered]; } - (void)setBordered:(BOOL)f { [DC setBordered:f]; }
- (id)delegate { return [DC delegate]; } - (void)setDelegate:(id)d { [DC setDelegate:d]; }
- (BOOL)presentsCalendarOverlay { return NO; } - (void)setPresentsCalendarOverlay:(BOOL)f {}
#undef DC
@end

/* ================================================================== NSTabView */
@interface NSObject (XEFTabViewInformal)
- (BOOL)tabView:(id)t shouldSelectTabViewItem:(id)i; - (void)tabView:(id)t willSelectTabViewItem:(id)i; - (void)tabView:(id)t didSelectTabViewItem:(id)i;
- (void)tabViewDidChangeNumberOfTabViewItems:(id)t;
@end

@implementation NSTabViewItem
+ (NSTabViewItem *)tabViewItemWithViewController:(id)vc { NSTabViewItem *i = [[[self alloc] initWithIdentifier:nil] autorelease]; [i setViewController:vc]; return i; }
- (id)init { return [self initWithIdentifier:nil]; }
- (id)initWithIdentifier:(id)i { if ((self = [super init])) { _identifier = [i retain]; _label = @""; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [self initWithIdentifier:[c decodeObjectForKey:@"NSIdentifier"]])) {
    _label = [[c decodeObjectForKey:@"NSLabel"] copy] ?: @""; _view = [[c decodeObjectForKey:@"NSView"] retain]; _color = [[c decodeObjectForKey:@"NSColor"] retain];
    _tabView = [c decodeObjectForKey:@"NSTabView"]; }
  return self; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc { [_identifier release]; [_label release]; [_toolTip release]; [_view release]; [_color release]; [_image release]; [_viewController release]; [super dealloc]; }
- (id)identifier { return _identifier; } - (void)setIdentifier:(id)i { [i retain]; [_identifier release]; _identifier = i; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [_label release]; _label = [l copy] ?: @""; [_tabView setNeedsDisplay:YES]; }
- (NSString *)toolTip { return _toolTip; } - (void)setToolTip:(NSString *)t { [_toolTip release]; _toolTip = [t copy]; }
- (NSColor *)color { return _color ?: [NSColor controlColor]; } - (void)setColor:(NSColor *)c { [c retain]; [_color release]; _color = c; }
- (NSImage *)image { return _image; } - (void)setImage:(NSImage *)i { [i retain]; [_image release]; _image = i; }
- (NSView *)view {
  if (!_view) {
    if (_viewController && [_viewController respondsToSelector:@selector(view)]) _view = [[_viewController view] retain];
    if (!_view) _view = [[NSView alloc] initWithFrame:_tabView ? [_tabView contentRect] : NSZeroRect]; }
  return _view; }
- (void)setView:(NSView *)v {
  if (v == _view) return;
  BOOL shown = _tabView && _tabView->_selectedItem == self;
  if (shown) [_view removeFromSuperview];
  [v retain]; [_view release]; _view = v;
  if (shown && v) { [v setFrame:[_tabView contentRect]]; [v setAutoresizingMask:2 | 16]; [_tabView addSubview:v]; [_tabView setNeedsDisplay:YES]; } }
- (id)viewController { return _viewController; } - (void)setViewController:(id)vc { [vc retain]; [_viewController release]; _viewController = vc; if ([vc respondsToSelector:@selector(title)] && [vc title] && ![_label length]) [self setLabel:[vc title]]; }
- (NSTabView *)tabView { return _tabView; }
- (NSInteger)tabState { return _tabView && _tabView->_selectedItem == self ? 0 : 1; }
- (NSView *)initialFirstResponder { return _initialFirst; } - (void)setInitialFirstResponder:(NSView *)v { _initialFirst = v; }
- (NSSize)sizeOfLabel:(BOOL)truncate { NSSize s = [_label sizeWithAttributes:attrs2([NSFont systemFontOfSize:13], nil, 1)]; return NSMakeSize(ceil(s.width), ceil(s.height)); }
- (void)drawLabel:(BOOL)truncate inRect:(NSRect)r { draw_centered(_label, r, attrs2([NSFont systemFontOfSize:13], nil, 1)); }
@end

@implementation NSTabView
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { _items = [[NSMutableArray alloc] init]; _drawsBg = YES; _truncated = YES; _font = [[NSFont systemFontOfSize:13] retain]; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    _items = [[NSMutableArray alloc] init]; _drawsBg = YES; _truncated = YES; _font = [[NSFont systemFontOfSize:13] retain];
    uint32_t fl = (uint32_t)[c decodeIntForKey:@"NSTvFlags"]; _type = fl & 7;
    for (NSTabViewItem *i in [c decodeObjectForKey:@"NSTabViewItems"]) if ([i isKindOfClass:[NSTabViewItem class]]) { [_items addObject:i]; i->_tabView = self; }
    NSTabViewItem *sel = [c decodeObjectForKey:@"NSSelectedTabViewItem"];
    for (NSView *s in [[_subviews copy] autorelease]) [s removeFromSuperview];      /* the archive holds the selected item's view as a subview */
    if (![_items containsObject:sel]) sel = [_items count] ? _items[0] : nil;
    if (sel) [self _xefShow:sel]; }
  return self; }
- (void)dealloc { for (NSTabViewItem *i in _items) i->_tabView = nil; [_items release]; [_font release]; [super dealloc]; }
- (BOOL)_hasTabs { return _type == 0 || _type == 1 || _type == 2 || _type == 5; }
- (NSRect)contentRect {
  if (_type == 4 /* no tabs, no border */) return _bounds;
  if (![self _hasTabs]) return NSInsetRect(_bounds, 1, 1);
  return NSMakeRect(_bounds.origin.x + 1, _bounds.origin.y + 1, fmax(0, _bounds.size.width - 2), fmax(0, _bounds.size.height - 30)); }
- (NSSize)minimumSize { return NSMakeSize(60, 40); }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSInteger)tabViewType { return _type; } - (void)setTabViewType:(NSInteger)t { _type = t; [self _xefLayoutSelected]; [self setNeedsDisplay:YES]; }
- (NSInteger)tabPosition { return _position; } - (void)setTabPosition:(NSInteger)p { _position = p; }
- (NSInteger)tabViewBorderType { return _border; } - (void)setTabViewBorderType:(NSInteger)b { _border = b; }
- (NSUInteger)controlSize { return _controlSize; } - (void)setControlSize:(NSUInteger)s { _controlSize = s; }
- (NSInteger)controlTint { return 0; } - (void)setControlTint:(NSInteger)t {}
- (BOOL)allowsTruncatedLabels { return _truncated; } - (void)setAllowsTruncatedLabels:(BOOL)f { _truncated = f; }
- (BOOL)drawsBackground { return _drawsBg; } - (void)setDrawsBackground:(BOOL)f { _drawsBg = f; [self setNeedsDisplay:YES]; }
- (NSFont *)font { return _font; } - (void)setFont:(NSFont *)f { [f retain]; [_font release]; _font = f; [self setNeedsDisplay:YES]; }
- (NSArray *)tabViewItems { return [[_items copy] autorelease]; }
- (void)setTabViewItems:(NSArray *)a { for (NSTabViewItem *i in [self tabViewItems]) [self removeTabViewItem:i]; for (NSTabViewItem *i in a) [self addTabViewItem:i]; }
- (NSInteger)numberOfTabViewItems { return [_items count]; }
- (NSTabViewItem *)tabViewItemAtIndex:(NSInteger)i { return i >= 0 && i < (NSInteger)[_items count] ? _items[i] : nil; }
- (NSInteger)indexOfTabViewItem:(NSTabViewItem *)i { return [_items indexOfObject:i]; }
- (NSInteger)indexOfTabViewItemWithIdentifier:(id)ident {
  for (NSUInteger i = 0; i < [_items count]; i++) { id x = ((NSTabViewItem *)_items[i])->_identifier; if (x == ident || [x isEqual:ident]) return i; }
  return NSNotFound; }
- (NSTabViewItem *)selectedTabViewItem { return _selectedItem; }
- (void)_xefLayoutSelected { NSView *v = _selectedItem ? [_selectedItem view] : nil; if (v && [v superview] == self) [v setFrame:[self contentRect]]; }
- (void)_xefShow:(NSTabViewItem *)i {
  if (_selectedItem) [_selectedItem->_view removeFromSuperview];
  _selectedItem = i;
  NSView *v = [i view];
  if (v) { [v setFrame:[self contentRect]]; [v setAutoresizingMask:2 | 16]; [self addSubview:v]; }
  [self setNeedsDisplay:YES]; }
- (void)selectTabViewItem:(NSTabViewItem *)i {
  if (!i || i == _selectedItem || ![_items containsObject:i]) return;
  if ([_delegate respondsToSelector:@selector(tabView:shouldSelectTabViewItem:)] && ![_delegate tabView:self shouldSelectTabViewItem:i]) return;
  if ([_delegate respondsToSelector:@selector(tabView:willSelectTabViewItem:)]) [_delegate tabView:self willSelectTabViewItem:i];
  [self _xefShow:i];
  if (_window && i->_initialFirst) [_window makeFirstResponder:i->_initialFirst];
  if ([_delegate respondsToSelector:@selector(tabView:didSelectTabViewItem:)]) [_delegate tabView:self didSelectTabViewItem:i]; }
- (void)selectTabViewItemAtIndex:(NSInteger)i { [self selectTabViewItem:[self tabViewItemAtIndex:i]]; }
- (void)selectTabViewItemWithIdentifier:(id)ident { NSInteger i = [self indexOfTabViewItemWithIdentifier:ident]; if (i != NSNotFound) [self selectTabViewItemAtIndex:i]; }
- (void)takeSelectedTabViewItemFromSender:(id)s {
  NSInteger i = [s respondsToSelector:@selector(indexOfSelectedItem)] ? [s indexOfSelectedItem] : [s respondsToSelector:@selector(selectedSegment)] ? [s selectedSegment] : -1;
  [self selectTabViewItemAtIndex:i]; }
- (void)selectFirstTabViewItem:(id)s { [self selectTabViewItemAtIndex:0]; }
- (void)selectLastTabViewItem:(id)s { [self selectTabViewItemAtIndex:[_items count] - 1]; }
/* AppKit asks the delegate once before, and again while, selecting the neighbour */
- (void)_xefStep:(NSInteger)d {
  if (![_items count]) return;
  NSInteger cur = _selectedItem ? [_items indexOfObject:_selectedItem] : 0, n = cur + d;
  if (n < 0) n = 0; if (n >= (NSInteger)[_items count]) n = [_items count] - 1;
  NSTabViewItem *t = _items[n];
  if ([_delegate respondsToSelector:@selector(tabView:shouldSelectTabViewItem:)]) [_delegate tabView:self shouldSelectTabViewItem:t];
  [self selectTabViewItem:t]; }
- (void)selectNextTabViewItem:(id)s { [self _xefStep:1]; }
- (void)selectPreviousTabViewItem:(id)s { [self _xefStep:-1]; }
- (void)_xefCountChanged { if ([_delegate respondsToSelector:@selector(tabViewDidChangeNumberOfTabViewItems:)]) [_delegate tabViewDidChangeNumberOfTabViewItems:self]; [self setNeedsDisplay:YES]; }
- (void)addTabViewItem:(NSTabViewItem *)i { [self insertTabViewItem:i atIndex:[_items count]]; }
- (void)insertTabViewItem:(NSTabViewItem *)i atIndex:(NSInteger)idx {
  if (!i || [_items containsObject:i]) return;
  [_items insertObject:i atIndex:idx < 0 ? 0 : idx > (NSInteger)[_items count] ? [_items count] : idx];
  i->_tabView = self;
  if (!_selectedItem) [self selectTabViewItem:i];
  [self _xefCountChanged]; }
- (void)removeTabViewItem:(NSTabViewItem *)i {
  NSUInteger idx = [_items indexOfObject:i]; if (idx == NSNotFound) return;
  [[i retain] autorelease];
  if (i == _selectedItem) {
    NSTabViewItem *next = idx + 1 < [_items count] ? _items[idx + 1] : idx > 0 ? _items[idx - 1] : nil;
    if (next) [self selectTabViewItem:next];
    if (_selectedItem == i) { [i->_view removeFromSuperview]; _selectedItem = nil; } }
  [_items removeObjectAtIndex:idx]; i->_tabView = nil;
  [self _xefCountChanged]; }
- (NSTabViewItem *)tabViewItemAtPoint:(NSPoint)p { for (NSTabViewItem *i in _items) if (NSPointInRect(p, i->_tabRect)) return i; return nil; }
- (void)setFrame:(NSRect)f { [super setFrame:f]; [self _xefLayoutSelected]; }
- (void)_xefTabRects {
  CGFloat total = 0; NSUInteger n = [_items count]; CGFloat w[n ? n : 1];
  for (NSUInteger k = 0; k < n; k++) { w[k] = [_items[k] sizeOfLabel:NO].width + 24; total += w[k]; }
  CGFloat x = fmax(_bounds.origin.x + 4, NSMidX(_bounds) - total / 2), top = NSMaxY(_bounds) - 26;
  for (NSUInteger k = 0; k < n; k++) { ((NSTabViewItem *)_items[k])->_tabRect = NSMakeRect(x, top, w[k], 22); x += w[k]; } }
- (void)drawRect:(NSRect)r {
  NSRect content = [self contentRect];
  if (_type == 4) return;
  if (_drawsBg && (_type == 0 || _type == 3 || _type == 1 || _type == 2)) fill_round(NSInsetRect(content, -1, -1), 5, gray(0.93), gray(0.78));
  else if (_type == 5 || _type == 6) { [gray(0.78) setFill]; NSRectFill(NSMakeRect(_bounds.origin.x, NSMaxY(content), _bounds.size.width, 1)); }
  if (![self _hasTabs] || ![_items count]) return;
  [self _xefTabRects];
  NSTabViewItem *first = _items[0], *last = [_items lastObject];
  fill_round(NSMakeRect(first->_tabRect.origin.x, first->_tabRect.origin.y, NSMaxX(last->_tabRect) - first->_tabRect.origin.x, 22), 5, gray(0.88), gray(0.75));
  for (NSTabViewItem *i in _items) {
    if (i == _selectedItem) fill_round(NSInsetRect(i->_tabRect, 1.5, 1.5), 4, [NSColor whiteColor], gray(0.7));
    draw_centered(i->_label, i->_tabRect, attrs2(_font, [NSColor controlTextColor], 1)); } }
- (void)mouseDown:(NSEvent *)e {
  [self _xefTabRects];
  NSTabViewItem *i = [self tabViewItemAtPoint:local_point(self, e)];
  if (i) { [self selectTabViewItem:i]; XEFRedrawWindowNow(_window); } else [super mouseDown:e]; }
@end

/* ================================================================== NSSplitView */
@interface NSObject (XEFSplitViewInformal)
- (CGFloat)splitView:(id)s constrainMinCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i; - (CGFloat)splitView:(id)s constrainMaxCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i;
- (CGFloat)splitView:(id)s constrainSplitPosition:(CGFloat)p ofSubviewAt:(NSInteger)i; - (void)splitView:(id)s resizeSubviewsWithOldSize:(NSSize)o;
- (void)splitViewWillResizeSubviews:(NSNotification *)n; - (void)splitViewDidResizeSubviews:(NSNotification *)n;
- (BOOL)splitView:(id)s canCollapseSubview:(id)v; - (BOOL)splitView:(id)s shouldAdjustSizeOfSubview:(id)v;
@end

@implementation NSSplitView
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { _dividerStyle = 1; _arrangesAll = YES; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    _vertical = [c decodeBoolForKey:@"NSIsVertical"]; _dividerStyle = [c containsValueForKey:@"NSDividerStyle"] ? [c decodeIntegerForKey:@"NSDividerStyle"] : 1;
    _autosave = [[c decodeObjectForKey:@"NSAutosaveName"] copy]; _arrangesAll = YES; }
  return self; }
- (void)dealloc { [_dividerColor release]; [_autosave release]; [_arranged release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (BOOL)isVertical { return _vertical; } - (void)setVertical:(BOOL)f { _vertical = f; [self setNeedsDisplay:YES]; }
- (NSInteger)dividerStyle { return _dividerStyle; } - (void)setDividerStyle:(NSInteger)s { _dividerStyle = s; [self setNeedsDisplay:YES]; }
- (CGFloat)dividerThickness { return _dividerStyle == 1 ? 9 : 1; }
- (NSColor *)dividerColor { return _dividerColor ?: [NSColor separatorColor]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSString *)autosaveName { return _autosave; } - (void)setAutosaveName:(NSString *)n { [_autosave release]; _autosave = [n copy]; }
- (BOOL)arrangesAllSubviews { return _arrangesAll; }
- (void)setArrangesAllSubviews:(BOOL)f { _arrangesAll = f; if (!f && !_arranged) _arranged = [[NSMutableArray alloc] initWithArray:_subviews]; }
- (NSArray *)arrangedSubviews { return _arrangesAll ? [[_subviews copy] autorelease] : [[_arranged copy] autorelease]; }
- (void)addArrangedSubview:(NSView *)v { [self insertArrangedSubview:v atIndex:[[self arrangedSubviews] count]]; }
- (void)insertArrangedSubview:(NSView *)v atIndex:(NSInteger)i {
  if ([v superview] != self) [self addSubview:v];
  if (_arrangesAll) { [v retain]; [_subviews removeObject:v]; [_subviews insertObject:v atIndex:i > (NSInteger)[_subviews count] ? [_subviews count] : i]; [v release]; }
  else { [_arranged removeObject:v]; [_arranged insertObject:v atIndex:i > (NSInteger)[_arranged count] ? [_arranged count] : i]; }
  [self adjustSubviews]; }
- (void)removeArrangedSubview:(NSView *)v { if (_arrangesAll) [v removeFromSuperview]; else [_arranged removeObject:v]; [self adjustSubviews]; }
- (NSArray *)_panes { NSMutableArray *a = [NSMutableArray array]; for (NSView *v in [self arrangedSubviews]) if (![v isHidden]) [a addObject:v]; return a; }
- (CGFloat)_len:(NSRect)r { return _vertical ? r.size.width : r.size.height; }
- (CGFloat)_pos:(NSRect)r { return _vertical ? r.origin.x : r.origin.y; }
- (NSRect)_pane:(CGFloat)pos length:(CGFloat)len { return _vertical ? NSMakeRect(pos, 0, len, _bounds.size.height) : NSMakeRect(0, pos, _bounds.size.width, len); }
- (BOOL)isSubviewCollapsed:(NSView *)v { return [v isHidden] || ([v superview] == self && [self _len:[v frame]] <= 0 && [[self _panes] count] > 1 && NO); }
- (CGFloat)holdingPriorityForSubviewAtIndex:(NSInteger)i { return 250; } - (void)setHoldingPriority:(float)p forSubviewAtIndex:(NSInteger)i {}
- (void)_notify:(NSString *)name selector:(SEL)sel {
  NSNotification *n = [NSNotification notificationWithName:name object:self];
  if ([_delegate respondsToSelector:sel]) [_delegate performSelector:sel withObject:n];
  [[NSNotificationCenter defaultCenter] postNotification:n]; }
/* the panes keep their proportions; positions are rounded to whole points, the last pane takes the rest */
- (void)adjustSubviews {
  if (_inAdjust) return;
  NSArray *panes = [self _panes]; NSUInteger n = [panes count]; if (!n) return;
  _inAdjust = YES;
  [self _notify:NSSplitViewWillResizeSubviewsNotification selector:@selector(splitViewWillResizeSubviews:)];
  CGFloat th = [self dividerThickness], total = [self _len:_bounds], avail = fmax(0, total - th * (n - 1)), sum = 0;
  for (NSView *v in panes) sum += fmax(0, [self _len:[v frame]]);
  CGFloat cum = 0, start = 0;
  for (NSUInteger i = 0; i < n; i++) {
    NSView *v = panes[i];
    cum += sum > 0 ? fmax(0, [self _len:[v frame]]) : 1;
    CGFloat end = i == n - 1 ? avail : round(cum / (sum > 0 ? sum : n) * avail);
    CGFloat len = fmax(0, end - (start - th * i));
    [v setFrame:[self _pane:start length:len]];
    start += len + th; }
  [self _notify:NSSplitViewDidResizeSubviewsNotification selector:@selector(splitViewDidResizeSubviews:)];
  _inAdjust = NO; [self setNeedsDisplay:YES]; }
- (CGFloat)minPossiblePositionOfDividerAtIndex:(NSInteger)i {
  NSArray *panes = [self _panes]; if (i < 0 || i + 1 >= (NSInteger)[panes count]) return 0;
  CGFloat p = [self _pos:[panes[i] frame]];
  if ([_delegate respondsToSelector:@selector(splitView:constrainMinCoordinate:ofSubviewAt:)]) p = [_delegate splitView:self constrainMinCoordinate:p ofSubviewAt:i];
  return p; }
- (CGFloat)maxPossiblePositionOfDividerAtIndex:(NSInteger)i {
  NSArray *panes = [self _panes]; if (i < 0 || i + 1 >= (NSInteger)[panes count]) return 0;
  NSRect nf = [panes[i + 1] frame]; CGFloat p = [self _pos:nf] + [self _len:nf] - [self dividerThickness];
  if ([_delegate respondsToSelector:@selector(splitView:constrainMaxCoordinate:ofSubviewAt:)]) p = [_delegate splitView:self constrainMaxCoordinate:p ofSubviewAt:i];
  return p; }
- (void)setPosition:(CGFloat)p ofDividerAtIndex:(NSInteger)i {
  NSArray *panes = [self _panes]; if (i < 0 || i + 1 >= (NSInteger)[panes count]) return;
  if ([_delegate respondsToSelector:@selector(splitView:constrainSplitPosition:ofSubviewAt:)]) p = [_delegate splitView:self constrainSplitPosition:p ofSubviewAt:i];
  p = clampd(p, [self minPossiblePositionOfDividerAtIndex:i], [self maxPossiblePositionOfDividerAtIndex:i]);
  NSView *a = panes[i], *b = panes[i + 1]; CGFloat th = [self dividerThickness];
  CGFloat a0 = [self _pos:[a frame]], bEnd = [self _pos:[b frame]] + [self _len:[b frame]];
  [self _notify:NSSplitViewWillResizeSubviewsNotification selector:@selector(splitViewWillResizeSubviews:)];
  [a setFrame:[self _pane:a0 length:p - a0]]; [b setFrame:[self _pane:p + th length:fmax(0, bEnd - p - th)]];
  [self _notify:NSSplitViewDidResizeSubviewsNotification selector:@selector(splitViewDidResizeSubviews:)];
  [self setNeedsDisplay:YES]; }
- (void)setFrame:(NSRect)f {
  NSSize old = _frame.size; BOOL saved = _autoresizesSubviews;
  _autoresizesSubviews = NO; [super setFrame:f]; _autoresizesSubviews = saved;
  if (old.width == f.size.width && old.height == f.size.height) return;
  if ([_delegate respondsToSelector:@selector(splitView:resizeSubviewsWithOldSize:)]) [_delegate splitView:self resizeSubviewsWithOldSize:old]; else [self adjustSubviews]; }
- (void)addSubview:(NSView *)v { [super addSubview:v]; if (!_arrangesAll && ![_arranged containsObject:v]) [_arranged addObject:v]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; if (_window) [self adjustSubviews]; }
- (NSRect)_dividerRect:(NSInteger)i panes:(NSArray *)panes {
  NSRect f = [panes[i] frame]; CGFloat p = [self _pos:f] + [self _len:f];
  return [self _pane:p length:[self dividerThickness]]; }
- (void)drawDividerInRect:(NSRect)r {
  if (_dividerStyle != 1) { [[self dividerColor] setFill]; NSRectFill(r); return; }
  [[NSColor colorWithCalibratedWhite:0.6 alpha:1] setFill];
  [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(r) - 2.5, NSMidY(r) - 2.5, 5, 5)] fill]; }
- (void)drawRect:(NSRect)r { NSArray *panes = [self _panes]; for (NSInteger i = 0; i + 1 < (NSInteger)[panes count]; i++) [self drawDividerInRect:[self _dividerRect:i panes:panes]]; }
- (void)mouseDown:(NSEvent *)e {
  NSArray *panes = [self _panes]; NSPoint p = local_point(self, e); NSInteger hit = -1;
  for (NSInteger i = 0; i + 1 < (NSInteger)[panes count]; i++) if (NSPointInRect(p, NSInsetRect([self _dividerRect:i panes:panes], _vertical ? -3 : 0, _vertical ? 0 : -3))) hit = i;
  if (hit < 0) { [super mouseDown:e]; return; }
  CGFloat off = (_vertical ? p.x : p.y) - [self _pos:[self _dividerRect:hit panes:panes]];
  for (;;) {
    NSEvent *n = XEFNextTrackingEvent(); if (!n) continue;
    if ([n type] == NSEventTypeLeftMouseUp) break;
    NSPoint q = local_point(self, n);
    [self setPosition:(_vertical ? q.x : q.y) - off ofDividerAtIndex:hit]; XEFRedrawWindowNow(_window); } }
@end

/* ================================================================== NSStackView */
@implementation NSStackView
+ (NSStackView *)stackViewWithViews:(NSArray *)views { NSStackView *s = [[[self alloc] initWithFrame:NSZeroRect] autorelease]; for (NSView *v in views) [s addArrangedSubview:v]; return s; }
- (id)initWithFrame:(NSRect)f {
  if ((self = [super initWithFrame:f])) { _arranged = [[NSMutableArray alloc] init]; _gravity = [[NSMutableDictionary alloc] init]; _spacing = 8; _alignment = 10 /* centerY */; _detachesHidden = YES;
    _customSpacing = [[NSMapTable weakToStrongObjectsMapTable] retain]; _visPriority = [[NSMapTable weakToStrongObjectsMapTable] retain]; }
  return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    _arranged = [[NSMutableArray alloc] init]; _gravity = [[NSMutableDictionary alloc] init]; _detachesHidden = YES;
    _customSpacing = [[NSMapTable weakToStrongObjectsMapTable] retain]; _visPriority = [[NSMapTable weakToStrongObjectsMapTable] retain];
    _orientation = [c decodeIntegerForKey:@"NSStackViewOrientation"]; _spacing = [c containsValueForKey:@"NSStackViewSpacing"] ? [c decodeDoubleForKey:@"NSStackViewSpacing"] : 8;
    _alignment = [c containsValueForKey:@"NSStackViewAlignment"] ? [c decodeIntegerForKey:@"NSStackViewAlignment"] : (_orientation ? 9 : 10);
    _distribution = [c decodeIntegerForKey:@"NSStackViewdistribution"];
    for (NSView *v in _subviews) [_arranged addObject:v]; }
  return self; }
- (void)dealloc { [_arranged release]; [_gravity release]; [_customSpacing release]; [_visPriority release]; [super dealloc]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSInteger)orientation { return _orientation; }
- (void)setOrientation:(NSInteger)o { if (o != _orientation) { _orientation = o; _alignment = o ? 9 /* centerX */ : 10; } [self _xefLayout]; }
- (NSInteger)alignment { return _alignment; } - (void)setAlignment:(NSInteger)a { _alignment = a; [self _xefLayout]; }
- (NSInteger)distribution { return _distribution; } - (void)setDistribution:(NSInteger)d { _distribution = d; [self _xefLayout]; }
- (CGFloat)spacing { return _spacing; } - (void)setSpacing:(CGFloat)s { _spacing = s; [self _xefLayout]; }
- (NSEdgeInsets)edgeInsets { return _insets; } - (void)setEdgeInsets:(NSEdgeInsets)i { _insets = i; [self _xefLayout]; }
- (BOOL)detachesHiddenViews { return _detachesHidden; } - (void)setDetachesHiddenViews:(BOOL)f { _detachesHidden = f; [self _xefLayout]; }
- (BOOL)hasEqualSpacing { return _distribution == 3; } - (void)setHasEqualSpacing:(BOOL)f { _distribution = f ? 3 : -1; }
- (NSArray *)arrangedSubviews { return [[_arranged copy] autorelease]; }
- (NSArray *)views { return [[_arranged copy] autorelease]; }
- (NSArray *)detachedViews { return @[]; }
- (void)addArrangedSubview:(NSView *)v { [self insertArrangedSubview:v atIndex:[_arranged count]]; }
- (void)insertArrangedSubview:(NSView *)v atIndex:(NSInteger)i {
  if (!v) return;
  [v retain]; [_arranged removeObject:v]; [_arranged insertObject:v atIndex:i < 0 ? 0 : i > (NSInteger)[_arranged count] ? [_arranged count] : i]; [v release];
  if ([v superview] != self) [self addSubview:v];
  [self _xefLayout]; }
- (void)removeArrangedSubview:(NSView *)v { [_arranged removeObject:v]; for (NSMutableArray *g in [_gravity allValues]) [g removeObject:v]; [self _xefLayout]; }
- (NSMutableArray *)_gravityList:(NSInteger)g { NSMutableArray *a = _gravity[@(g)]; if (!a) { a = [NSMutableArray array]; _gravity[@(g)] = a; } return a; }
- (void)_xefRebuildFromGravity {
  NSMutableArray *all = [NSMutableArray array];
  for (NSInteger g = 1; g <= 3; g++) [all addObjectsFromArray:_gravity[@(g)] ?: @[]];
  for (NSView *v in [[_arranged copy] autorelease]) if (![all containsObject:v]) [v removeFromSuperview];
  [_arranged setArray:all];
  for (NSView *v in all) if ([v superview] != self) [self addSubview:v];
  [self _xefLayout]; }
- (void)addView:(NSView *)v inGravity:(NSInteger)g { [[self _gravityList:g] addObject:v]; [self _xefRebuildFromGravity]; }
- (void)insertView:(NSView *)v atIndex:(NSUInteger)i inGravity:(NSInteger)g { NSMutableArray *a = [self _gravityList:g]; [a insertObject:v atIndex:i > [a count] ? [a count] : i]; [self _xefRebuildFromGravity]; }
- (void)removeView:(NSView *)v { [[v retain] autorelease]; [_arranged removeObject:v]; for (NSMutableArray *g in [_gravity allValues]) [g removeObject:v]; [v removeFromSuperview]; [self _xefLayout]; }
- (NSArray *)viewsInGravity:(NSInteger)g { return [[_gravity[@(g)] copy] autorelease] ?: @[]; }
- (void)setViews:(NSArray *)views inGravity:(NSInteger)g { _gravity[@(g)] = [NSMutableArray arrayWithArray:views]; [self _xefRebuildFromGravity]; }
- (CGFloat)customSpacingAfterView:(NSView *)v { NSNumber *n = [_customSpacing objectForKey:v]; return n ? [n doubleValue] : NSStackViewSpacingUseDefault; }
- (void)setCustomSpacing:(CGFloat)s afterView:(NSView *)v { if (s == NSStackViewSpacingUseDefault) [_customSpacing removeObjectForKey:v]; else [_customSpacing setObject:@(s) forKey:v]; [self _xefLayout]; }
- (float)visibilityPriorityForView:(NSView *)v { NSNumber *n = [_visPriority objectForKey:v]; return n ? [n floatValue] : 1000; }
- (void)setVisibilityPriority:(float)p forView:(NSView *)v { [_visPriority setObject:@(p) forKey:v]; }
- (float)clippingResistancePriorityForOrientation:(NSInteger)o { return 1000; } - (void)setClippingResistancePriority:(float)p forOrientation:(NSInteger)o {}
- (float)huggingPriorityForOrientation:(NSInteger)o { return 250; } - (void)setHuggingPriority:(float)p forOrientation:(NSInteger)o {}
- (NSSize)_sizeOf:(NSView *)v {
  NSSize s = [v frame].size;
  if ((s.width <= 0 || s.height <= 0) && [v respondsToSelector:@selector(intrinsicContentSize)]) {
    NSSize i = [v intrinsicContentSize]; if (s.width <= 0 && i.width > 0) s.width = i.width; if (s.height <= 0 && i.height > 0) s.height = i.height; }
  return s; }
- (NSArray *)_visible { NSMutableArray *a = [NSMutableArray array]; for (NSView *v in _arranged) if (!(_detachesHidden && [v isHidden])) [a addObject:v]; return a; }
- (NSSize)fittingSize {
  CGFloat along = 0, across = 0; NSArray *vis = [self _visible];
  for (NSUInteger i = 0; i < [vis count]; i++) {
    NSSize s = [self _sizeOf:vis[i]]; along += _orientation ? s.height : s.width; across = fmax(across, _orientation ? s.width : s.height);
    if (i + 1 < [vis count]) { CGFloat c = [self customSpacingAfterView:vis[i]]; along += c == NSStackViewSpacingUseDefault ? _spacing : c; } }
  return _orientation ? NSMakeSize(across + _insets.left + _insets.right, along + _insets.top + _insets.bottom) : NSMakeSize(along + _insets.left + _insets.right, across + _insets.top + _insets.bottom); }
- (NSSize)intrinsicContentSize { return [self fittingSize]; }
/* without a constraint solver: the views keep their sizes and are placed one after another from the leading edge
 * (the top for a vertical stack); the fill distributions give the last view the remaining length */
- (void)_xefLayout {
  NSArray *vis = [self _visible]; NSUInteger n = [vis count]; if (!n) return;
  if (_bounds.size.width <= 0 && _bounds.size.height <= 0) { NSSize fit = [self fittingSize]; _frame.size = fit; _bounds.size = fit; }
  BOOL vert = _orientation == 1;
  CGFloat total = vert ? _bounds.size.height - _insets.top - _insets.bottom : _bounds.size.width - _insets.left - _insets.right, used = 0;
  for (NSUInteger i = 0; i < n; i++) {
    NSSize s = [self _sizeOf:vis[i]]; used += vert ? s.height : s.width;
    if (i + 1 < n) { CGFloat c = [self customSpacingAfterView:vis[i]]; used += c == NSStackViewSpacingUseDefault ? _spacing : c; } }
  CGFloat extra = total - used, pos = vert ? _insets.top : _insets.left;
  CGFloat each = _distribution == 1 /* fill equally */ ? (total - _spacing * (n - 1)) / n : 0;
  CGFloat gap = _distribution == 3 /* equal spacing */ && n > 1 ? fmax(0, extra) / (n - 1) : 0;
  for (NSUInteger i = 0; i < n; i++) {
    NSView *v = vis[i]; NSSize s = [self _sizeOf:v];
    CGFloat len = vert ? s.height : s.width, cross = vert ? s.width : s.height;
    if (each > 0) len = each; else if (_distribution == 0 && i == n - 1 && extra > 0) len += extra;
    CGFloat crossTotal = vert ? _bounds.size.width - _insets.left - _insets.right : _bounds.size.height - _insets.top - _insets.bottom, cpos;
    NSRect f;
    if (vert) {
      /* NSLayoutAttribute: left 1, right 2, leading 5, trailing 6, width 7, centerX 9 */
      if (_alignment == 1 || _alignment == 5) cpos = _insets.left; else if (_alignment == 2 || _alignment == 6) cpos = _insets.left + crossTotal - cross;
      else if (_alignment == 7) { cpos = _insets.left; cross = crossTotal; } else cpos = _insets.left + (crossTotal - cross) / 2;
      f = NSMakeRect(cpos, _bounds.size.height - pos - len, cross, len);          /* not flipped: the first view is at the top */
    } else {
      /* top 3, bottom 4, height 8, centerY 10 */
      if (_alignment == 3) cpos = _bounds.size.height - _insets.top - cross; else if (_alignment == 4) cpos = _insets.bottom;
      else if (_alignment == 8) { cpos = _insets.bottom; cross = crossTotal; } else cpos = _insets.bottom + (crossTotal - cross) / 2;
      f = NSMakeRect(pos, cpos, len, cross); }
    [v setFrame:f];
    CGFloat c = [self customSpacingAfterView:v];
    pos += len + (c == NSStackViewSpacingUseDefault ? _spacing : c) + gap; }
  [self setNeedsDisplay:YES]; }
- (void)layout { [self _xefLayout]; }
- (void)setFrame:(NSRect)f { BOOL saved = _autoresizesSubviews; _autoresizesSubviews = NO; [super setFrame:f]; _autoresizesSubviews = saved; [self _xefLayout]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; if (_window) [self _xefLayout]; }
@end

/* ================================================================== NSVisualEffectView, NSPanel */
@implementation NSVisualEffectView
- (NSInteger)material { return _material; } - (void)setMaterial:(NSInteger)m { _material = m; [self setNeedsDisplay:YES]; }
- (NSInteger)blendingMode { return _blending; } - (void)setBlendingMode:(NSInteger)m { _blending = m; }
- (NSInteger)state { return _state; } - (void)setState:(NSInteger)s { _state = s; }
- (BOOL)isEmphasized { return _emphasized; } - (void)setEmphasized:(BOOL)f { _emphasized = f; }
- (NSImage *)maskImage { return _mask; } - (void)setMaskImage:(NSImage *)i { [i retain]; [_mask release]; _mask = i; }
- (NSInteger)interiorBackgroundStyle { return 1; }
- (void)dealloc { [_mask release]; [super dealloc]; }
- (void)drawRect:(NSRect)r { [[NSColor colorWithCalibratedWhite:_material == 7 || _material == 21 ? 0.9 : 0.94 alpha:1] setFill]; NSRectFill(_bounds); }
@end

@implementation NSPanel
- (id)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)s backing:(NSBackingStoreType)b defer:(BOOL)d {
  if ((self = [super initWithContentRect:r styleMask:s backing:b defer:d])) {
    _hidesOnDeactivate = YES; _released = NO;
    if (s & (1 << 4) /* utility window */) { _floating = YES; _level = 3; } }
  return self; }
- (BOOL)isFloatingPanel { return _floating; } - (void)setFloatingPanel:(BOOL)f { _floating = f; [self setLevel:f ? 3 : 0]; }
- (BOOL)becomesKeyOnlyIfNeeded { return _keyOnlyIfNeeded; } - (void)setBecomesKeyOnlyIfNeeded:(BOOL)f { _keyOnlyIfNeeded = f; }
- (BOOL)worksWhenModal { return _worksWhenModal; } - (void)setWorksWhenModal:(BOOL)f { _worksWhenModal = f; }
- (BOOL)hidesOnDeactivate { return _hidesOnDeactivate; } - (void)setHidesOnDeactivate:(BOOL)f { _hidesOnDeactivate = f; }
- (BOOL)canBecomeMainWindow { return NO; }
- (BOOL)isReleasedWhenClosed { return _released; }
@end

/* ================================================================== NSGradient */
@implementation NSGradient
+ (BOOL)supportsSecureCoding { return YES; }
- (id)initWithColors:(NSArray *)colors atLocations:(const CGFloat *)locs colorSpace:(NSColorSpace *)cs {
  if ((self = [super init])) {
    NSUInteger n = [colors count]; if (!n) { [self release]; return nil; }
    _colors = [colors copy]; _locs = malloc(sizeof(CGFloat) * n); _space = [cs retain];
    for (NSUInteger i = 0; i < n; i++) _locs[i] = locs ? locs[i] : (n > 1 ? (CGFloat)i / (n - 1) : 0); }
  return self; }
- (id)initWithColors:(NSArray *)colors { return [self initWithColors:colors atLocations:NULL colorSpace:nil]; }
- (id)initWithStartingColor:(NSColor *)a endingColor:(NSColor *)b { return [self initWithColors:@[a, b] atLocations:NULL colorSpace:nil]; }
- (id)initWithColorsAndLocations:(NSColor *)first, ... {
  NSMutableArray *colors = [NSMutableArray array]; CGFloat locs[64]; int n = 0;
  va_list ap; va_start(ap, first);
  for (NSColor *c = first; c && n < 64; c = va_arg(ap, NSColor *)) { [colors addObject:c]; locs[n++] = va_arg(ap, double); }
  va_end(ap);
  return [self initWithColors:colors atLocations:locs colorSpace:nil]; }
- (id)initWithCoder:(NSCoder *)c { return [self initWithColors:[c decodeObjectForKey:@"NSColorArray"] ?: @[[NSColor blackColor], [NSColor whiteColor]]]; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (void)dealloc { [_colors release]; [_space release]; free(_locs); [super dealloc]; }
- (NSColorSpace *)colorSpace { return _space ?: [NSColorSpace sRGBColorSpace]; }
- (NSInteger)numberOfColorStops { return [_colors count]; }
- (void)getColor:(NSColor **)c location:(CGFloat *)l atIndex:(NSInteger)i { if (c) *c = _colors[i]; if (l) *l = _locs[i]; }
- (NSColor *)interpolatedColorAtLocation:(CGFloat)l {
  NSUInteger n = [_colors count];
  if (l <= _locs[0]) return _colors[0];
  if (l >= _locs[n - 1]) return _colors[n - 1];
  NSUInteger i = 1; while (i < n - 1 && l > _locs[i]) i++;
  NSColor *a = _colors[i - 1], *b = _colors[i]; CGFloat span = _locs[i] - _locs[i - 1], t = span > 0 ? (l - _locs[i - 1]) / span : 0;
  return [NSColor colorWithCalibratedRed:a->r + (b->r - a->r) * t green:a->g + (b->g - a->g) * t blue:a->b + (b->b - a->b) * t alpha:a->a + (b->a - a->a) * t]; }
- (CGGradientRef)_cg {
  NSUInteger n = [_colors count]; CGFloat comps[n * 4];
  for (NSUInteger i = 0; i < n; i++) { NSColor *c = _colors[i]; comps[i * 4] = c->r; comps[i * 4 + 1] = c->g; comps[i * 4 + 2] = c->b; comps[i * 4 + 3] = c->a; }
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, _locs, n);
  CGColorSpaceRelease(cs); return g; }
- (void)drawFromPoint:(NSPoint)a toPoint:(NSPoint)b options:(NSUInteger)o {
  CGGradientRef g = [self _cg]; CGContextDrawLinearGradient(XEFCurrentCGContext(), g, a, b, (CGGradientDrawingOptions)o); CGGradientRelease(g); }
- (void)drawInRect:(NSRect)r angle:(CGFloat)angle {
  CGContextRef c = XEFCurrentCGContext(); CGContextSaveGState(c); CGContextClipToRect(c, r);
  double a = angle * M_PI / 180, dx = cos(a), dy = sin(a);
  if ([[NSGraphicsContext currentContext] isFlipped]) dy = -dy;
  /* the gradient spans the projection of the rectangle onto the direction */
  double half = (fabs(dx) * r.size.width + fabs(dy) * r.size.height) / 2;
  NSPoint m = NSMakePoint(NSMidX(r), NSMidY(r));
  [self drawFromPoint:NSMakePoint(m.x - dx * half, m.y - dy * half) toPoint:NSMakePoint(m.x + dx * half, m.y + dy * half) options:3];
  CGContextRestoreGState(c); }
- (void)drawInBezierPath:(NSBezierPath *)p angle:(CGFloat)angle {
  [NSGraphicsContext saveGraphicsState]; [p addClip]; [self drawInRect:CGPathGetBoundingBox(p->_path) angle:angle]; [NSGraphicsContext restoreGraphicsState]; }
- (void)drawFromCenter:(NSPoint)a radius:(CGFloat)ar toCenter:(NSPoint)b radius:(CGFloat)br options:(NSUInteger)o {
  CGGradientRef g = [self _cg]; CGContextDrawRadialGradient(XEFCurrentCGContext(), g, a, ar, b, br, (CGGradientDrawingOptions)o); CGGradientRelease(g); }
- (void)drawInRect:(NSRect)r relativeCenterPosition:(NSPoint)rc {
  CGContextRef c = XEFCurrentCGContext(); CGContextSaveGState(c); CGContextClipToRect(c, r);
  NSPoint m = NSMakePoint(NSMidX(r) + rc.x * r.size.width / 2, NSMidY(r) + rc.y * r.size.height / 2);
  [self drawFromCenter:m radius:0 toCenter:m radius:hypot(r.size.width, r.size.height) / 2 options:3];
  CGContextRestoreGState(c); }
- (void)drawInBezierPath:(NSBezierPath *)p relativeCenterPosition:(NSPoint)rc {
  [NSGraphicsContext saveGraphicsState]; [p addClip]; [self drawInRect:CGPathGetBoundingBox(p->_path) relativeCenterPosition:rc]; [NSGraphicsContext restoreGraphicsState]; }
@end

/* ================================================================== NSAnimationContext */
/* No interpolation: changes made in a group apply at once and the completion handler runs on the next turn of the run loop. */
static NSMutableArray *g_animation_stack;
@implementation NSAnimationContext
+ (NSAnimationContext *)currentContext {
  if (!g_animation_stack) g_animation_stack = [[NSMutableArray alloc] initWithObjects:[[[NSAnimationContext alloc] init] autorelease], nil];
  return [g_animation_stack lastObject]; }
- (id)init { if ((self = [super init])) { _duration = 0.25; } return self; }
- (void)dealloc { [_timing release]; [_completion release]; [super dealloc]; }
+ (void)beginGrouping { [self currentContext]; [g_animation_stack addObject:[[[NSAnimationContext alloc] init] autorelease]]; }
+ (void)endGrouping {
  [self currentContext];
  if ([g_animation_stack count] < 2) return;
  NSAnimationContext *c = [[[g_animation_stack lastObject] retain] autorelease]; [g_animation_stack removeLastObject];
  if (c->_completion) [c performSelector:@selector(_xefComplete) withObject:nil afterDelay:0]; }
- (void)_xefComplete { void (^h)(void) = _completion; _completion = nil; if (h) { h(); [h release]; } }
+ (void)runAnimationGroup:(void (^)(NSAnimationContext *))changes completionHandler:(void (^)(void))done {
  [self beginGrouping]; [[self currentContext] setCompletionHandler:done];
  if (changes) changes([self currentContext]);
  [self endGrouping]; }
+ (void)runAnimationGroup:(void (^)(NSAnimationContext *))changes { [self runAnimationGroup:changes completionHandler:nil]; }
- (NSTimeInterval)duration { return _duration; } - (void)setDuration:(NSTimeInterval)d { _duration = d; }
- (id)timingFunction { return _timing; } - (void)setTimingFunction:(id)t { [t retain]; [_timing release]; _timing = t; }
- (void (^)(void))completionHandler { return _completion; } - (void)setCompletionHandler:(void (^)(void))h { [_completion release]; _completion = [h copy]; }
- (BOOL)allowsImplicitAnimation { return _implicit; } - (void)setAllowsImplicitAnimation:(BOOL)f { _implicit = f; }
@end
