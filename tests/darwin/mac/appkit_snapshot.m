// NSDiffableDataSourceSnapshot (sections and items, appends, inserts, moves, deletes) and NSWorkspaceOpenConfiguration. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *J(NSArray *a) { return [[a componentsJoinedByString:@","] UTF8String]; }
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSDiffableDataSourceSnapshot *s = [[NSDiffableDataSourceSnapshot alloc] init];
  P("empty: items %ld sections %ld\n", (long)s.numberOfItems, (long)s.numberOfSections);
  [s appendSectionsWithIdentifiers:@[@"A", @"B"]]; P("sections %s count %ld\n", J(s.sectionIdentifiers), (long)s.numberOfSections);
  [s appendItemsWithIdentifiers:@[@"a1", @"a2"] intoSectionWithIdentifier:@"A"]; [s appendItemsWithIdentifiers:@[@"b1"] intoSectionWithIdentifier:@"B"];
  P("items %s total %ld inA %ld inB %ld\n", J(s.itemIdentifiers), (long)s.numberOfItems, (long)[s numberOfItemsInSection:@"A"], (long)[s numberOfItemsInSection:@"B"]);
  P("itemsInA %s sectionOf(b1) %s\n", J([s itemIdentifiersInSectionWithIdentifier:@"A"]), [[s sectionIdentifierForSectionContainingItemIdentifier:@"b1"] UTF8String]);
  P("indexOf a2 %ld b1 %ld missing %ld; section B %ld\n", (long)[s indexOfItemIdentifier:@"a2"], (long)[s indexOfItemIdentifier:@"b1"], (long)[s indexOfItemIdentifier:@"zz"], (long)[s indexOfSectionIdentifier:@"B"]);
  [s insertItemsWithIdentifiers:@[@"x"] beforeItemWithIdentifier:@"a2"]; P("insert before a2: %s\n", J(s.itemIdentifiers));
  [s insertItemsWithIdentifiers:@[@"y"] afterItemWithIdentifier:@"a2"]; P("insert after a2: %s\n", J(s.itemIdentifiers));
  [s moveItemWithIdentifier:@"b1" beforeItemWithIdentifier:@"a1"]; P("move b1 before a1: %s (sections: A=%s B=%s)\n", J(s.itemIdentifiers), J([s itemIdentifiersInSectionWithIdentifier:@"A"]), J([s itemIdentifiersInSectionWithIdentifier:@"B"]));
  [s moveItemWithIdentifier:@"b1" afterItemWithIdentifier:@"y"]; P("move b1 after y: %s\n", J(s.itemIdentifiers));
  [s deleteItemsWithIdentifiers:@[@"x", @"nonexistent"]]; P("delete x: %s\n", J(s.itemIdentifiers));
  [s insertSectionsWithIdentifiers:@[@"C"] beforeSectionWithIdentifier:@"A"]; P("insert section C before A: %s\n", J(s.sectionIdentifiers));
  [s insertSectionsWithIdentifiers:@[@"D"] afterSectionWithIdentifier:@"A"]; P("insert D after A: %s\n", J(s.sectionIdentifiers));
  [s moveSectionWithIdentifier:@"B" beforeSectionWithIdentifier:@"C"]; P("move B before C: %s\n", J(s.sectionIdentifiers));
  [s moveSectionWithIdentifier:@"B" afterSectionWithIdentifier:@"D"]; P("move B after D: %s items %s\n", J(s.sectionIdentifiers), J(s.itemIdentifiers));
  [s deleteSectionsWithIdentifiers:@[@"A"]]; P("delete section A: sections %s items %s\n", J(s.sectionIdentifiers), J(s.itemIdentifiers));
  [s reloadSectionsWithIdentifiers:@[@"B"]]; P("reload ok items %ld\n", (long)s.numberOfItems);
  [s appendItemsWithIdentifiers:@[@"q"]]; P("append into last section: %s (last %s)\n", J(s.itemIdentifiers), [[s sectionIdentifierForSectionContainingItemIdentifier:@"q"] UTF8String]);
  [s deleteAllItems]; P("deleteAll: items %ld sections %ld\n", (long)s.numberOfItems, (long)s.numberOfSections);
  NSWorkspaceOpenConfiguration *c = [NSWorkspaceOpenConfiguration configuration];
  P("config defaults: prompts %d recents %d activates %d hides %d hidesOthers %d printing %d newInstance %d universal %d args %lu env %lu\n", c.promptsUserIfNeeded, c.addsToRecentItems, c.activates, c.hides, c.hidesOthers, c.isForPrinting, c.createsNewApplicationInstance, c.requiresUniversalLinks, (unsigned long)c.arguments.count, (unsigned long)c.environment.count);
  c.activates = NO; c.arguments = @[@"-x"]; c.environment = @{ @"K": @"V" }; c.hides = YES; c.forPrinting = YES;
  P("set: activates %d args %s env %lu hides %d printing %d\n", c.activates, J(c.arguments), (unsigned long)c.environment.count, c.hides, c.isForPrinting);
  P("PASS appkit_snapshot\n");
  fflush(stdout); _exit(0);
} return 0; }
