// NSTableView / NSTableColumn / NSOutlineView without a window: defaults, geometry of rows and columns, selection rules and
// notifications, column management, row updates, the outline's expansion state. Real AppKit's output is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *R(NSRect r) { return [[NSString stringWithFormat:@"{%g,%g,%g,%g}", r.origin.x, r.origin.y, r.size.width, r.size.height] UTF8String]; }
static const char *IS(NSIndexSet *s) {
  NSMutableArray *a = [NSMutableArray array];
  [s enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [a addObject:@(i)]; }];
  return [[NSString stringWithFormat:@"[%@]", [a componentsJoinedByString:@","]] UTF8String]; }

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate> { @public NSMutableArray *rows; int changes; BOOL viewBased; }
@end
@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return rows.count; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r { return [NSString stringWithFormat:@"%@-%@", c.identifier, rows[r]]; }
- (void)tableViewSelectionDidChange:(NSNotification *)n { changes++; P("  selectionDidChange %s\n", IS([n.object selectedRowIndexes])); }
- (BOOL)selectionShouldChangeInTableView:(NSTableView *)t { P("  selectionShouldChange\n"); return YES; }
- (BOOL)tableView:(NSTableView *)t shouldSelectRow:(NSInteger)r { P("  shouldSelectRow %ld\n", (long)r); return YES; }
- (void)tableView:(NSTableView *)t sortDescriptorsDidChange:(NSArray *)old { P("  sortDescriptorsDidChange old %ld new %ld\n", (long)old.count, (long)t.sortDescriptors.count); }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
  if (!viewBased) return nil;
  NSTextField *f = [NSTextField labelWithString:[NSString stringWithFormat:@"v%ld", (long)r]]; f.identifier = c.identifier; return f; }
@end

static void columns(void) {
  P("== NSTableColumn\n");
  NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  P("identifier %s title '%s' width %g min %g max %g resizing %lu editable %d hidden %d header %s tableView %d\n", [c.identifier UTF8String], [c.title UTF8String], c.width, c.minWidth,
    c.maxWidth > 1e6 ? 1e6 : c.maxWidth, (unsigned long)c.resizingMask, c.editable, c.hidden, [[c.headerCell className] UTF8String], c.tableView != nil);
  c.title = @"Name"; P("title %s header string %s\n", [c.title UTF8String], [[c.headerCell stringValue] UTF8String]);
  c.minWidth = 40; c.maxWidth = 120; c.width = 500; P("width 500 -> %g\n", c.width); c.width = 5; P("width 5 -> %g\n", c.width);
  c.minWidth = 80; P("min 80 -> width %g\n", c.width); c.maxWidth = 60; P("max 60 -> width %g min %g\n", c.width, c.minWidth);
}

