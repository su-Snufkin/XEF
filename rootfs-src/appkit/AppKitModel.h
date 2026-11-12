/* AppKit-lite model classes: NSToolbar, NSAnimation, NSPopover and the object / array controllers (AppKitModel.m). */
#import "AppKitLite.h"

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
