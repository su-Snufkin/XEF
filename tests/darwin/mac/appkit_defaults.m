// Default values of classes that AppKit-lite only has as generated placeholders (captured from the Mac by tools/capture_defaults.py).
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSWorkspaceOpenConfiguration *c = [NSWorkspaceOpenConfiguration configuration];
  P("open config: prompts %d substitution %d architecture %lld\n", c.promptsUserIfNeeded, c.allowsRunningApplicationSubstitution, (long long)c.architecture);
  c.promptsUserIfNeeded = NO; P("prompts now %d\n", c.promptsUserIfNeeded);
  NSScrubberProportionalLayout *l = [[NSScrubberProportionalLayout alloc] init]; P("proportional visible items %ld mirrors %d\n", (long)l.numberOfVisibleItems, l.automaticallyMirrorsInRightToLeftLayout);
  NSScrubberLayoutAttributes *a = [[NSScrubberLayoutAttributes alloc] init]; P("layout attributes index %ld alpha %g\n", (long)a.itemIndex, a.alpha);
  NSTextLayoutManager *t = [[NSTextLayoutManager alloc] init]; P("text layout manager usesFontLeading %d\n", t.usesFontLeading);
  NSDraggingSession *dummy = nil; (void)dummy;
  NSPrintPanel *pp = [NSPrintPanel printPanel]; P("print panel options %ld\n", (long)pp.options);
  P("PASS appkit_defaults\n");
  fflush(stdout); _exit(0);
} return 0; }
