/* AppKit-lite: NSTableView (cell-based and view-based), NSTableColumn, NSTableHeaderView, NSTableRowView, NSTableCellView and
 * NSOutlineView. Geometry, selection rules, notifications and the outline's expansion bookkeeping follow real AppKit as
 * recorded by tests/darwin/mac/appkit_table.m (plain table style). */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitControls.h"
#import "AppKitTable.h"
#include <objc/runtime.h>
#include <math.h>

NSString *const NSTableViewSelectionDidChangeNotification = @"NSTableViewSelectionDidChangeNotification";
NSString *const NSTableViewSelectionIsChangingNotification = @"NSTableViewSelectionIsChangingNotification";
NSString *const NSTableViewColumnDidMoveNotification = @"NSTableViewColumnDidMoveNotification";
NSString *const NSTableViewColumnDidResizeNotification = @"NSTableViewColumnDidResizeNotification";
NSString *const NSTableViewRowViewKey = @"NSTableViewRowViewKey";
NSString *const NSOutlineViewSelectionDidChangeNotification = @"NSOutlineViewSelectionDidChangeNotification";
NSString *const NSOutlineViewSelectionIsChangingNotification = @"NSOutlineViewSelectionIsChangingNotification";
NSString *const NSOutlineViewColumnDidMoveNotification = @"NSOutlineViewColumnDidMoveNotification";
NSString *const NSOutlineViewColumnDidResizeNotification = @"NSOutlineViewColumnDidResizeNotification";
NSString *const NSOutlineViewItemWillExpandNotification = @"NSOutlineViewItemWillExpandNotification";
NSString *const NSOutlineViewItemDidExpandNotification = @"NSOutlineViewItemDidExpandNotification";
NSString *const NSOutlineViewItemWillCollapseNotification = @"NSOutlineViewItemWillCollapseNotification";
NSString *const NSOutlineViewItemDidCollapseNotification = @"NSOutlineViewItemDidCollapseNotification";
NSString *const NSOutlineViewDisclosureButtonKey = @"NSOutlineViewDisclosureButtonKey";
NSString *const NSOutlineViewShowHideButtonKey = @"NSOutlineViewShowHideButtonKey";

@interface NSObject (XEFTableInformal)
- (NSInteger)numberOfRowsInTableView:(id)t; - (id)tableView:(id)t objectValueForTableColumn:(id)c row:(NSInteger)r;
- (void)tableView:(id)t setObjectValue:(id)v forTableColumn:(id)c row:(NSInteger)r; - (void)tableView:(id)t sortDescriptorsDidChange:(NSArray *)old;
- (NSView *)tableView:(id)t viewForTableColumn:(id)c row:(NSInteger)r; - (id)tableView:(id)t rowViewForRow:(NSInteger)r;
- (void)tableView:(id)t willDisplayCell:(id)cell forTableColumn:(id)c row:(NSInteger)r; - (CGFloat)tableView:(id)t heightOfRow:(NSInteger)r;
- (BOOL)selectionShouldChangeInTableView:(id)t; - (BOOL)tableView:(id)t shouldSelectRow:(NSInteger)r; - (void)tableViewSelectionDidChange:(NSNotification *)n;
- (void)tableView:(id)t didClickTableColumn:(id)c; - (void)tableView:(id)t mouseDownInHeaderOfTableColumn:(id)c; - (BOOL)tableView:(id)t isGroupRow:(NSInteger)r;
- (void)tableViewColumnDidResize:(NSNotification *)n; - (void)tableViewColumnDidMove:(NSNotification *)n; - (id)tableView:(id)t dataCellForTableColumn:(id)c row:(NSInteger)r;
- (NSInteger)outlineView:(id)o numberOfChildrenOfItem:(id)i; - (id)outlineView:(id)o child:(NSInteger)n ofItem:(id)i; - (BOOL)outlineView:(id)o isItemExpandable:(id)i;
- (id)outlineView:(id)o objectValueForTableColumn:(id)c byItem:(id)i; - (NSView *)outlineView:(id)o viewForTableColumn:(id)c item:(id)i;
- (BOOL)outlineView:(id)o shouldExpandItem:(id)i; - (BOOL)outlineView:(id)o shouldCollapseItem:(id)i; - (BOOL)outlineView:(id)o shouldSelectItem:(id)i;
- (BOOL)selectionShouldChangeInOutlineView:(id)o; - (void)outlineView:(id)o sortDescriptorsDidChange:(NSArray *)old; - (CGFloat)outlineView:(id)o heightOfRowByItem:(id)i;
- (void)outlineView:(id)o willDisplayCell:(id)cell forTableColumn:(id)c item:(id)i; - (BOOL)outlineView:(id)o isGroupItem:(id)i;
- (void)outlineViewSelectionDidChange:(NSNotification *)n; - (void)outlineViewItemWillExpand:(NSNotification *)n; - (void)outlineViewItemDidExpand:(NSNotification *)n;
- (void)outlineViewItemWillCollapse:(NSNotification *)n; - (void)outlineViewItemDidCollapse:(NSNotification *)n;
- (void)outlineView:(id)o didClickTableColumn:(id)c;
@end

static NSDictionary *tattrs(NSFont *f, NSColor *c, NSInteger align) {
  NSMutableParagraphStyle *p = [[[NSMutableParagraphStyle alloc] init] autorelease];
  [p setAlignment:align]; [p setLineBreakMode:4];
  return @{ NSFontAttributeName: f ?: [NSFont systemFontOfSize:13], NSForegroundColorAttributeName: c ?: [NSColor controlTextColor], NSParagraphStyleAttributeName: p }; }
static NSColor *tgray(CGFloat w) { return [NSColor colorWithCalibratedWhite:w alpha:1]; }

/* ================================================================== columns */
@implementation NSTableHeaderCell
- (id)initTextCell:(NSString *)s { if ((self = [super initTextCell:s])) { [self setFont:[NSFont systemFontOfSize:11]]; } return self; }
- (void)drawSortIndicatorWithFrame:(NSRect)r inView:(NSView *)v ascending:(BOOL)asc priority:(NSInteger)p {
  if (p != 0) return;
  [tgray(0.45) setStroke]; NSBezierPath *b = [NSBezierPath bezierPath]; CGFloat cx = NSMaxX(r) - 10, cy = NSMidY(r), d = asc ? 1 : -1;
  [b moveToPoint:NSMakePoint(cx - 3, cy + 1.5 * d)]; [b lineToPoint:NSMakePoint(cx, cy - 1.5 * d)]; [b lineToPoint:NSMakePoint(cx + 3, cy + 1.5 * d)]; [b stroke]; }
- (NSRect)sortIndicatorRectForBounds:(NSRect)r { return NSMakeRect(NSMaxX(r) - 16, r.origin.y, 12, r.size.height); }
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v {
  NSString *s = [self stringValue]; NSDictionary *a = tattrs(_font, tgray(0.25), _align == 4 ? 0 : _align);
  NSSize ts = [s sizeWithAttributes:a];
  [s drawInRect:NSMakeRect(r.origin.x + 6, NSMidY(r) - ts.height / 2, r.size.width - 12, ts.height) withAttributes:a]; }
@end

@implementation NSTableColumn
- (id)init { return [self initWithIdentifier:@""]; }
- (id)initWithIdentifier:(NSString *)i {
  if ((self = [super init])) {
    _identifier = [i copy]; _width = 100; _minWidth = 10; _maxWidth = 3.40282347e+38F; _resizingMask = 3; _editable = YES;
    _headerCell = [[NSTableHeaderCell alloc] initTextCell:@"Field"];
    NSTextFieldCell *d = [[NSTextFieldCell alloc] initTextCell:@""]; [d setWraps:NO]; [d setLineBreakMode:4]; _dataCell = d; }
  return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [self initWithIdentifier:[c decodeObjectForKey:@"NSIdentifier"]])) {
    if ([c containsValueForKey:@"NSWidth"]) _width = [c decodeDoubleForKey:@"NSWidth"];
    if ([c containsValueForKey:@"NSMinWidth"]) _minWidth = [c decodeDoubleForKey:@"NSMinWidth"];
    if ([c containsValueForKey:@"NSMaxWidth"]) _maxWidth = [c decodeDoubleForKey:@"NSMaxWidth"];
    id h = [c decodeObjectForKey:@"NSHeaderCell"]; if ([h isKindOfClass:[NSCell class]]) { [_headerCell release]; _headerCell = [h retain]; }
    id d = [c decodeObjectForKey:@"NSDataCell"]; if ([d isKindOfClass:[NSCell class]]) { [_dataCell release]; _dataCell = [d retain]; }
    if ([c containsValueForKey:@"NSResizingMask"]) _resizingMask = [c decodeIntegerForKey:@"NSResizingMask"];
    if ([c containsValueForKey:@"NSIsEditable"]) _editable = [c decodeBoolForKey:@"NSIsEditable"];
    _hidden = [c decodeBoolForKey:@"NSHidden"]; _sortProto = [[c decodeObjectForKey:@"NSSortDescriptorPrototype"] retain]; _tableView = [c decodeObjectForKey:@"NSTableView"]; }
  return self; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc { [_identifier release]; [_headerToolTip release]; [_headerCell release]; [_dataCell release]; [_sortProto release]; [super dealloc]; }
