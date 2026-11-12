// NSSearchFieldCell and NSPrintPanel: stored settings, button cells, rects; print panel options. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSSearchFieldCell *c = [[NSSearchFieldCell alloc] initTextCell:@""];
  P("defaults: recents %lu autosave nil %d menu nil %d sendsWhole %d maxRecents %ld immediate %d searchBtn %d cancelBtn %d\n", (unsigned long)c.recentSearches.count, c.recentsAutosaveName == nil, c.searchMenuTemplate == nil, c.sendsWholeSearchString, (long)c.maximumRecents, c.sendsSearchStringImmediately, c.searchButtonCell != nil, c.cancelButtonCell != nil);
  c.recentSearches = @[@"x"]; c.maximumRecents = 3; c.sendsWholeSearchString = YES; c.sendsSearchStringImmediately = YES; c.recentsAutosaveName = @"r";
  P("set: %lu %ld %d %d %s\n", (unsigned long)c.recentSearches.count, (long)c.maximumRecents, c.sendsWholeSearchString, c.sendsSearchStringImmediately, [c.recentsAutosaveName UTF8String]);
  NSRect b = NSMakeRect(0, 0, 200, 22);
  NSRect st = [c searchTextRectForBounds:b], sb = [c searchButtonRectForBounds:b], cb = [c cancelButtonRectForBounds:b];
  P("rects: text inside %d searchButton left %d cancelButton right %d\n", NSContainsRect(b, st), sb.origin.x < st.origin.x, cb.origin.x > st.origin.x);
  NSButtonCell *sbc = c.searchButtonCell; [c resetSearchButtonCell]; [c resetCancelButtonCell]; P("reset ok, cell replaced or same %d\n", c.searchButtonCell != nil);
  NSPrintPanel *pp = [NSPrintPanel printPanel];
  P("print panel: options %lu jobStyleHint nil %d defaultButtonTitle nil %d helpAnchor nil %d accessory %lu\n", (unsigned long)pp.options, pp.jobStyleHint == nil, pp.defaultButtonTitle == nil, pp.helpAnchor == nil, (unsigned long)pp.accessoryControllers.count);
  pp.options = NSPrintPanelShowsCopies; pp.defaultButtonTitle = @"Go"; pp.helpAnchor = @"h"; P("set: options %lu title %s anchor %s\n", (unsigned long)pp.options, [pp.defaultButtonTitle UTF8String], [pp.helpAnchor UTF8String]);
  P("PASS appkit_searchcell\n");
  fflush(stdout); _exit(0);
} return 0; }
