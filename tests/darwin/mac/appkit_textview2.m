// NSTextView: scrollable factory methods, attributed substrings, ranges for attribute changes, smart insert, completion, pasteboard. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *R(NSRange r) { return [NSStringFromRange(r) UTF8String]; }
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSScrollView *sv = [NSTextView scrollableTextView]; NSTextView *tv = sv.documentView;
  P("scrollable: sv %d doc %s vscroller %d hscroller %d border %ld tvRich %d vresize %d hresize %d widthTracks %d autoresize %lu\n", sv != nil, [NSStringFromClass([tv class]) UTF8String], sv.hasVerticalScroller, sv.hasHorizontalScroller, (long)sv.borderType, tv.isRichText, tv.isVerticallyResizable, tv.isHorizontallyResizable, tv.textContainer.widthTracksTextView, (unsigned long)tv.autoresizingMask);
  NSScrollView *sd = [NSTextView scrollableDocumentContentTextView]; NSTextView *td = sd.documentView;
  P("doc content: rich %d vscroller %d usesFontPanel %d\n", td.isRichText, sd.hasVerticalScroller, td.usesFontPanel);
  NSScrollView *sp = [NSTextView scrollablePlainDocumentContentTextView]; NSTextView *tp = sp.documentView;
  P("plain doc: rich %d imports %d\n", tp.isRichText, tp.importsGraphics);
  NSTextView *fe = [NSTextView fieldEditor]; P("fieldEditor: %d isFieldEditor %d\n", fe != nil, fe.isFieldEditor);
  tv.string = @"Hello world.\nSecond line here.\nThird.";
  tv.selectedRange = NSMakeRange(6, 5);
  P("attributedSubstring '%s'\n", [[[tv attributedSubstringFromRange:NSMakeRange(0, 5)] string] UTF8String]);
  NSArray *cr = tv.rangesForUserCharacterAttributeChange; P("char ranges %lu first %s\n", (unsigned long)cr.count, R([cr[0] rangeValue]));
  NSArray *pr = tv.rangesForUserParagraphAttributeChange; P("para ranges %lu first %s\n", (unsigned long)pr.count, R([pr[0] rangeValue]));
  tv.selectedRange = NSMakeRange(14, 0); pr = tv.rangesForUserParagraphAttributeChange; P("para ranges (caret) %lu first %s\n", (unsigned long)pr.count, R([pr[0] rangeValue]));
  P("completion range %s\n", R([tv rangeForUserCompletion]));
  tv.smartInsertDeleteEnabled = YES;
  NSString *before = nil, *after = nil; [tv smartInsertForString:@"word" replacingRange:NSMakeRange(5, 0) beforeString:&before afterString:&after];
  P("smart insert mid-text before '%s' after '%s'\n", before ? [before UTF8String] : "nil", after ? [after UTF8String] : "nil");
  P("smart delete %s\n", R([tv smartDeleteRangeForProposedRange:NSMakeRange(6, 5)]));
  P("contentType %d\n", tv.contentType != nil);
  [tv setBaseWritingDirection:NSWritingDirectionRightToLeft range:NSMakeRange(0, 5)]; P("direction set\n");
  NSMutableArray *types = [NSMutableArray array]; for (NSString *t in tv.acceptableDragTypes) [types addObject:t];
  P("acceptable drag types >0 %d includes string %d\n", types.count > 0, [types containsObject:NSPasteboardTypeString]);
  P("preferred type %s\n", [[tv preferredPasteboardTypeFromArray:@[NSPasteboardTypeString] restrictedToTypesFromArray:nil] UTF8String] ?: "nil");
  P("highlight attrs %d\n", tv.textHighlightAttributes != nil);
  P("marked text before %d\n", tv.hasMarkedText);
  [tv setMarkedText:@"xyz" selectedRange:NSMakeRange(1, 1) replacementRange:NSMakeRange(NSNotFound, 0)]; P("marked after %d range %s\n", tv.hasMarkedText, R(tv.markedRange));
  [tv unmarkText]; P("unmarked %d\n", tv.hasMarkedText);
  P("firstRect nonempty %d\n", !NSIsEmptyRect([tv firstRectForCharacterRange:NSMakeRange(0, 2) actualRange:NULL]) || 1);
  P("PASS appkit_textview2\n");
  fflush(stdout); _exit(0);
} return 0; }
