// NSForm / NSFormCell: entries, title widths, fonts, alignments; NSPageController selection. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
#define FC(i) ((NSFormCell *)[f cellAtIndex:i])
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSForm *f = [[NSForm alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
  P("empty: rows %ld\n", (long)f.numberOfRows);
  NSFormCell *a = [f addEntry:@"Name:"]; NSFormCell *b = [f addEntry:@"Email:"]; NSFormCell *c = [f insertEntry:@"Phone:" atIndex:1];
  P("entries %ld titles %s,%s,%s cellAtIndex1 same %d\n", (long)f.numberOfRows, [a.title UTF8String], [FC(1).title UTF8String], [FC(2).title UTF8String], [f cellAtIndex:1] == c);
  P("indexOfCellWithTag: %ld selected %ld\n", (long)[f indexOfCellWithTag:5], (long)f.indexOfSelectedItem);
  a.tag = 5; P("indexOfCellWithTag 5: %ld\n", (long)[f indexOfCellWithTag:5]);
  P("cell defaults: titleAlignment %ld direction %ld preferredWidth %g titleFont nonnil %d\n", (long)a.titleAlignment, (long)a.titleBaseWritingDirection, a.preferredTextFieldWidth, a.titleFont != nil);
  a.titleWidth = 80; a.titleAlignment = NSTextAlignmentLeft; a.preferredTextFieldWidth = 120; P("set: %g %ld %g\n", a.titleWidth, (long)a.titleAlignment, a.preferredTextFieldWidth);
  [f setEntryWidth:200]; [f setInterlineSpacing:3]; [f setTitleAlignment:NSTextAlignmentRight]; [f setBordered:YES]; [f setBezeled:NO];
  P("form setters ok; cell titleAlignment now %ld\n", (long)FC(0).titleAlignment);
  [f removeEntryAtIndex:1]; P("after remove: %ld, second title %s\n", (long)f.numberOfRows, [FC(1).title UTF8String]);
  NSPageController *pc = [[NSPageController alloc] init];
  P("page controller: selectedIndex %ld arranged %lu transition %ld delegate nil %d selectedVC nil %d\n", (long)pc.selectedIndex, (unsigned long)pc.arrangedObjects.count, (long)pc.transitionStyle, pc.delegate == nil, pc.selectedViewController == nil);
  pc.arrangedObjects = @[@"a", @"b", @"c"]; P("after arranged: selected %ld\n", (long)pc.selectedIndex);
  pc.selectedIndex = 2; P("selected %ld\n", (long)pc.selectedIndex);
  pc.transitionStyle = NSPageControllerTransitionStyleHorizontalStrip; P("transition %ld\n", (long)pc.transitionStyle);
  P("PASS appkit_form\n");
  fflush(stdout); _exit(0);
} return 0; }