- (NSString *)identifier { return _identifier; } - (void)setIdentifier:(NSString *)i { [_identifier release]; _identifier = [i copy]; }
- (NSTableView *)tableView { return _tableView; } - (void)setTableView:(NSTableView *)t { _tableView = t; }
- (void)_xefChanged { [_tableView tile]; [_tableView setNeedsDisplay:YES]; [[_tableView headerView] setNeedsDisplay:YES]; }
- (CGFloat)width { return _width; }
- (void)setWidth:(CGFloat)w {
  CGFloat old = _width; _width = fmin(fmax(w, _minWidth), _maxWidth);
  if (_width != old && _tableView) {
    [self _xefChanged];
    NSNotification *n = [NSNotification notificationWithName:NSTableViewColumnDidResizeNotification object:_tableView userInfo:@{ @"NSTableColumn": self, @"NSOldWidth": @(old) }];
    id d = [_tableView delegate]; if ([d respondsToSelector:@selector(tableViewColumnDidResize:)]) [d tableViewColumnDidResize:n];
    [[NSNotificationCenter defaultCenter] postNotification:n]; } }
- (CGFloat)minWidth { return _minWidth; } - (void)setMinWidth:(CGFloat)w { _minWidth = w; [self setWidth:_width]; }
- (CGFloat)maxWidth { return _maxWidth; } - (void)setMaxWidth:(CGFloat)w { _maxWidth = w; [self setWidth:_width]; }
- (NSString *)title { return [_headerCell stringValue]; } - (void)setTitle:(NSString *)t { [_headerCell setStringValue:t ?: @""]; [[_tableView headerView] setNeedsDisplay:YES]; }
- (id)headerCell { return _headerCell; } - (void)setHeaderCell:(NSCell *)c { [c retain]; [_headerCell release]; _headerCell = c; }
- (id)dataCell { return _dataCell; } - (void)setDataCell:(NSCell *)c { [c retain]; [_dataCell release]; _dataCell = c; }
- (id)dataCellForRow:(NSInteger)r { return _dataCell; }
- (BOOL)isEditable { return _editable; } - (void)setEditable:(BOOL)f { _editable = f; }
- (BOOL)isHidden { return _hidden; } - (void)setHidden:(BOOL)f { if (f != _hidden) { _hidden = f; [self _xefChanged]; } }
- (NSUInteger)resizingMask { return _resizingMask; } - (void)setResizingMask:(NSUInteger)m { _resizingMask = m; }
- (BOOL)isResizable { return _resizingMask != 0; } - (void)setResizable:(BOOL)f { _resizingMask = f ? 3 : 0; }
- (NSSortDescriptor *)sortDescriptorPrototype { return _sortProto; } - (void)setSortDescriptorPrototype:(NSSortDescriptor *)s { [s retain]; [_sortProto release]; _sortProto = s; }
- (NSString *)headerToolTip { return _headerToolTip; } - (void)setHeaderToolTip:(NSString *)t { [_headerToolTip release]; _headerToolTip = [t copy]; }
- (void)sizeToFit { [self setWidth:ceil([[_headerCell stringValue] sizeWithAttributes:tattrs([_headerCell font], nil, 0)].width) + 14]; }
@end

/* ================================================================== header */
@implementation NSTableHeaderView
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { _pressed = _resized = _dragged = -1; } return self; }
- (id)initWithCoder:(NSCoder *)c { if ((self = [super initWithCoder:c])) { _pressed = _resized = _dragged = -1; _tableView = [c decodeObjectForKey:@"NSTableView"]; } return self; }
- (BOOL)isFlipped { return YES; }
- (NSTableView *)tableView { return _tableView; } - (void)setTableView:(NSTableView *)t { _tableView = t; }
- (NSInteger)draggedColumn { return _dragged; } - (CGFloat)draggedDistance { return 0; } - (NSInteger)resizedColumn { return _resized; }
- (NSRect)headerRectOfColumn:(NSInteger)c { NSRect r = [_tableView rectOfColumn:c]; return NSMakeRect(r.origin.x, 0, r.size.width, _bounds.size.height); }
- (NSInteger)columnAtPoint:(NSPoint)p { return [_tableView columnAtPoint:NSMakePoint(p.x, 0)]; }
- (void)drawRect:(NSRect)r {
  [[NSColor whiteColor] setFill]; NSRectFill(_bounds);
  NSArray *cols = [_tableView tableColumns]; NSArray *sorts = [_tableView sortDescriptors];
  for (NSUInteger i = 0; i < [cols count]; i++) {
    NSTableColumn *c = cols[i]; if ([c isHidden]) continue;
    NSRect hr = [self headerRectOfColumn:i];
    if ((NSInteger)i == _pressed) { [tgray(0.9) setFill]; NSRectFill(hr); }
    [[c headerCell] drawWithFrame:hr inView:self];
    NSSortDescriptor *first = [sorts count] ? sorts[0] : nil;
    if (first && [c sortDescriptorPrototype] && [[first key] isEqual:[[c sortDescriptorPrototype] key]] && [[c headerCell] respondsToSelector:@selector(drawSortIndicatorWithFrame:inView:ascending:priority:)])
      [(NSTableHeaderCell *)[c headerCell] drawSortIndicatorWithFrame:hr inView:self ascending:[first ascending] priority:0];
    [tgray(0.85) setFill]; NSRectFill(NSMakeRect(NSMaxX(hr) - 1, 4, 1, _bounds.size.height - 8)); }
  [tgray(0.8) setFill]; NSRectFill(NSMakeRect(0, _bounds.size.height - 1, _bounds.size.width, 1)); }
- (void)mouseDown:(NSEvent *)e {
  NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil]; NSArray *cols = [_tableView tableColumns];
  /* a drag on a column's right edge resizes it */
  for (NSUInteger i = 0; i < [cols count] && [_tableView allowsColumnResizing]; i++) {
    NSTableColumn *c = cols[i]; NSRect hr = [self headerRectOfColumn:i];
    if ([c isHidden] || !([c resizingMask] & 2) || fabs(p.x - NSMaxX(hr)) > 3) continue;
    _resized = i; CGFloat start = p.x, w0 = [c width];
    for (;;) {
      NSEvent *n = XEFNextTrackingEvent(); if (!n) continue;
      if ([n type] == NSEventTypeLeftMouseUp) break;
      [c setWidth:w0 + [self convertPoint:[n locationInWindow] fromView:nil].x - start]; XEFRedrawWindowNow(_window); }
    _resized = -1; return; }
  NSInteger col = [self columnAtPoint:p]; if (col < 0) return;
  NSTableColumn *c = cols[col]; id d = [_tableView delegate]; BOOL outline = [_tableView isKindOfClass:[NSOutlineView class]];
  if (!outline && [d respondsToSelector:@selector(tableView:mouseDownInHeaderOfTableColumn:)]) [d tableView:_tableView mouseDownInHeaderOfTableColumn:c];
  _pressed = col; [self setNeedsDisplay:YES]; XEFRedrawWindowNow(_window);
  BOOL inside = YES;
  for (;;) { NSEvent *n = XEFNextTrackingEvent(); if (!n) continue; if ([n type] == NSEventTypeLeftMouseUp) { inside = [self columnAtPoint:[self convertPoint:[n locationInWindow] fromView:nil]] == col; break; } }
  _pressed = -1; [self setNeedsDisplay:YES];
  if (!inside) return;
  NSSortDescriptor *proto = [c sortDescriptorPrototype];
  if (proto) {
    NSMutableArray *sorts = [NSMutableArray arrayWithArray:[_tableView sortDescriptors] ?: @[]]; NSSortDescriptor *next = proto;
    if ([sorts count] && [[sorts[0] key] isEqual:[proto key]]) next = [sorts[0] reversedSortDescriptor];
    for (NSSortDescriptor *s in [[sorts copy] autorelease]) if ([[s key] isEqual:[proto key]]) [sorts removeObject:s];
    [sorts insertObject:next atIndex:0]; [_tableView setSortDescriptors:sorts]; }
  if (outline) { if ([d respondsToSelector:@selector(outlineView:didClickTableColumn:)]) [d outlineView:_tableView didClickTableColumn:c]; }
  else if ([d respondsToSelector:@selector(tableView:didClickTableColumn:)]) [d tableView:_tableView didClickTableColumn:c]; }
@end

/* ================================================================== row and cell views */
@implementation NSTableRowView
- (BOOL)isFlipped { return YES; }
- (void)dealloc { [_bg release]; [super dealloc]; }
- (BOOL)isSelected { return _selected; } - (void)setSelected:(BOOL)f { _selected = f; [self setNeedsDisplay:YES]; }
- (BOOL)isEmphasized { return _emphasized; } - (void)setEmphasized:(BOOL)f { _emphasized = f; [self setNeedsDisplay:YES]; }
- (BOOL)isGroupRowStyle { return _groupRow; } - (void)setGroupRowStyle:(BOOL)f { _groupRow = f; }
- (BOOL)isFloating { return _floating; } - (void)setFloating:(BOOL)f { _floating = f; }
- (BOOL)isPreviousRowSelected { return _previousSelected; } - (void)setPreviousRowSelected:(BOOL)f { _previousSelected = f; }
- (BOOL)isNextRowSelected { return _nextSelected; } - (void)setNextRowSelected:(BOOL)f { _nextSelected = f; }
- (BOOL)isTargetForDropOperation { return _targetForDrop; } - (void)setTargetForDropOperation:(BOOL)f { _targetForDrop = f; }
- (NSInteger)selectionHighlightStyle { return _highlightStyle; } - (void)setSelectionHighlightStyle:(NSInteger)s { _highlightStyle = s; }
- (NSInteger)draggingDestinationFeedbackStyle { return 0; } - (void)setDraggingDestinationFeedbackStyle:(NSInteger)s {}
- (CGFloat)indentationForDropOperation { return _dropIndent; } - (void)setIndentationForDropOperation:(CGFloat)i { _dropIndent = i; }
- (NSInteger)interiorBackgroundStyle { return _selected && _emphasized ? 3 : 0; }
- (NSColor *)backgroundColor { return _bg ?: [NSColor controlBackgroundColor]; } - (void)setBackgroundColor:(NSColor *)c { [c retain]; [_bg release]; _bg = c; }
- (NSInteger)numberOfColumns { return [_subviews count]; }
- (id)viewAtColumn:(NSInteger)c { return c >= 0 && c < (NSInteger)[_subviews count] ? _subviews[c] : nil; }
- (void)drawBackgroundInRect:(NSRect)r { if (_bg) { [_bg setFill]; NSRectFill(r); } }
- (void)drawSelectionInRect:(NSRect)r { [(_emphasized ? [NSColor alternateSelectedControlColor] : tgray(0.86)) setFill]; NSRectFill(_bounds); }
- (void)drawSeparatorInRect:(NSRect)r {} - (void)drawDraggingDestinationFeedbackInRect:(NSRect)r {}
- (void)drawRect:(NSRect)r { [self drawBackgroundInRect:r]; if (_selected) [self drawSelectionInRect:r]; }
@end

