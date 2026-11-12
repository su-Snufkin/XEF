// NSBrowser, classic matrix-based delegate API: rows per column, cells filled by the delegate, selection, path. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface D : NSObject <NSBrowserDelegate> { @public NSMutableArray *log; } @end
@implementation D
- (NSInteger)browser:(NSBrowser *)b numberOfRowsInColumn:(NSInteger)c { [log addObject:[NSString stringWithFormat:@"rows%ld", (long)c]]; return c == 0 ? 3 : c == 1 ? 2 : 0; }
- (void)browser:(NSBrowser *)b willDisplayCell:(id)cell atRow:(NSInteger)r column:(NSInteger)c {
  [log addObject:[NSString stringWithFormat:@"cell%ld.%ld", (long)c, (long)r]];
  [cell setStringValue:[NSString stringWithFormat:@"c%ld-r%ld", (long)c, (long)r]]; [cell setLeaf:(c == 1 && r == 1)]; }
@end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  D *d = [D new]; d->log = [NSMutableArray array];
  NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  NSBrowser *b = [[NSBrowser alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)]; [w.contentView addSubview:b];
  b.delegate = d;
  P("cellClass %s matrixClass %s\n", [NSStringFromClass([NSBrowser cellClass]) UTF8String], [NSStringFromClass([b matrixClass]) UTF8String]);
  [b loadColumnZero];
  P("log after load: %s\n", [[d->log componentsJoinedByString:@" "] UTF8String]); [d->log removeAllObjects];
  NSMatrix *m0 = [b matrixInColumn:0]; P("matrix0 rows %ld cols %ld\n", (long)m0.numberOfRows, (long)m0.numberOfColumns);
  P("loaded cell (0,1) '%s'\n", [[[b loadedCellAtRow:1 column:0] stringValue] UTF8String]);
  P("lastColumn %ld titleOfColumn0 '%s'\n", (long)b.lastColumn, [b titleOfColumn:0] ? [[b titleOfColumn:0] UTF8String] : "nil");
  [b selectRow:1 inColumn:0];
  P("log after select: %s\n", [[d->log componentsJoinedByString:@" "] UTF8String]); [d->log removeAllObjects];
  P("lastColumn %ld selectedColumn %ld selectedRow(0) %ld selectedCell '%s' path '%s'\n", (long)b.lastColumn, (long)b.selectedColumn, (long)[b selectedRowInColumn:0], [[[b selectedCell] stringValue] UTF8String], [b.path UTF8String]);
  P("matrix1 rows %ld\n", (long)[b matrixInColumn:1].numberOfRows);
  [b selectRow:1 inColumn:1];
  P("leaf selected: lastColumn %ld path '%s' column of matrix1 %ld\n", (long)b.lastColumn, [b.path UTF8String], (long)[b columnOfMatrix:[b matrixInColumn:1]]);
  P("selectedCells %lu\n", (unsigned long)b.selectedCells.count);
  P("setPath ok %d\n", [b setPath:@"/c0-r2"]);
  P("after setPath: lastColumn %ld path '%s'\n", (long)b.lastColumn, [b.path UTF8String]);
  P("setPath missing %d\n", [b setPath:@"/nothing"]);
  P("PASS appkit_browser2\n");
  fflush(stdout); _exit(0);
} return 0; }
