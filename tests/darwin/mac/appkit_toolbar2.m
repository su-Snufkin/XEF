// NSToolbar / NSToolbarItem / NSMenuItem additions: item identifiers, centered items, titles, badges, subtitles; NSDocumentController bits. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface TD : NSObject <NSToolbarDelegate> @end
@implementation TD
- (NSToolbarItem *)toolbar:(NSToolbar *)t itemForItemIdentifier:(NSToolbarItemIdentifier)i willBeInsertedIntoToolbar:(BOOL)f { NSToolbarItem *it = [[NSToolbarItem alloc] initWithItemIdentifier:i]; it.label = i; return it; }
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)t { return @[@"a", @"b", @"c"]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)t { return @[@"a", @"b", @"c", @"d"]; }
@end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  TD *d = [TD new]; NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"tb"]; tb.delegate = d;
  P("toolbar: itemIdentifiers %lu items %lu centered %lu allowsDisplayModeCustomization %d\n", (unsigned long)tb.itemIdentifiers.count, (unsigned long)tb.items.count, (unsigned long)tb.centeredItemIdentifiers.count, tb.allowsDisplayModeCustomization);
  [tb insertItemWithItemIdentifier:@"a" atIndex:0]; [tb insertItemWithItemIdentifier:@"b" atIndex:1]; [tb insertItemWithItemIdentifier:@"c" atIndex:2];
  P("after inserts: ids %s\n", [[[tb.items valueForKey:@"itemIdentifier"] componentsJoinedByString:@","] UTF8String]);
  [tb removeItemWithItemIdentifier:@"b"]; P("after removeItemWithItemIdentifier b: %s\n", [[[tb.items valueForKey:@"itemIdentifier"] componentsJoinedByString:@","] UTF8String]);
  tb.centeredItemIdentifiers = [NSSet setWithObject:@"a"]; P("centered %lu\n", (unsigned long)tb.centeredItemIdentifiers.count);
  tb.allowsDisplayModeCustomization = NO; P("allowsDisplayModeCustomization %d\n", tb.allowsDisplayModeCustomization);
  NSToolbarItem *it = [[NSToolbarItem alloc] initWithItemIdentifier:@"x"];
  P("item defaults: title '%s' style %ld hidden %d visible %d badge nil %d possibleLabels %lu bgTint nil %d\n", [it.title UTF8String], (long)it.style, it.isHidden, it.isVisible, it.badge == nil, (unsigned long)it.possibleLabels.count, it.backgroundTintColor == nil);
  it.title = @"T"; it.hidden = YES; it.possibleLabels = [NSSet setWithObjects:@"A", @"B", nil]; it.style = NSToolbarItemStyleProminent; P("set: %s hidden %d labels %lu style %ld\n", [it.title UTF8String], it.isHidden, (unsigned long)it.possibleLabels.count, (long)it.style);
  NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:@"m" action:NULL keyEquivalent:@""];
  P("menuitem defaults: subtitle nil %d badge nil %d identifier nil %d localizeKeys %d mirrorKeys %d\n", mi.subtitle == nil, mi.badge == nil, mi.identifier == nil, mi.allowsAutomaticKeyEquivalentLocalization, mi.allowsAutomaticKeyEquivalentMirroring);
  mi.subtitle = @"sub"; mi.identifier = @"id"; mi.allowsAutomaticKeyEquivalentLocalization = NO; P("set: %s %s %d\n", [mi.subtitle UTF8String], [mi.identifier UTF8String], mi.allowsAutomaticKeyEquivalentLocalization);
  NSDocumentController *dc = [NSDocumentController sharedDocumentController]; P("document controller current directory nil %d\n", dc.currentDirectory == nil);
  P("PASS appkit_toolbar2\n");
  fflush(stdout); _exit(0);
} return 0; }
