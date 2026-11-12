// NSToolbar / NSToolbarItem, NSPopover, NSAnimation, NSArrayController / NSObjectController, NSGridView without a visible
// window: defaults, delegate call order, state rules. Real AppKit's output is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *R(NSRect r) { return [[NSString stringWithFormat:@"{%g,%g,%g,%g}", r.origin.x, r.origin.y, r.size.width, r.size.height] UTF8String]; }
static const char *J(NSArray *a) { return [[a componentsJoinedByString:@","] UTF8String]; }

@interface TBD : NSObject <NSToolbarDelegate>
@end
@implementation TBD
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)t { return @[@"new", @"open", NSToolbarFlexibleSpaceItemIdentifier, @"save"]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)t { return @[@"new", @"open", @"save", @"extra", NSToolbarSpaceItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier]; }
- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)t { return @[@"open", @"save"]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)t itemForItemIdentifier:(NSString *)i willBeInsertedIntoToolbar:(BOOL)flag {
  P("  itemForItemIdentifier %s inserted %d\n", [i UTF8String], flag);
  NSToolbarItem *it = [[NSToolbarItem alloc] initWithItemIdentifier:i]; it.label = [i capitalizedString]; return it; }
- (void)toolbarWillAddItem:(NSNotification *)n { P("  willAddItem %s\n", [[n.userInfo[@"item"] itemIdentifier] UTF8String]); }
- (void)toolbarDidRemoveItem:(NSNotification *)n { P("  didRemoveItem %s\n", [[n.userInfo[@"item"] itemIdentifier] UTF8String]); }
@end