@implementation NSTableCellView
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) { _textField = [c decodeObjectForKey:@"NSTextField"]; _imageView = [c decodeObjectForKey:@"NSImageView"]; }
  return self; }
- (void)dealloc { [_objectValue release]; [_dragging release]; [super dealloc]; }
- (id)objectValue { return _objectValue; }
- (void)setObjectValue:(id)v { [v retain]; [_objectValue release]; _objectValue = v; }
- (NSTextField *)textField { return _textField; } - (void)setTextField:(NSTextField *)t { _textField = t; }
- (id)imageView { return _imageView; } - (void)setImageView:(id)i { _imageView = i; }
- (NSInteger)backgroundStyle { return _backgroundStyle; }
- (void)setBackgroundStyle:(NSInteger)s {
  _backgroundStyle = s;
  if (_textField && [[_textField cell] respondsToSelector:@selector(setBackgroundStyle:)]) [(id)[_textField cell] setBackgroundStyle:s]; }
- (NSInteger)rowSizeStyle { return _rowSizeStyle; } - (void)setRowSizeStyle:(NSInteger)s { _rowSizeStyle = s; }
- (NSArray *)draggingImageComponents { return _dragging ?: @[]; }
@end

/* ================================================================== NSTableView */
@implementation NSTableView
- (void)_xefCommonInit {
  _columns = [[NSMutableArray alloc] init]; _sel = [[NSMutableIndexSet alloc] init]; _selCols = [[NSMutableIndexSet alloc] init];
  _rowHeight = 24; _spacing = NSMakeSize(17, 0); _empty = YES; _reorder = YES; _resize = YES; _clickedRow = _clickedCol = _editedRow = _editedCol = -1; _anchor = -1;
  _autoresizingStyle = 4; _typeSelect = YES; _floatsGroups = YES; _verticalMotion = YES;
  _views = [[NSMutableDictionary alloc] init]; _rowViews = [[NSMutableDictionary alloc] init]; _reuse = [[NSMutableDictionary alloc] init]; _nibs = [[NSMutableDictionary alloc] init];
  _header = [[NSTableHeaderView alloc] initWithFrame:NSMakeRect(0, 0, _frame.size.width, 23)]; [_header setTableView:self];
  _corner = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 15, 23)]; }
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { [self _xefCommonInit]; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    [self _xefCommonInit];
    for (NSTableColumn *col in [c decodeObjectForKey:@"NSTableColumns"]) if ([col isKindOfClass:[NSTableColumn class]]) { [_columns addObject:col]; [col setTableView:self]; }
    if ([c containsValueForKey:@"NSRowHeight"]) _rowHeight = [c decodeDoubleForKey:@"NSRowHeight"];
    if ([c containsValueForKey:@"NSIntercellSpacingWidth"]) _spacing.width = [c decodeDoubleForKey:@"NSIntercellSpacingWidth"];
    if ([c containsValueForKey:@"NSIntercellSpacingHeight"]) _spacing.height = [c decodeDoubleForKey:@"NSIntercellSpacingHeight"];
    id h = [c decodeObjectForKey:@"NSHeaderView"];
    if ([h isKindOfClass:[NSTableHeaderView class]]) { [_header release]; _header = [h retain]; [_header setTableView:self]; }
    else if ([c containsValueForKey:@"NSHeaderView"] || ![c containsValueForKey:@"NSTableColumns"]) {} else { [_header release]; _header = nil; }
    uint32_t fl = (uint32_t)[c decodeIntForKey:@"NSTvFlags"];
    _multiple = (fl & 0x08000000) != 0; _empty = (fl & 0x10000000) != 0; _columnSelection = (fl & 0x04000000) != 0; _alternating = (fl & 0x00800000) != 0;
    _gridMask = [c decodeIntegerForKey:@"NSGridStyleMask"]; _bg = [[c decodeObjectForKey:@"NSBackgroundColor"] retain]; _grid = [[c decodeObjectForKey:@"NSGridColor"] retain];
    _dataSource = [c decodeObjectForKey:@"NSDataSource"]; _delegate = [c decodeObjectForKey:@"NSDelegate"]; _autosave = [[c decodeObjectForKey:@"NSAutosaveName"] copy]; }
  return self; }
