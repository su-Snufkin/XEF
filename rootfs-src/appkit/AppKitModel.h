/* AppKit-lite model classes: NSToolbar, NSAnimation, NSPopover and the object / array controllers (AppKitModel.m). */
#import "AppKitLite.h"
#import "AppKitControls.h"
#import "AppKitControllers.h"

@interface NSToolbarItem : NSObject <NSCopying> {
@public
  NSString *_ident, *_label, *_palette, *_tip; NSInteger _tag, _priority; BOOL _enabled, _bordered, _autovalidates, _navigational; NSSize _min, _max;
  NSView *_view; id _target, _image; SEL _action; id _toolbar; NSMenuItem *_menu;
}
- (id)initWithItemIdentifier:(NSString *)i; - (NSString *)itemIdentifier; - (NSString *)label; - (void)setLabel:(NSString *)l;
@end
@interface NSToolbarItemGroup : NSToolbarItem { @public NSArray *_subitems; NSInteger _selectionMode, _selectedIndex, _representation; }
@end

@interface NSToolbar : NSObject {
@public
  NSString *_ident, *_selected; NSMutableArray *_items; id _delegate; NSWindow *_window; NSInteger _display, _size; BOOL _visible, _customizes, _autosaves, _baseline, _extensions;
}
- (id)initWithIdentifier:(NSString *)i; - (NSString *)identifier; - (id)delegate; - (void)setDelegate:(id)d; - (NSArray *)items;
- (void)insertItemWithItemIdentifier:(NSString *)i atIndex:(NSInteger)idx; - (void)removeItemAtIndex:(NSInteger)idx; - (void)_xefSetWindow:(NSWindow *)w;
@end

@interface NSAnimation : NSObject <NSCopying> {
@public
  NSTimeInterval _duration; NSInteger _curve, _blocking; float _frameRate, _progress; id _delegate; NSMutableArray *_marks; BOOL _running; NSTimer *_timer; NSTimeInterval _start; NSInteger _nextMark;
}
- (id)initWithDuration:(NSTimeInterval)d animationCurve:(NSInteger)c; - (void)startAnimation; - (void)stopAnimation; - (BOOL)isAnimating;
@end

@interface NSPopover : NSObject {
@public
  id _delegate, _vc; NSSize _size; NSRect _rect; BOOL _animates, _shown, _detached; NSInteger _behavior; NSWindow *_window; id _appearance; NSView *_positioningView;
}
- (BOOL)isShown;
@end

@interface NSController : NSObject <NSCoding> { @public BOOL _editing; }
- (BOOL)commitEditing; - (void)discardEditing; - (BOOL)isEditing;
@end
@interface NSObjectController : NSController {
@public
  id _content; Class _class; BOOL _editable, _prepares, _usesLazy; id _selectionProxy;
}
- (id)initWithContent:(id)c; - (id)content; - (void)setContent:(id)c; - (id)selection; - (NSArray *)selectedObjects; - (Class)objectClass; - (BOOL)canAdd; - (BOOL)canRemove;
@end
@interface NSArrayController : NSObjectController {
@public
  NSMutableArray *_arranged; NSMutableIndexSet *_sel; NSArray *_sorts; NSPredicate *_filter; BOOL _preserves, _selectsInserted, _avoidsEmpty, _clearsFilter, _rearranges;
}
- (NSArray *)arrangedObjects; - (NSIndexSet *)selectionIndexes; - (void)rearrangeObjects;
@end

/* NSGridView: the model, and cell frames computed directly (the view reports its fitting size as its intrinsic size) */
@class NSGridView, NSGridRow, NSGridColumn;
@interface NSGridCell : NSObject {
@public
  NSView *_content; NSGridRow *_row; NSGridColumn *_column; NSInteger _x, _y, _rowAlign; NSArray *_custom; NSRange _cols, _rows;
}
- (NSView *)contentView; - (void)setContentView:(NSView *)v;
@end
@interface NSGridRow : NSObject { @public NSGridView *_grid; NSMutableArray *_cells; CGFloat _height, _top, _bottom; BOOL _hidden; NSInteger _y, _align; }
@end
@interface NSGridColumn : NSObject { @public NSGridView *_grid; CGFloat _width, _lead, _trail; BOOL _hidden; NSInteger _x; }
@end
@interface NSGridView : NSView {
@public
  NSMutableArray *_grows, *_gcols; NSInteger _x, _y, _align; CGFloat _rowSpacing, _colSpacing;
}
- (NSInteger)numberOfRows; - (NSInteger)numberOfColumns; - (NSGridCell *)cellAtColumnIndex:(NSInteger)c rowIndex:(NSInteger)r;
- (void)_xefApplyHidden; - (void)mergeCellsInHorizontalRange:(NSRange)h verticalRange:(NSRange)v;
- (NSGridRow *)addRowWithViews:(NSArray *)v; - (NSGridColumn *)addColumnWithViews:(NSArray *)v;
@end
@interface NSView (XEFGridDeclarations)
- (void)invalidateIntrinsicContentSize; - (BOOL)isHidden; - (void)setHidden:(BOOL)f;
@end

