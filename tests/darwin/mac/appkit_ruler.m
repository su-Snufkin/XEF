// NSRulerView / NSRulerMarker: defaults, thickness, units, markers, client view. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 800)]; sv.documentView = doc;
  NSRulerView *r = [[NSRulerView alloc] initWithScrollView:sv orientation:NSHorizontalRuler];
  P("defaults: orientation %ld scrollView same %d thickness %g ruleThickness %g markersThickness %g accessoryThickness %g required %g units %s origin %g clientView nil %d markers %lu accessory %d baseline %g\n",
    (long)r.orientation, r.scrollView == sv, r.ruleThickness + r.reservedThicknessForMarkers + r.reservedThicknessForAccessoryView, r.ruleThickness, r.reservedThicknessForMarkers, r.reservedThicknessForAccessoryView, r.requiredThickness, [r.measurementUnits UTF8String], r.originOffset, r.clientView == nil, (unsigned long)r.markers.count, r.accessoryView != nil, r.baselineLocation);
  r.ruleThickness = 20; r.reservedThicknessForMarkers = 10; r.reservedThicknessForAccessoryView = 5; P("required after set %g\n", r.requiredThickness);
  r.measurementUnits = @"Centimeters"; r.originOffset = 12; P("units %s origin %g\n", [r.measurementUnits UTF8String], r.originOffset);
  P("unit registered? ");
  [NSRulerView registerUnitWithName:@"Furlongs" abbreviation:@"fur" unitToPointsConversionFactor:50 stepUpCycle:@[@2] stepDownCycle:@[@0.5]]; r.measurementUnits = @"Furlongs"; P("%s\n", [r.measurementUnits UTF8String]);
  r.clientView = doc; P("client set %d\n", r.clientView == doc);
  NSRulerMarker *mk = [[NSRulerMarker alloc] initWithRulerView:r markerLocation:30 image:[[NSImage alloc] initWithSize:NSMakeSize(8, 8)] imageOrigin:NSMakePoint(4, 0)];
  P("marker: location %g movable %d removable %d ruler same %d\n", mk.markerLocation, mk.isMovable, mk.isRemovable, [mk ruler] == r);
  [r addMarker:mk]; P("markers %lu\n", (unsigned long)r.markers.count);
  mk.markerLocation = 55; P("marker location %g\n", mk.markerLocation);
  [r removeMarker:mk]; P("markers after remove %lu\n", (unsigned long)r.markers.count);
  r.markers = @[mk]; P("markers set %lu\n", (unsigned long)r.markers.count);
  r.accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)]; P("accessory set %d\n", r.accessoryView != nil);
  r.orientation = NSVerticalRuler; P("orientation %ld\n", (long)r.orientation);
  P("PASS appkit_ruler\n");
  fflush(stdout); _exit(0);
} return 0; }