- (void)dealloc {
  for (NSTableColumn *c in _columns) [c setTableView:nil];
  [_header setTableView:nil]; [_header release]; [_corner release]; [_columns release]; [_sel release]; [_selCols release]; [_sortDescriptors release]; [_bg release]; [_grid release]; [_autosave release];
  [_views release]; [_rowViews release]; [_reuse release]; [_nibs release]; free(_offsets); [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isOpaque { return YES; }
- (id)dataSource { return _dataSource; } - (void)setDataSource:(id)d { _dataSource = d; [self reloadData]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; [self _xefDropViews]; [self tile]; [self setNeedsDisplay:YES]; }
- (NSTableHeaderView *)headerView { return _header; }
- (void)setHeaderView:(NSTableHeaderView *)h { [h retain]; [_header setTableView:nil]; [_header release]; _header = h; [h setTableView:self]; [[self enclosingScrollView] tile]; }
- (NSView *)cornerView { return _corner; } - (void)setCornerView:(NSView *)v { [v retain]; [_corner release]; _corner = v; }
#define FLAG(get, set, ivar) - (BOOL)get { return ivar; } - (void)set:(BOOL)f { ivar = f; }
#define INTP(get, set, ivar) - (NSInteger)get { return ivar; } - (void)set:(NSInteger)v { ivar = v; [self setNeedsDisplay:YES]; }
FLAG(allowsMultipleSelection, setAllowsMultipleSelection, _multiple) FLAG(allowsEmptySelection, setAllowsEmptySelection, _empty)
FLAG(allowsColumnSelection, setAllowsColumnSelection, _columnSelection) FLAG(allowsColumnReordering, setAllowsColumnReordering, _reorder)
FLAG(allowsColumnResizing, setAllowsColumnResizing, _resize) FLAG(allowsTypeSelect, setAllowsTypeSelect, _typeSelect)
FLAG(floatsGroupRows, setFloatsGroupRows, _floatsGroups) FLAG(autosaveTableColumns, setAutosaveTableColumns, _autosaveColumns)
FLAG(usesAutomaticRowHeights, setUsesAutomaticRowHeights, _usesAutoHeights) FLAG(usesStaticContents, setUsesStaticContents, _usesStatic)
FLAG(verticalMotionCanBeginDrag, setVerticalMotionCanBeginDrag, _verticalMotion)
INTP(style, setStyle, _style) INTP(selectionHighlightStyle, setSelectionHighlightStyle, _highlightStyle) INTP(rowSizeStyle, setRowSizeStyle, _rowSizeStyle)
INTP(draggingDestinationFeedbackStyle, setDraggingDestinationFeedbackStyle, _draggingStyle) INTP(userInterfaceLayoutDirection, setUserInterfaceLayoutDirection, _layoutDirection)
- (NSInteger)effectiveStyle { return _style ? _style : 4; } - (NSInteger)effectiveRowSizeStyle { return _rowSizeStyle > 0 ? _rowSizeStyle : 2; }
- (BOOL)usesAlternatingRowBackgroundColors { return _alternating; } - (void)setUsesAlternatingRowBackgroundColors:(BOOL)f { _alternating = f; [self setNeedsDisplay:YES]; }
- (NSUInteger)gridStyleMask { return _gridMask; } - (void)setGridStyleMask:(NSUInteger)m { _gridMask = m; [self setNeedsDisplay:YES]; }
- (NSUInteger)columnAutoresizingStyle { return _autoresizingStyle; } - (void)setColumnAutoresizingStyle:(NSUInteger)s { _autoresizingStyle = s; }
- (NSColor *)backgroundColor { return _bg ?: [NSColor controlBackgroundColor]; } - (void)setBackgroundColor:(NSColor *)c { [c retain]; [_bg release]; _bg = c; [self setNeedsDisplay:YES]; }
- (NSColor *)gridColor { return _grid ?: [NSColor gridColor]; } - (void)setGridColor:(NSColor *)c { [c retain]; [_grid release]; _grid = c; }
- (NSString *)autosaveName { return _autosave; } - (void)setAutosaveName:(NSString *)n { [_autosave release]; _autosave = [n copy]; }
- (SEL)doubleAction { return _doubleAction; } - (void)setDoubleAction:(SEL)a { _doubleAction = a; }
- (NSInteger)clickedRow { return _clickedRow; } - (NSInteger)clickedColumn { return _clickedCol; } - (NSInteger)editedRow { return _editedRow; } - (NSInteger)editedColumn { return _editedCol; }
- (NSTableColumn *)highlightedTableColumn { return _highlightedColumn; } - (void)setHighlightedTableColumn:(NSTableColumn *)c { _highlightedColumn = c; [_header setNeedsDisplay:YES]; }
- (NSImage *)indicatorImageInTableColumn:(NSTableColumn *)c { return nil; } - (void)setIndicatorImage:(NSImage *)i inTableColumn:(NSTableColumn *)c {}
- (NSArray *)registeredNibsByIdentifier { return _nibs; } - (void)registerNib:(id)nib forIdentifier:(NSString *)i { if (nib) _nibs[i] = nib; else [_nibs removeObjectForKey:i]; }
- (NSArray *)hiddenRowIndexes { return (id)[NSIndexSet indexSet]; } - (void)hideRowsAtIndexes:(NSIndexSet *)s withAnimation:(NSUInteger)a {} - (void)unhideRowsAtIndexes:(NSIndexSet *)s withAnimation:(NSUInteger)a {}
- (void)setDraggingSourceOperationMask:(NSUInteger)m forLocal:(BOOL)l {} - (void)setDropRow:(NSInteger)r dropOperation:(NSUInteger)o {}
- (BOOL)canDragRowsWithIndexes:(NSIndexSet *)s atPoint:(NSPoint)p { return NO; }
- (id)dragImageForRowsWithIndexes:(NSIndexSet *)s tableColumns:(NSArray *)c event:(NSEvent *)e offset:(NSPointPointer)o { return nil; }
- (NSArray *)rowActionsVisible { return NO ? nil : nil; } - (void)setRowActionsVisible:(BOOL)f {}
- (void)editColumn:(NSInteger)c row:(NSInteger)r withEvent:(NSEvent *)e select:(BOOL)s {}
- (void)highlightSelectionInClipRect:(NSRect)r {} - (void)drawGridInClipRect:(NSRect)r {} - (void)drawBackgroundInClipRect:(NSRect)r {}
- (void)sizeLastColumnToFit {
  NSTableColumn *last = nil; CGFloat used = 0; NSView *sup = _superview;
  for (NSTableColumn *c in _columns) if (![c isHidden]) { used += [c width] + _spacing.width; last = c; }
  if (last && sup) [last setWidth:[last width] + [sup bounds].size.width - used]; }
- (void)sizeToFit { [self tile]; }
- (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)s { [self tile]; [self setNeedsDisplay:YES]; }
- (void)scrollRowToVisible:(NSInteger)r { if (r >= 0 && r < _rows) [self scrollRectToVisible:[self rectOfRow:r]]; }
- (void)scrollColumnToVisible:(NSInteger)c { if (c >= 0 && c < (NSInteger)[_columns count]) { NSRect cr = [self rectOfColumn:c], v = [self visibleRect]; [self scrollRectToVisible:NSMakeRect(cr.origin.x, v.origin.y, cr.size.width, 1)]; } }
- (CGFloat)rowHeight { return _rowHeight; } - (void)setRowHeight:(CGFloat)h { _rowHeight = h; [self tile]; [self setNeedsDisplay:YES]; }
- (NSSize)intercellSpacing { return _spacing; } - (void)setIntercellSpacing:(NSSize)s { _spacing = s; [self tile]; [self setNeedsDisplay:YES]; }

/* ---- columns */
- (NSArray *)tableColumns { return [[_columns copy] autorelease]; }
- (NSInteger)numberOfColumns { return [_columns count]; }
- (void)addTableColumn:(NSTableColumn *)c { if (!c || [_columns containsObject:c]) return; [_columns addObject:c]; [c setTableView:self]; [self _xefDropViews]; [self tile]; [self setNeedsDisplay:YES]; }
- (void)removeTableColumn:(NSTableColumn *)c { if (![_columns containsObject:c]) return; [[c retain] autorelease]; [_columns removeObject:c]; [c setTableView:nil]; [self _xefDropViews]; [self tile]; [self setNeedsDisplay:YES]; }
- (void)moveColumn:(NSInteger)a toColumn:(NSInteger)b {
  if (a < 0 || b < 0 || a >= (NSInteger)[_columns count] || b >= (NSInteger)[_columns count] || a == b) return;
  NSTableColumn *c = [[_columns[a] retain] autorelease]; [_columns removeObjectAtIndex:a]; [_columns insertObject:c atIndex:b];
  [self _xefDropViews]; [self tile]; [self setNeedsDisplay:YES];
  NSNotification *n = [NSNotification notificationWithName:NSTableViewColumnDidMoveNotification object:self userInfo:@{ @"NSOldColumn": @(a), @"NSNewColumn": @(b) }];
  if ([_delegate respondsToSelector:@selector(tableViewColumnDidMove:)]) [_delegate tableViewColumnDidMove:n];
  [[NSNotificationCenter defaultCenter] postNotification:n]; }
- (NSInteger)columnWithIdentifier:(NSString *)i { for (NSUInteger k = 0; k < [_columns count]; k++) if ([[_columns[k] identifier] isEqual:i]) return k; return -1; }
- (NSTableColumn *)tableColumnWithIdentifier:(NSString *)i { NSInteger k = [self columnWithIdentifier:i]; return k < 0 ? nil : _columns[k]; }
- (NSArray *)sortDescriptors { return _sortDescriptors ?: @[]; }
- (void)_xefSortChanged:(NSArray *)old { if ([_dataSource respondsToSelector:@selector(tableView:sortDescriptorsDidChange:)]) [_dataSource tableView:self sortDescriptorsDidChange:old]; }
- (void)setSortDescriptors:(NSArray *)a {
  NSArray *old = [[[self sortDescriptors] retain] autorelease];
  if ([old isEqual:a ?: @[]]) return;
  [_sortDescriptors release]; _sortDescriptors = [a copy]; [_header setNeedsDisplay:YES];
  [self _xefSortChanged:old]; }

/* ---- rows and geometry */
- (NSInteger)_xefFetchRowCount { return [_dataSource respondsToSelector:@selector(numberOfRowsInTableView:)] ? [_dataSource numberOfRowsInTableView:self] : 0; }
- (CGFloat)_xefHeightOfRow:(NSInteger)r { return [_delegate respondsToSelector:@selector(tableView:heightOfRow:)] ? [_delegate tableView:self heightOfRow:r] : _rowHeight; }
- (BOOL)_xefVariableHeights { return [_delegate respondsToSelector:@selector(tableView:heightOfRow:)]; }
- (NSInteger)numberOfRows { return _rows; }
- (CGFloat)_xefRowY:(NSInteger)r { return _offsets && r <= _noffsets ? _offsets[r] : r * (_rowHeight + _spacing.height); }
- (void)tile {
  free(_offsets); _offsets = NULL; _noffsets = 0;
  if (_rows > 0 && [self _xefVariableHeights]) {
    _offsets = malloc(sizeof(CGFloat) * (_rows + 1)); _noffsets = _rows; CGFloat y = 0;
    for (NSInteger r = 0; r < _rows; r++) { _offsets[r] = y; y += [self _xefHeightOfRow:r] + _spacing.height; }
    _offsets[_rows] = y; }
  CGFloat w = 0; for (NSTableColumn *c in _columns) if (![c isHidden]) w += [c width] + _spacing.width;
  CGFloat h = [self _xefRowY:_rows];
  if ([_superview isKindOfClass:[NSClipView class]]) { NSSize cs = [_superview bounds].size; w = fmax(w, cs.width); h = fmax(h, cs.height); }
  _frame.size = NSMakeSize(w, h); _bounds.size = _frame.size;
  if (_header) { NSRect hf = [_header frame]; hf.size.width = w; [_header setFrame:hf]; }
  if ([_superview isKindOfClass:[NSClipView class]] && [[_superview superview] respondsToSelector:@selector(reflectScrolledClipView:)]) [(id)[_superview superview] reflectScrolledClipView:(id)_superview]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; if (_window) [self tile]; }
- (void)_xefDropViews {
  for (NSView *v in [_views allValues]) [v removeFromSuperview];
  [_views removeAllObjects]; [_rowViews removeAllObjects]; }
- (void)reloadData {
  _rows = [self _xefFetchRowCount];
  NSMutableIndexSet *keep = [[_sel mutableCopy] autorelease]; [keep removeIndexesInRange:NSMakeRange(_rows, NSNotFound - _rows - 1)];
  [_sel removeAllIndexes]; [_sel addIndexes:keep];
  [self _xefDropViews]; [self tile]; [self setNeedsDisplay:YES]; }
- (void)reloadDataForRowIndexes:(NSIndexSet *)rows columnIndexes:(NSIndexSet *)cols { [self _xefDropViews]; [self setNeedsDisplay:YES]; }
- (void)noteNumberOfRowsChanged {
  _rows = [self _xefFetchRowCount];
  NSMutableIndexSet *keep = [[_sel mutableCopy] autorelease]; [keep removeIndexesInRange:NSMakeRange(_rows, NSNotFound - _rows - 1)];
  [self _xefDropViews]; [self tile]; [self _xefSetSelection:keep notify:YES]; [self setNeedsDisplay:YES]; }
- (NSRect)rectOfRow:(NSInteger)r {
  if (r < 0 || r >= _rows) return NSZeroRect;
  CGFloat y = [self _xefRowY:r]; return NSMakeRect(0, y, _bounds.size.width, [self _xefRowY:r + 1] - y); }
- (NSRect)rectOfColumn:(NSInteger)c {
  if (c < 0 || c >= (NSInteger)[_columns count] || [_columns[c] isHidden]) return NSZeroRect;
  CGFloat x = 0; for (NSInteger i = 0; i < c; i++) if (![_columns[i] isHidden]) x += [_columns[i] width] + _spacing.width;
  return NSMakeRect(x, 0, [_columns[c] width] + _spacing.width, _bounds.size.height); }
- (CGFloat)_xefIndentForColumn:(NSInteger)c row:(NSInteger)r { return 0; }
- (NSRect)frameOfCellAtColumn:(NSInteger)c row:(NSInteger)r {
  if (c < 0 || c >= (NSInteger)[_columns count] || r < 0 || r >= _rows) return NSZeroRect;
  NSRect cr = [self rectOfColumn:c], rr = [self rectOfRow:r]; CGFloat ind = [self _xefIndentForColumn:c row:r];
  return NSMakeRect(floor(cr.origin.x + _spacing.width / 2) + ind, rr.origin.y + floor(_spacing.height / 2), fmax(0, [_columns[c] width] - ind), rr.size.height - _spacing.height); }
- (NSInteger)rowAtPoint:(NSPoint)p {
  if (p.y < 0 || p.x < 0 || p.x >= _bounds.size.width || _rows <= 0) return -1;
  if (!_offsets) { CGFloat h = _rowHeight + _spacing.height; NSInteger r = h > 0 ? (NSInteger)floor(p.y / h) : -1; return r < _rows ? r : -1; }
  for (NSInteger r = 0; r < _rows; r++) if (p.y < _offsets[r + 1]) return r;
  return -1; }
- (NSInteger)columnAtPoint:(NSPoint)p {
  CGFloat x = 0; if (p.x < 0) return -1;
  for (NSUInteger i = 0; i < [_columns count]; i++) { if ([_columns[i] isHidden]) continue; x += [_columns[i] width] + _spacing.width; if (p.x < x) return i; }
  return -1; }
- (NSRange)rowsInRect:(NSRect)r {
  NSInteger first = -1, last = -1;
  for (NSInteger i = 0; i < _rows; i++) { CGFloat y0 = [self _xefRowY:i], y1 = [self _xefRowY:i + 1]; if (y1 > r.origin.y && y0 < NSMaxY(r)) { if (first < 0) first = i; last = i; } else if (first >= 0) break; }
  return first < 0 ? NSMakeRange(0, 0) : NSMakeRange(first, last - first + 1); }
- (NSIndexSet *)columnIndexesInRect:(NSRect)r {
  NSMutableIndexSet *s = [NSMutableIndexSet indexSet];
  for (NSUInteger i = 0; i < [_columns count]; i++) { NSRect cr = [self rectOfColumn:i]; if (cr.size.width > 0 && NSMaxX(cr) >= r.origin.x && cr.origin.x <= NSMaxX(r)) [s addIndex:i]; }
  return s; }
- (NSRange)columnsInRect:(NSRect)r { NSIndexSet *s = [self columnIndexesInRect:r]; return [s count] ? NSMakeRange([s firstIndex], [s lastIndex] - [s firstIndex] + 1) : NSMakeRange(0, 0); }

/* ---- selection */
- (void)_xefSelectionChanged {
  NSNotification *n = [NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self];
  if ([_delegate respondsToSelector:@selector(tableViewSelectionDidChange:)]) [_delegate tableViewSelectionDidChange:n];
  [[NSNotificationCenter defaultCenter] postNotification:n]; }
- (void)_xefSetSelection:(NSIndexSet *)s notify:(BOOL)notify {
  if ([_sel isEqualToIndexSet:s]) return;
  [_sel removeAllIndexes]; [_sel addIndexes:s]; [self setNeedsDisplay:YES];
  if (notify) [self _xefSelectionChanged]; }
- (NSIndexSet *)selectedRowIndexes { return [[_sel copy] autorelease]; }
- (NSInteger)selectedRow { return [_sel count] ? (NSInteger)[_sel lastIndex] : -1; }
- (NSInteger)numberOfSelectedRows { return [_sel count]; }
- (BOOL)isRowSelected:(NSInteger)r { return r >= 0 && [_sel containsIndex:r]; }
- (void)selectRowIndexes:(NSIndexSet *)s byExtendingSelection:(BOOL)extend {
  NSMutableIndexSet *n = extend ? [[_sel mutableCopy] autorelease] : [NSMutableIndexSet indexSet];
  [n addIndexes:s]; [n removeIndexesInRange:NSMakeRange(_rows, NSNotFound - _rows - 1)];
  if (![n count] && !_empty && [_sel count]) return;
  if ([s count]) _anchor = [s firstIndex];
  [self _xefSetSelection:n notify:YES]; }
- (void)selectRow:(NSInteger)r byExtendingSelection:(BOOL)e { [self selectRowIndexes:[NSIndexSet indexSetWithIndex:r] byExtendingSelection:e]; }
- (void)deselectRow:(NSInteger)r {
  if (![_sel containsIndex:r] || (!_empty && [_sel count] == 1)) return;
  NSMutableIndexSet *n = [[_sel mutableCopy] autorelease]; [n removeIndex:r]; [self _xefSetSelection:n notify:YES]; }
- (BOOL)_xefSelectionShouldChange { return [_delegate respondsToSelector:@selector(selectionShouldChangeInTableView:)] ? [_delegate selectionShouldChangeInTableView:self] : YES; }
- (BOOL)_xefShouldSelectRow:(NSInteger)r { return [_delegate respondsToSelector:@selector(tableView:shouldSelectRow:)] ? [_delegate tableView:self shouldSelectRow:r] : YES; }
- (void)selectAll:(id)sender {
  if (!_multiple || ![self _xefSelectionShouldChange]) return;
  NSMutableIndexSet *n = [NSMutableIndexSet indexSet];
  for (NSInteger r = 0; r < _rows; r++) if ([self _xefShouldSelectRow:r]) [n addIndex:r];
  [self _xefSetSelection:n notify:YES]; }
- (void)deselectAll:(id)sender {
  if (!_empty || ![self _xefSelectionShouldChange]) return;
  [_selCols removeAllIndexes]; [self _xefSetSelection:[NSIndexSet indexSet] notify:YES]; }
- (NSIndexSet *)selectedColumnIndexes { return [[_selCols copy] autorelease]; }
- (NSInteger)selectedColumn { return [_selCols count] ? (NSInteger)[_selCols lastIndex] : -1; }
- (NSInteger)numberOfSelectedColumns { return [_selCols count]; }
- (BOOL)isColumnSelected:(NSInteger)c { return c >= 0 && [_selCols containsIndex:c]; }
- (void)selectColumnIndexes:(NSIndexSet *)s byExtendingSelection:(BOOL)e {
  NSMutableIndexSet *n = e ? [[_selCols mutableCopy] autorelease] : [NSMutableIndexSet indexSet]; [n addIndexes:s];
  if ([n isEqualToIndexSet:_selCols]) return;
  [_selCols removeAllIndexes]; [_selCols addIndexes:n]; [self setNeedsDisplay:YES]; [self _xefSelectionChanged]; }
- (void)deselectColumn:(NSInteger)c { if ([_selCols containsIndex:c]) { [_selCols removeIndex:c]; [self setNeedsDisplay:YES]; [self _xefSelectionChanged]; } }

/* ---- row updates */
- (void)beginUpdates { _updates++; } - (void)endUpdates { if (_updates > 0) _updates--; }
- (void)insertRowsAtIndexes:(NSIndexSet *)s withAnimation:(NSUInteger)a {
  NSMutableIndexSet *sel = _sel;
  [s enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [sel shiftIndexesStartingAtIndex:i by:1]; }];
  _rows += [s count]; [self _xefDropViews]; [self tile]; [self setNeedsDisplay:YES]; }
- (void)removeRowsAtIndexes:(NSIndexSet *)s withAnimation:(NSUInteger)a {
  NSMutableIndexSet *n = [[_sel mutableCopy] autorelease]; __block BOOL changed = NO;
  [s enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger i, BOOL *stop) {
    if ([n containsIndex:i]) { [n removeIndex:i]; changed = YES; }
    [n shiftIndexesStartingAtIndex:i + 1 by:-1]; }];
  _rows = _rows > (NSInteger)[s count] ? _rows - [s count] : 0;
  [self _xefDropViews]; [self tile];
  [_sel removeAllIndexes]; [_sel addIndexes:n]; [self setNeedsDisplay:YES];
  if (changed) [self _xefSelectionChanged]; }