static void table(void) {
  P("== NSTableView\n");
  NSTableView *t = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  t.style = NSTableViewStylePlain;
  P("defaults rows %ld columns %ld rowHeight %g spacing %g,%g multiple %d empty %d columnSelection %d reorder %d resize %d flipped %d\n", (long)t.numberOfRows, (long)t.numberOfColumns, t.rowHeight,
    t.intercellSpacing.width, t.intercellSpacing.height, t.allowsMultipleSelection, t.allowsEmptySelection, t.allowsColumnSelection, t.allowsColumnReordering, t.allowsColumnResizing, t.isFlipped);
  P("header %s corner %d alternating %d grid %lu highlight %ld selectedRow %ld clicked %ld,%ld edited %ld,%ld autoresizing %lu\n", [[t.headerView className] UTF8String], t.cornerView != nil,
    t.usesAlternatingRowBackgroundColors, (unsigned long)t.gridStyleMask, (long)t.selectionHighlightStyle, (long)t.selectedRow, (long)t.clickedRow, (long)t.clickedColumn, (long)t.editedRow, (long)t.editedColumn,
    (unsigned long)t.columnAutoresizingStyle);
  Source *s = [[Source alloc] init]; s->rows = [@[@"a", @"b", @"c", @"d", @"e"] mutableCopy];
  NSTableColumn *c1 = [[NSTableColumn alloc] initWithIdentifier:@"one"], *c2 = [[NSTableColumn alloc] initWithIdentifier:@"two"];
  c1.width = 100; c2.width = 150;
  [t addTableColumn:c1]; [t addTableColumn:c2];
  P("columns %ld column.tableView %d index of two %ld missing %ld by id %d\n", (long)t.numberOfColumns, c1.tableView == t, (long)[t columnWithIdentifier:@"two"], (long)[t columnWithIdentifier:@"zzz"],
    [t tableColumnWithIdentifier:@"two"] == c2);
  t.dataSource = s; t.delegate = s; [t reloadData];
  P("rows %ld frame %s\n", (long)t.numberOfRows, R(t.frame));
  P("rectOfRow 0 %s 2 %s 9 %s\n", R([t rectOfRow:0]), R([t rectOfRow:2]), R([t rectOfRow:9]));
  P("rectOfColumn 0 %s 1 %s\n", R([t rectOfColumn:0]), R([t rectOfColumn:1]));
  P("cell 1,2 %s\n", R([t frameOfCellAtColumn:1 row:2]));
  NSRect r2 = [t rectOfRow:2], col1 = [t rectOfColumn:1];
  P("rowAtPoint in row 2: %ld, below all: %ld, columnAtPoint in col 1: %ld, right of all: %ld\n", (long)[t rowAtPoint:NSMakePoint(5, NSMidY(r2))], (long)[t rowAtPoint:NSMakePoint(5, 5000)],
    (long)[t columnAtPoint:NSMakePoint(NSMidX(col1), 5)], (long)[t columnAtPoint:NSMakePoint(5000, 5)]);
  NSRange rr = [t rowsInRect:NSUnionRect([t rectOfRow:1], [t rectOfRow:3])]; P("rowsInRect %lu+%lu columns %s\n", (unsigned long)rr.location, (unsigned long)rr.length, IS([t columnIndexesInRect:col1]));
  P("select 1\n"); [t selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
  P("selectedRow %ld set %s count %ld isSelected(1) %d\n", (long)t.selectedRow, IS(t.selectedRowIndexes), (long)t.numberOfSelectedRows, [t isRowSelected:1]);
  P("select 1 again\n"); [t selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
  P("extend with 3 (single selection)\n"); [t selectRowIndexes:[NSIndexSet indexSetWithIndex:3] byExtendingSelection:YES]; P("set %s\n", IS(t.selectedRowIndexes));
  t.allowsMultipleSelection = YES;
  P("extend with 0,4\n"); NSMutableIndexSet *m = [NSMutableIndexSet indexSetWithIndex:0]; [m addIndex:4]; [t selectRowIndexes:m byExtendingSelection:YES];
  P("set %s selectedRow %ld\n", IS(t.selectedRowIndexes), (long)t.selectedRow);
  P("deselect 4\n"); [t deselectRow:4]; P("set %s selectedRow %ld\n", IS(t.selectedRowIndexes), (long)t.selectedRow);
  P("selectAll\n"); [t selectAll:nil]; P("set %s\n", IS(t.selectedRowIndexes));
  P("deselectAll\n"); [t deselectAll:nil]; P("set %s selectedRow %ld\n", IS(t.selectedRowIndexes), (long)t.selectedRow);
  t.allowsEmptySelection = NO; P("empty not allowed: set %s\n", IS(t.selectedRowIndexes));
  [t selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO]; P("deselectAll again\n"); [t deselectAll:nil]; P("set %s\n", IS(t.selectedRowIndexes));
  t.allowsEmptySelection = YES;
  P("shrink data to 2 rows\n"); [s->rows removeObjectsInRange:NSMakeRange(2, 3)]; [t selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 4)] byExtendingSelection:NO];
  [t noteNumberOfRowsChanged]; P("rows %ld set %s frame %s\n", (long)t.numberOfRows, IS(t.selectedRowIndexes), R(t.frame));
  P("insert rows\n"); [s->rows insertObject:@"x" atIndex:0]; [t beginUpdates]; [t insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:0] withAnimation:0]; [t endUpdates];
  P("rows %ld set %s\n", (long)t.numberOfRows, IS(t.selectedRowIndexes));
  P("remove row 1\n"); [s->rows removeObjectAtIndex:1]; [t removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:1] withAnimation:0]; P("rows %ld set %s\n", (long)t.numberOfRows, IS(t.selectedRowIndexes));
  t.rowHeight = 30; P("rowHeight 30: row 1 %s frame %s\n", R([t rectOfRow:1]), R(t.frame));
  t.intercellSpacing = NSMakeSize(10, 6); P("spacing 10,6: row 1 %s col 1 %s cell 1,1 %s\n", R([t rectOfRow:1]), R([t rectOfColumn:1]), R([t frameOfCellAtColumn:1 row:1]));
  P("move column 0 to 1\n"); [t moveColumn:0 toColumn:1]; P("order %s %s\n", [t.tableColumns[0].identifier UTF8String], [t.tableColumns[1].identifier UTF8String]);
  P("sort descriptors\n"); t.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"x" ascending:YES]];
  [t removeTableColumn:c1]; P("removed: columns %ld column.tableView %d\n", (long)t.numberOfColumns, c1.tableView != nil);
  NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 320, 240)]; sv.documentView = t;
  P("in scroll view: enclosing %d header superview %s\n", t.enclosingScrollView == sv, [[t.headerView.superview className] UTF8String]);
  P("changes %d\n", s->changes);
}

