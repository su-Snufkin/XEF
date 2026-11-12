// NSColorPanel and NSColorList: shared panel state, color/alpha, modes, target/action; named color lists. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface T : NSObject { @public int hits; } - (void)changed:(id)s; @end
@implementation T - (void)changed:(id)s { hits++; } @end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSColorPanel *cp = [NSColorPanel sharedColorPanel];
  P("shared %d same %d exists %d\n", cp != nil, cp == [NSColorPanel sharedColorPanel], [NSColorPanel sharedColorPanelExists]);
  P("defaults: continuous %d showsAlpha %d mode %ld accessory nil %d alpha %g visible %d\n", cp.isContinuous, cp.showsAlpha, (long)cp.mode, cp.accessoryView == nil, cp.alpha, cp.isVisible);
  T *t = [T new]; [cp setTarget:t]; [cp setAction:@selector(changed:)];
  cp.color = [NSColor colorWithCalibratedRed:0.2 green:0.4 blue:0.6 alpha:0.5];
  CGFloat r, g, b, a; [[cp.color colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]] getRed:&r green:&g blue:&b alpha:&a]; P("color roundtrip %.2f %.2f %.2f alpha %.2f panel alpha %.2f\n", r, g, b, a, cp.alpha);
  P("action called by setColor %d\n", t->hits);
  cp.showsAlpha = YES; cp.continuous = YES; cp.mode = NSColorPanelModeWheel; P("set: alpha %d continuous %d mode %ld\n", cp.showsAlpha, cp.isContinuous, (long)cp.mode);
  NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)]; cp.accessoryView = v; P("accessory set %d\n", cp.accessoryView == v);
  P("== color lists\n");
  NSColorList *l = [[NSColorList alloc] initWithName:@"XefList"];
  P("name %s keys %lu editable %d\n", [l.name UTF8String], (unsigned long)l.allKeys.count, l.isEditable);
  [l setColor:[NSColor redColor] forKey:@"Red"]; [l setColor:[NSColor blueColor] forKey:@"Blue"]; [l insertColor:[NSColor greenColor] key:@"Green" atIndex:1];
  P("keys %s\n", [[l.allKeys componentsJoinedByString:@","] UTF8String]);
  P("colorWithKey Red equals %d missing nil %d\n", [[l colorWithKey:@"Red"] isEqual:[NSColor redColor]], [l colorWithKey:@"Nope"] == nil);
  [l removeColorWithKey:@"Blue"]; P("after remove: %s\n", [[l.allKeys componentsJoinedByString:@","] UTF8String]);
  [l setColor:[NSColor yellowColor] forKey:@"Red"]; P("replace keeps position %s equals yellow %d\n", [[l.allKeys componentsJoinedByString:@","] UTF8String], [[l colorWithKey:@"Red"] isEqual:[NSColor yellowColor]]);
  P("available lists >0 %d\n", [NSColorList availableColorLists].count > 0);
  P("PASS appkit_colorpanel\n");
  fflush(stdout); _exit(0);
} return 0; }
