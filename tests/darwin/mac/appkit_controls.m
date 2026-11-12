// AppKit controls without a window: defaults, value clamping, selection and delegate behaviour of NSSlider, NSStepper,
// NSProgressIndicator, NSSegmentedControl, NSLevelIndicator, NSImageView, NSColorWell, NSSwitch, NSComboBox, NSTabView,
// NSSplitView, NSGradient, NSPanel. The output of real AppKit is the reference (tests/darwin/macref.sh).
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *R(NSRect r) { return [[NSString stringWithFormat:@"{%g,%g,%g,%g}", r.origin.x, r.origin.y, r.size.width, r.size.height] UTF8String]; }

@interface Target : NSObject <NSTabViewDelegate, NSComboBoxDelegate, NSSplitViewDelegate> { @public int hits; }
@end
@implementation Target
- (void)act:(id)s { hits++; P("  action from %s\n", [[s className] UTF8String]); }
- (BOOL)tabView:(NSTabView *)t shouldSelectTabViewItem:(NSTabViewItem *)i { P("  shouldSelect %s\n", [[i label] UTF8String]); return ![[i label] isEqual:@"locked"]; }
- (void)tabView:(NSTabView *)t willSelectTabViewItem:(NSTabViewItem *)i { P("  willSelect %s\n", [[i label] UTF8String]); }
- (void)tabView:(NSTabView *)t didSelectTabViewItem:(NSTabViewItem *)i { P("  didSelect %s\n", [[i label] UTF8String]); }
- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)t { P("  count now %ld\n", (long)[t numberOfTabViewItems]); }
- (void)comboBoxSelectionDidChange:(NSNotification *)n { P("  comboBoxSelectionDidChange\n"); }
@end

static void slider(Target *t) {
  P("== NSSlider\n");
  NSSlider *s = [[NSSlider alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
  P("defaults min %g max %g value %g ticks %ld vertical %d type %ld alt %g onlyTicks %d continuous %d enabled %d\n", s.minValue, s.maxValue, s.doubleValue,
    (long)s.numberOfTickMarks, s.vertical, (long)s.sliderType, s.altIncrementValue, s.allowsTickMarkValuesOnly, s.continuous, s.enabled);
  P("cell %s flipped %d\n", [[[s cell] className] UTF8String], s.isFlipped);
  s.minValue = 10; s.maxValue = 50;
  P("after range value %g\n", s.doubleValue);
  s.doubleValue = 100; P("set 100 -> %g\n", s.doubleValue);
  s.doubleValue = -5; P("set -5 -> %g\n", s.doubleValue);
  s.intValue = 33; P("int 33 -> %g %d %s\n", s.doubleValue, s.intValue, [s.stringValue UTF8String]);
  s.numberOfTickMarks = 5;
  for (int i = 0; i < 5; i++) P("tick %d = %g\n", i, [s tickMarkValueAtIndex:i]);
  P("closest to 33 = %g, to 49 = %g\n", [s closestTickMarkValueToValue:33], [s closestTickMarkValueToValue:49]);
  s.allowsTickMarkValuesOnly = YES; s.doubleValue = 33; P("ticks only 33 -> %g\n", s.doubleValue);
  s.maxValue = 20; P("max 20 -> value %g\n", s.doubleValue);
  NSSlider *v = [[NSSlider alloc] initWithFrame:NSMakeRect(0, 0, 24, 200)];
  P("tall frame vertical %d\n", v.vertical);
  NSSlider *c = [NSSlider sliderWithValue:3 minValue:1 maxValue:9 target:t action:@selector(act:)];
  P("convenience %g %g %g target %d\n", c.doubleValue, c.minValue, c.maxValue, c.target == t);
  [c performClick:nil]; P("hits %d\n", t->hits);
  NSSliderCell *cell = [[NSSliderCell alloc] init];
  P("cell defaults %g %g %g\n", cell.minValue, cell.maxValue, cell.doubleValue);
}

static void stepper(void) {
  P("== NSStepper\n");
  NSStepper *s = [[NSStepper alloc] initWithFrame:NSMakeRect(0, 0, 19, 27)];
  P("defaults min %g max %g inc %g value %g wraps %d autorepeat %d\n", s.minValue, s.maxValue, s.increment, s.doubleValue, s.valueWraps, s.autorepeat);
  s.doubleValue = 100; P("set 100 -> %g\n", s.doubleValue);
  s.doubleValue = -3; P("set -3 -> %g\n", s.doubleValue);
  s.minValue = 5; P("min 5 -> %g\n", s.doubleValue);
  s.maxValue = 2; P("max 2 -> %g (min %g)\n", s.doubleValue, s.minValue);
}

static void progress(void) {
  P("== NSProgressIndicator\n");
  NSProgressIndicator *p = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
  P("defaults min %g max %g value %g indeterminate %d style %ld displayedWhenStopped %d threaded %d hidden %d\n", p.minValue, p.maxValue, p.doubleValue,
    p.indeterminate, (long)p.style, p.displayedWhenStopped, p.usesThreadedAnimation, p.hidden);
  p.indeterminate = NO;
  p.doubleValue = 250; P("set 250 -> %g\n", p.doubleValue);
  p.doubleValue = -1; P("set -1 -> %g\n", p.doubleValue);
  p.doubleValue = 40; [p incrementBy:15]; P("40 + 15 -> %g\n", p.doubleValue);
  [p incrementBy:100]; P("+100 -> %g\n", p.doubleValue);
  p.maxValue = 30; P("max 30 -> %g\n", p.doubleValue);
  p.minValue = 50; P("min 50 -> value %g max %g\n", p.doubleValue, p.maxValue);
  NSProgressIndicator *sp = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 32, 32)];
  sp.style = NSProgressIndicatorStyleSpinning; sp.displayedWhenStopped = NO;
  P("spinner hidden %d\n", sp.hidden); [sp startAnimation:nil]; P("animating hidden %d\n", sp.hidden); [sp stopAnimation:nil]; P("stopped hidden %d\n", sp.hidden);
}

