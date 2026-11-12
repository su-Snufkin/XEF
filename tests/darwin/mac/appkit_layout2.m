// NSLayoutManager: temporary attributes (add / set / remove, effective ranges), glyph helpers, hyphenation flag. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *R(NSRange r) { return [NSStringFromRange(r) UTF8String]; }
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSTextStorage *ts = [[NSTextStorage alloc] initWithString:@"Hello temporary attributes world"];
  NSLayoutManager *lm = [[NSLayoutManager alloc] init]; [ts addLayoutManager:lm];
  NSTextContainer *tc = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200, 1e7)]; [lm addTextContainer:tc];
  NSRange er; NSDictionary *d = [lm temporaryAttributesAtCharacterIndex:3 effectiveRange:&er]; P("none: count %lu range %s\n", (unsigned long)d.count, R(er));
  [lm addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] forCharacterRange:NSMakeRange(6, 9)];
  d = [lm temporaryAttributesAtCharacterIndex:8 effectiveRange:&er]; P("inside: count %lu range %s hasBg %d\n", (unsigned long)d.count, R(er), d[NSBackgroundColorAttributeName] != nil);
  d = [lm temporaryAttributesAtCharacterIndex:2 effectiveRange:&er]; P("before: count %lu range %s\n", (unsigned long)d.count, R(er));
  d = [lm temporaryAttributesAtCharacterIndex:20 effectiveRange:&er]; P("after: count %lu range %s\n", (unsigned long)d.count, R(er));
  [lm addTemporaryAttributes:@{ NSUnderlineStyleAttributeName: @1, NSForegroundColorAttributeName: [NSColor redColor] } forCharacterRange:NSMakeRange(10, 10)];
  d = [lm temporaryAttributesAtCharacterIndex:12 effectiveRange:&er]; P("overlap: count %lu range %s\n", (unsigned long)d.count, R(er));
  d = [lm temporaryAttributesAtCharacterIndex:7 effectiveRange:&er]; P("first part: count %lu range %s\n", (unsigned long)d.count, R(er));
  id v = [lm temporaryAttribute:NSForegroundColorAttributeName atCharacterIndex:12 effectiveRange:&er]; P("single attr %d range %s\n", v != nil, R(er));
  NSRange lr; v = [lm temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:8 longestEffectiveRange:&lr inRange:NSMakeRange(0, 32)]; P("longest bg %d range %s\n", v != nil, R(lr));
  [lm removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:NSMakeRange(0, 32)];
  d = [lm temporaryAttributesAtCharacterIndex:8 effectiveRange:&er]; P("after remove bg: count %lu\n", (unsigned long)d.count);
  [lm setTemporaryAttributes:@{ NSUnderlineStyleAttributeName: @2 } forCharacterRange:NSMakeRange(10, 4)];
  d = [lm temporaryAttributesAtCharacterIndex:11 effectiveRange:&er]; P("after set: count %lu range %s underline %d\n", (unsigned long)d.count, R(er), [d[NSUnderlineStyleAttributeName] intValue]);
  P("storage attrs untouched %d\n", [ts attributesAtIndex:12 effectiveRange:NULL].count == 0 || [ts attributesAtIndex:12 effectiveRange:NULL][NSBackgroundColorAttributeName] == nil);
  P("hyphenation default %d", lm.usesDefaultHyphenation); lm.usesDefaultHyphenation = YES; P(" -> %d\n", lm.usesDefaultHyphenation);
  P("attributedString same %d\n", lm.attributedString == (NSAttributedString *)ts);
  BOOL valid = NO; CGGlyph g = [lm CGGlyphAtIndex:1 isValidIndex:&valid]; P("glyph valid %d nonzero %d\n", valid, g != 0);
  valid = YES; [lm CGGlyphAtIndex:9999 isValidIndex:&valid]; P("glyph out of range valid %d\n", valid);
  P("notShown 'H' %d\n", [lm notShownAttributeForGlyphAtIndex:0]);
  P("drawsOutside %d\n", [lm drawsOutsideLineFragmentForGlyphAtIndex:0]);
  P("PASS appkit_layout2\n");
  fflush(stdout); _exit(0);
} return 0; }