- (void)moveRowAtIndex:(NSInteger)from toIndex:(NSInteger)to {
  BOOL was = [_sel containsIndex:from];
  [_sel removeIndex:from]; [_sel shiftIndexesStartingAtIndex:from + 1 by:-1]; [_sel shiftIndexesStartingAtIndex:to by:1]; if (was) [_sel addIndex:to];
  [self _xefDropViews]; [self setNeedsDisplay:YES]; }

/* ---- content */
- (BOOL)_xefViewBased { return [_delegate respondsToSelector:@selector(tableView:viewForTableColumn:row:)]; }
- (id)_xefObjectValueForColumn:(NSTableColumn *)c row:(NSInteger)r {
  return [_dataSource respondsToSelector:@selector(tableView:objectValueForTableColumn:row:)] ? [_dataSource tableView:self objectValueForTableColumn:c row:r] : nil; }
- (NSView *)_xefMakeViewForColumn:(NSTableColumn *)c row:(NSInteger)r { return [_delegate tableView:self viewForTableColumn:c row:r]; }
- (void)_xefWillDisplayCell:(NSCell *)cell column:(NSTableColumn *)c row:(NSInteger)r {
  if ([_delegate respondsToSelector:@selector(tableView:willDisplayCell:forTableColumn:row:)]) [_delegate tableView:self willDisplayCell:cell forTableColumn:c row:r]; }
- (id)makeViewWithIdentifier:(NSString *)ident owner:(id)owner {
  NSMutableArray *q = _reuse[ident ?: @""];
  if ([q count]) { NSView *v = [[[q lastObject] retain] autorelease]; [q removeLastObject]; if ([v respondsToSelector:@selector(prepareForReuse)]) [v performSelector:@selector(prepareForReuse)]; return v; }
  return nil; }
- (NSView *)viewAtColumn:(NSInteger)c row:(NSInteger)r makeIfNecessary:(BOOL)make {
  if (c < 0 || c >= (NSInteger)[_columns count] || r < 0 || r >= _rows || ![self _xefViewBased]) return nil;
  NSNumber *key = @(r * 4096 + c); NSView *v = _views[key];
  if (v || !make) return v;
  v = [self _xefMakeViewForColumn:_columns[c] row:r]; if (!v) return nil;
  _views[key] = v;
  if ([v isKindOfClass:[NSTableCellView class]]) { id ov = [self _xefObjectValueForColumn:_columns[c] row:r]; if (ov) [(NSTableCellView *)v setObjectValue:ov]; }
  [v setFrame:[self frameOfCellAtColumn:c row:r]]; [self addSubview:v];
  return v; }