static void segmented(Target *t) {
  P("== NSSegmentedControl\n");
  NSSegmentedControl *s = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
  P("defaults count %ld selected %ld tracking %ld style %ld\n", (long)s.segmentCount, (long)s.selectedSegment, (long)s.trackingMode, (long)s.segmentStyle);
  s.segmentCount = 3;
  [s setLabel:@"One" forSegment:0]; [s setLabel:@"Two" forSegment:1]; [s setLabel:@"Three" forSegment:2];
  P("labels %s %s %s enabled %d width %g selected %ld\n", [[s labelForSegment:0] UTF8String], [[s labelForSegment:1] UTF8String], [[s labelForSegment:2] UTF8String],
    [s isEnabledForSegment:1], [s widthForSegment:1], (long)s.selectedSegment);
  s.selectedSegment = 1; P("select 1 -> %ld sel0 %d sel1 %d\n", (long)s.selectedSegment, [s isSelectedForSegment:0], [s isSelectedForSegment:1]);
  [s setSelected:YES forSegment:2]; P("setSelected 2 -> %ld sel1 %d sel2 %d\n", (long)s.selectedSegment, [s isSelectedForSegment:1], [s isSelectedForSegment:2]);
  [s setSelected:NO forSegment:2]; P("deselect 2 -> %ld\n", (long)s.selectedSegment);
  s.trackingMode = NSSegmentSwitchTrackingSelectAny;
  [s setSelected:YES forSegment:0]; [s setSelected:YES forSegment:2];
  P("any: %d %d %d selectedSegment %ld\n", [s isSelectedForSegment:0], [s isSelectedForSegment:1], [s isSelectedForSegment:2], (long)s.selectedSegment);
  s.selectedSegment = 1; P("any after select 1: %d %d %d -> %ld\n", [s isSelectedForSegment:0], [s isSelectedForSegment:1], [s isSelectedForSegment:2], (long)s.selectedSegment);
  [[s cell] setTag:7 forSegment:2]; P("tag %ld select %d -> sel2 %d\n", (long)[[s cell] tagForSegment:2], [s selectSegmentWithTag:7], [s isSelectedForSegment:2]);
  P("select missing tag %d\n", [s selectSegmentWithTag:99]);
  s.segmentCount = 2; P("shrink count %ld selected %ld\n", (long)s.segmentCount, (long)s.selectedSegment);
  [s setWidth:55 forSegment:0]; [s setEnabled:NO forSegment:1]; P("width %g enabled %d\n", [s widthForSegment:0], [s isEnabledForSegment:1]);
  NSSegmentedControl *c = [NSSegmentedControl segmentedControlWithLabels:@[@"A", @"B"] trackingMode:NSSegmentSwitchTrackingMomentary target:t action:@selector(act:)];
  P("convenience count %ld mode %ld label %s selected %ld\n", (long)c.segmentCount, (long)c.trackingMode, [[c labelForSegment:1] UTF8String], (long)c.selectedSegment);
  c.selectedSegment = 1; P("momentary select -> %ld\n", (long)c.selectedSegment);
}

