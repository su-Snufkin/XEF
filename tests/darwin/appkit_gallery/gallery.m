// AppKit control gallery: one window with the controls and container views of AppKitControls2.m / AppKitTable.m.
// Build: tests/darwin/appkit_gallery/build.sh; screenshot: XEF_APPKIT_SHOT=out.ppm XEF_APPKIT_SHOT_EXIT=1.
#import <Cocoa/Cocoa.h>

@interface Model : NSObject <NSTableViewDataSource, NSOutlineViewDataSource>
@end
@implementation Model
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 6; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
  NSArray *names = @[@"Mercury", @"Venus", @"Earth", @"Mars", @"Jupiter", @"Saturn"], *moons = @[@"0", @"0", @"1", @"2", @"95", @"146"];
  return [c.identifier isEqual:@"name"] ? names[r] : moons[r]; }
- (NSInteger)outlineView:(NSOutlineView *)o numberOfChildrenOfItem:(id)i { return i ? [i count] : 2; }
- (id)outlineView:(NSOutlineView *)o child:(NSInteger)n ofItem:(id)i {
  static NSArray *roots; if (!roots) roots = @[@[@"apple", @"pear"], @[@"oak", @"pine", @"birch"]];
  return i ? i[n] : roots[n]; }
- (BOOL)outlineView:(NSOutlineView *)o isItemExpandable:(id)i { return [i isKindOfClass:[NSArray class]]; }
- (id)outlineView:(NSOutlineView *)o objectValueForTableColumn:(NSTableColumn *)c byItem:(id)i { return [i isKindOfClass:[NSArray class]] ? ([i count] == 2 ? @"Fruit" : @"Trees") : i; }
@end

