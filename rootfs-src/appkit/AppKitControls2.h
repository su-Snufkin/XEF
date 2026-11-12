/* AppKit-lite: more controls and container views (AppKitControls2.m). */
#import "AppKitControls.h"

@interface NSSliderCell : NSActionCell {
@public
  double _min, _max, _value, _alt; NSInteger _ticks, _tickPos, _sliderType; BOOL _ticksOnly; int _vertical; /* -1: from the frame */ NSColor *_trackFill;
}
- (double)minValue; - (void)setMinValue:(double)v; - (double)maxValue; - (void)setMaxValue:(double)v;
- (NSInteger)numberOfTickMarks; - (void)setNumberOfTickMarks:(NSInteger)n; - (BOOL)allowsTickMarkValuesOnly; - (void)setAllowsTickMarkValuesOnly:(BOOL)f;
- (double)tickMarkValueAtIndex:(NSInteger)i; - (double)closestTickMarkValueToValue:(double)v;
- (NSRect)knobRectFlipped:(BOOL)f; - (NSRect)barRectFlipped:(BOOL)f; - (NSRect)rectOfTickMarkAtIndex:(NSInteger)i;
@end
@interface NSSlider : NSControl
- (double)minValue; - (void)setMinValue:(double)v; - (double)maxValue; - (void)setMaxValue:(double)v; - (BOOL)isVertical;
@end

@interface NSStepperCell : NSActionCell { @public double _min, _max, _inc, _value; BOOL _valueWraps, _autorepeat; int _pressed; }
@end
@interface NSStepper : NSControl
@end

@interface NSProgressIndicator : NSView {
@public
  double _min, _max, _value; BOOL _indeterminate, _bezeled, _displayedWhenStopped, _animating, _threaded; NSInteger _style, _controlSize, _tint; NSTimer *_timer; double _phase;
}
- (double)doubleValue; - (void)setDoubleValue:(double)v; - (void)startAnimation:(id)s; - (void)stopAnimation:(id)s;
@end

@interface XEFSegment : NSObject { @public NSString *_label, *_toolTip; NSImage *_image; CGFloat _width; BOOL _enabled, _selected; NSInteger _tag, _align, _scaling; NSMenu *_menu; }
@end
@interface NSSegmentedCell : NSActionCell { @public NSMutableArray *_segments; NSInteger _mode, _style, _last, _pressed; }
- (NSInteger)segmentCount; - (void)setSegmentCount:(NSInteger)n; - (NSInteger)selectedSegment; - (void)setSelectedSegment:(NSInteger)i;
- (BOOL)isSelectedForSegment:(NSInteger)i; - (void)setSelected:(BOOL)f forSegment:(NSInteger)i;
- (NSInteger)tagForSegment:(NSInteger)i; - (void)setTag:(NSInteger)t forSegment:(NSInteger)i; - (BOOL)selectSegmentWithTag:(NSInteger)t;
@end
@interface NSSegmentedControl : NSControl
@end

@interface NSImageCell : NSCell { @public NSInteger _scaling, _imageAlign, _frameStyle; }
@end
@interface NSImageView : NSControl { @public BOOL _editableIV, _animates, _allowsCut; NSColor *_tint; }
- (NSImage *)image; - (void)setImage:(NSImage *)i;
@end

@interface NSLevelIndicatorCell : NSActionCell { @public double _min, _max, _value, _warn, _crit; NSInteger _style, _ticks, _major, _tickPos; }
@end
@interface NSLevelIndicator : NSControl { @public BOOL _editableLI; NSColor *_fill, *_warnFill, *_critFill; }
@end

@interface NSColorWell : NSControl { @public NSColor *_color; BOOL _active, _borderedCW; NSInteger _wellStyle; }
- (NSColor *)color; - (void)setColor:(NSColor *)c;
@end

@interface NSSwitch : NSControl { @public NSInteger _stateSW; }
- (NSInteger)state; - (void)setState:(NSInteger)s;
@end