static void misc(void) {
  P("== NSLevelIndicator\n");
  NSLevelIndicator *l = [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(0, 0, 100, 16)];
  P("defaults min %g max %g value %g warn %g crit %g style %ld ticks %ld major %ld editable %d\n", l.minValue, l.maxValue, l.doubleValue, l.warningValue, l.criticalValue,
    (long)l.levelIndicatorStyle, (long)l.numberOfTickMarks, (long)l.numberOfMajorTickMarks, l.editable);
  l.maxValue = 10; l.doubleValue = 25; P("set 25 -> %g\n", l.doubleValue);
  P("== NSImageView\n");
  NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
  P("defaults image %d scaling %ld align %ld frame %ld editable %d animates %d cell %s\n", iv.image != nil, (long)iv.imageScaling, (long)iv.imageAlignment, (long)iv.imageFrameStyle,
    iv.editable, iv.animates, [[[iv cell] className] UTF8String]);
  NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(8, 6)];
  iv.image = img; P("image set %d objectValue %d\n", iv.image == img, [iv objectValue] == img);
  NSImageView *iv2 = [NSImageView imageViewWithImage:img]; P("convenience image %d\n", iv2.image == img);
  P("== NSColorWell\n");
  NSColorWell *w = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 23)];
  NSColor *wc = [w.color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
  P("defaults color %.2f %.2f %.2f %.2f active %d bordered %d\n", wc.redComponent, wc.greenComponent, wc.blueComponent, wc.alphaComponent, w.active, w.bordered);
  w.color = [NSColor colorWithSRGBRed:0.25 green:0.5 blue:0.75 alpha:1]; P("set color %.2f\n", [w.color blueComponent]);
  P("== NSSwitch\n");
  NSSwitch *sw = [[NSSwitch alloc] initWithFrame:NSMakeRect(0, 0, 40, 24)];
  P("defaults state %ld enabled %d\n", (long)sw.state, sw.enabled); sw.state = NSControlStateValueOn; P("on %ld\n", (long)sw.state);
  P("== NSPanel\n");
  NSPanel *pn = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow backing:NSBackingStoreBuffered defer:YES];
  P("floating %d keyOnlyIfNeeded %d worksWhenModal %d hidesOnDeactivate %d releasedWhenClosed %d canMain %d\n", pn.floatingPanel, pn.becomesKeyOnlyIfNeeded, pn.worksWhenModal,
    pn.hidesOnDeactivate, pn.releasedWhenClosed, pn.canBecomeMainWindow);
  pn.floatingPanel = YES; P("floating %d level %ld\n", pn.floatingPanel, (long)pn.level);
  P("== NSGradient\n");
  NSGradient *g = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1] endingColor:[NSColor colorWithSRGBRed:0 green:0 blue:1 alpha:1]];
  NSColor *mid = [g interpolatedColorAtLocation:0.25]; CGFloat loc; NSColor *c1;
  [g getColor:&c1 location:&loc atIndex:1];
  P("stops %ld mid %.2f %.2f %.2f stop1 at %g blue %.2f\n", (long)g.numberOfColorStops, mid.redComponent, mid.greenComponent, mid.blueComponent, loc, c1.blueComponent);
  NSGradient *g3 = [[NSGradient alloc] initWithColors:@[[NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:1], [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1], [NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1]]];
  [g3 getColor:&c1 location:&loc atIndex:1]; NSColor *q = [g3 interpolatedColorAtLocation:0.75];
  P("three stops %ld middle at %g, 0.75 -> %.2f %.2f %.2f, clamp -> %.2f\n", (long)g3.numberOfColorStops, loc, q.redComponent, q.greenComponent, q.blueComponent, [[g3 interpolatedColorAtLocation:5] greenComponent]);
}