/* NSMatrix: a grid of cells (radio groups, lists) that is one control */
@interface NSMatrix : NSControl {
@public
  NSMutableArray *_cells, *_selected; NSInteger _rows, _cols, _mode, _selRow, _selCol; NSSize _cellSize, _spacing;
  BOOL _allowsEmpty, _autosizes, _sizeSet; Class _cellClass; NSCell *_proto; id _target; SEL _action, _doubleAction; BOOL _enabled;
}
- (NSInteger)numberOfRows; - (NSInteger)numberOfColumns; - (NSCell *)cellAtRow:(NSInteger)r column:(NSInteger)c;
@end

/* NSCollectionView with the flow layout */
@class NSCollectionView, NSCollectionViewLayout;
@interface NSCollectionViewLayoutAttributes : NSObject <NSCopying> {
@public
  NSRect _frame; NSIndexPath *_path; NSInteger _zIndex, _category; BOOL _hidden; CGFloat _alpha; NSString *_kind;
}
@end
@interface NSCollectionViewLayout : NSObject {
@public
  NSCollectionView *_cv; BOOL _valid;
}
- (NSSize)collectionViewContentSize; - (void)invalidateLayout; - (NSCollectionView *)collectionView;
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)p; - (NSArray *)layoutAttributesForElementsInRect:(NSRect)r;
@end
@interface NSCollectionViewFlowLayout : NSCollectionViewLayout {
@public
  NSSize _item, _header, _footer, _estimated; CGFloat _line, _inter; NSEdgeInsets _inset; NSInteger _dir; BOOL _pin; NSMutableArray *_attrs; NSSize _content;
}
@end
@interface NSCollectionViewItem : NSViewController { @public BOOL _selected; NSInteger _highlight; NSCollectionView *_cv; id _imageView, _textField; }
- (BOOL)isSelected; - (void)setSelected:(BOOL)f; - (NSCollectionView *)collectionView;
@end
@interface NSCollectionView : NSView {
@public
  id _dataSource, _delegate; NSCollectionViewLayout *_layout; NSMutableDictionary *_classes, *_nibs, *_visible; NSMutableDictionary *_reuse; NSMutableArray *_counts;
  NSMutableSet *_selection; BOOL _selectable, _multiple, _empty; NSArray *_bg; NSInteger _sections;
}
- (NSInteger)numberOfSections; - (NSInteger)numberOfItemsInSection:(NSInteger)s; - (void)reloadData;
@end
@interface NSIndexPath (XEFCollection)
+ (NSIndexPath *)indexPathForItem:(NSInteger)i inSection:(NSInteger)s; - (NSInteger)item; - (NSInteger)section;
@end

/* NSTreeNode / NSTreeController: a tree of represented objects built from the content and childrenKeyPath */
@interface NSTreeNode : NSObject { @public id _obj; NSTreeNode *_parent; NSMutableArray *_kids; BOOL _leaf; }
+ (id)treeNodeWithRepresentedObject:(id)o; - (id)initWithRepresentedObject:(id)o; - (id)representedObject; - (NSTreeNode *)parentNode;
- (NSArray *)childNodes; - (NSMutableArray *)mutableChildNodes; - (BOOL)isLeaf; - (NSIndexPath *)indexPath;
@end
@interface NSTreeController : NSObjectController {
@public
  NSString *_childrenKP, *_countKP, *_leafKP; NSTreeNode *_root; NSMutableArray *_selPaths; NSArray *_sorts;
  BOOL _preserves, _selectsInserted, _avoidsEmpty, _multMarker;
}
- (NSTreeNode *)arrangedObjects; - (NSArray *)selectionIndexPaths; - (void)rearrangeObjects;
@end

/* NSBrowser with the item-based delegate API: columns of children, one selection path */
@interface NSBrowser : NSControl {
@public
  id _delegate, _root; BOOL _loaded, _titled, _multi, _branch, _empty, _reuses, _separates, _typeSelect, _hscroll, _arrows, _sendsArrows, _autohides, _takesTitle;
  NSMutableArray *_parents, *_items, *_sel; NSMutableDictionary *_titles, *_widths; NSString *_sep; CGFloat _minW, _defW, _rowH; NSInteger _maxVis, _resizing;
  SEL _dbl; Class _cellClass, _matrixClass; id _bg, _proto; NSInteger _clickedRow, _clickedCol;
}
- (BOOL)isLoaded; - (void)loadColumnZero; - (NSInteger)lastColumn; - (void)selectRow:(NSInteger)r inColumn:(NSInteger)c;
@end