@interface NSComboBoxCell : NSTextFieldCell {
@public
  NSMutableArray *_items; NSInteger _selected, _visibleItems; BOOL _usesDataSource, _scroller, _completes, _buttonBordered; id _dataSource; CGFloat _itemHeight; NSSize _spacing;
}
@end
@interface NSComboBox : NSTextField
@end

@interface NSDatePickerCell : NSActionCell { @public NSDate *_date, *_minDate, *_maxDate; NSInteger _dpStyle, _mode; NSUInteger _elements; NSTimeInterval _interval; NSCalendar *_calendar; NSLocale *_locale; NSTimeZone *_tz; NSColor *_bg, *_tc; BOOL _drawsBg; id _dpDelegate; }
@end
@interface NSDatePicker : NSControl
@end

@class NSTabView;
@interface NSTabViewItem : NSObject <NSCoding> {
@public
  id _identifier; NSString *_label, *_toolTip; NSView *_view; NSTabView *_tabView; NSColor *_color; NSImage *_image; id _viewController; NSView *_initialFirst; NSRect _tabRect;
}
- (id)initWithIdentifier:(id)i; - (NSString *)label; - (NSView *)view; - (void)setView:(NSView *)v;
@end
@interface NSTabView : NSView {
@public
  NSMutableArray *_items; NSTabViewItem *_selectedItem; id _delegate; NSInteger _type, _position, _border, _controlSize; BOOL _truncated, _drawsBg; NSFont *_font;
}
- (NSInteger)numberOfTabViewItems; - (NSTabViewItem *)selectedTabViewItem; - (void)selectTabViewItem:(NSTabViewItem *)i; - (NSRect)contentRect;
- (void)addTabViewItem:(NSTabViewItem *)i; - (void)insertTabViewItem:(NSTabViewItem *)i atIndex:(NSInteger)idx; - (void)removeTabViewItem:(NSTabViewItem *)i;
@end

@interface NSSplitView : NSView {
@public
  BOOL _vertical, _arrangesAll; NSInteger _dividerStyle; id _delegate; NSColor *_dividerColor; NSString *_autosave; NSMutableArray *_arranged; BOOL _inAdjust;
}
- (BOOL)isVertical; - (CGFloat)dividerThickness; - (void)adjustSubviews; - (NSArray *)arrangedSubviews;
- (void)setPosition:(CGFloat)p ofDividerAtIndex:(NSInteger)i;
@end

@interface NSStackView : NSView {
@public
  NSMutableArray *_arranged; NSMutableDictionary *_gravity; NSMapTable *_customSpacing, *_visPriority; NSInteger _orientation, _alignment, _distribution; CGFloat _spacing; NSEdgeInsets _insets;
  BOOL _detachesHidden; id _delegate;
}
- (NSArray *)arrangedSubviews; - (void)addArrangedSubview:(NSView *)v;
@end

@interface NSVisualEffectView : NSView { @public NSInteger _material, _blending, _state; BOOL _emphasized; NSImage *_mask; }
@end

@interface NSPanel : NSWindow { @public BOOL _floating, _keyOnlyIfNeeded, _worksWhenModal, _hidesOnDeactivate; }
@end

@interface NSGradient : NSObject <NSCopying, NSSecureCoding> { @public NSArray *_colors; CGFloat *_locs; NSColorSpace *_space; }
- (id)initWithColors:(NSArray *)colors; - (id)initWithStartingColor:(NSColor *)a endingColor:(NSColor *)b;
- (void)drawInRect:(NSRect)r angle:(CGFloat)a; - (NSColor *)interpolatedColorAtLocation:(CGFloat)l;
@end

@interface NSAnimationContext : NSObject { @public NSTimeInterval _duration; BOOL _implicit; id _timing; void (^_completion)(void); }
+ (NSAnimationContext *)currentContext;
@end