static void toolbar(void) {
  P("== NSToolbar\n");
  NSToolbar *t = [[NSToolbar alloc] initWithIdentifier:@"main"];
  P("defaults id %s displayMode %ld sizeMode %ld visible %d customizes %d autosaves %d baseline %d items %ld visibleItems %ld selected %d delegate %d customizationPaletteIsRunning %d allowsExtension %d\n", [t.identifier UTF8String],
    (long)t.displayMode, (long)t.sizeMode, t.visible, t.allowsUserCustomization, t.autosavesConfiguration, t.showsBaselineSeparator, (long)t.items.count, (long)t.visibleItems.count, t.selectedItemIdentifier != nil,
    t.delegate != nil, t.customizationPaletteIsRunning, t.allowsExtensionItems);
  TBD *d = [[TBD alloc] init];
  P("set delegate\n"); t.delegate = d;
  P("items after delegate %ld\n", (long)t.items.count);
  NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
  P("attach to window\n"); w.toolbar = t;
  P("toolbar of window is t %d items %ld: %s\n", w.toolbar == t, (long)t.items.count, J([t.items valueForKey:@"itemIdentifier"]));
  P("labels %s\n", J([t.items valueForKey:@"label"]));
  P("insert extra at 1\n"); [t insertItemWithItemIdentifier:@"extra" atIndex:1];
  P("items: %s\n", J([t.items valueForKey:@"itemIdentifier"]));
  P("remove index 0\n"); [t removeItemAtIndex:0];
  P("items: %s\n", J([t.items valueForKey:@"itemIdentifier"]));
  P("select open\n"); t.selectedItemIdentifier = @"open"; P("selected %s\n", [t.selectedItemIdentifier UTF8String]);
  t.selectedItemIdentifier = @"extra"; P("select non-selectable: %s\n", [t.selectedItemIdentifier UTF8String]);
  t.visible = NO; P("visible %d\n", t.visible); t.displayMode = NSToolbarDisplayModeIconOnly; t.sizeMode = NSToolbarSizeModeSmall; P("mode %ld size %ld\n", (long)t.displayMode, (long)t.sizeMode);
  P("remove all\n"); while (t.items.count) [t removeItemAtIndex:0]; P("items %ld\n", (long)t.items.count);
  P("identifiers: space %s flex %s separator %s customize %s print %s\n", [NSToolbarSpaceItemIdentifier UTF8String], [NSToolbarFlexibleSpaceItemIdentifier UTF8String], [NSToolbarSeparatorItemIdentifier UTF8String],
    [NSToolbarCustomizeToolbarItemIdentifier UTF8String], [NSToolbarPrintItemIdentifier UTF8String]);

  P("== NSToolbarItem\n");
  NSToolbarItem *i = [[NSToolbarItem alloc] initWithItemIdentifier:@"x"];
  P("defaults id %s label '%s' palette '%s' tip %d tag %ld enabled %d view %d min %g,%g max %g,%g priority %ld action %d target %d image %d bordered %d autovalidates %d menu %d navigational %d toolbar %d\n", [i.itemIdentifier UTF8String],
    [i.label UTF8String], [i.paletteLabel UTF8String], i.toolTip != nil, (long)i.tag, i.enabled, i.view != nil, i.minSize.width, i.minSize.height, i.maxSize.width, i.maxSize.height, (long)i.visibilityPriority,
    i.action != NULL, i.target != nil, i.image != nil, i.bordered, i.autovalidates, i.menuFormRepresentation != nil, i.navigational, i.toolbar != nil);
  i.label = @"Hello"; P("label set: label %s palette %s\n", [i.label UTF8String], [i.paletteLabel UTF8String]);
  i.paletteLabel = @"Pal"; i.toolTip = @"tip"; i.tag = 7; i.enabled = NO; i.minSize = NSMakeSize(10, 20); i.maxSize = NSMakeSize(30, 40);
  P("after: palette %s tip %s tag %ld enabled %d min %g,%g max %g,%g\n", [i.paletteLabel UTF8String], [i.toolTip UTF8String], (long)i.tag, i.enabled, i.minSize.width, i.minSize.height, i.maxSize.width, i.maxSize.height);
  NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 50, 30)]; i.view = v; P("view set: view %d min %g,%g max %g,%g\n", i.view == v, i.minSize.width, i.minSize.height, i.maxSize.width, i.maxSize.height);
  NSToolbarItem *c = [i copy]; P("copy: id %s label %s tag %ld\n", [c.itemIdentifier UTF8String], [c.label UTF8String], (long)c.tag);
  NSToolbarItemGroup *g = [[NSToolbarItemGroup alloc] initWithItemIdentifier:@"grp"]; P("group: subitems %ld selectionMode %ld selectedIndex %ld controlRepresentation %ld\n", (long)g.subitems.count, (long)g.selectionMode, (long)g.selectedIndex, (long)g.controlRepresentation);
  g.subitems = @[[[NSToolbarItem alloc] initWithItemIdentifier:@"s1"], [[NSToolbarItem alloc] initWithItemIdentifier:@"s2"]]; P("subitems %ld first %s\n", (long)g.subitems.count, [[g.subitems[0] itemIdentifier] UTF8String]);
}

@interface AD : NSObject <NSAnimationDelegate> { @public double lastProgress; }
@end
@implementation AD
- (BOOL)animationShouldStart:(NSAnimation *)a { P("  shouldStart\n"); return YES; }
- (void)animationDidEnd:(NSAnimation *)a { P("  didEnd progress %g\n", a.currentProgress); }
- (void)animationDidStop:(NSAnimation *)a { P("  didStop\n"); }
- (void)animation:(NSAnimation *)a didReachProgressMark:(NSAnimationProgress)p { P("  mark %g\n", p); }
@end
@interface AD2 : NSObject <NSAnimationDelegate>
@end
@implementation AD2
- (float)animation:(NSAnimation *)a valueForProgress:(NSAnimationProgress)p { return p * p; }
@end

