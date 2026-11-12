/* AppKit-lite Auto Layout (AppKitLayout.m): constraints, anchors, layout guides and the solver behind them. */
#import "AppKitLite.h"

@class NSLayoutAnchor, NSLayoutXAxisAnchor, NSLayoutYAxisAnchor, NSLayoutDimension, NSLayoutGuide;

@interface NSLayoutConstraint : NSObject <NSCoding> {
@public
  id _first, _second;                       /* views or layout guides, not retained */
  NSInteger _firstAttr, _secondAttr, _relation; CGFloat _multiplier, _constant; float _priority; BOOL _active, _archived; NSString *_identifier; NSView *_holder;
}
+ (id)constraintWithItem:(id)a attribute:(NSInteger)aa relatedBy:(NSInteger)rel toItem:(id)b attribute:(NSInteger)ba multiplier:(CGFloat)m constant:(CGFloat)c;
+ (void)activateConstraints:(NSArray *)a; + (void)deactivateConstraints:(NSArray *)a;
- (BOOL)isActive; - (void)setActive:(BOOL)f; - (CGFloat)constant; - (void)setConstant:(CGFloat)c; - (float)priority; - (void)setPriority:(float)p;
@end

@interface NSLayoutAnchor : NSObject <NSCopying, NSCoding> { @public id _item; NSInteger _attr; }
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c;
@end
@interface NSLayoutXAxisAnchor : NSLayoutAnchor
@end
@interface NSLayoutYAxisAnchor : NSLayoutAnchor
@end
@interface NSLayoutDimension : NSLayoutAnchor
@end

@interface NSLayoutGuide : NSObject <NSCoding> { @public NSView *_owner; NSString *_identifier; NSRect _frame; }
- (NSView *)owningView; - (NSRect)frame;
@end

@interface NSView (XEFLayoutDeclarations)
- (NSView *)ancestorSharedWithView:(NSView *)v; - (void)addLayoutGuide:(NSLayoutGuide *)g; - (void)removeLayoutGuide:(NSLayoutGuide *)g;
- (float)contentHuggingPriorityForOrientation:(NSInteger)o; - (float)contentCompressionResistancePriorityForOrientation:(NSInteger)o;
@end

/* solves the constraints of the hierarchy v belongs to and sets the frames of its constraint-positioned views */
void XEFLayoutSolveIfNeeded(NSView *v);
/* the smallest size of v that satisfies the constraints inside it; NO when nothing constrains it */
BOOL XEFLayoutFittingSize(NSView *v, NSSize *out);
void XEFLayoutInvalidate(void);
void XEFLayoutViewGone(NSView *v);
