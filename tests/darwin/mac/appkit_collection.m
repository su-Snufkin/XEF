// NSCollectionView with the flow layout: data source calls, item creation and reuse, layout attributes, selection.
#import <Cocoa/Cocoa.h>
#include <unistd.h>
#define P(...) printf(__VA_ARGS__)
static const char *R(NSRect r) { return [[NSString stringWithFormat:@"{%g,%g,%g,%g}", r.origin.x, r.origin.y, r.size.width, r.size.height] UTF8String]; }
static const char *SZ(NSSize s) { return [[NSString stringWithFormat:@"{%g,%g}", s.width, s.height] UTF8String]; }

@interface Item : NSCollectionViewItem { @public int serial; }
@end
static int g_serial;
@implementation Item
- (void)loadView { self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)]; serial = ++g_serial; }
@end

@interface DS : NSObject <NSCollectionViewDataSource, NSCollectionViewDelegate> { @public NSInteger count; NSMutableArray *log; }
@end
@implementation DS
- (id)init { count = 7; log = [NSMutableArray array]; return self; }
- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)cv { [log addObject:@"sections"]; return 2; }
- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)s { [log addObject:[NSString stringWithFormat:@"count%ld", (long)s]]; return s == 0 ? count : 2; }
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv itemForRepresentedObjectAtIndexPath:(NSIndexPath *)ip {
  [log addObject:[NSString stringWithFormat:@"item%ld.%ld", (long)ip.section, (long)ip.item]];
  Item *it = (Item *)[cv makeItemWithIdentifier:@"cell" forIndexPath:ip]; it.representedObject = @(ip.item); return it; }
- (BOOL)collectionView:(NSCollectionView *)cv shouldSelectItemsAtIndexPaths:(NSSet *)p { [log addObject:@"shouldSelect"]; return YES; }
- (void)collectionView:(NSCollectionView *)cv didSelectItemsAtIndexPaths:(NSSet *)p { [log addObject:[NSString stringWithFormat:@"didSelect%lu", (unsigned long)p.count]]; }
- (void)collectionView:(NSCollectionView *)cv didDeselectItemsAtIndexPaths:(NSSet *)p { [log addObject:[NSString stringWithFormat:@"didDeselect%lu", (unsigned long)p.count]]; }
@end
static void flush(DS *d, const char *what) { P("%s: %s\n", what, [[d->log componentsJoinedByString:@" "] UTF8String]); [d->log removeAllObjects]; }

