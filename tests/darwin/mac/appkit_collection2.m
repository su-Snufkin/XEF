// NSCollectionView: background view, legacy selectionIndexes / content, supplementary views, prefetch data source, moves. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface Item : NSCollectionViewItem @end
@implementation Item - (void)loadView { self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)]; } @end
@interface DS : NSObject <NSCollectionViewDataSource> @end
@implementation DS
- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)cv { return 1; }
- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)s { return 5; }
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv itemForRepresentedObjectAtIndexPath:(NSIndexPath *)ip { return [cv makeItemWithIdentifier:@"cell" forIndexPath:ip]; }
@end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  NSCollectionView *cv = [[NSCollectionView alloc] initWithFrame:NSMakeRect(0, 0, 320, 400)]; [w.contentView addSubview:cv];
  DS *ds = [DS new]; cv.dataSource = ds; [cv registerClass:[Item class] forItemWithIdentifier:@"cell"];
  P("defaults: background nil %d scrollsWithContent %d prefetch nil %d content count %lu\n", cv.backgroundView == nil, cv.backgroundViewScrollsWithContent, cv.prefetchDataSource == nil, (unsigned long)cv.content.count);
  NSView *bg = [[NSView alloc] initWithFrame:NSZeroRect]; cv.backgroundView = bg; P("background set %d\n", cv.backgroundView == bg);
  cv.backgroundViewScrollsWithContent = YES; P("scrolls %d\n", cv.backgroundViewScrollsWithContent);
  cv.selectable = YES; cv.allowsMultipleSelection = YES; [cv reloadData];
  P("isFirstResponder %d\n", cv.isFirstResponder);
  NSCollectionViewLayoutAttributes *sa = [cv.collectionViewLayout layoutAttributesForSupplementaryViewOfKind:NSCollectionElementKindSectionHeader atIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]]; P("header attrs nil %d\n", sa == nil);
  P("visible supplementary %lu\n", (unsigned long)[cv visibleSupplementaryViewsOfKind:NSCollectionElementKindSectionHeader].count);
  P("supplementary paths %lu\n", (unsigned long)[cv indexPathsForVisibleSupplementaryElementsOfKind:NSCollectionElementKindSectionHeader].count);
  P("supplementaryView nil %d\n", [cv supplementaryViewForElementKind:NSCollectionElementKindSectionHeader atIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]] == nil);
  [cv setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES]; P("drag mask ok\n");
  P("PASS appkit_collection2\n");
  fflush(stdout); _exit(0);
} return 0; }
