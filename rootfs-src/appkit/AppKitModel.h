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
