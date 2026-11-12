// NSMatrix: row/column edits with cells, sorting, state, sendAction to all cells, background, tool tips, delegate, key cell. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface T : NSObject { @public int hits; } - (void)act:(id)s; @end
@implementation T - (void)act:(id)s { hits++; } @end
static NSButtonCell *bc(NSString *t) { NSButtonCell *c = [[NSButtonCell alloc] initTextCell:t]; [c setButtonType:NSButtonTypeSwitch]; return c; }
static const char *titles(NSMatrix *m) { NSMutableArray *a = [NSMutableArray array]; for (NSCell *c in m.cells) [a addObject:c.title]; return [[a componentsJoinedByString:@","] UTF8String]; }
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSMatrix *m = [[NSMatrix alloc] initWithFrame:NSMakeRect(0, 0, 200, 80) mode:NSListModeMatrix cellClass:[NSButtonCell class] numberOfRows:2 numberOfColumns:2];
  int i = 0; for (NSCell *c in m.cells) { c.title = [NSString stringWithFormat:@"c%d", i++]; }
  NSInteger r = -1, c = -1; [m getNumberOfRows:&r columns:&c]; P("size %ldx%ld titles %s\n", (long)r, (long)c, titles(m));
  [m addRowWithCells:@[bc(@"x0"), bc(@"x1")]]; [m getNumberOfRows:&r columns:&c]; P("addRow -> %ldx%ld titles %s\n", (long)r, (long)c, titles(m));
  [m insertRow:1 withCells:@[bc(@"y0"), bc(@"y1")]]; P("insertRow -> rows %ld titles %s\n", (long)m.numberOfRows, titles(m));
  [m addColumnWithCells:@[bc(@"z0"), bc(@"z1"), bc(@"z2"), bc(@"z3")]]; P("addColumn -> cols %ld titles %s\n", (long)m.numberOfColumns, titles(m));
  [m insertColumn:0 withCells:@[bc(@"w0"), bc(@"w1"), bc(@"w2"), bc(@"w3")]]; P("insertColumn -> cols %ld titles %s\n", (long)m.numberOfColumns, titles(m));
  NSCell *made = [m makeCellAtRow:0 column:0]; P("makeCell class %s\n", [NSStringFromClass([made class]) UTF8String]);
  [m setState:1 atRow:0 column:1]; P("state(0,1) %ld\n", (long)[m cellAtRow:0 column:1].state);
  T *t = [T new]; [m setTarget:t]; 
  [m sendAction:@selector(act:) to:t forAllCells:NO]; P("sendAction (cells share nothing) hits %d\n", t->hits);
  [m sendAction:@selector(act:) to:t forAllCells:YES]; P("sendAction forAllCells hits %d (cells %lu)\n", t->hits, (unsigned long)m.cells.count);
  [m sortUsingSelector:@selector(compare:)]; P("sorted: %s\n", titles(m));
  P("== settings\n");
  P("defaults: drawsBackground %d drawsCellBackground %d scrollable? autoscroll %d autorecalc %d tabTraverses %d validateSize? delegate %d\n", m.drawsBackground, m.drawsCellBackground, m.isAutoscroll, m.autorecalculatesCellSize, m.tabKeyTraversesCells, 0, m.delegate != nil);
  m.drawsBackground = YES; m.backgroundColor = [NSColor redColor]; P("bg %d color ok %d\n", m.drawsBackground, [m.backgroundColor isEqual:[NSColor redColor]]);
  m.drawsCellBackground = YES; m.cellBackgroundColor = [NSColor blueColor]; P("cellBg %d color ok %d\n", m.drawsCellBackground, [m.cellBackgroundColor isEqual:[NSColor blueColor]]);
  m.autoscroll = YES; m.tabKeyTraversesCells = NO; P("autoscroll %d tab %d\n", m.isAutoscroll, m.tabKeyTraversesCells);
  NSCell *k = [m cellAtRow:1 column:1]; m.keyCell = k; P("keyCell set %d\n", m.keyCell == k);
  [m setToolTip:@"tip" forCell:k]; P("tooltip '%s' other %d\n", [[m toolTipForCell:k] UTF8String], [m toolTipForCell:[m cellAtRow:0 column:0]] != nil);
  m.delegate = t; P("delegate set %d\n", m.delegate == t);
  [m selectCellAtRow:0 column:0]; [m setSelectionFrom:0 to:3 anchor:0 highlight:YES]; P("selected after setSelectionFrom %lu\n", (unsigned long)m.selectedCells.count);
  P("PASS appkit_matrix2\n");
  fflush(stdout); _exit(0);
} return 0; }