static void animation(void) {
  P("== NSAnimation\n");
  NSAnimation *a = [[NSAnimation alloc] initWithDuration:0.1 animationCurve:NSAnimationLinear];
  P("defaults duration %g curve %ld frameRate %g blocking %ld progress %g value %g animating %d marks %ld delegate %d\n", a.duration, (long)a.animationCurve, a.frameRate, (long)a.animationBlockingMode, a.currentProgress, a.currentValue,
    a.isAnimating, (long)a.progressMarks.count, a.delegate != nil);
  AD *d = [[AD alloc] init]; a.delegate = d; a.animationBlockingMode = NSAnimationBlocking; a.progressMarks = @[@0.5, @0.25];
  P("marks %s\n", J(a.progressMarks)); [a addProgressMark:0.75]; P("marks %s\n", J(a.progressMarks)); [a removeProgressMark:0.25]; P("marks %s\n", J(a.progressMarks));
  P("start (blocking)\n"); [a startAnimation]; P("done: progress %g value %g animating %d\n", a.currentProgress, a.currentValue, a.isAnimating);
  a.currentProgress = 0.3; P("set progress 0.3: value %g\n", a.currentValue);
  NSAnimation *e = [[NSAnimation alloc] initWithDuration:1 animationCurve:NSAnimationEaseIn]; e.currentProgress = 0.5; P("ease in at 0.5: %g\n", e.currentValue);
  e.animationCurve = NSAnimationEaseOut; P("ease out at 0.5: %g at 0.25 %g\n", e.currentValue, (e.currentProgress = 0.25, e.currentValue));
  e.animationCurve = NSAnimationEaseInOut; e.currentProgress = 0.25; P("ease in-out at 0.25: %g at 0.75 %g\n", e.currentValue, (e.currentProgress = 0.75, e.currentValue));
  e.currentProgress = 5; P("clamped high: %g\n", e.currentProgress); e.currentProgress = -1; P("clamped low: %g\n", e.currentProgress);
  NSAnimation *z = [[NSAnimation alloc] initWithDuration:0 animationCurve:NSAnimationLinear]; z.animationBlockingMode = NSAnimationBlocking; z.delegate = d; P("zero duration\n"); [z startAnimation]; P("progress %g\n", z.currentProgress);
}