- (id)rowViewAtRow:(NSInteger)r makeIfNecessary:(BOOL)make {
  if (r < 0 || r >= _rows) return nil;
  NSTableRowView *rv = _rowViews[@(r)];
  if (!rv && make) {
    rv = [_delegate respondsToSelector:@selector(tableView:rowViewForRow:)] ? [_delegate tableView:self rowViewForRow:r] : nil;
    if (!rv) rv = [[[NSTableRowView alloc] initWithFrame:[self rectOfRow:r]] autorelease];
    _rowViews[@(r)] = rv; }
  [rv setSelected:[_sel containsIndex:r]];
  return rv; }
- (NSInteger)rowForView:(NSView *)v {
  for (NSView *x = v; x && x != self; x = [x superview]) for (NSNumber *k in _views) if (_views[k] == x) return [k integerValue] / 4096;
  return -1; }
- (NSInteger)columnForView:(NSView *)v {
  for (NSView *x = v; x && x != self; x = [x superview]) for (NSNumber *k in _views) if (_views[k] == x) return [k integerValue] % 4096;
  return -1; }
- (void)enumerateAvailableRowViewsUsingBlock:(void (^)(NSTableRowView *, NSInteger))block { for (NSNumber *k in [[_rowViews allKeys] sortedArrayUsingSelector:@selector(compare:)]) block(_rowViews[k], [k integerValue]); }
- (id)preparedCellAtColumn:(NSInteger)c row:(NSInteger)r {
  if (c < 0 || c >= (NSInteger)[_columns count] || r < 0 || r >= _rows) return nil;
  NSTableColumn *col = _columns[c]; NSCell *cell = [col dataCellForRow:r];
  [cell setObjectValue:[self _xefObjectValueForColumn:col row:r]]; [self _xefWillDisplayCell:cell column:col row:r];
  return cell; }
/* view-based tables: the cell views of the visible rows are subviews; those of rows scrolled away are queued for reuse */
- (void)_xefSyncViews {
  if (![self _xefViewBased]) { if ([_views count]) [self _xefDropViews]; return; }
  NSRange vis = [self rowsInRect:[self visibleRect]];
  for (NSNumber *k in [_views allKeys]) {
    NSInteger r = [k integerValue] / 4096;
    if (r >= (NSInteger)vis.location && r < (NSInteger)NSMaxRange(vis)) continue;
    NSView *v = _views[k]; NSString *ident = [v respondsToSelector:@selector(identifier)] ? [(id)v identifier] : nil;
    if (ident) { NSMutableArray *q = _reuse[ident]; if (!q) { q = [NSMutableArray array]; _reuse[ident] = q; } if ([q count] < 64) [q addObject:v]; }
    [v removeFromSuperview]; [_views removeObjectForKey:k]; }
  BOOL emphasized = [_window isKeyWindow];
  for (NSInteger r = vis.location; r < (NSInteger)NSMaxRange(vis); r++)
    for (NSInteger c = 0; c < (NSInteger)[_columns count]; c++) {
      if ([_columns[c] isHidden]) continue;
      NSView *v = [self viewAtColumn:c row:r makeIfNecessary:YES]; if (!v) continue;
      NSRect f = [self frameOfCellAtColumn:c row:r]; NSRect cur = [v frame];
      if (!NSEqualRects(cur, f)) [v setFrame:f];
      if ([v respondsToSelector:@selector(setBackgroundStyle:)]) [(id)v setBackgroundStyle:[_sel containsIndex:r] && emphasized ? 3 : 0]; } }
- (void)_xefDrawRowDecoration:(NSInteger)r {}
- (void)drawRow:(NSInteger)r clipRect:(NSRect)clip {
  BOOL selected = [_sel containsIndex:r], emphasized = [_window isKeyWindow];
  [self _xefDrawRowDecoration:r];
  for (NSInteger c = 0; c < (NSInteger)[_columns count]; c++) {
    NSTableColumn *col = _columns[c]; if ([col isHidden]) continue;
    if (_views[@(r * 4096 + c)]) continue;
    NSRect f = [self frameOfCellAtColumn:c row:r];
    NSCell *cell = [col dataCellForRow:r]; if (!cell) continue;
    [cell setObjectValue:[self _xefObjectValueForColumn:col row:r] ?: @""];
    if ([cell respondsToSelector:@selector(setTextColor:)]) [(id)cell setTextColor:selected && emphasized ? [NSColor whiteColor] : [NSColor controlTextColor]];
    [self _xefWillDisplayCell:cell column:col row:r];
    [cell drawWithFrame:f inView:self]; } }
- (void)drawRect:(NSRect)dirty {
  [self _xefSyncViews];
  NSRect vis = [self visibleRect]; if (vis.size.width <= 0 || vis.size.height <= 0) vis = _bounds;
  [[self backgroundColor] setFill]; NSRectFill(vis);
  NSRange rows = [self rowsInRect:vis]; BOOL emphasized = [_window isKeyWindow];
  for (NSInteger r = rows.location; r < (NSInteger)NSMaxRange(rows); r++) {
    NSRect rr = [self rectOfRow:r];
    if (_alternating && (r & 1)) { [tgray(0.96) setFill]; NSRectFill(rr); }
    if ([_sel containsIndex:r] && _highlightStyle != -1) { [(emphasized ? [NSColor alternateSelectedControlColor] : tgray(0.86)) setFill]; NSRectFill(rr); }
    if (_gridMask & 2) { [[self gridColor] setFill]; NSRectFill(NSMakeRect(rr.origin.x, NSMaxY(rr) - 1, rr.size.width, 1)); } }
  if (_gridMask & 1) { [[self gridColor] setFill]; for (NSUInteger c = 0; c < [_columns count]; c++) { NSRect cr = [self rectOfColumn:c]; if (cr.size.width > 0) NSRectFill(NSMakeRect(NSMaxX(cr) - 1, vis.origin.y, 1, vis.size.height)); } }
  for (NSInteger r = rows.location; r < (NSInteger)NSMaxRange(rows); r++) [self drawRow:r clipRect:vis]; }
/* clicks on passive content of a cell view (labels, images, plain views) select the row; real controls keep their clicks */
- (NSView *)hitTest:(NSPoint)p {
  NSView *v = [super hitTest:p];
  for (NSView *x = v; x && x != self; x = [x superview]) {
    if (![x isKindOfClass:[NSControl class]]) continue;
    if ([x isKindOfClass:[NSTextField class]] && ![(NSTextField *)x isEditable] && ![(NSTextField *)x isSelectable]) continue;
    if ([x isKindOfClass:NSClassFromString(@"NSImageView")] && ![(NSControl *)x action]) continue;
    return v; }
  return v ? self : nil; }

/* ---- events */
- (BOOL)_xefClickAt:(NSPoint)p row:(NSInteger)r column:(NSInteger)c { return NO; }
- (void)mouseDown:(NSEvent *)e {
  NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
  NSInteger r = [self rowAtPoint:p], c = [self columnAtPoint:p];
  [_window makeFirstResponder:self];
  _clickedRow = r; _clickedCol = c;
  if (r >= 0 && [self _xefClickAt:p row:r column:c]) return;
  NSEventModifierFlags mods = [e modifierFlags];
  if (r < 0) { if ([_sel count]) [self deselectAll:nil]; }
  else if ([self _xefSelectionShouldChange]) {
    if ((mods & NSEventModifierFlagCommand) && [_sel containsIndex:r]) [self deselectRow:r];
    else if ([self _xefShouldSelectRow:r]) {
      if ((mods & NSEventModifierFlagShift) && _multiple && _anchor >= 0) {
        NSInteger a = _anchor, lo = a < r ? a : r, hi = a < r ? r : a;
        [self _xefSetSelection:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(lo, hi - lo + 1)] notify:YES];
      } else { NSInteger keep = _anchor; [self selectRowIndexes:[NSIndexSet indexSetWithIndex:r] byExtendingSelection:(mods & NSEventModifierFlagCommand) && _multiple]; (void)keep; } } }
  XEFRedrawWindowNow(_window);
  for (;;) { NSEvent *n = XEFNextTrackingEvent(); if (n && [n type] == NSEventTypeLeftMouseUp) break; }
  if ([e clickCount] >= 2 && _doubleAction) [self sendAction:_doubleAction to:[self target]];
  else if ([self action]) [self sendAction:[self action] to:[self target]]; }
- (void)_xefMoveSelection:(NSInteger)d extend:(BOOL)extend {
  if (_rows <= 0) return;
  NSInteger cur = [self selectedRow], n = cur < 0 ? (d > 0 ? 0 : _rows - 1) : cur + d;
  if (n < 0 || n >= _rows || ![self _xefSelectionShouldChange] || ![self _xefShouldSelectRow:n]) return;
  [self selectRowIndexes:[NSIndexSet indexSetWithIndex:n] byExtendingSelection:extend && _multiple]; [self scrollRowToVisible:n]; }
- (void)keyDown:(NSEvent *)e {
  unsigned short k = [e keyCode];
  if (k == 125) [self _xefMoveSelection:1 extend:([e modifierFlags] & NSEventModifierFlagShift) != 0];
  else if (k == 126) [self _xefMoveSelection:-1 extend:([e modifierFlags] & NSEventModifierFlagShift) != 0];
  else if ((k == 36 || k == 76) && _doubleAction && [_sel count]) { _clickedRow = [self selectedRow]; [self sendAction:_doubleAction to:[self target]]; }
  else [super keyDown:e]; }
