/* AppKit-lite: NSTableView, NSOutlineView and their helpers (AppKitTable.m). */
#import "AppKitControls.h"

@class NSTableView, NSTableHeaderView;

@interface NSTableHeaderCell : NSTextFieldCell
@end

@interface NSTableColumn : NSObject <NSCoding> {
@public
  NSString *_identifier, *_headerToolTip; CGFloat _width, _minWidth, _maxWidth; NSCell *_headerCell, *_dataCell; NSUInteger _resizingMask; BOOL _editable, _hidden;
  NSTableView *_tableView; NSSortDescriptor *_sortProto;
}
- (id)initWithIdentifier:(NSString *)i; - (NSString *)identifier; - (CGFloat)width; - (void)setWidth:(CGFloat)w; - (NSString *)title; - (BOOL)isHidden;
- (id)headerCell; - (id)dataCell; - (id)dataCellForRow:(NSInteger)r; - (NSTableView *)tableView;
@end

@interface NSTableHeaderView : NSView { @public NSTableView *_tableView; NSInteger _pressed, _resized, _dragged; }
- (NSTableView *)tableView; - (void)setTableView:(NSTableView *)t; - (NSRect)headerRectOfColumn:(NSInteger)c; - (NSInteger)columnAtPoint:(NSPoint)p;
@end

@interface NSTableRowView : NSView {
@public
  BOOL _selected, _emphasized, _groupRow, _floating, _previousSelected, _nextSelected, _targetForDrop; NSInteger _highlightStyle, _interior; NSColor *_bg; CGFloat _dropIndent;
}
@end

@interface NSTableCellView : NSView { @public id _objectValue; NSTextField *_textField; id _imageView; NSInteger _backgroundStyle, _rowSizeStyle; NSArray *_dragging; }
- (id)objectValue; - (void)setObjectValue:(id)v; - (NSTextField *)textField; - (void)setTextField:(NSTextField *)t;
@end

@interface NSTableView : NSControl {
@public
  NSMutableArray *_columns; id _dataSource, _delegate; NSInteger _rows; CGFloat _rowHeight; NSSize _spacing; NSMutableIndexSet *_sel, *_selCols;
  NSTableHeaderView *_header; NSView *_corner; NSInteger _clickedRow, _clickedCol, _editedRow, _editedCol, _style, _highlightStyle, _rowSizeStyle, _updates, _anchor;
  NSInteger _draggingStyle, _layoutDirection; NSUInteger _gridMask, _autoresizingStyle;
  BOOL _multiple, _empty, _columnSelection, _reorder, _resize, _alternating, _typeSelect, _floatsGroups, _autosaveColumns, _usesAutoHeights, _usesStatic, _verticalMotion;
  NSArray *_sortDescriptors; SEL _doubleAction; NSColor *_bg, *_grid; NSString *_autosave; NSMutableDictionary *_views, *_rowViews, *_reuse, *_nibs;
  CGFloat *_offsets; NSInteger _noffsets; NSTableColumn *_highlightedColumn;
}
- (id)dataSource; - (void)setDataSource:(id)d; - (id)delegate; - (void)setDelegate:(id)d; - (void)reloadData; - (void)tile;
- (NSInteger)numberOfRows; - (NSInteger)numberOfColumns; - (NSArray *)tableColumns; - (NSInteger)selectedRow; - (NSIndexSet *)selectedRowIndexes;
- (NSRect)rectOfRow:(NSInteger)r; - (NSRect)rectOfColumn:(NSInteger)c; - (NSRect)frameOfCellAtColumn:(NSInteger)c row:(NSInteger)r;
- (NSInteger)rowAtPoint:(NSPoint)p; - (NSInteger)columnAtPoint:(NSPoint)p; - (NSTableHeaderView *)headerView; - (BOOL)allowsColumnResizing;
- (void)selectRowIndexes:(NSIndexSet *)s byExtendingSelection:(BOOL)e; - (void)setSortDescriptors:(NSArray *)a; - (NSArray *)sortDescriptors;
/* overridden by NSOutlineView */
- (NSInteger)_xefFetchRowCount; - (id)_xefObjectValueForColumn:(NSTableColumn *)c row:(NSInteger)r; - (NSView *)_xefMakeViewForColumn:(NSTableColumn *)c row:(NSInteger)r;
- (BOOL)_xefViewBased; - (BOOL)_xefShouldSelectRow:(NSInteger)r; - (void)_xefSelectionChanged; - (CGFloat)_xefIndentForColumn:(NSInteger)c row:(NSInteger)r;
- (void)_xefSetSelection:(NSIndexSet *)s notify:(BOOL)n; - (CGFloat)_xefHeightOfRow:(NSInteger)r; - (void)_xefWillDisplayCell:(NSCell *)cell column:(NSTableColumn *)c row:(NSInteger)r;
- (BOOL)_xefClickAt:(NSPoint)p row:(NSInteger)r column:(NSInteger)c; - (void)_xefDrawRowDecoration:(NSInteger)r;
@end

@interface XEFOutlineNode : NSObject { @public id _item; XEFOutlineNode *_parent; NSInteger _level; BOOL _expanded, _reopen; NSMutableArray *_children; }
@end

@interface NSOutlineView : NSTableView {
@public
  NSMapTable *_nodes; XEFOutlineNode *_root; NSMutableArray *_rowNodes; NSTableColumn *_outlineColumn; CGFloat _indentation; BOOL _autoresizesOutline, _markerFollows, _autosaveExpanded, _stronglyReferences;
}
- (id)itemAtRow:(NSInteger)r; - (NSInteger)rowForItem:(id)i; - (BOOL)isItemExpanded:(id)i; - (BOOL)isExpandable:(id)i;
- (void)expandItem:(id)i expandChildren:(BOOL)c; - (void)collapseItem:(id)i collapseChildren:(BOOL)c;
@end
