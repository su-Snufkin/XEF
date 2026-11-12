// NSTypesetter / NSATSTypesetter: defaults, shared instance, paragraph ranges, control character actions, break decisions. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *R(NSRange r) { return [NSStringFromRange(r) UTF8String]; }
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSTypesetter *t = [NSTypesetter sharedSystemTypesetter];
  P("shared %d same %d class %s behavior default %ld\n", t != nil, t == [NSTypesetter sharedSystemTypesetter], [NSStringFromClass([t class]) UTF8String], (long)[NSTypesetter defaultTypesetterBehavior]);
  NSATSTypesetter *a = [[NSATSTypesetter alloc] init];
  P("defaults: usesFontLeading %d behavior %ld hyphenation %g padding %g bidi %d layoutManager %d containers %lu currentContainer %d paragraphStyle %d\n", a.usesFontLeading, (long)a.typesetterBehavior, a.hyphenationFactor, a.lineFragmentPadding, a.bidiProcessingEnabled, a.layoutManager != nil, (unsigned long)a.textContainers.count, a.currentTextContainer != nil, a.currentParagraphStyle != nil);
  a.usesFontLeading = NO; a.hyphenationFactor = 0.5; a.lineFragmentPadding = 2; a.bidiProcessingEnabled = YES; a.typesetterBehavior = NSTypesetterLatestBehavior;
  P("set: leading %d hyph %g padding %g bidi %d behavior %ld\n", a.usesFontLeading, a.hyphenationFactor, a.lineFragmentPadding, a.bidiProcessingEnabled, (long)a.typesetterBehavior);
  NSAttributedString *s = [[NSAttributedString alloc] initWithString:@"one two\nthree\tfour"];
  a.attributedString = s; P("attributedString same %d\n", a.attributedString == s);
  [a setParagraphGlyphRange:NSMakeRange(0, 8) separatorGlyphRange:NSMakeRange(7, 1)];
  P("paragraph glyph %s separator glyph %s char %s sepchar %s\n", R(a.paragraphGlyphRange), R(a.paragraphSeparatorGlyphRange), R(a.paragraphCharacterRange), R(a.paragraphSeparatorCharacterRange));
  P("actions: newline %lu tab %lu space %lu\n", (unsigned long)[a actionForControlCharacterAtIndex:7], (unsigned long)[a actionForControlCharacterAtIndex:13], (unsigned long)[a actionForControlCharacterAtIndex:3]);
  P("shouldBreakByWord(3) %d hyphenate(3) %d hyphFactorForGlyph %g\n", [a shouldBreakLineByWordBeforeCharacterAtIndex:3], [a shouldBreakLineByHyphenatingBeforeCharacterAtIndex:3], [a hyphenationFactorForGlyphAtIndex:3]);
  P("hyphenChar %u\n", [a hyphenCharacterForGlyphAtIndex:3]);
  NSFont *f = [NSFont systemFontOfSize:12]; NSFont *sub = [a substituteFontForFont:f]; P("substitute font same %d\n", sub == f);
  P("lineSpacingAfter %g paragraphBefore %g after %g\n", [a lineSpacingAfterGlyphAtIndex:0 withProposedLineFragmentRect:NSMakeRect(0, 0, 100, 14)], [a paragraphSpacingBeforeGlyphAtIndex:0 withProposedLineFragmentRect:NSMakeRect(0, 0, 100, 14)], [a paragraphSpacingAfterGlyphAtIndex:0 withProposedLineFragmentRect:NSMakeRect(0, 0, 100, 14)]);
  P("baseline %g\n", [a baselineOffsetInLayoutManager:nil glyphIndex:0]);
  P("PASS appkit_typesetter\n");
  fflush(stdout); _exit(0);
} return 0; }
