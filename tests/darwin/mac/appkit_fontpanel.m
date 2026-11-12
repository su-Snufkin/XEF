// NSFontPanel: shared panel, panel font, conversion, enabled flag, visibility. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSFontPanel *fp = [NSFontPanel sharedFontPanel];
  P("shared %d same %d exists %d visible %d enabled %d\n", fp != nil, fp == [NSFontPanel sharedFontPanel], [NSFontPanel sharedFontPanelExists], fp.isVisible, fp.isEnabled);
  NSFont *f = [NSFont boldSystemFontOfSize:20]; [fp setPanelFont:f isMultiple:NO]; P("panelFont same %d\n", [fp panelConvertFont:[NSFont systemFontOfSize:12]] != nil);
  P("accessory nil %d worksWhenModal %d\n", fp.accessoryView == nil, fp.worksWhenModal);
  fp.enabled = NO; P("enabled %d\n", fp.isEnabled); fp.enabled = YES;
  P("PASS appkit_fontpanel\n");
  fflush(stdout); _exit(0);
} return 0; }
