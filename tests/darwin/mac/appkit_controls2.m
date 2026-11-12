// NSTextField / NSButton / NSView additions: factories, defaults, placeholder strings, appearance, deprecated conversions. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface T : NSObject { @public int begin, end, change; } @end
@implementation T
- (void)controlTextDidBeginEditing:(NSNotification *)n { begin++; } - (void)controlTextDidEndEditing:(NSNotification *)n { end++; } - (void)controlTextDidChange:(NSNotification *)n { change++; }
@end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(8, 8)];
  NSButton *b = [NSButton buttonWithTitle:@"Go" image:img target:nil action:NULL];
  P("button factory: title %s image %d type %ld bezel %ld imagePosition %ld\n", [b.title UTF8String], b.image == img, (long)b.bezelStyle, (long)b.bezelStyle, (long)b.imagePosition);
  P("defaults: springLoaded %d maxAccel %ld tint %ld imageHugsTitle %d borderShape %ld altAttr nil %d\n", b.isSpringLoaded, (long)b.maxAcceleratorLevel, (long)b.tintProminence, b.imageHugsTitle, (long)b.borderShape, b.attributedAlternateTitle.length == 0);
  b.springLoaded = YES; b.maxAcceleratorLevel = 1; b.imageHugsTitle = YES; b.tintProminence = NSTintProminenceSecondary; P("set: %d %ld %d %ld\n", b.isSpringLoaded, (long)b.maxAcceleratorLevel, b.imageHugsTitle, (long)b.tintProminence);
  float d = 0, i = 0; [b getPeriodicDelay:&d interval:&i]; P("periodic %.2f %.3f\n", d, i);
  NSTextField *l = [NSTextField labelWithAttributedString:[[NSAttributedString alloc] initWithString:@"lab"]];
  P("label: editable %d selectable %d bezeled %d drawsBackground %d string %s\n", l.isEditable, l.isSelectable, l.isBezeled, l.drawsBackground, [l.stringValue UTF8String]);
  NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
  P("tf defaults: lineBreakStrategy %lu allowsWritingTools %d placeholderStrings nil %d resolvesNatural %d contentType nil %d\n", (unsigned long)tf.lineBreakStrategy, tf.allowsWritingTools, tf.placeholderStrings == nil, tf.resolvesNaturalAlignmentWithBaseWritingDirection, tf.contentType == nil);
  tf.placeholderStrings = @[@"a", @"b"]; P("placeholderStrings %lu\n", (unsigned long)tf.placeholderStrings.count);
  tf.lineBreakStrategy = NSLineBreakStrategyPushOut; P("lineBreakStrategy %lu\n", (unsigned long)tf.lineBreakStrategy);
  T *t = [T new]; tf.delegate = t;
  NSText *fe = [[NSTextView alloc] initWithFrame:NSZeroRect];
  P("textShouldBegin %d\n", [tf textShouldBeginEditing:fe]); [tf textDidBeginEditing:[NSNotification notificationWithName:NSTextDidBeginEditingNotification object:fe]];
  [tf textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:fe]];
  P("textShouldEnd %d\n", [tf textShouldEndEditing:fe]);
  P("delegate calls begin %d change %d\n", t->begin, t->change);
  NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
  P("view: appearance nil %d effective nil %d animator ok %d animations %lu acceptsTouch %d\n", v.appearance == nil, v.effectiveAppearance == nil, [v animator] != nil, (unsigned long)v.animations.count, v.acceptsTouchEvents);
  v.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; P("appearance name %s effective %s\n", [v.appearance.name UTF8String], [v.effectiveAppearance.name UTF8String]);
  NSSize s = [v convertSizeToBase:NSMakeSize(3, 4)]; P("convertSizeToBase %g,%g\n", s.width, s.height);
  P("performMnemonic %d shouldDrawColor %d gState %ld\n", [v performMnemonic:@"x"], v.shouldDrawColor, (long)v.gState);
  P("PASS appkit_controls2\n");
  fflush(stdout); _exit(0);
} return 0; }