static const char *IS(NSIndexSet *s) { NSMutableArray *a = [NSMutableArray array]; [s enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *st) { [a addObject:@(i)]; }]; return [[NSString stringWithFormat:@"[%@]", [a componentsJoinedByString:@","]] UTF8String]; }
static NSMutableDictionary *row(NSString *n, int age) { return [NSMutableDictionary dictionaryWithObjectsAndKeys:n, @"name", @(age), @"age", nil]; }
static void controllers(void) {
  P("== NSArrayController\n");
  NSMutableArray *rows = [NSMutableArray arrayWithObjects:row(@"carol", 3), row(@"alice", 7), row(@"bob", 5), nil];
  NSArrayController *c = [[NSArrayController alloc] initWithContent:rows];
  P("defaults editable %d preserveSelection %d selectsInserted %d avoidsEmpty %d clearsFilter %d autoRearranges %d canAdd %d canRemove %d canInsert %d canSelectNext %d canSelectPrevious %d\n", c.isEditable,
    c.preservesSelection, c.selectsInsertedObjects, c.avoidsEmptySelection, c.clearsFilterPredicateOnInsertion, c.automaticallyRearrangesObjects, c.canAdd, c.canRemove, c.canInsert, c.canSelectNext, c.canSelectPrevious);
  P("content %ld arranged %ld selectionIndex %ld indexes %s selected %ld objectClass %s sort %ld filter %d\n", (long)[c.content count], (long)[c.arrangedObjects count], (long)c.selectionIndex, IS(c.selectionIndexes),
    (long)c.selectedObjects.count, [NSStringFromClass(c.objectClass) UTF8String], (long)c.sortDescriptors.count, c.filterPredicate != nil);
  P("arranged names: %s\n", J([c.arrangedObjects valueForKey:@"name"]));
  c.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]; P("sorted: %s selection %s\n", J([c.arrangedObjects valueForKey:@"name"]), IS(c.selectionIndexes));
  c.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"age" ascending:NO]]; P("by age desc: %s selection %s\n", J([c.arrangedObjects valueForKey:@"name"]), IS(c.selectionIndexes));
  c.filterPredicate = [NSPredicate predicateWithFormat:@"age > 3"]; P("filtered: %s content still %ld selection %s\n", J([c.arrangedObjects valueForKey:@"name"]), (long)[c.content count], IS(c.selectionIndexes));
  c.filterPredicate = nil; P("unfiltered: %ld\n", (long)[c.arrangedObjects count]);
  [c setSelectionIndex:1]; P("selectionIndex 1: %s next %d prev %d selectedObjects %s\n", J([c.selectedObjects valueForKey:@"name"]), c.canSelectNext, c.canSelectPrevious, J([c.selectedObjects valueForKey:@"name"]));
  [c setSelectionIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]]; P("two selected: indexes %s count %ld selectionIndex %ld\n", IS(c.selectionIndexes), (long)c.selectedObjects.count, (long)c.selectionIndex);
  [c setSelectionIndex:NSNotFound]; P("cleared: %s\n", IS(c.selectionIndexes));
  id sel = c.selection; [c setSelectionIndex:0]; P("selection proxy name %s age %s\n", [[[c selection] valueForKey:@"name"] UTF8String], [[[[c selection] valueForKey:@"age"] description] UTF8String]);
  P("add object\n"); [c addObject:row(@"dave", 9)]; P("content %ld arranged %s selection %s\n", (long)[c.content count], J([c.arrangedObjects valueForKey:@"name"]), IS(c.selectionIndexes));
  P("insert at 0\n"); [c insertObject:row(@"zed", 1) atArrangedObjectIndex:0]; P("arranged %s selection %s\n", J([c.arrangedObjects valueForKey:@"name"]), IS(c.selectionIndexes));
  P("remove selected\n"); [c removeObjectsAtArrangedObjectIndexes:c.selectionIndexes]; P("arranged %s selection %s content %ld\n", J([c.arrangedObjects valueForKey:@"name"]), IS(c.selectionIndexes), (long)[c.content count]);
  P("remove object\n"); [c removeObject:c.arrangedObjects[0]]; P("arranged %s selection %s\n", J([c.arrangedObjects valueForKey:@"name"]), IS(c.selectionIndexes));
  c.automaticallyRearrangesObjects = YES; c.avoidsEmptySelection = YES; [c setSelectionIndexes:[NSIndexSet indexSet]]; P("avoids empty: %s\n", IS(c.selectionIndexes));
  c.content = @[row(@"x", 1), row(@"y", 2)]; P("new content: arranged %s selection %s\n", J([c.arrangedObjects valueForKey:@"name"]), IS(c.selectionIndexes));
  c.sortDescriptors = nil; c.editable = NO; P("not editable: canAdd %d canRemove %d\n", c.canAdd, c.canRemove);
  NSArrayController *e = [[NSArrayController alloc] init]; P("empty: content %d arranged %ld canRemove %d selectionIndex %ld\n", e.content != nil, (long)[e.arrangedObjects count], e.canRemove, (long)e.selectionIndex);
  P("== NSObjectController\n");
  NSObjectController *o = [[NSObjectController alloc] initWithContent:row(@"solo", 4)];
  P("content %d selection name %s selectedObjects %ld objectClass %s editable %d canAdd %d canRemove %d automaticallyPreparesContent %d\n", o.content != nil, [[[o selection] valueForKey:@"name"] UTF8String],
    (long)o.selectedObjects.count, [NSStringFromClass(o.objectClass) UTF8String], o.isEditable, o.canAdd, o.canRemove, o.automaticallyPreparesContent);
  [o setContent:nil]; P("cleared: content %d selectedObjects %ld canRemove %d\n", o.content != nil, (long)o.selectedObjects.count, o.canRemove);
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    toolbar(); animation(); controllers();
    P("done\n");
  }
  return 0;
}
