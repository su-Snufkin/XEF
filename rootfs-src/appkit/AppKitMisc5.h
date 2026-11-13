/* Dock tile, menu badge, glyph info, accessibility actions/rotors, attachment cells, predicate row templates, ... (AppKitMisc5.m). */
#import "AppKitMisc4.h"

@interface NSDockTile : NSObject { @public NSView *_cv; NSString *_badge; BOOL _showsBadge; id _owner; }
- (NSSize)size; - (NSView *)contentView; - (void)setContentView:(NSView *)v; - (void)display; - (BOOL)showsApplicationBadge; - (void)setShowsApplicationBadge:(BOOL)f;
- (NSString *)badgeLabel; - (void)setBadgeLabel:(NSString *)l; - (id)owner;
@end
@interface NSMenuItemBadge : NSObject <NSCopying> { @public NSInteger _count, _type; NSString *_str; }
+ (id)updatesWithCount:(NSInteger)n; + (id)newItemsWithCount:(NSInteger)n; + (id)alertsWithCount:(NSInteger)n; - (id)initWithCount:(NSInteger)n type:(NSInteger)t; - (id)initWithCount:(NSInteger)n; - (id)initWithString:(NSString *)s;
- (NSInteger)itemCount; - (NSInteger)type; - (NSString *)stringValue;
@end
@interface NSGlyphInfo : NSObject <NSCopying> { @public NSString *_base, *_name; NSUInteger _cid, _coll; unsigned short _gid; }
+ (id)glyphInfoWithCGGlyph:(unsigned short)g forFont:(NSFont *)f baseString:(NSString *)b; - (unsigned short)glyphID; - (NSString *)baseString;
+ (id)glyphInfoWithGlyphName:(NSString *)n forFont:(NSFont *)f baseString:(NSString *)b; + (id)glyphInfoWithGlyph:(unsigned int)g forFont:(NSFont *)f baseString:(NSString *)b;
+ (id)glyphInfoWithCharacterIdentifier:(NSUInteger)c collection:(NSInteger)col baseString:(NSString *)b; - (NSString *)glyphName; - (NSUInteger)characterIdentifier; - (NSInteger)characterCollection;
@end
@interface NSAccessibilityCustomAction : NSObject { @public NSString *_name; BOOL (^_handler)(void); id _target; SEL _sel; }
- (id)initWithName:(NSString *)n handler:(BOOL (^)(void))h; - (id)initWithName:(NSString *)n target:(id)t selector:(SEL)s; - (NSString *)name; - (void)setName:(NSString *)n;
- (id)handler; - (void)setHandler:(id)h; - (id)target; - (void)setTarget:(id)t; - (SEL)selector; - (void)setSelector:(SEL)s;
@end
@interface NSAccessibilityCustomRotor : NSObject { @public NSString *_label; NSInteger _type; id _del, _load; }
- (id)initWithLabel:(NSString *)l itemSearchDelegate:(id)d; - (id)initWithRotorType:(NSInteger)t itemSearchDelegate:(id)d; - (NSInteger)type; - (void)setType:(NSInteger)t; - (NSString *)label; - (void)setLabel:(NSString *)l;
- (id)itemSearchDelegate; - (void)setItemSearchDelegate:(id)d; - (id)itemLoadingDelegate; - (void)setItemLoadingDelegate:(id)d;
@end
@interface NSTextAttachmentCell : NSCell { @public NSTextAttachment *_att; }
- (BOOL)wantsToTrackMouse; - (NSPoint)cellBaselineOffset; - (id)attachment; - (void)setAttachment:(id)a;
- (void)drawWithFrame:(NSRect)f inView:(NSView *)v characterIndex:(NSUInteger)i; - (void)drawWithFrame:(NSRect)f inView:(NSView *)v characterIndex:(NSUInteger)i layoutManager:(NSLayoutManager *)lm;
- (BOOL)wantsToTrackMouseForEvent:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v atCharacterIndex:(NSUInteger)i;
- (BOOL)trackMouse:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v atCharacterIndex:(NSUInteger)i untilMouseUp:(BOOL)u;
- (NSRect)cellFrameForTextContainer:(NSTextContainer *)c proposedLineFragment:(NSRect)l glyphPosition:(NSPoint)g characterIndex:(NSUInteger)i;
@end
@interface NSTextAttachmentViewProvider : NSObject { @public NSTextAttachment *_att; id _tlm, _loc; NSView *_view, *_parent; BOOL _tracks; }
- (id)initWithTextAttachment:(NSTextAttachment *)a parentView:(NSView *)p textLayoutManager:(id)m location:(id)l; - (NSTextAttachment *)textAttachment; - (id)textLayoutManager; - (id)location;
- (NSView *)view; - (void)setView:(NSView *)v; - (void)loadView; - (BOOL)tracksTextAttachmentViewBounds; - (void)setTracksTextAttachmentViewBounds:(BOOL)f;
- (NSRect)attachmentBoundsForAttributes:(NSDictionary *)a location:(id)l textContainer:(NSTextContainer *)c proposedLineFragment:(NSRect)r position:(NSPoint)p;
@end
@interface NSOpenGLLayer : NSObject { @public NSView *_view; NSOpenGLPixelFormat *_pf; NSOpenGLContext *_ctx; }
- (NSView *)view; - (void)setView:(NSView *)v; - (NSOpenGLPixelFormat *)openGLPixelFormat; - (void)setOpenGLPixelFormat:(NSOpenGLPixelFormat *)p; - (NSOpenGLContext *)openGLContext; - (void)setOpenGLContext:(NSOpenGLContext *)c;
- (NSOpenGLPixelFormat *)openGLPixelFormatForDisplayMask:(unsigned int)m; - (NSOpenGLContext *)openGLContextForPixelFormat:(NSOpenGLPixelFormat *)p;
- (BOOL)canDrawInOpenGLContext:(NSOpenGLContext *)c pixelFormat:(NSOpenGLPixelFormat *)p forLayerTime:(double)t displayTime:(const void *)d;
- (void)drawInOpenGLContext:(NSOpenGLContext *)c pixelFormat:(NSOpenGLPixelFormat *)p forLayerTime:(double)t displayTime:(const void *)d;
@end
@interface NSColorPicker : NSObject { @public NSColorPanel *_panel; NSUInteger _mask; }
- (id)initWithPickerMask:(NSUInteger)m colorPanel:(NSColorPanel *)p; - (NSColorPanel *)colorPanel; - (id)provideNewButtonImage; - (void)insertNewButtonImage:(NSImage *)i in:(NSButtonCell *)c; - (void)viewSizeChanged:(id)s;
- (void)attachColorList:(id)l; - (void)detachColorList:(id)l; - (void)setMode:(NSInteger)m; - (NSString *)buttonToolTip; - (NSSize)minContentSize; - (void)alphaControlAddedOrRemoved:(id)s;
@end
@interface NSTouch : NSObject { @public id _identity; NSUInteger _phase; NSPoint _np; BOOL _resting; NSSize _dsz; NSInteger _type; }
- (id)identity; - (NSUInteger)phase; - (NSPoint)normalizedPosition; - (BOOL)isResting; - (id)device; - (NSSize)deviceSize; - (NSInteger)type; - (NSPoint)locationInView:(NSView *)v; - (NSPoint)previousLocationInView:(NSView *)v;
@end
@interface NSDraggingSession : NSObject { @public NSInteger _form, _leader, _seq; BOOL _anim; NSPasteboard *_pb; NSPoint _loc; }
- (NSInteger)draggingFormation; - (void)setDraggingFormation:(NSInteger)f; - (BOOL)animatesToStartingPositionsOnCancelOrFail; - (void)setAnimatesToStartingPositionsOnCancelOrFail:(BOOL)f;
- (NSInteger)draggingLeaderIndex; - (void)setDraggingLeaderIndex:(NSInteger)i; - (NSPasteboard *)draggingPasteboard; - (NSInteger)draggingSequenceNumber; - (NSPoint)draggingLocation;
- (void)enumerateDraggingItemsWithOptions:(NSUInteger)o forView:(NSView *)v classes:(NSArray *)c searchOptions:(NSDictionary *)s usingBlock:(void (^)(id, NSInteger, BOOL *))b;
@end
@interface NSPredicateEditorRowTemplate : NSObject { @public NSArray *_left, *_right, *_ops, *_compound; NSUInteger _mod, _opts; NSInteger _rtype; NSPredicate *_pred; }
- (double)matchForPredicate:(NSPredicate *)p; - (NSArray *)templateViews; - (void)setPredicate:(NSPredicate *)p; - (NSPredicate *)predicateWithSubpredicates:(NSArray *)s; - (NSArray *)displayableSubpredicatesOfPredicate:(NSPredicate *)p;
- (id)initWithLeftExpressions:(NSArray *)l rightExpressions:(NSArray *)r modifier:(NSUInteger)m operators:(NSArray *)o options:(NSUInteger)opt;
- (id)initWithLeftExpressions:(NSArray *)l rightExpressionAttributeType:(NSUInteger)t modifier:(NSUInteger)m operators:(NSArray *)o options:(NSUInteger)opt; - (id)initWithCompoundTypes:(NSArray *)t;
- (NSArray *)leftExpressions; - (NSArray *)rightExpressions; - (NSUInteger)rightExpressionAttributeType; - (NSUInteger)modifier; - (NSArray *)operators; - (NSUInteger)options; - (NSArray *)compoundTypes;
+ (NSArray *)templatesWithAttributeKeyPaths:(NSArray *)k inEntityDescription:(id)e;
@end
@interface NSTokenFieldCell (XEFMisc)
- (NSInteger)tokenStyle; - (void)setTokenStyle:(NSInteger)s; - (NSTimeInterval)completionDelay; - (void)setCompletionDelay:(NSTimeInterval)d; + (NSTimeInterval)defaultCompletionDelay;
- (NSCharacterSet *)tokenizingCharacterSet; - (void)setTokenizingCharacterSet:(NSCharacterSet *)c; - (id)delegate; - (void)setDelegate:(id)d;
@end
@interface NSSound (XEFMisc)
+ (BOOL)canInitWithPasteboard:(NSPasteboard *)p; - (id)initWithPasteboard:(NSPasteboard *)p; - (void)writeToPasteboard:(NSPasteboard *)p; - (NSString *)playbackDeviceIdentifier; - (void)setPlaybackDeviceIdentifier:(NSString *)i;
- (void)setChannelMapping:(NSArray *)m; - (NSArray *)channelMapping; + (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p; - (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p;
@end
@interface NSPopUpButton (XEFMisc)
+ (id)popUpButtonWithMenu:(NSMenu *)m target:(id)t action:(SEL)a; + (id)pullDownButtonWithTitle:(NSString *)t menu:(NSMenu *)m; + (id)pullDownButtonWithImage:(NSImage *)i menu:(NSMenu *)m;
+ (id)pullDownButtonWithTitle:(NSString *)t image:(NSImage *)i menu:(NSMenu *)m; - (BOOL)usesItemFromMenu; - (void)setUsesItemFromMenu:(BOOL)f; - (BOOL)altersStateOfSelectedItem; - (void)setAltersStateOfSelectedItem:(BOOL)f;
- (NSInteger)indexOfItemWithTarget:(id)t andAction:(SEL)a;
@end
@interface NSPasteboardItem (XEFMisc)
- (NSString *)availableTypeFromArray:(NSArray *)a; - (void)setDataProvider:(id)p forTypes:(NSArray *)t; - (BOOL)setPropertyList:(id)l forType:(NSString *)t; - (id)propertyListForType:(NSString *)t;
- (void)detectPatternsForPatterns:(NSSet *)p completionHandler:(void (^)(NSSet *, NSError *))h; - (void)detectValuesForPatterns:(NSSet *)p completionHandler:(void (^)(NSDictionary *, NSError *))h;
- (void)detectMetadataForTypes:(NSSet *)t completionHandler:(void (^)(id, NSError *))h; - (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p; + (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p;
@end
