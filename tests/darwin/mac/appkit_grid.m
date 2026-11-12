// NSGridView: model (rows, columns, cells, merging) and the frames Auto Layout gives the content views.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *R(NSRect r) { return [[NSString stringWithFormat:@"{%g,%g,%g,%g}", r.origin.x, r.origin.y, r.size.width, r.size.height] UTF8String]; }
@interface Box : NSView { @public NSSize intrinsic; }
@end
@implementation Box
- (NSSize)intrinsicContentSize { return intrinsic; }
@end
static Box *b(CGFloat w, CGFloat h) { Box *x = [[Box alloc] initWithFrame:NSZeroRect]; x->intrinsic = NSMakeSize(w, h); return x; }
int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    P("== model\n");
    NSGridView *g = [NSGridView gridViewWithNumberOfColumns:3 rows:2];
    P("rows %ld cols %ld rowSpacing %g colSpacing %g xPlacement %ld yPlacement %ld rowAlignment %ld\n", (long)g.numberOfRows, (long)g.numberOfColumns, g.rowSpacing, g.columnSpacing, (long)g.xPlacement, (long)g.yPlacement, (long)g.rowAlignment);
    NSGridCell *c = [g cellAtColumnIndex:1 rowIndex:0];
    P("cell: content %d column %d row %d xPlacement %ld yPlacement %ld rowAlignment %ld customPlacement %lu\n", c.contentView != nil, c.column != nil, c.row != nil, (long)c.xPlacement, (long)c.yPlacement, (long)c.rowAlignment, (unsigned long)c.customPlacementConstraints.count);
    NSGridRow *r0 = [g rowAtIndex:0]; NSGridColumn *c0 = [g columnAtIndex:0];
    P("row: height %g hidden %d yPlacement %ld cells %ld; column: width %g hidden %d xPlacement %ld cells %ld\n", r0.height, r0.hidden, (long)r0.yPlacement, (long)r0.numberOfCells, c0.width, c0.hidden, (long)c0.xPlacement, (long)c0.numberOfCells);
    Box *v1 = b(50, 20), *v2 = b(80, 30), *v3 = b(30, 10);
    NSGridRow *added = [g addRowWithViews:@[v1, v2, v3]]; P("add row: rows %ld index %ld cells %ld\n", (long)g.numberOfRows, (long)[g indexOfRow:added], (long)added.numberOfCells);
    P("views added to grid %d superview is grid %d\n", [g.subviews containsObject:v1], v1.superview == g);
    [g insertRowAtIndex:1 withViews:@[b(10, 10)]]; P("insert row at 1: rows %ld row1 cells %ld\n", (long)g.numberOfRows, (long)[g rowAtIndex:1].numberOfCells);
    [g removeRowAtIndex:1]; P("remove row: rows %ld\n", (long)g.numberOfRows);
    [g addColumnWithViews:@[b(5, 5), b(6, 6), b(7, 7)]]; P("add column: cols %ld\n", (long)g.numberOfColumns);
    [g removeColumnAtIndex:3]; P("remove column: cols %ld\n", (long)g.numberOfColumns);
    [g moveRowAtIndex:2 toIndex:0]; P("move row: first row first cell view is v1 %d\n", [g cellAtColumnIndex:0 rowIndex:0].contentView == v1);
    P("== frames\n");
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    NSGridView *h = [NSGridView gridViewWithViews:@[@[b(50, 20), b(80, 30)], @[b(30, 10), b(60, 40)]]];
    h.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:h];
    NSLayoutConstraint *l = [h.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:10], *t = [h.topAnchor constraintEqualToAnchor:root.topAnchor constant:20];
    [NSLayoutConstraint activateConstraints:@[l, t]];
    [root layoutSubtreeIfNeeded];
    P("grid %s fitting %g,%g\n", R(h.frame), h.fittingSize.width, h.fittingSize.height);
    for (int row = 0; row < 2; row++) for (int col = 0; col < 2; col++) P("cell %d,%d %s\n", col, row, R([h cellAtColumnIndex:col rowIndex:row].contentView.frame));
    h.rowSpacing = 10; h.columnSpacing = 4; [root layoutSubtreeIfNeeded];
    P("spacing 10/4: grid %s cell 1,1 %s\n", R(h.frame), R([h cellAtColumnIndex:1 rowIndex:1].contentView.frame));
    h.xPlacement = NSGridCellPlacementTrailing; h.yPlacement = NSGridCellPlacementBottom; [root layoutSubtreeIfNeeded];
    P("trailing/bottom: cell 0,1 %s cell 0,0 %s\n", R([h cellAtColumnIndex:0 rowIndex:1].contentView.frame), R([h cellAtColumnIndex:0 rowIndex:0].contentView.frame));
    h.xPlacement = NSGridCellPlacementCenter; h.yPlacement = NSGridCellPlacementCenter; [root layoutSubtreeIfNeeded];
    P("center: cell 0,1 %s cell 0,0 %s\n", R([h cellAtColumnIndex:0 rowIndex:1].contentView.frame), R([h cellAtColumnIndex:0 rowIndex:0].contentView.frame));
    h.xPlacement = NSGridCellPlacementFill; h.yPlacement = NSGridCellPlacementFill; [root layoutSubtreeIfNeeded];
    P("fill: cell 0,1 %s cell 1,0 %s\n", R([h cellAtColumnIndex:0 rowIndex:1].contentView.frame), R([h cellAtColumnIndex:1 rowIndex:0].contentView.frame));
    [h columnAtIndex:0].width = 100; [root layoutSubtreeIfNeeded]; P("column 0 width 100: cell 0,0 %s cell 1,0 %s grid %s\n", R([h cellAtColumnIndex:0 rowIndex:0].contentView.frame), R([h cellAtColumnIndex:1 rowIndex:0].contentView.frame), R(h.frame));
    [h rowAtIndex:1].height = 70; [root layoutSubtreeIfNeeded]; P("row 1 height 70: cell 1,1 %s grid %s\n", R([h cellAtColumnIndex:1 rowIndex:1].contentView.frame), R(h.frame));
    [h columnAtIndex:1].hidden = YES; [root layoutSubtreeIfNeeded]; P("column 1 hidden: grid %s view hidden %d\n", R(h.frame), [h cellAtColumnIndex:1 rowIndex:0].contentView.hidden);
    [h columnAtIndex:1].hidden = NO; [h rowAtIndex:0].hidden = YES; [root layoutSubtreeIfNeeded]; P("row 0 hidden: grid %s\n", R(h.frame));
    [h rowAtIndex:0].hidden = NO;
    [h mergeCellsInHorizontalRange:NSMakeRange(0, 2) verticalRange:NSMakeRange(0, 1)]; [root layoutSubtreeIfNeeded];
    P("merged top row: cell 0,0 view %s same cell for 1,0 %d\n", R([h cellAtColumnIndex:0 rowIndex:0].contentView.frame), [h cellAtColumnIndex:1 rowIndex:0] == [h cellAtColumnIndex:0 rowIndex:0]);
    NSGridView *e = [NSGridView gridViewWithNumberOfColumns:0 rows:0]; P("empty grid: rows %ld cols %ld\n", (long)e.numberOfRows, (long)e.numberOfColumns);
    P("done\n");
  }
  return 0;
}