int main(void) {
  setvbuf(stdout, NULL, _IONBF, 0);
  @autoreleasepool {
    [NSApplication sharedApplication];
    P("== defaults\n");
    NSCollectionView *cv = [[NSCollectionView alloc] initWithFrame:NSMakeRect(0, 0, 320, 400)];
    P("selectable %d allowsMultiple %d allowsEmpty %d layout %s sections %ld isFirstResponder %d backgroundColors %ld content nil %d\n", cv.selectable, cv.allowsMultipleSelection, cv.allowsEmptySelection, [NSStringFromClass([cv.collectionViewLayout class]) UTF8String],
      (long)cv.numberOfSections, cv.acceptsFirstResponder, (long)cv.backgroundColors.count, cv.dataSource == nil);
    NSCollectionViewFlowLayout *fl = [[NSCollectionViewFlowLayout alloc] init];
    P("flow defaults: itemSize %s minLineSpacing %g minInteritemSpacing %g direction %ld insets %g,%g,%g,%g headerSize %s footerSize %s estimated %s sectionHeadersPinned %d\n", SZ(fl.itemSize), fl.minimumLineSpacing, fl.minimumInteritemSpacing, (long)fl.scrollDirection,
      fl.sectionInset.top, fl.sectionInset.left, fl.sectionInset.bottom, fl.sectionInset.right, SZ(fl.headerReferenceSize), SZ(fl.footerReferenceSize), SZ(fl.estimatedItemSize), fl.sectionHeadersPinToVisibleBounds);
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 320, 400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    NSScrollView *sc = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 320, 400)]; sc.hasVerticalScroller = YES; sc.documentView = cv; win.contentView = sc;
    P("== layout\n");
    fl.itemSize = NSMakeSize(80, 60); fl.minimumLineSpacing = 10; fl.minimumInteritemSpacing = 6; fl.sectionInset = NSEdgeInsetsMake(8, 12, 8, 12);
    cv.collectionViewLayout = fl; P("layout set: layout is fl %d\n", cv.collectionViewLayout == fl);
    DS *ds = [[DS alloc] init]; cv.dataSource = ds; cv.delegate = ds; cv.selectable = YES;
    [cv registerClass:[Item class] forItemWithIdentifier:@"cell"];
    P("data source set, log: %s\n", [[ds->log componentsJoinedByString:@" "] UTF8String]); [ds->log removeAllObjects];
    [cv reloadData]; flush(ds, "reloadData"); [win orderFront:nil]; [win layoutIfNeeded]; [cv layoutSubtreeIfNeeded]; [cv displayIfNeeded]; flush(ds, "after layout");
    P("sections %ld items in 0: %ld in 1: %ld\n", (long)cv.numberOfSections, (long)[cv numberOfItemsInSection:0], (long)[cv numberOfItemsInSection:1]); flush(ds, "counts");
    NSSize cs = fl.collectionViewContentSize; P("content size %s\n", SZ(cs));
    for (NSInteger i = 0; i < 7; i++) { NSCollectionViewLayoutAttributes *a = [fl layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]]; P("item %ld frame %s\n", (long)i, R(a.frame)); }
    NSCollectionViewLayoutAttributes *s1 = [fl layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:1]]; P("section 1 item 0 frame %s\n", R(s1.frame));
    NSArray *vis = [fl layoutAttributesForElementsInRect:NSMakeRect(0, 0, 320, 100)]; P("elements in top 100pt: %lu\n", (unsigned long)vis.count);
    P("== items\n");
    NSCollectionViewItem *it = [cv itemAtIndexPath:[NSIndexPath indexPathForItem:2 inSection:0]]; P("itemAtIndexPath 2 non-nil %d class %s frame %s represented %s\n", it != nil, it ? [NSStringFromClass([it class]) UTF8String] : "-", it ? R(it.view.frame) : "-", it ? [[it.representedObject description] UTF8String] : "-");
    flush(ds, "after itemAt");
    P("visibleItems %lu\n", (unsigned long)cv.visibleItems.count); flush(ds, "after visibleItems");
    P("== selection\n");
    NSIndexPath *a = [NSIndexPath indexPathForItem:1 inSection:0], *b = [NSIndexPath indexPathForItem:3 inSection:0];
    cv.selectionIndexPaths = [NSSet setWithObject:a]; P("select 1: paths %lu item selected %d\n", (unsigned long)cv.selectionIndexPaths.count, [cv itemAtIndexPath:a].selected); flush(ds, "log");
    cv.selectionIndexPaths = [NSSet setWithObject:b]; P("select 3: paths %lu old selected %d new selected %d\n", (unsigned long)cv.selectionIndexPaths.count, [cv itemAtIndexPath:a].selected, [cv itemAtIndexPath:b].selected); flush(ds, "log");
    cv.allowsMultipleSelection = YES; [cv selectItemsAtIndexPaths:[NSSet setWithObject:a] scrollPosition:NSCollectionViewScrollPositionNone]; P("multiple: paths %lu\n", (unsigned long)cv.selectionIndexPaths.count); flush(ds, "log");
    [cv deselectItemsAtIndexPaths:[NSSet setWithObject:a]]; P("deselect: paths %lu\n", (unsigned long)cv.selectionIndexPaths.count); flush(ds, "log");
    [cv deselectAll:nil]; P("deselectAll: paths %lu\n", (unsigned long)cv.selectionIndexPaths.count); flush(ds, "log");
    P("== data changes\n");
    ds->count = 3; [cv reloadData]; flush(ds, "reload with 3"); [win layoutIfNeeded]; [cv layoutSubtreeIfNeeded]; flush(ds, "after layout");
    P("items in 0: %ld content size %s visibleItems %lu\n", (long)[cv numberOfItemsInSection:0], SZ(fl.collectionViewContentSize), (unsigned long)cv.visibleItems.count);
    NSIndexPath *ip = [NSIndexPath indexPathForItem:2 inSection:1]; P("indexPath section %ld item %ld length %lu\n", (long)ip.section, (long)ip.item, (unsigned long)ip.length);
    fl.itemSize = NSMakeSize(120, 40); [fl invalidateLayout]; [win layoutIfNeeded]; [cv layoutSubtreeIfNeeded];
    P("itemSize 120x40: content size %s item 1 frame %s item 2 frame %s\n", SZ(fl.collectionViewContentSize), R([fl layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0]].frame), R([fl layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:2 inSection:0]].frame));
    fl.scrollDirection = NSCollectionViewScrollDirectionHorizontal; [fl invalidateLayout]; [win layoutIfNeeded]; [cv layoutSubtreeIfNeeded];
    P("horizontal: content size %s item 1 frame %s item 2 frame %s\n", SZ(fl.collectionViewContentSize), R([fl layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0]].frame), R([fl layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:2 inSection:0]].frame));
    P("done\n");
  }
  _exit(0);
}
