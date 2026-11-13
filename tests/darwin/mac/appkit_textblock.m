// NSTextBlock / NSTextTable / NSTextTableBlock model, compared with macOS.
#import <Cocoa/Cocoa.h>
int main(void){ @autoreleasepool { [NSApplication sharedApplication];
  NSTextBlock *b = [[NSTextBlock alloc] init];
  printf("def cw %g/%ld va %ld bg %d\n", [b contentWidth], (long)[b contentWidthValueType], (long)[b verticalAlignment], [b backgroundColor] != nil);
  for (int d = 0; d <= 6; d++) printf("dim%d %g %ld\n", d, [b valueForDimension:d], (long)[b valueTypeForDimension:d]);
  [b setContentWidth:50 type:NSTextBlockPercentageValueType]; printf("cw %g/%ld w-dim %g\n", [b contentWidth], (long)[b contentWidthValueType], [b valueForDimension:NSTextBlockWidth]);
  [b setValue:20 type:NSTextBlockAbsoluteValueType forDimension:NSTextBlockMinimumHeight]; printf("minh %g/%ld\n", [b valueForDimension:NSTextBlockMinimumHeight], (long)[b valueTypeForDimension:NSTextBlockMinimumHeight]);
  [b setWidth:4 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding edge:NSMinXEdge];
  printf("pad minx %g maxx %g\n", [b widthForLayer:NSTextBlockPadding edge:NSMinXEdge], [b widthForLayer:NSTextBlockPadding edge:NSMaxXEdge]);
  [b setWidth:2 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder]; 
  for (int e = 0; e < 4; e++) printf("border e%d %g/%ld\n", e, [b widthForLayer:NSTextBlockBorder edge:e], (long)[b widthValueTypeForLayer:NSTextBlockBorder edge:e]);
  [b setBackgroundColor:[NSColor redColor]]; printf("bg %d\n", [b backgroundColor] != nil);
  [b setBorderColor:[NSColor blueColor]]; for (int e = 0; e < 4; e++) printf("bc e%d %d\n", e, [b borderColorForEdge:e] != nil);
  [b setVerticalAlignment:NSTextBlockMiddleAlignment]; printf("va %ld\n", (long)[b verticalAlignment]);
  NSTextTable *t = [[NSTextTable alloc] init];
  printf("table super %s cols %lu auto %d layout %ld coll %d hide %d\n", [NSStringFromClass([t superclass]) UTF8String], (unsigned long)[t numberOfColumns], [t collapsesBorders], (long)[t layoutAlgorithm], [t collapsesBorders], [t hidesEmptyCells]);
  [t setNumberOfColumns:3]; printf("cols %lu\n", (unsigned long)[t numberOfColumns]);
  NSTextTableBlock *tb = [[NSTextTableBlock alloc] initWithTable:t startingRow:1 rowSpan:2 startingColumn:0 columnSpan:3];
  printf("tb row %ld/%ld col %ld/%ld table %d\n", (long)[tb startingRow], (long)[tb rowSpan], (long)[tb startingColumn], (long)[tb columnSpan], [tb table] == t);
  NSTextContainer *c = [[NSTextContainer alloc] initWithSize:NSMakeSize(200, 1e6)];
  NSRect r = [b rectForLayoutAtPoint:NSMakePoint(0, 0) inRect:NSMakeRect(0, 0, 200, 100) textContainer:c characterRange:NSMakeRange(0, 5)];
  printf("layout rect w>0=%d h>=0=%d\n", r.size.width > 0, r.size.height >= 0);
  NSRect br = [b boundsRectForContentRect:NSMakeRect(10, 10, 100, 20) inRect:NSMakeRect(0, 0, 200, 100) textContainer:c characterRange:NSMakeRange(0, 5)];
  printf("bounds %g %g %g %g\n", br.origin.x, br.origin.y, br.size.width, br.size.height);
  NSTextBlock *copy = [b copy]; printf("copy cw %g bgcopy %d\n", [copy contentWidth], [copy backgroundColor] != nil);
  return 0; } }
