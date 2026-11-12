// NSMenu extras and NSSavePanel/NSOpenPanel properties and legacy API. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSMenu *m = [[NSMenu alloc] initWithTitle:@"M"];
  P("menu defaults: identifier %s presentationStyle %ld selectionMode %ld selectedItems %lu tornOff %d attached %d changeMsgs %d contextPlugins %d\n", m.identifier ? [m.identifier UTF8String] : "nil", (long)m.presentationStyle, (long)m.selectionMode, (unsigned long)m.selectedItems.count, m.isTornOff, m.isAttached, m.menuChangedMessagesEnabled, m.allowsContextMenuPlugIns);
  m.identifier = @"com.example.menu"; P("identifier %s\n", [m.identifier UTF8String]);
  m.menuChangedMessagesEnabled = NO; P("changeMsgs now %d\n", m.menuChangedMessagesEnabled); m.menuChangedMessagesEnabled = YES;
  NSMenuItem *a = [m addItemWithTitle:@"A" action:NULL keyEquivalent:@""], *b = [m addItemWithTitle:@"B" action:NULL keyEquivalent:@""];
  m.selectionMode = NSMenuSelectionModeSelectOne; P("selectionMode %ld\n", (long)m.selectionMode);
  m.selectedItems = @[b]; P("selected %lu first %s b.state %ld\n", (unsigned long)m.selectedItems.count, [[m.selectedItems.firstObject title] UTF8String], (long)b.state);
  m.presentationStyle = NSMenuPresentationStylePalette; P("style %ld\n", (long)m.presentationStyle);
  P("menuBarHeight >0 %d\n", [[NSApp mainMenu] menuBarHeight] >= 0);
  [m sizeToFit]; P("sizeToFit ok\n");
  NSMenu *pm = [NSMenu paletteMenuWithColors:@[[NSColor redColor], [NSColor blueColor]] titles:@[@"Red", @"Blue"] selectionHandler:^(NSMenu *x) {}];
  P("palette items %ld style %ld\n", (long)pm.numberOfItems, (long)pm.presentationStyle);
  P("== panels\n");
  NSSavePanel *sp = [NSSavePanel savePanel];
  P("save defaults: extHidden %d canSelectHidden %d packagesAsDirs %d showsHidden %d showsTag %d showsContentTypes %d expanded %d identifier %s nameFieldLabel %s tagNames %lu accessory %d\n", sp.isExtensionHidden, sp.canSelectHiddenExtension, sp.treatsFilePackagesAsDirectories, sp.showsHiddenFiles, sp.showsTagField, sp.showsContentTypes, sp.isExpanded, sp.identifier ? [sp.identifier UTF8String] : "nil", sp.nameFieldLabel ? [sp.nameFieldLabel UTF8String] : "nil", (unsigned long)sp.tagNames.count, sp.accessoryView != nil);
  sp.canSelectHiddenExtension = YES; sp.extensionHidden = YES; sp.treatsFilePackagesAsDirectories = YES; sp.showsHiddenFiles = YES; sp.showsTagField = NO; sp.identifier = @"id1"; sp.nameFieldLabel = @"Save as:";
  P("set: canSelect %d hidden %d packages %d showsHidden %d tag %d id %s label %s\n", sp.canSelectHiddenExtension, sp.isExtensionHidden, sp.treatsFilePackagesAsDirectories, sp.showsHiddenFiles, sp.showsTagField, [sp.identifier UTF8String], [sp.nameFieldLabel UTF8String]);
  NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 30)]; sp.accessoryView = v; P("accessory set %d\n", sp.accessoryView == v);
  sp.tagNames = @[@"x"]; P("tags %lu\n", (unsigned long)sp.tagNames.count);
  sp.directory = @"/tmp"; P("directory (legacy) %s url %s\n", [sp.directory UTF8String], [sp.directoryURL.path UTF8String]);
  sp.requiredFileType = @"txt"; P("requiredFileType %s allowedFileTypes %s\n", [sp.requiredFileType UTF8String], [[sp.allowedFileTypes componentsJoinedByString:@","] UTF8String]);
  P("PASS appkit_menu_panel\n");
  fflush(stdout); _exit(0);
} return 0; }