@end

/* ================================================================== NSOutlineView */
@implementation XEFOutlineNode
- (void)dealloc { [_item release]; [_children release]; [super dealloc]; }
@end

@implementation NSOutlineView
- (void)_xefOutlineInit {
  _nodes = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsObjectPointerPersonality | NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory capacity:64];
  _root = [[XEFOutlineNode alloc] init]; _root->_level = -1; _root->_expanded = YES; _rowNodes = [[NSMutableArray alloc] init];
  _indentation = 13; _autoresizesOutline = YES; _markerFollows = YES; }
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { [self _xefOutlineInit]; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    [self _xefOutlineInit];
    if ([c containsValueForKey:@"NSIndentationPerLevel"]) _indentation = [c decodeDoubleForKey:@"NSIndentationPerLevel"];
    _outlineColumn = [c decodeObjectForKey:@"NSOutlineViewOutlineTableColumnKey"]; if (!_outlineColumn && [_columns count]) _outlineColumn = _columns[0]; }
  return self; }
- (void)dealloc { [_nodes release]; [_root release]; [_rowNodes release]; [super dealloc]; }
- (CGFloat)indentationPerLevel { return _indentation; } - (void)setIndentationPerLevel:(CGFloat)i { _indentation = i; [self setNeedsDisplay:YES]; }
- (NSTableColumn *)outlineTableColumn { return _outlineColumn; } - (void)setOutlineTableColumn:(NSTableColumn *)c { _outlineColumn = c; [self setNeedsDisplay:YES]; }
- (BOOL)autoresizesOutlineColumn { return _autoresizesOutline; } - (void)setAutoresizesOutlineColumn:(BOOL)f { _autoresizesOutline = f; }
- (BOOL)indentationMarkerFollowsCell { return _markerFollows; } - (void)setIndentationMarkerFollowsCell:(BOOL)f { _markerFollows = f; }
- (BOOL)autosaveExpandedItems { return _autosaveExpanded; } - (void)setAutosaveExpandedItems:(BOOL)f { _autosaveExpanded = f; }
- (BOOL)stronglyReferencesItems { return YES; } - (void)setStronglyReferencesItems:(BOOL)f {}
- (void)addTableColumn:(NSTableColumn *)c { [super addTableColumn:c]; if (!_outlineColumn) _outlineColumn = c; }
- (void)removeTableColumn:(NSTableColumn *)c { [super removeTableColumn:c]; if (_outlineColumn == c) _outlineColumn = [_columns count] ? _columns[0] : nil; }
- (XEFOutlineNode *)_node:(id)item { return item ? [_nodes objectForKey:item] : _root; }
- (BOOL)isExpandable:(id)item { return item && [_dataSource respondsToSelector:@selector(outlineView:isItemExpandable:)] ? [_dataSource outlineView:self isItemExpandable:item] : NO; }
- (NSInteger)numberOfChildrenOfItem:(id)item { return [_dataSource respondsToSelector:@selector(outlineView:numberOfChildrenOfItem:)] ? [_dataSource outlineView:self numberOfChildrenOfItem:item] : 0; }
- (id)child:(NSInteger)i ofItem:(id)item { return [_dataSource respondsToSelector:@selector(outlineView:child:ofItem:)] ? [_dataSource outlineView:self child:i ofItem:item] : nil; }
/* asks the data source for the children of a node; nodes of items seen before keep their state */
- (void)_xefLoadChildren:(XEFOutlineNode *)n {
  NSInteger count = [self numberOfChildrenOfItem:n->_item];
  NSMutableArray *kids = [NSMutableArray arrayWithCapacity:count];
  for (NSInteger i = 0; i < count; i++) {
    id item = [self child:i ofItem:n->_item]; if (!item) continue;
    XEFOutlineNode *k = [_nodes objectForKey:item];
    if (!k) { k = [[[XEFOutlineNode alloc] init] autorelease]; k->_item = [item retain]; [_nodes setObject:k forKey:item]; }
    k->_parent = n; k->_level = n->_level + 1; [kids addObject:k]; }
  [n->_children release]; n->_children = [kids retain]; }
- (void)_xefAppendRows:(XEFOutlineNode *)n { for (XEFOutlineNode *k in n->_children) { [_rowNodes addObject:k]; if (k->_expanded) [self _xefAppendRows:k]; } }
- (NSArray *)_xefSelectedNodes { NSMutableArray *a = [NSMutableArray array]; NSArray *rows = _rowNodes; [_sel enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { if (i < [rows count]) [a addObject:rows[i]]; }]; return a; }
/* after the visible rows changed: the selection follows its items; items that are no longer visible leave it */
- (void)_xefRowsChanged:(NSArray *)selected {
  [_rowNodes removeAllObjects]; [self _xefAppendRows:_root];
  _rows = [_rowNodes count];
  NSMutableIndexSet *n = [NSMutableIndexSet indexSet];
  for (XEFOutlineNode *k in selected) { NSUInteger i = [_rowNodes indexOfObjectIdenticalTo:k]; if (i != NSNotFound) [n addIndex:i]; }
  [self _xefDropViews]; [self tile]; [self setNeedsDisplay:YES];
  [self _xefSetSelection:n notify:YES]; }
- (NSInteger)_xefFetchRowCount { return [_rowNodes count]; }
- (void)_xefPost:(NSString *)name selector:(SEL)sel item:(id)item {
  NSNotification *n = [NSNotification notificationWithName:name object:self userInfo:@{ @"NSObject": item }];
  if ([_delegate respondsToSelector:sel]) [_delegate performSelector:sel withObject:n];
  [[NSNotificationCenter defaultCenter] postNotification:n]; }
- (BOOL)_xefShouldExpand:(id)item { return [_delegate respondsToSelector:@selector(outlineView:shouldExpandItem:)] ? [_delegate outlineView:self shouldExpandItem:item] : YES; }
/* expands one node: the delegate is asked even when it is already open; children that were open when an ancestor was
 * collapsed open again */
- (BOOL)_xefExpand:(XEFOutlineNode *)n ask:(BOOL)ask {
  if (n == _root) return YES;
  if (![self isExpandable:n->_item]) return NO;
  if (n->_expanded) { if (ask) [self _xefShouldExpand:n->_item]; return YES; }
  if (ask && ![self _xefShouldExpand:n->_item]) return NO;
  [self _xefPost:NSOutlineViewItemWillExpandNotification selector:@selector(outlineViewItemWillExpand:) item:n->_item];
  n->_expanded = YES; [self _xefLoadChildren:n];
  [self _xefPost:NSOutlineViewItemDidExpandNotification selector:@selector(outlineViewItemDidExpand:) item:n->_item];
  for (XEFOutlineNode *k in [[n->_children copy] autorelease]) if (k->_reopen) { k->_reopen = NO; [self _xefExpand:k ask:YES]; }
  return YES; }
- (void)_xefExpandAll:(XEFOutlineNode *)n {
  if (![self _xefExpand:n ask:YES]) return;
  for (XEFOutlineNode *k in [[n->_children copy] autorelease]) [self _xefExpandAll:k]; }
- (void)expandItem:(id)item expandChildren:(BOOL)children {
  XEFOutlineNode *n = [self _node:item]; if (!n) return;
  NSArray *sel = [self _xefSelectedNodes];
  if (children) [self _xefExpandAll:n]; else [self _xefExpand:n ask:YES];
  [self _xefRowsChanged:sel]; }
- (void)expandItem:(id)item { [self expandItem:item expandChildren:NO]; }
- (void)_xefForget:(XEFOutlineNode *)n { for (XEFOutlineNode *k in n->_children) { k->_reopen = NO; [self _xefForget:k]; } }
- (void)_xefCollapse:(XEFOutlineNode *)n children:(BOOL)children {
  if (!n->_expanded) { if (children) [self _xefForget:n]; return; }
  for (XEFOutlineNode *k in [[n->_children copy] autorelease]) {
    BOOL open = k->_expanded;
    [self _xefCollapse:k children:children];
    k->_reopen = open && !children; }
  if (n == _root) return;
  [self _xefPost:NSOutlineViewItemWillCollapseNotification selector:@selector(outlineViewItemWillCollapse:) item:n->_item];
  n->_expanded = NO;
  [self _xefPost:NSOutlineViewItemDidCollapseNotification selector:@selector(outlineViewItemDidCollapse:) item:n->_item]; }
- (void)collapseItem:(id)item collapseChildren:(BOOL)children {
  XEFOutlineNode *n = [self _node:item]; if (!n) return;
  if (n != _root && n->_expanded && [_delegate respondsToSelector:@selector(outlineView:shouldCollapseItem:)] && ![_delegate outlineView:self shouldCollapseItem:item]) return;
  NSArray *sel = [self _xefSelectedNodes];
  [self _xefCollapse:n children:children];
  [self _xefRowsChanged:sel]; }
- (void)collapseItem:(id)item { [self collapseItem:item collapseChildren:NO]; }
/* reloadData: the tree is read again; items that were open stay open if the delegate still agrees (no notifications) */
- (void)_xefReload:(XEFOutlineNode *)n {
  [self _xefLoadChildren:n];
  for (XEFOutlineNode *k in n->_children) {
    if (!k->_expanded) continue;
    if ([self isExpandable:k->_item] && [self _xefShouldExpand:k->_item]) [self _xefReload:k]; else k->_expanded = NO; } }
- (void)reloadData {
  if (!_root) return;
  NSArray *sel = [self _xefSelectedNodes];
  [self _xefReload:_root];
  [_rowNodes removeAllObjects]; [self _xefAppendRows:_root]; _rows = [_rowNodes count];
  NSMutableIndexSet *n = [NSMutableIndexSet indexSet];
  for (XEFOutlineNode *k in sel) { NSUInteger i = [_rowNodes indexOfObjectIdenticalTo:k]; if (i != NSNotFound) [n addIndex:i]; }
  [_sel removeAllIndexes]; [_sel addIndexes:n];
  [self _xefDropViews]; [self tile]; [self setNeedsDisplay:YES]; }
