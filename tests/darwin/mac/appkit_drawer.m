// NSDrawer state machine (open / close / toggle with delegate), sizes, edges; NSPrinter lookups. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface D : NSObject <NSDrawerDelegate> { @public NSMutableArray *log; BOOL allowClose; } @end
@implementation D
- (BOOL)drawerShouldClose:(NSDrawer *)d { [log addObject:@"shouldClose"]; return allowClose; }
- (void)drawerWillOpen:(NSNotification *)n { [log addObject:@"willOpen"]; } - (void)drawerDidOpen:(NSNotification *)n { [log addObject:@"didOpen"]; }
- (void)drawerWillClose:(NSNotification *)n { [log addObject:@"willClose"]; } - (void)drawerDidClose:(NSNotification *)n { [log addObject:@"didClose"]; }
@end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  NSDrawer *dr = [[NSDrawer alloc] initWithContentSize:NSMakeSize(120, 200) preferredEdge:NSMaxXEdge];
  P("init: contentSize %gx%g preferredEdge %lu state %ld parent nil %d content nil %d minContent %gx%g maxContent %gx%g leading %g trailing %g\n", dr.contentSize.width, dr.contentSize.height, (unsigned long)dr.preferredEdge, (long)dr.state, dr.parentWindow == nil, dr.contentView == nil, dr.minContentSize.width, dr.minContentSize.height, dr.maxContentSize.width, dr.maxContentSize.height, dr.leadingOffset, dr.trailingOffset);
  D *d = [D new]; d->log = [NSMutableArray array]; dr.delegate = d; dr.parentWindow = w;
  P("parent set %d\n", dr.parentWindow == w);
  NSView *cv = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 200)]; dr.contentView = cv; P("content set %d\n", dr.contentView == cv);
  [dr open]; P("after open: state %ld edge %lu log %s\n", (long)dr.state, (unsigned long)dr.edge, [[d->log componentsJoinedByString:@","] UTF8String]); [d->log removeAllObjects];
  d->allowClose = NO; [dr close]; P("close denied: state %ld log %s\n", (long)dr.state, [[d->log componentsJoinedByString:@","] UTF8String]); [d->log removeAllObjects];
  d->allowClose = YES; [dr close:nil]; P("close allowed: state %ld log %s\n", (long)dr.state, [[d->log componentsJoinedByString:@","] UTF8String]); [d->log removeAllObjects];
  [dr toggle:nil]; P("toggle -> state %ld\n", (long)dr.state);
  [dr toggle:nil]; P("toggle -> state %ld\n", (long)dr.state);
  [dr openOnEdge:NSMinXEdge]; P("openOnEdge min: edge %lu state %ld\n", (unsigned long)dr.edge, (long)dr.state);
  dr.minContentSize = NSMakeSize(50, 50); dr.maxContentSize = NSMakeSize(300, 300); P("min/max set %g %g\n", dr.minContentSize.width, dr.maxContentSize.width);
  dr.leadingOffset = 5; dr.trailingOffset = 7; P("offsets %g %g\n", dr.leadingOffset, dr.trailingOffset);
  NSArray *pn = [NSPrinter printerNames]; P("printerNames array %d\n", pn != nil);
  P("printerWithName missing %d\n", [NSPrinter printerWithName:@"NoSuchPrinterAnywhere"] != nil);
  P("PASS appkit_drawer\n");
  fflush(stdout); _exit(0);
} return 0; }
