// NSScrubber: data source, item views, reuse, selection, modes. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface IV : NSScrubberItemView @end
@implementation IV @end
@interface D : NSObject <NSScrubberDataSource, NSScrubberDelegate> { @public int count; NSMutableArray *log; } @end
@implementation D
- (NSInteger)numberOfItemsForScrubber:(NSScrubber *)s { [log addObject:@"count"]; return count; }
- (NSScrubberItemView *)scrubber:(NSScrubber *)s viewForItemAtIndex:(NSInteger)i { [log addObject:[NSString stringWithFormat:@"view%ld", (long)i]]; return [s makeItemWithIdentifier:@"cell" owner:nil]; }
- (void)scrubber:(NSScrubber *)s didSelectItemAtIndex:(NSInteger)i { [log addObject:[NSString stringWithFormat:@"selected%ld", (long)i]]; }
@end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSScrubber *s = [[NSScrubber alloc] initWithFrame:NSMakeRect(0, 0, 300, 30)];
  P("defaults: items %ld selected %ld highlighted %ld mode %ld alignment %ld continuous %d floats %d arrows %d additional %d\n", (long)s.numberOfItems, (long)s.selectedIndex, (long)s.highlightedIndex, (long)s.mode, (long)s.itemAlignment, s.isContinuous, s.floatsSelectionViews, s.showsArrowButtons, s.showsAdditionalContentIndicators);
  P("layout nil %d dataSource nil %d\n", s.scrubberLayout == nil, s.dataSource == nil);
  D *d = [D new]; d->count = 4; d->log = [NSMutableArray array]; s.dataSource = d; s.delegate = d;
  [s registerClass:[IV class] forItemIdentifier:@"cell"];
  [s reloadData]; P("after reload: items %ld log %s\n", (long)s.numberOfItems, [[d->log componentsJoinedByString:@","] UTF8String]); [d->log removeAllObjects];
  NSScrubberItemView *v = [s itemViewForItemAtIndex:1]; P("itemView %d class %s\n", v != nil, v ? [NSStringFromClass([v class]) UTF8String] : "nil"); P("log %s\n", [[d->log componentsJoinedByString:@","] UTF8String]); [d->log removeAllObjects];
  s.selectedIndex = 2; P("selected %ld log %s\n", (long)s.selectedIndex, [[d->log componentsJoinedByString:@","] UTF8String]); [d->log removeAllObjects];
  s.mode = NSScrubberModeFixed; s.itemAlignment = NSScrubberAlignmentCenter; s.continuous = YES; s.showsArrowButtons = YES; P("set: mode %ld alignment %ld continuous %d arrows %d\n", (long)s.mode, (long)s.itemAlignment, s.isContinuous, s.showsArrowButtons);
  d->count = 2; [s reloadData]; P("reload with 2: items %ld selected %ld\n", (long)s.numberOfItems, (long)s.selectedIndex);
  NSScrubberItemView *made = [s makeItemWithIdentifier:@"cell" owner:nil]; P("makeItem %d class %s\n", made != nil, made ? [NSStringFromClass([made class]) UTF8String] : "nil");
  P("makeItem unregistered %d\n", [s makeItemWithIdentifier:@"nope" owner:nil] != nil);
  NSScrubberFlowLayout *fl = [[NSScrubberFlowLayout alloc] init]; s.scrubberLayout = fl; P("layout set %d\n", s.scrubberLayout == fl);
  P("PASS appkit_scrubber\n");
  fflush(stdout); _exit(0);
} return 0; }