- (void)reloadItem:(id)item reloadChildren:(BOOL)children {
  if (!item) { [self reloadData]; return; }
  XEFOutlineNode *n = [self _node:item]; if (!n) return;
  if (!children || !n->_expanded) { [self _xefDropViews]; [self setNeedsDisplay:YES]; return; }
  NSArray *sel = [self _xefSelectedNodes];
  NSMutableArray *open = [NSMutableArray array];
  for (XEFOutlineNode *k in n->_children) if (k->_expanded) { [open addObject:k]; k->_expanded = NO; }
  [self _xefPost:NSOutlineViewItemWillExpandNotification selector:@selector(outlineViewItemWillExpand:) item:n->_item];
  [self _xefLoadChildren:n];
  [self _xefPost:NSOutlineViewItemDidExpandNotification selector:@selector(outlineViewItemDidExpand:) item:n->_item];
  for (XEFOutlineNode *k in open) if ([n->_children indexOfObjectIdenticalTo:k] != NSNotFound) [self _xefExpand:k ask:YES];
  [self _xefRowsChanged:sel]; }
- (void)reloadItem:(id)item { [self reloadItem:item reloadChildren:NO]; }
- (void)noteNumberOfRowsChanged { [self reloadData]; }
- (id)itemAtRow:(NSInteger)r { return r >= 0 && r < (NSInteger)[_rowNodes count] ? ((XEFOutlineNode *)_rowNodes[r])->_item : nil; }
- (NSInteger)rowForItem:(id)item { XEFOutlineNode *n = item ? [_nodes objectForKey:item] : nil; NSUInteger i = n ? [_rowNodes indexOfObjectIdenticalTo:n] : NSNotFound; return i == NSNotFound ? -1 : (NSInteger)i; }
- (id)parentForItem:(id)item { XEFOutlineNode *n = item ? [_nodes objectForKey:item] : nil; return n && n->_parent ? n->_parent->_item : nil; }
- (NSInteger)childIndexForItem:(id)item { XEFOutlineNode *n = item ? [_nodes objectForKey:item] : nil; NSUInteger i = n && n->_parent ? [n->_parent->_children indexOfObjectIdenticalTo:n] : NSNotFound; return i == NSNotFound ? -1 : (NSInteger)i; }
- (NSInteger)levelForItem:(id)item { NSInteger r = [self rowForItem:item]; return r < 0 ? -1 : ((XEFOutlineNode *)_rowNodes[r])->_level; }
- (NSInteger)levelForRow:(NSInteger)r { return r >= 0 && r < (NSInteger)[_rowNodes count] ? ((XEFOutlineNode *)_rowNodes[r])->_level : -1; }
- (BOOL)isItemExpanded:(id)item { XEFOutlineNode *n = item ? [_nodes objectForKey:item] : nil; return n ? n->_expanded : NO; }
- (void)insertItemsAtIndexes:(NSIndexSet *)s inParent:(id)p withAnimation:(NSUInteger)a { XEFOutlineNode *n = [self _node:p]; if (n && n->_expanded) { NSArray *sel = [self _xefSelectedNodes]; [self _xefLoadChildren:n]; [self _xefRowsChanged:sel]; } }
- (void)removeItemsAtIndexes:(NSIndexSet *)s inParent:(id)p withAnimation:(NSUInteger)a { [self insertItemsAtIndexes:s inParent:p withAnimation:a]; }
- (void)moveItemAtIndex:(NSInteger)f inParent:(id)op toIndex:(NSInteger)t inParent:(id)np { [self insertItemsAtIndexes:nil inParent:op withAnimation:0]; if (np != op) [self insertItemsAtIndexes:nil inParent:np withAnimation:0]; }
- (void)setDropItem:(id)i dropChildIndex:(NSInteger)c {} - (BOOL)shouldCollapseAutoExpandedItemsForDeposited:(BOOL)d { return YES; }
- (NSInteger)userInterfaceLayoutDirection { return 0; } - (void)setUserInterfaceLayoutDirection:(NSInteger)d {}
/* table hooks */
- (id)_xefObjectValueForColumn:(NSTableColumn *)c row:(NSInteger)r {
  id item = [self itemAtRow:r];
  return item && [_dataSource respondsToSelector:@selector(outlineView:objectValueForTableColumn:byItem:)] ? [_dataSource outlineView:self objectValueForTableColumn:c byItem:item] : nil; }
- (BOOL)_xefViewBased { return [_delegate respondsToSelector:@selector(outlineView:viewForTableColumn:item:)]; }
- (NSView *)_xefMakeViewForColumn:(NSTableColumn *)c row:(NSInteger)r { id item = [self itemAtRow:r]; return item ? [_delegate outlineView:self viewForTableColumn:c item:item] : nil; }
- (void)_xefWillDisplayCell:(NSCell *)cell column:(NSTableColumn *)c row:(NSInteger)r {
  id item = [self itemAtRow:r];
  if (item && [_delegate respondsToSelector:@selector(outlineView:willDisplayCell:forTableColumn:item:)]) [_delegate outlineView:self willDisplayCell:cell forTableColumn:c item:item]; }
- (BOOL)_xefVariableHeights { return [_delegate respondsToSelector:@selector(outlineView:heightOfRowByItem:)]; }
- (CGFloat)_xefHeightOfRow:(NSInteger)r { id item = [self itemAtRow:r]; return item && [self _xefVariableHeights] ? [_delegate outlineView:self heightOfRowByItem:item] : _rowHeight; }
- (BOOL)_xefSelectionShouldChange { return [_delegate respondsToSelector:@selector(selectionShouldChangeInOutlineView:)] ? [_delegate selectionShouldChangeInOutlineView:self] : YES; }
- (BOOL)_xefShouldSelectRow:(NSInteger)r { id item = [self itemAtRow:r]; return item && [_delegate respondsToSelector:@selector(outlineView:shouldSelectItem:)] ? [_delegate outlineView:self shouldSelectItem:item] : YES; }
- (void)_xefSelectionChanged {
  NSNotification *n = [NSNotification notificationWithName:NSOutlineViewSelectionDidChangeNotification object:self];
  if ([_delegate respondsToSelector:@selector(outlineViewSelectionDidChange:)]) [_delegate outlineViewSelectionDidChange:n];
  [[NSNotificationCenter defaultCenter] postNotification:n]; }
- (void)_xefSortChanged:(NSArray *)old { if ([_dataSource respondsToSelector:@selector(outlineView:sortDescriptorsDidChange:)]) [_dataSource outlineView:self sortDescriptorsDidChange:old]; }
- (CGFloat)_xefIndentForColumn:(NSInteger)c row:(NSInteger)r { return c >= 0 && c < (NSInteger)[_columns count] && _columns[c] == _outlineColumn ? [self levelForRow:r] * _indentation + 16 : 0; }
- (NSRect)frameOfOutlineCellAtRow:(NSInteger)r {
  id item = [self itemAtRow:r]; NSUInteger c = _outlineColumn ? [_columns indexOfObjectIdenticalTo:_outlineColumn] : NSNotFound;
  if (!item || c == NSNotFound || ![self isExpandable:item]) return NSZeroRect;
  NSRect cr = [self rectOfColumn:c], rr = [self rectOfRow:r];
  return NSMakeRect(floor(cr.origin.x + _spacing.width / 2) + [self levelForRow:r] * _indentation, rr.origin.y, 16, rr.size.height); }
- (void)_xefDrawRowDecoration:(NSInteger)r {
  NSRect d = [self frameOfOutlineCellAtRow:r]; if (d.size.width <= 0) return;
  BOOL open = [self isItemExpanded:[self itemAtRow:r]], white = [_sel containsIndex:r] && [_window isKeyWindow];
  [(white ? [NSColor whiteColor] : tgray(0.45)) setStroke];
  NSBezierPath *p = [NSBezierPath bezierPath]; [p setLineWidth:1.5]; CGFloat cx = NSMidX(d), cy = NSMidY(d);
  if (open) { [p moveToPoint:NSMakePoint(cx - 3.5, cy - 1.5)]; [p lineToPoint:NSMakePoint(cx, cy + 2)]; [p lineToPoint:NSMakePoint(cx + 3.5, cy - 1.5)]; }
  else { [p moveToPoint:NSMakePoint(cx - 1.5, cy - 3.5)]; [p lineToPoint:NSMakePoint(cx + 2, cy)]; [p lineToPoint:NSMakePoint(cx - 1.5, cy + 3.5)]; }
  [p stroke]; }
- (BOOL)_xefClickAt:(NSPoint)p row:(NSInteger)r column:(NSInteger)c {
  if (!NSPointInRect(p, [self frameOfOutlineCellAtRow:r])) return NO;
  id item = [self itemAtRow:r];
  for (;;) { NSEvent *n = XEFNextTrackingEvent(); if (n && [n type] == NSEventTypeLeftMouseUp) break; }
  if ([self isItemExpanded:item]) [self collapseItem:item]; else [self expandItem:item];
  XEFRedrawWindowNow(_window); return YES; }
- (void)keyDown:(NSEvent *)e {
  unsigned short k = [e keyCode]; id item = [self itemAtRow:[self selectedRow]];
  if (k == 124 && item) [self expandItem:item];
  else if (k == 123 && item) { if ([self isItemExpanded:item]) [self collapseItem:item]; else { NSInteger pr = [self rowForItem:[self parentForItem:item]]; if (pr >= 0) [self selectRowIndexes:[NSIndexSet indexSetWithIndex:pr] byExtendingSelection:NO]; } }
  else [super keyDown:e]; }
@end
