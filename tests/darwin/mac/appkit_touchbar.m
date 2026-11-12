// NSTouchBar and its item classes as a model: identifiers, delegate item creation, template items, custom and group items. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface D : NSObject <NSTouchBarDelegate> { @public int made; } @end
@implementation D
- (NSTouchBarItem *)touchBar:(NSTouchBar *)tb makeItemForIdentifier:(NSTouchBarItemIdentifier)i {
  made++; NSCustomTouchBarItem *it = [[NSCustomTouchBarItem alloc] initWithIdentifier:i]; it.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 30, 30)]; it.customizationLabel = [@"L-" stringByAppendingString:i]; return it; }
@end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSTouchBar *tb = [[NSTouchBar alloc] init];
  P("defaults: default ids %lu itemIdentifiers %lu visible %d delegate nil %d principal nil %d escape nil %d customId nil %d templates %lu allowed %lu required %lu\n", (unsigned long)tb.defaultItemIdentifiers.count, (unsigned long)tb.itemIdentifiers.count, tb.isVisible, tb.delegate == nil, tb.principalItemIdentifier == nil, tb.escapeKeyReplacementItemIdentifier == nil, tb.customizationIdentifier == nil, (unsigned long)tb.templateItems.count, (unsigned long)tb.customizationAllowedItemIdentifiers.count, (unsigned long)tb.customizationRequiredItemIdentifiers.count);
  D *d = [D new]; tb.delegate = d; tb.defaultItemIdentifiers = @[@"a", @"b", NSTouchBarItemIdentifierFlexibleSpace, @"c"];
  P("ids %s\n", [[tb.itemIdentifiers componentsJoinedByString:@","] UTF8String]);
  NSTouchBarItem *a = [tb itemForIdentifier:@"a"]; P("item a: %d id %s made %d class %s\n", a != nil, [a.identifier UTF8String], d->made, [NSStringFromClass([a class]) UTF8String]);
  P("same item again %d made %d\n", [tb itemForIdentifier:@"a"] == a, d->made);
  P("flexible space item %d\n", [tb itemForIdentifier:NSTouchBarItemIdentifierFlexibleSpace] != nil);
  NSCustomTouchBarItem *ci = (NSCustomTouchBarItem *)a; P("custom: view %d label %s priority %g visible %d\n", ci.view != nil, [ci.customizationLabel UTF8String], ci.visibilityPriority, ci.isVisible);
  ci.visibilityPriority = NSTouchBarItemPriorityHigh; P("priority set %g\n", ci.visibilityPriority);
  tb.principalItemIdentifier = @"b"; tb.escapeKeyReplacementItemIdentifier = @"c"; tb.customizationIdentifier = @"com.example.tb"; tb.customizationAllowedItemIdentifiers = @[@"a", @"b"]; tb.customizationRequiredItemIdentifiers = @[@"a"];
  P("set: principal %s escape %s custom %s allowed %lu required %lu\n", [tb.principalItemIdentifier UTF8String], [tb.escapeKeyReplacementItemIdentifier UTF8String], [tb.customizationIdentifier UTF8String], (unsigned long)tb.customizationAllowedItemIdentifiers.count, (unsigned long)tb.customizationRequiredItemIdentifiers.count);
  NSCustomTouchBarItem *t1 = [[NSCustomTouchBarItem alloc] initWithIdentifier:@"t1"];
  NSTouchBar *tb2 = [[NSTouchBar alloc] init]; tb2.templateItems = [NSSet setWithObject:t1]; tb2.defaultItemIdentifiers = @[@"t1"];
  P("template: item found %d templates %lu\n", [tb2 itemForIdentifier:@"t1"] == t1, (unsigned long)tb2.templateItems.count);
  NSGroupTouchBarItem *g = [NSGroupTouchBarItem groupItemWithIdentifier:@"grp" items:@[t1]];
  P("group: id %s bar items %lu prefersEqual %d preferredWidth %g\n", [g.identifier UTF8String], (unsigned long)g.groupTouchBar.itemIdentifiers.count, g.prefersEqualWidths, g.preferredItemWidth);
  g.prefersEqualWidths = YES; g.preferredItemWidth = 80; g.customizationLabel = @"G"; P("group set %d %g %s\n", g.prefersEqualWidths, g.preferredItemWidth, [g.customizationLabel UTF8String]);
  P("auto customize menu item %d\n", [NSTouchBar isAutomaticCustomizeTouchBarMenuItemEnabled]);
  P("PASS appkit_touchbar\n");
  fflush(stdout); _exit(0);
} return 0; }
