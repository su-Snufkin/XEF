// NSSplitViewItem additions: collapse behavior, accessory controllers, defaults; NSTextInputContext basics. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSViewController *vc = [[NSViewController alloc] init];
  NSSplitViewItem *it = [NSSplitViewItem splitViewItemWithViewController:vc];
  P("defaults: collapseBehavior %ld canCollapseFromResize %d autoSafeArea %d topAccessories %lu bottomAccessories %lu\n", (long)it.collapseBehavior, it.canCollapseFromWindowResize, it.automaticallyAdjustsSafeAreaInsets, (unsigned long)it.topAlignedAccessoryViewControllers.count, (unsigned long)it.bottomAlignedAccessoryViewControllers.count);
  it.collapseBehavior = NSSplitViewItemCollapseBehaviorPreferResizingSiblingsWithFixedSplitView; it.canCollapseFromWindowResize = NO; it.automaticallyAdjustsSafeAreaInsets = YES;
  P("set: %ld %d %d\n", (long)it.collapseBehavior, it.canCollapseFromWindowResize, it.automaticallyAdjustsSafeAreaInsets);
  NSTextInputContext *ctx = [NSTextInputContext currentInputContext]; P("current input context nil %d\n", ctx == nil);
  P("PASS appkit_splititem\n");
  fflush(stdout); _exit(0);
} return 0; }
