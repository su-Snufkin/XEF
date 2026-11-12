// NSPathControl: path items from a URL, styles, items' URLs and titles, placeholder, defaults. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static void dump(NSPathControl *p, const char *tag) {
  NSMutableArray *t = [NSMutableArray array], *u = [NSMutableArray array];
  for (NSPathControlItem *i in p.pathItems) { if ([i.URL.absoluteString isEqualToString:@"file:///"]) { [t addObject:@"<vol>"]; [u addObject:@"file:///"]; continue; } [t addObject:i.title ?: @"(nil)"]; [u addObject:i.URL ? i.URL.absoluteString : @"(nil)"]; }
  P("%s: URL %s items %lu titles [%s] urls [%s] cells %lu\n", tag, p.URL ? [p.URL.absoluteString UTF8String] : "nil", (unsigned long)p.pathItems.count, [[t componentsJoinedByString:@"|"] UTF8String], [[u componentsJoinedByString:@"|"] UTF8String], (unsigned long)p.pathComponentCells.count);
}
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSPathControl *p = [[NSPathControl alloc] initWithFrame:NSMakeRect(0, 0, 400, 24)];
  P("defaults: style %ld editable %d placeholder %s items %lu cells %lu doubleAction %d delegate %d allowedTypes %lu\n", (long)p.pathStyle, p.isEditable, p.placeholderString ? [p.placeholderString UTF8String] : "nil", (unsigned long)p.pathItems.count, (unsigned long)p.pathComponentCells.count, p.doubleAction != NULL, p.delegate != nil, (unsigned long)p.allowedTypes.count);
  p.URL = [NSURL fileURLWithPath:@"/usr/local/bin"];
  dump(p, "standard");
  P("clicked %d\n", p.clickedPathItem != nil);
  p.pathStyle = NSPathStyleNavigationBar; P("style now %ld\n", (long)p.pathStyle);
  dump(p, "navbar");
  p.pathStyle = NSPathStylePopUp; dump(p, "popup");
  p.URL = nil; dump(p, "nil");
  p.placeholderString = @"Choose"; P("placeholder %s\n", [p.placeholderString UTF8String]);
  p.editable = YES; P("editable %d\n", p.isEditable);
  p.URL = [NSURL URLWithString:@"http://example.com/a/b"]; dump(p, "http");
  P("== items\n");
  NSPathControlItem *it = [NSPathControlItem new]; it.title = @"Custom";
  P("item title %s url %d image %d\n", [it.title UTF8String], it.URL != nil, it.image != nil);
  p.pathItems = @[it]; dump(p, "custom items");
  p.pathStyle = NSPathStyleStandard;
  NSPathComponentCell *c = [NSPathComponentCell new]; c.URL = [NSURL fileURLWithPath:@"/tmp"]; P("component cell url %s\n", [c.URL.path UTF8String]);
  P("cell class %s\n", [NSStringFromClass([p.cell class]) UTF8String]);
  P("PASS appkit_pathcontrol\n");
  fflush(stdout); _exit(0);
} return 0; }