static void combo(Target *t) {
  P("== NSComboBox\n");
  NSComboBox *c = [[NSComboBox alloc] initWithFrame:NSMakeRect(0, 0, 150, 26)];
  c.delegate = t;
  P("defaults items %ld selected %ld visible %ld usesDataSource %d scroller %d completes %d bordered %d editable %d cell %s\n", (long)c.numberOfItems, (long)c.indexOfSelectedItem,
    (long)c.numberOfVisibleItems, c.usesDataSource, c.hasVerticalScroller, c.completes, c.buttonBordered, c.editable, [[[c cell] className] UTF8String]);
  [c addItemWithObjectValue:@"apple"]; [c addItemsWithObjectValues:@[@"banana", @"cherry"]]; [c insertItemWithObjectValue:@"avocado" atIndex:1];
  P("items %ld: %s\n", (long)c.numberOfItems, [[c.objectValues componentsJoinedByString:@","] UTF8String]);
  P("index of cherry %ld, of none %d\n", (long)[c indexOfItemWithObjectValue:@"cherry"], [c indexOfItemWithObjectValue:@"none"] == NSNotFound);
  [c selectItemAtIndex:2];
  P("selected %ld value %s string '%s'\n", (long)c.indexOfSelectedItem, [[c.objectValueOfSelectedItem description] UTF8String], [c.stringValue UTF8String]);
  [c selectItemWithObjectValue:@"cherry"]; P("select by value -> %ld\n", (long)c.indexOfSelectedItem);
  c.stringValue = @"typed"; P("typed: selected %ld string '%s'\n", (long)c.indexOfSelectedItem, [c.stringValue UTF8String]);
  [c removeItemAtIndex:0]; P("removed 0: items %ld selected %ld\n", (long)c.numberOfItems, (long)c.indexOfSelectedItem);
  [c deselectItemAtIndex:c.indexOfSelectedItem]; P("deselected %ld\n", (long)c.indexOfSelectedItem);
  [c removeItemWithObjectValue:@"banana"]; [c removeAllItems]; P("cleared %ld\n", (long)c.numberOfItems);
}