@interface Node : NSObject { @public NSString *name; NSMutableArray *kids; }
@end
@implementation Node
+ (Node *)n:(NSString *)name kids:(NSArray *)k { Node *x = [[Node alloc] init]; x->name = name; x->kids = [k mutableCopy]; return x; }
@end
@interface Tree : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate> { @public NSArray *roots; }
@end
@implementation Tree
- (NSInteger)outlineView:(NSOutlineView *)o numberOfChildrenOfItem:(id)i { return i ? ((Node *)i)->kids.count : roots.count; }
- (id)outlineView:(NSOutlineView *)o child:(NSInteger)n ofItem:(id)i { return i ? ((Node *)i)->kids[n] : roots[n]; }
- (BOOL)outlineView:(NSOutlineView *)o isItemExpandable:(id)i { return ((Node *)i)->kids.count > 0; }
- (id)outlineView:(NSOutlineView *)o objectValueForTableColumn:(NSTableColumn *)c byItem:(id)i { return ((Node *)i)->name; }
- (BOOL)outlineView:(NSOutlineView *)o shouldExpandItem:(id)i { P("  shouldExpand %s\n", [((Node *)i)->name UTF8String]); return ![((Node *)i)->name isEqual:@"sealed"]; }
- (void)outlineViewItemWillExpand:(NSNotification *)n { P("  willExpand %s\n", [((Node *)n.userInfo[@"NSObject"])->name UTF8String]); }
- (void)outlineViewItemDidExpand:(NSNotification *)n { P("  didExpand %s\n", [((Node *)n.userInfo[@"NSObject"])->name UTF8String]); }
- (void)outlineViewItemDidCollapse:(NSNotification *)n { P("  didCollapse %s\n", [((Node *)n.userInfo[@"NSObject"])->name UTF8String]); }
- (void)outlineViewSelectionDidChange:(NSNotification *)n { P("  selectionDidChange %s\n", IS([n.object selectedRowIndexes])); }
@end

static const char *rowsOf(NSOutlineView *o) {
  NSMutableArray *a = [NSMutableArray array];
  for (NSInteger i = 0; i < o.numberOfRows; i++) [a addObject:[NSString stringWithFormat:@"%@/%ld", ((Node *)[o itemAtRow:i])->name, (long)[o levelForRow:i]]];
  return [[a componentsJoinedByString:@" "] UTF8String]; }

