// NSTextInputContext: client, glyph info, input sources, activation. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 50)];
  NSTextInputContext *c = [[NSTextInputContext alloc] initWithClient:tv];
  P("ctx %d client same %d acceptsGlyphInfo %d locales nil %d\n", c != nil, c.client == tv, c.acceptsGlyphInfo, c.allowedInputSourceLocales == nil);
  c.acceptsGlyphInfo = YES; c.allowedInputSourceLocales = @[NSAllRomanInputSourcesLocaleIdentifier]; P("set: glyph %d locales %lu\n", c.acceptsGlyphInfo, (unsigned long)c.allowedInputSourceLocales.count);
  P("sources array %d selected nonnil %d\n", c.keyboardInputSources != nil, c.selectedKeyboardInputSource != nil);
  [c activate]; [c deactivate]; [c discardMarkedText]; [c invalidateCharacterCoordinates]; P("lifecycle calls ok\n");
  P("handleEvent nil -> %d\n", [c handleEvent:nil]);
  P("PASS appkit_inputctx\n");
  fflush(stdout); _exit(0);
} return 0; }