static void tabs(Target *t) {
  P("== NSTabView\n");
  NSTabView *tv = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  tv.delegate = t;
  P("defaults count %ld selected %d type %ld drawsBackground %d truncated %d\n", (long)tv.numberOfTabViewItems, tv.selectedTabViewItem != nil, (long)tv.tabViewType, tv.drawsBackground, tv.allowsTruncatedLabels);
  NSTabViewItem *a = [[NSTabViewItem alloc] initWithIdentifier:@"a"]; a.label = @"first";
  NSTabViewItem *b = [[NSTabViewItem alloc] initWithIdentifier:@"b"]; b.label = @"second";
  NSTabViewItem *c = [[NSTabViewItem alloc] initWithIdentifier:@"c"]; c.label = @"locked";
  P("item defaults view %d state %ld tabView %d label %s\n", a.view != nil, (long)a.tabState, a.tabView != nil, [b.label UTF8String]);
  P("add a\n"); [tv addTabViewItem:a];
  P("selected %s state %ld view superview is tabview %d\n", [tv.selectedTabViewItem.label UTF8String], (long)a.tabState, a.view.superview == tv);
  P("add b, c\n"); [tv addTabViewItem:b]; [tv addTabViewItem:c];
  P("select index 1\n"); [tv selectTabViewItemAtIndex:1];
  P("selected %s a.state %ld b.state %ld a.view in tree %d b.view in tree %d\n", [tv.selectedTabViewItem.label UTF8String], (long)a.tabState, (long)b.tabState, a.view.superview != nil, b.view.superview == tv);
  P("select locked\n"); [tv selectTabViewItem:c]; P("selected %s\n", [tv.selectedTabViewItem.label UTF8String]);
  P("index of b %ld, identifier c %ld, missing %d\n", (long)[tv indexOfTabViewItem:b], (long)[tv indexOfTabViewItemWithIdentifier:@"c"], [tv indexOfTabViewItemWithIdentifier:@"zz"] == NSNotFound);
  P("select next / previous / first / last\n"); [tv selectNextTabViewItem:nil]; P("-> %s\n", [tv.selectedTabViewItem.label UTF8String]);
  [tv selectPreviousTabViewItem:nil]; [tv selectPreviousTabViewItem:nil]; P("-> %s\n", [tv.selectedTabViewItem.label UTF8String]);
  [tv selectLastTabViewItem:nil]; P("-> %s\n", [tv.selectedTabViewItem.label UTF8String]); [tv selectFirstTabViewItem:nil]; P("-> %s\n", [tv.selectedTabViewItem.label UTF8String]);
  P("remove selected a\n"); [tv removeTabViewItem:a]; P("selected %s count %ld a.tabView %d\n", [tv.selectedTabViewItem.label UTF8String], (long)tv.numberOfTabViewItems, a.tabView != nil);
  P("insert a at 0\n"); [tv insertTabViewItem:a atIndex:0]; P("order %s %s %s selected %s\n", [[tv tabViewItemAtIndex:0].label UTF8String], [[tv tabViewItemAtIndex:1].label UTF8String], [[tv tabViewItemAtIndex:2].label UTF8String], [tv.selectedTabViewItem.label UTF8String]);
  NSView *custom = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)]; b.view = custom; P("custom view of selected in tree %d\n", custom.superview == tv);
}

static void split(void) {
  P("== NSSplitView\n");
  NSSplitView *s = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 302, 202)];
  P("defaults vertical %d style %ld thickness %g arranges all %d\n", s.vertical, (long)s.dividerStyle, s.dividerThickness, s.arrangesAllSubviews);
  s.dividerStyle = NSSplitViewDividerStyleThin; P("thin thickness %g\n", s.dividerThickness);
  NSView *a = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 302, 50)], *b = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 302, 50)], *c = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 302, 100)];
  [s addSubview:a]; [s addSubview:b]; [s addSubview:c]; [s adjustSubviews];
  P("horizontal a %s b %s c %s\n", R(a.frame), R(b.frame), R(c.frame));
  P("arranged %ld flipped %d\n", (long)s.arrangedSubviews.count, s.isFlipped);
  [s setPosition:80 ofDividerAtIndex:0]; P("divider 0 at 80: a %s b %s c %s\n", R(a.frame), R(b.frame), R(c.frame));
  P("min %g max %g of divider 1\n", [s minPossiblePositionOfDividerAtIndex:1], [s maxPossiblePositionOfDividerAtIndex:1]);
  [s setPosition:500 ofDividerAtIndex:1]; P("divider 1 past the end: b %s c %s\n", R(b.frame), R(c.frame));
  [s setPosition:150 ofDividerAtIndex:1];
  s.vertical = YES; [s adjustSubviews]; P("vertical a %s b %s c %s\n", R(a.frame), R(b.frame), R(c.frame));
  [s setFrameSize:NSMakeSize(602, 202)]; [s adjustSubviews]; P("resized a %s b %s c %s\n", R(a.frame), R(b.frame), R(c.frame));
  P("collapsed %d\n", [s isSubviewCollapsed:a]);
  [b removeFromSuperview]; [s setFrameSize:NSMakeSize(601, 202)]; [s adjustSubviews]; P("two panes a %s c %s\n", R(a.frame), R(c.frame));
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    Target *t = [[Target alloc] init];
    slider(t); stepper(); progress(); segmented(t); misc(); combo(t); tabs(t); split();
    P("done\n");
  }
  return 0;
}