static void outlines(void) {
  P("== NSOutlineView\n");
  NSOutlineView *o = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  o.style = NSTableViewStylePlain;
  NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"name"]; c.width = 200; [o addTableColumn:c];
  P("defaults indentation %g outlineColumn set %d autoresizes %d follows cell %d autosave %d\n", o.indentationPerLevel, o.outlineTableColumn != nil, o.autoresizesOutlineColumn, o.indentationMarkerFollowsCell,
    o.autosaveExpandedItems);
  o.outlineTableColumn = c;
  Node *leaf1 = [Node n:@"leaf1" kids:@[]], *leaf2 = [Node n:@"leaf2" kids:@[]], *deep = [Node n:@"deep" kids:@[[Node n:@"deeper" kids:@[]]]];
  Node *a = [Node n:@"a" kids:@[leaf1, deep]], *b = [Node n:@"b" kids:@[leaf2]], *sealed = [Node n:@"sealed" kids:@[[Node n:@"hidden" kids:@[]]]];
  Tree *t = [[Tree alloc] init]; t->roots = @[a, b, sealed];
  o.dataSource = t; o.delegate = t; [o reloadData];
  P("rows %ld: %s\n", (long)o.numberOfRows, rowsOf(o));
  P("expandable a %d leaf1 %d expanded a %d row of b %ld row of leaf1 %ld level of deep %ld\n", [o isExpandable:a], [o isExpandable:leaf1], [o isItemExpanded:a], (long)[o rowForItem:b], (long)[o rowForItem:leaf1], (long)[o levelForItem:deep]);
  P("expand a\n"); [o expandItem:a]; P("rows %ld: %s\n", (long)o.numberOfRows, rowsOf(o));
  P("expand a again\n"); [o expandItem:a];
  P("parent of deep %s of a %d child index of deep %ld of b %ld children of a %ld\n", [((Node *)[o parentForItem:deep])->name UTF8String], [o parentForItem:a] != nil, (long)[o childIndexForItem:deep], (long)[o childIndexForItem:b],
    (long)[o numberOfChildrenOfItem:a]);
  P("select deep\n"); [o selectRowIndexes:[NSIndexSet indexSetWithIndex:[o rowForItem:deep]] byExtendingSelection:NO];
  P("expand b\n"); [o expandItem:b]; P("rows %s selected %s\n", rowsOf(o), IS(o.selectedRowIndexes));
  P("expand deep with children\n"); [o expandItem:deep expandChildren:YES]; P("rows %s\n", rowsOf(o));
  P("expand sealed\n"); [o expandItem:sealed]; P("expanded %d rows %ld\n", [o isItemExpanded:sealed], (long)o.numberOfRows);
  P("collapse a\n"); [o collapseItem:a]; P("rows %s selected %s deep expanded %d\n", rowsOf(o), IS(o.selectedRowIndexes), [o isItemExpanded:deep]);
  P("expand a (deep was open)\n"); [o expandItem:a]; P("rows %s\n", rowsOf(o));
  P("collapse a with children, expand\n"); [o collapseItem:a collapseChildren:YES]; [o expandItem:a]; P("rows %s\n", rowsOf(o));
  P("expand nil with children\n"); [o expandItem:nil expandChildren:YES]; P("rows %s\n", rowsOf(o));
  P("reload with a changed tree\n"); [a->kids removeObject:leaf1]; [o reloadItem:a reloadChildren:YES]; P("rows %s\n", rowsOf(o));
  P("reloadData keeps expansion: "); [o reloadData]; P("%s\n", rowsOf(o));
  P("frame of cell 0 at row of deeper is indented %d\n", [o frameOfCellAtColumn:0 row:[o rowForItem:deep]].origin.x > [o frameOfCellAtColumn:0 row:0].origin.x);
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    columns(); table(); outlines();
    P("done\n");
  }
  return 0;
}
