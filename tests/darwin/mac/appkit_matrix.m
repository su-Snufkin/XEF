// NSMatrix: construction, modes, selection rules, geometry and row / column edits. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *R(NSRect r) { return [[NSString stringWithFormat:@"{%g,%g,%g,%g}", r.origin.x, r.origin.y, r.size.width, r.size.height] UTF8String]; }
static const char *SZ(NSSize s) { return [[NSString stringWithFormat:@"{%g,%g}", s.width, s.height] UTF8String]; }
@interface T : NSObject { @public int clicks; }
- (void)act:(id)s;
@end
@implementation T
- (void)act:(id)s { clicks++; P("  action from %s selectedRow %ld col %ld\n", [[s className] UTF8String], (long)[(NSMatrix *)s selectedRow], (long)[(NSMatrix *)s selectedColumn]); }
@end
static const char *tags(NSMatrix *m) { NSMutableArray *a = [NSMutableArray array]; for (NSCell *c in m.cells) [a addObject:@(c.tag)]; return [[a componentsJoinedByString:@","] UTF8String]; }
static const char *titles(NSMatrix *m) { NSMutableArray *a = [NSMutableArray array]; for (NSCell *c in m.cells) [a addObject:c.title]; return [[a componentsJoinedByString:@","] UTF8String]; }
int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    P("== construction\n");
    NSButtonCell *proto = [[NSButtonCell alloc] init]; [proto setButtonType:NSButtonTypeRadio]; proto.title = @"Opt";
    NSMatrix *m = [[NSMatrix alloc] initWithFrame:NSMakeRect(0, 0, 200, 60) mode:NSRadioModeMatrix prototype:proto numberOfRows:3 numberOfColumns:2];
    P("rows %ld cols %ld mode %ld cells %ld cellClass %s prototype %d allowsEmpty %d selectedCell %d selectedRow %ld selectedColumn %ld\n", (long)m.numberOfRows, (long)m.numberOfColumns, (long)m.mode, (long)m.cells.count,
      [NSStringFromClass(m.cellClass) UTF8String], m.prototype != nil, m.allowsEmptySelection, m.selectedCell != nil, (long)m.selectedRow, (long)m.selectedColumn);
    m.cellSize = NSMakeSize(44.5, 16);   // text metrics differ between platforms: sizes are set, not measured
    P("spacing %s autosizes %d flipped %d frame %s\n", SZ(m.intercellSpacing), m.autosizesCells, m.isFlipped, R(m.frame));
    P("cell 0,0 title '%s' tag %ld; 2,1 %s\n", [[m cellAtRow:0 column:0].title UTF8String], (long)[m cellAtRow:0 column:0].tag, [[m cellAtRow:2 column:1].title UTF8String]);
    P("cellAtRow out of range %d\n", [m cellAtRow:5 column:0] == nil);
    P("cell frames: 0,0 %s 1,1 %s 2,1 %s\n", R([m cellFrameAtRow:0 column:0]), R([m cellFrameAtRow:1 column:1]), R([m cellFrameAtRow:2 column:1]));
    NSInteger r, c; BOOL hit = [m getRow:&r column:&c forPoint:NSMakePoint(150, 25)]; P("point 150,25: %d row %ld col %ld\n", hit, (long)r, (long)c);
    hit = [m getRow:&r column:&c forPoint:NSMakePoint(500, 25)]; P("point outside: %d\n", hit);
    hit = [m getRow:&r column:&c ofCell:[m cellAtRow:2 column:0]]; P("cell location %d %ld,%ld\n", hit, (long)r, (long)c);
    P("== selection\n");
    int tag = 10; for (NSCell *cell in m.cells) cell.tag = tag++;
    for (NSInteger i = 0; i < 6; i++) [m cellAtRow:i / 2 column:i % 2].title = [NSString stringWithFormat:@"c%ld", (long)i];
    P("titles %s tags %s\n", titles(m), tags(m));
    [m selectCellAtRow:1 column:1]; P("select 1,1: row %ld col %ld tag %ld state %ld title %s\n", (long)m.selectedRow, (long)m.selectedColumn, (long)m.selectedCell.tag, (long)m.selectedCell.state, [m.selectedCell.title UTF8String]);
    [m selectCellAtRow:0 column:0]; P("radio select 0,0: previous state %ld new state %ld selectedCells %ld\n", (long)[m cellAtRow:1 column:1].state, (long)[m cellAtRow:0 column:0].state, (long)m.selectedCells.count);
    P("selectCellWithTag 14: %d row %ld col %ld; tag 99: %d\n", [m selectCellWithTag:14], (long)m.selectedRow, (long)m.selectedColumn, [m selectCellWithTag:99]);
    P("cellWithTag 12 is c2 %d\n", [[m cellWithTag:12].title isEqual:@"c2"]);
    P("selectCellWithTag keeps row %ld\n", (long)m.selectedRow);
    [m deselectAllCells]; P("deselectAll: selectedCell %d row %ld allowsEmpty %d state of 2,1 %ld\n", m.selectedCell != nil, (long)m.selectedRow, m.allowsEmptySelection, (long)[m cellAtRow:2 column:1].state);
    m.allowsEmptySelection = NO; [m selectCellAtRow:1 column:0]; [m deselectAllCells]; P("empty not allowed: row %ld col %ld\n", (long)m.selectedRow, (long)m.selectedColumn);
    m.allowsEmptySelection = YES; [m deselectAllCells];
    [m selectCellAtRow:5 column:5]; P("select out of range: row %ld\n", (long)m.selectedRow);
    P("== modes\n");
    NSMatrix *l = [[NSMatrix alloc] initWithFrame:NSMakeRect(0, 0, 100, 60) mode:NSListModeMatrix cellClass:[NSTextFieldCell class] numberOfRows:4 numberOfColumns:1];
    P("list mode %ld rows %ld cellClass %s selectedCell %d\n", (long)l.mode, (long)l.numberOfRows, [NSStringFromClass(l.cellClass) UTF8String], l.selectedCell != nil);
    [l selectCellAtRow:1 column:0]; [l selectCellAtRow:2 column:0]; P("list: selected cells %ld (select replaces) selectedRow %ld\n", (long)l.selectedCells.count, (long)l.selectedRow);
    [l selectAll:nil]; P("select all: %ld cells selected\n", (long)l.selectedCells.count);
    NSMatrix *h = [[NSMatrix alloc] initWithFrame:NSMakeRect(0, 0, 100, 60) mode:NSHighlightModeMatrix cellClass:[NSButtonCell class] numberOfRows:1 numberOfColumns:3]; P("highlight mode %ld cellClass %s\n", (long)h.mode, [NSStringFromClass(h.cellClass) UTF8String]);
    m.mode = NSTrackModeMatrix; P("mode changed to %ld\n", (long)m.mode);
    P("== geometry and edits\n");
    NSMatrix *g = [[NSMatrix alloc] initWithFrame:NSMakeRect(0, 0, 300, 100) mode:NSRadioModeMatrix cellClass:[NSButtonCell class] numberOfRows:2 numberOfColumns:3];
    P("frame %s\n", R(g.frame));
    g.cellSize = NSMakeSize(50, 20); g.intercellSpacing = NSMakeSize(4, 2); P("set cellSize 50x20 spacing 4x2: frame %s cell 1,2 %s\n", R(g.frame), R([g cellFrameAtRow:1 column:2]));
    [g sizeToCells]; P("sizeToCells: frame %s\n", R(g.frame));
    g.autosizesCells = YES; [g setFrameSize:NSMakeSize(308, 200)]; P("autosizes + resized: cellSize %s\n", SZ(g.cellSize));
    [g addRow]; P("addRow: rows %ld cells %ld\n", (long)g.numberOfRows, (long)g.cells.count);
    [g insertRow:0]; P("insertRow 0: rows %ld\n", (long)g.numberOfRows); [g removeRow:0]; P("removeRow: rows %ld\n", (long)g.numberOfRows);
    [g addColumn]; P("addColumn: cols %ld cells %ld\n", (long)g.numberOfColumns, (long)g.cells.count);
    [g renewRows:2 columns:2]; P("renew 2x2: rows %ld cols %ld cells %ld\n", (long)g.numberOfRows, (long)g.numberOfColumns, (long)g.cells.count);
    [g putCell:[[NSButtonCell alloc] initTextCell:@"put"] atRow:0 column:1]; P("putCell: title %s\n", [[g cellAtRow:0 column:1].title UTF8String]);
    [g removeColumn:0]; P("removeColumn: cols %ld\n", (long)g.numberOfColumns);
    P("== target and action\n");
    T *t = [[T alloc] init]; m.target = t; m.action = @selector(act:); m.doubleAction = @selector(act:); P("target %d action %d doubleAction %d tag %ld enabled %d\n", m.target == t, m.action != NULL, m.doubleAction != NULL, (long)m.tag, m.isEnabled);
    [m sendAction]; [m selectCellAtRow:2 column:0]; [m sendAction]; P("clicks %d\n", t->clicks);
    P("cell action overrides: "); NSButtonCell *c1 = [m cellAtRow:1 column:0]; P("%d\n", c1.action == NULL);
    NSMatrix *e = [[NSMatrix alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)]; P("empty matrix rows %ld cols %ld mode %ld cellClass %s\n", (long)e.numberOfRows, (long)e.numberOfColumns, (long)e.mode, [NSStringFromClass(e.cellClass) UTF8String]);
    P("done\n");
  }
  return 0;
}
