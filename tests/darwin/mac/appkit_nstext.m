// NSText (the abstract base of NSTextView) used directly: string, selection, attributes, flags, defaults. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *R(NSRange r) { return [NSStringFromRange(r) UTF8String]; }
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSText *t = [[NSText alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
  P("class %s string '%s' selectedRange %s\n", [NSStringFromClass([t class]) UTF8String], [t.string UTF8String], R(t.selectedRange));
  P("defaults: editable %d selectable %d richText %d imports %d fieldEditor %d usesFontPanel %d drawsBackground %d vresize %d hresize %d alignment %ld direction %ld\n", t.isEditable, t.isSelectable, t.isRichText, t.importsGraphics, t.isFieldEditor, t.usesFontPanel, t.drawsBackground, t.isVerticallyResizable, t.isHorizontallyResizable, (long)t.alignment, (long)t.baseWritingDirection);
  P("sizes min %g,%g max %g,%g\n", t.minSize.width, t.minSize.height, t.maxSize.width, t.maxSize.height);
  t.string = @"Hello world"; P("string '%s' selected %s\n", [t.string UTF8String], R(t.selectedRange));
  t.selectedRange = NSMakeRange(6, 5); P("selected %s\n", R(t.selectedRange));
  [t replaceCharactersInRange:NSMakeRange(6, 5) withString:@"there"]; P("replace -> '%s'\n", [t.string UTF8String]);
  t.editable = NO; t.selectable = NO; P("flags %d %d\n", t.isEditable, t.isSelectable);
  t.richText = YES; t.importsGraphics = YES; t.fieldEditor = YES; t.usesFontPanel = NO; P("rich %d imports %d field %d fontPanel %d\n", t.isRichText, t.importsGraphics, t.isFieldEditor, t.usesFontPanel);
  NSFont *f = [NSFont boldSystemFontOfSize:20]; t.font = f; P("font set %d same %d\n", t.font != nil, t.font == f);
  t.textColor = [NSColor redColor]; P("textColor red %d\n", [t.textColor isEqual:[NSColor redColor]]);
  t.alignment = NSTextAlignmentCenter; P("alignment %ld\n", (long)t.alignment);
  t.backgroundColor = [NSColor blueColor]; t.drawsBackground = YES; P("bg blue %d draws %d\n", [t.backgroundColor isEqual:[NSColor blueColor]], t.drawsBackground);
  t.minSize = NSMakeSize(10, 10); t.maxSize = NSMakeSize(500, 500); t.verticallyResizable = YES; t.horizontallyResizable = YES; P("min %g max %g vr %d hr %d\n", t.minSize.width, t.maxSize.width, t.isVerticallyResizable, t.isHorizontallyResizable);
  P("rtf data nonempty %d\n", [t RTFFromRange:NSMakeRange(0, 5)].length > 0);
  P("rulerVisible %d\n", t.isRulerVisible);
  P("PASS appkit_nstext\n");
  fflush(stdout); _exit(0);
} return 0; }