static NSTextField *label(NSString *s, CGFloat x, CGFloat y, NSView *in) {
  NSTextField *l = [NSTextField labelWithString:s]; [l setFrameOrigin:NSMakePoint(x, y)]; [in addSubview:l]; return l; }

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 760, 520) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    w.title = @"AppKit gallery";
    NSView *c = w.contentView;
    static Model *model; model = [[Model alloc] init];
    const char *skip = getenv("GALLERY_SKIP") ?: "";   // letters of the sections to leave out (debugging)

    if (!strchr(skip, 'a')) {
    label(@"Slider", 20, 480, c);
    NSSlider *s1 = [[NSSlider alloc] initWithFrame:NSMakeRect(110, 476, 200, 24)]; s1.doubleValue = 0.35; [c addSubview:s1];
    NSSlider *s2 = [[NSSlider alloc] initWithFrame:NSMakeRect(110, 444, 200, 28)]; s2.numberOfTickMarks = 6; s2.doubleValue = 0.6; [c addSubview:s2];
    NSSlider *s3 = [[NSSlider alloc] initWithFrame:NSMakeRect(325, 420, 24, 84)]; s3.doubleValue = 0.75; [c addSubview:s3];
    label(@"Progress", 20, 412, c);
    NSProgressIndicator *p = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(110, 410, 200, 20)]; p.indeterminate = NO; p.doubleValue = 65; [c addSubview:p];
    NSProgressIndicator *sp = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(325, 384, 28, 28)]; sp.style = NSProgressIndicatorStyleSpinning; [c addSubview:sp];
    }
    if (!strchr(skip, 'b')) {
    label(@"Segmented", 20, 378, c);
    NSSegmentedControl *sg = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(110, 372, 200, 26)]; sg.segmentCount = 3;
    [sg setLabel:@"Day" forSegment:0]; [sg setLabel:@"Week" forSegment:1]; [sg setLabel:@"Month" forSegment:2]; sg.selectedSegment = 1; [c addSubview:sg];
    label(@"Stepper", 20, 342, c);
    NSStepper *st = [[NSStepper alloc] initWithFrame:NSMakeRect(110, 334, 19, 28)]; [c addSubview:st];
    NSSwitch *sw = [[NSSwitch alloc] initWithFrame:NSMakeRect(150, 336, 42, 24)]; sw.state = NSControlStateValueOn; [c addSubview:sw];
    NSSwitch *sw2 = [[NSSwitch alloc] initWithFrame:NSMakeRect(200, 336, 42, 24)]; [c addSubview:sw2];
    NSColorWell *cw = [[NSColorWell alloc] initWithFrame:NSMakeRect(260, 336, 44, 24)]; cw.color = [NSColor systemOrangeColor]; [c addSubview:cw];
    }
    if (!strchr(skip, 'c')) {
    label(@"Level", 20, 306, c);
    NSLevelIndicator *li = [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(110, 304, 120, 18)]; li.maxValue = 8; li.doubleValue = 5; li.warningValue = 6; li.criticalValue = 7; [c addSubview:li];
    NSLevelIndicator *ra = [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(245, 304, 80, 18)]; ra.levelIndicatorStyle = NSLevelIndicatorStyleRating; ra.maxValue = 5; ra.doubleValue = 3; [c addSubview:ra];
    label(@"Combo, date", 20, 270, c);
    NSComboBox *cb = [[NSComboBox alloc] initWithFrame:NSMakeRect(110, 266, 120, 26)]; [cb addItemsWithObjectValues:@[@"Red", @"Green", @"Blue"]]; [cb selectItemAtIndex:1]; [c addSubview:cb];
    NSDatePicker *dp = [[NSDatePicker alloc] initWithFrame:NSMakeRect(240, 266, 120, 26)]; dp.datePickerElements = NSDatePickerElementFlagYearMonthDay; dp.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    dp.dateValue = [NSDate dateWithTimeIntervalSince1970:1000000000]; [c addSubview:dp];
    }

    if (!strchr(skip, 'd')) {
    NSTabView *tv = [[NSTabView alloc] initWithFrame:NSMakeRect(20, 20, 340, 230)];
    NSTabViewItem *t1 = [[NSTabViewItem alloc] initWithIdentifier:@"split"]; t1.label = @"Split";
    NSTabViewItem *t2 = [[NSTabViewItem alloc] initWithIdentifier:@"other"]; t2.label = @"Stack";
    NSSplitView *sv = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 320, 180)]; sv.vertical = YES; sv.dividerStyle = NSSplitViewDividerStyleThin;
    NSBox *left = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 100, 180)]; left.title = @"Left"; NSBox *right = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 200, 180)]; right.title = @"Right";
    [sv addSubview:left]; [sv addSubview:right]; [sv adjustSubviews];
    t1.view = sv;
    NSStackView *stack = [NSStackView stackViewWithViews:@[[NSButton buttonWithTitle:@"One" target:nil action:NULL], [NSButton buttonWithTitle:@"Two" target:nil action:NULL], [NSButton buttonWithTitle:@"Three" target:nil action:NULL]]];
    t2.view = stack;
    [tv addTabViewItem:t1]; [tv addTabViewItem:t2]; [c addSubview:tv];
    }

    if (!strchr(skip, 'e')) {
    NSScrollView *ts = [[NSScrollView alloc] initWithFrame:NSMakeRect(380, 270, 360, 230)]; ts.hasVerticalScroller = YES; ts.borderType = NSBezelBorder;
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 360, 200)]; table.style = NSTableViewStylePlain; table.usesAlternatingRowBackgroundColors = YES;
    NSTableColumn *c1 = [[NSTableColumn alloc] initWithIdentifier:@"name"]; c1.title = @"Planet"; c1.width = 180;
    NSTableColumn *c2 = [[NSTableColumn alloc] initWithIdentifier:@"moons"]; c2.title = @"Moons"; c2.width = 100;
    [table addTableColumn:c1]; [table addTableColumn:c2]; table.dataSource = model; [table reloadData];
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
    ts.documentView = table; [c addSubview:ts];
    }

    if (!strchr(skip, 'f')) {
    NSScrollView *os = [[NSScrollView alloc] initWithFrame:NSMakeRect(380, 20, 360, 230)]; os.hasVerticalScroller = YES; os.borderType = NSBezelBorder;
    NSOutlineView *ov = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 360, 200)]; ov.style = NSTableViewStylePlain;
    NSTableColumn *oc = [[NSTableColumn alloc] initWithIdentifier:@"item"]; oc.title = @"Outline"; oc.width = 300; [ov addTableColumn:oc]; ov.outlineTableColumn = oc;
    ov.dataSource = model; [ov reloadData]; [ov expandItem:[ov itemAtRow:1]]; [ov expandItem:[ov itemAtRow:0]];
    os.documentView = ov; [c addSubview:os];
    }

    [w makeKeyAndOrderFront:nil];
    [NSApp run];
  }
  return 0;
}
