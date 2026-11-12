// NSBrowser, item-based delegate API: columns from the tree, selection, path, index paths. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface N : NSObject { @public NSString *name; NSMutableArray *kids; } @end
@implementation N @end
static N *mk(NSString *n, NSArray *k) { N *x = [N new]; x->name = n; x->kids = k ? [NSMutableArray arrayWithArray:k] : nil; return x; }
@interface D : NSObject <NSBrowserDelegate> { @public N *root; int calls; } @end
@implementation D
- (id)rootItemForBrowser:(NSBrowser *)b { P("  rootItem\n"); return root; }
- (NSInteger)browser:(NSBrowser *)b numberOfChildrenOfItem:(id)i { calls++; return [((N *)i)->kids count]; }
- (id)browser:(NSBrowser *)b child:(NSInteger)idx ofItem:(id)i { return ((N *)i)->kids[idx]; }
- (BOOL)browser:(NSBrowser *)b isLeafItem:(id)i { return ((N *)i)->kids == nil; }
- (id)browser:(NSBrowser *)b objectValueForItem:(id)i { return ((N *)i)->name; }
- (void)browserSelectionDidChange:(NSBrowser *)b { P("  selectionDidChange\n"); }
- (void)browser:(NSBrowser *)b willDisplayCell:(id)c atRow:(NSInteger)r column:(NSInteger)col { }
@end
static const char *ip(NSIndexPath *p) { NSMutableString *s = [NSMutableString stringWithString:@"["]; for (NSUInteger i = 0; i < p.length; i++) [s appendFormat:@"%s%lu", i ? "," : "", (unsigned long)[p indexAtPosition:i]]; [s appendString:@"]"]; return [s UTF8String]; }
static void state(NSBrowser *b, const char *tag) {
  P("%s: lastColumn %ld path '%s' selIndexPath %s selIndexPaths %lu selectedColumn %ld\n", tag, (long)b.lastColumn, [b.path UTF8String], b.selectionIndexPath ? ip(b.selectionIndexPath) : "nil", (unsigned long)b.selectionIndexPaths.count, (long)b.selectedColumn);
}
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  D *d = [D new];
  d->root = mk(@"root", @[mk(@"a", @[mk(@"a1", @[mk(@"a1x", nil)]), mk(@"a2", nil)]), mk(@"b", nil), mk(@"c", @[mk(@"c1", nil)])]);
  NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  NSBrowser *b = [[NSBrowser alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)];
  [w.contentView addSubview:b];
  P("defaults: sep '%s' titled %d multi %d branch %d empty %d minW %g maxVis %ld reuses %d separates %d typeSelect %d resizing %ld hscroll %d\n", [b.pathSeparator UTF8String], b.isTitled, b.allowsMultipleSelection, b.allowsBranchSelection, b.allowsEmptySelection,
    b.minColumnWidth, (long)b.maxVisibleColumns, b.reusesColumns, b.separatesColumns, b.allowsTypeSelect, (long)b.columnResizingType, b.hasHorizontalScroller);
  b.delegate = d;
  P("loaded before %d\n", b.isLoaded);
  [b loadColumnZero];
  P("loaded after %d\n", b.isLoaded);
  state(b, "after load");
  P("item(0,0)=%s parentCol0=%s\n", [((N *)[b itemAtRow:0 inColumn:0])->name UTF8String], [((N *)[b parentForItemsInColumn:0])->name UTF8String]);
  P("leaf a %d b %d\n", [b isLeafItem:[b itemAtRow:0 inColumn:0]], [b isLeafItem:[b itemAtRow:1 inColumn:0]]);
  P("== select\n");
  [b selectRow:0 inColumn:0];
  state(b, "sel a");
  P("selectedRowInColumn 0 %ld, 1 %ld\n", (long)[b selectedRowInColumn:0], (long)[b selectedRowInColumn:1]);
  P("col1 first %s parent %s\n", [((N *)[b itemAtRow:0 inColumn:1])->name UTF8String], [((N *)[b parentForItemsInColumn:1])->name UTF8String]);
  [b selectRow:0 inColumn:1];
  state(b, "sel a1");
  [b selectRow:1 inColumn:1];
  state(b, "sel a2 (leaf)");
  [b selectRow:1 inColumn:0];
  state(b, "sel b (leaf)");
  [b selectRow:2 inColumn:0];
  state(b, "sel c");
  P("pathToColumn:1 '%s'\n", [[b pathToColumn:1] UTF8String]);
  P("== setPath\n");
  P("setPath ok %d\n", [b setPath:@"/a/a1"]);
  state(b, "after setPath");
  P("setPath bad %d\n", [b setPath:@"/zzz"]);
  state(b, "after bad setPath");
  P("setSelectionIndexPath\n");
  b.selectionIndexPath = [NSIndexPath indexPathWithIndexes:(NSUInteger[]){2, 0} length:2];
  state(b, "after setSel");
  P("indexPathForColumn:1 %s\n", ip([b indexPathForColumn:1]));
  P("== reload\n");
  [((N *)d->root->kids[0])->kids addObject:mk(@"a3", nil)];
  [b reloadColumn:1];
  state(b, "after reloadColumn");
  P("== titles / widths\n");
  [b setTitle:@"Col" ofColumn:0];
  P("title0 '%s' titled %d\n", [[b titleOfColumn:0] UTF8String], b.isTitled);
  [b setWidth:90 ofColumn:0]; P("width0 now %g\n", [b widthOfColumn:0]);
  P("== multiple\n");
  b.allowsMultipleSelection = YES; b.allowsBranchSelection = YES;
  [b selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] inColumn:0];
  P("selected rows col0 %lu\n", (unsigned long)[b selectedRowIndexesInColumn:0].count);
  state(b, "multi");
  P("PASS appkit_browser\n");
  fflush(stdout); _exit(0);
} return 0; }