/* NSPathControl: path items from a URL, drawn as a row of titles */
@interface NSPathControlItem : NSObject { @public NSString *_title; NSAttributedString *_atitle; id _image; NSURL *_url; }
- (NSString *)title; - (void)setTitle:(NSString *)t; - (NSURL *)URL;
@end
@interface NSPathComponentCell : NSCell { @public NSURL *_url; }
- (NSURL *)URL; - (void)setURL:(NSURL *)u;
@end
@interface NSPathCell : NSCell { @public NSURL *_url; NSInteger _style; NSArray *_cells; id _delegate; NSString *_ph; }
@end
@interface NSPathControl : NSControl {
@public
  NSURL *_url; NSInteger _style; BOOL _editable; NSString *_ph; NSAttributedString *_aph; NSArray *_items, *_types; id _delegate, _bg; SEL _dbl; NSPathControlItem *_clicked; NSMenu *_menu;
}
- (NSURL *)URL; - (void)setURL:(NSURL *)u; - (NSArray *)pathItems; - (void)setPathItems:(NSArray *)i;
@end

/* NSSound: the WAV is parsed (duration) and playback is timed; no audio device is driven */
@interface NSSound : NSObject <NSCopying> {
@public
  NSData *_data; NSTimeInterval _duration, _offset, _started; float _volume; BOOL _loops, _playing, _paused; id _delegate; NSString *_name; NSTimer *_timer;
}
- (id)initWithData:(NSData *)d; - (BOOL)play; - (BOOL)stop; - (BOOL)isPlaying; - (NSTimeInterval)duration;
@end

@interface NSBrowserCell : NSCell { @public BOOL _leaf, _loaded; id _alt; }
- (BOOL)isLeaf; - (void)setLeaf:(BOOL)f; - (BOOL)isLoaded; - (void)setLoaded:(BOOL)f;
@end

/* NSRuleEditor: rows (simple / compound, nested) whose criteria and display values come from the delegate */
@interface NSRuleEditor : NSControl {
@public
  id _delegate; NSInteger _nesting; CGFloat _rowH; BOOL _editable, _canRemoveAll; NSMutableArray *_rows; NSMutableIndexSet *_selRows; Class _rowClass;
  NSString *_kpType, *_kpSub, *_kpCrit, *_kpDisp, *_fmtFile; NSDictionary *_fmtDict;
}
- (NSInteger)numberOfRows; - (void)reloadCriteria;
@end

/* NSRulerView / NSRulerMarker: the model (thickness, units, markers) with a simple hash-mark drawing */
@class NSRulerMarker;
@interface NSRulerView : NSView {
@public
  NSScrollView *_sv; NSView *_client, *_accessory; NSInteger _orient; CGFloat _rule, _markersT, _accT, _origin; NSString *_units; NSMutableArray *_markers;
}
- (id)initWithScrollView:(NSScrollView *)s orientation:(NSInteger)o; - (CGFloat)requiredThickness; - (NSArray *)markers; - (CGFloat)ruleThickness; - (NSInteger)orientation;
@end
@interface NSRulerMarker : NSObject <NSCopying> { @public NSRulerView *_ruler; CGFloat _loc; NSImage *_image; NSPoint _origin; BOOL _movable, _removable, _dragging; id _rep; }
- (id)initWithRulerView:(NSRulerView *)r markerLocation:(CGFloat)l image:(NSImage *)i imageOrigin:(NSPoint)o;
- (NSRulerView *)ruler; - (CGFloat)markerLocation; - (void)setMarkerLocation:(CGFloat)l;
@end

/* Touch Bar model: identifiers, items made by the delegate or taken from template items (nothing is shown) */
@interface NSTouchBarItem : NSObject { @public NSString *_ident; float _prio; id _view, _vc; NSString *_label; }
- (id)initWithIdentifier:(NSString *)i; - (NSString *)identifier;
@end
@interface NSCustomTouchBarItem : NSTouchBarItem @end
@class NSTouchBar;
@interface NSGroupTouchBarItem : NSTouchBarItem { @public NSTouchBar *_bar; BOOL _equal; CGFloat _width; }
+ (id)groupItemWithIdentifier:(NSString *)i items:(NSArray *)items;
@end
@interface NSTouchBar : NSObject <NSCoding> {
@public
  NSArray *_default, *_allowed, *_required; NSSet *_templates; NSString *_principal, *_escape, *_custom; id _delegate; NSMutableDictionary *_cache;
}
- (NSArray *)defaultItemIdentifiers; - (void)setDefaultItemIdentifiers:(NSArray *)a; - (id)itemForIdentifier:(NSString *)i; - (void)setTemplateItems:(NSSet *)s;
@end

/* NSDrawer: the open / close state machine (no window is shown); NSPrinter: no printers */
@interface NSDrawer : NSObject {
@public
  NSWindow *_parent; NSView *_content; NSSize _size, _min, _max; NSUInteger _pref, _edge; CGFloat _lead, _trail; id _delegate; NSInteger _state; NSTimer *_timer;
}
- (id)initWithContentSize:(NSSize)s preferredEdge:(NSUInteger)e; - (NSInteger)state; - (void)open; - (void)close;
@end
@interface NSPrinter : NSObject { @public NSString *_name, *_type; }
@end
