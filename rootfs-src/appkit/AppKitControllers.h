/* AppKit-lite view controllers (AppKitNib.m, AppKitControllers.m). */
#import "AppKitLite.h"
#import "AppKitControls2.h"

@class NSStoryboard;
@interface NSViewController : NSResponder <NSCoding> {
@public
  NSView *_view; NSString *_nibName; NSBundle *_nibBundle; id _representedObject; NSString *_title;
  NSStoryboard *_storyboard; BOOL _loading;
}
- (id)initWithNibName:(NSString *)n bundle:(NSBundle *)b;
- (NSView *)view; - (void)setView:(NSView *)v; - (void)loadView; - (void)viewDidLoad; - (BOOL)isViewLoaded;
- (void)viewWillAppear; - (void)viewDidAppear; - (void)viewWillDisappear; - (void)viewDidDisappear;
- (NSString *)title; - (NSSize)preferredContentSize; - (void)setPreferredContentSize:(NSSize)s;
@end
@interface NSViewController (XEFDeclarations)
- (NSString *)identifier; - (NSViewController *)parentViewController; - (NSArray *)childViewControllers;
- (void)insertChildViewController:(NSViewController *)c atIndex:(NSInteger)i; - (void)addChildViewController:(NSViewController *)c; - (void)removeFromParentViewController;
- (NSView *)viewIfLoaded; - (void)loadViewIfNeeded; - (NSViewController *)presentingViewController;
@end
@interface NSWindow (XEFSheets)
+ (NSWindow *)windowWithContentViewController:(NSViewController *)vc; - (void)beginSheet:(NSWindow *)sheet completionHandler:(void (^)(NSInteger))h;
- (void)endSheet:(NSWindow *)sheet; - (BOOL)isSheet;
@end
@interface NSTabViewItem (XEFVC)
+ (NSTabViewItem *)tabViewItemWithViewController:(NSViewController *)vc; - (NSViewController *)viewController; - (void)setViewController:(NSViewController *)vc;
@end

@interface NSSplitView (XEFVC)
- (void)setVertical:(BOOL)f; - (void)setDividerStyle:(NSInteger)s; - (void)setDelegate:(id)d;
- (void)insertArrangedSubview:(NSView *)v atIndex:(NSInteger)i; - (void)removeArrangedSubview:(NSView *)v; - (void)addArrangedSubview:(NSView *)v;
@end
@interface NSTabView (XEFVC)
- (void)selectTabViewItemAtIndex:(NSInteger)i; - (void)setDelegate:(id)d;
@end
@interface NSTabViewItem (XEFVC2)
- (void)setLabel:(NSString *)l;
@end
@interface NSView (XEFGestures)
- (NSArray *)gestureRecognizers;
@end
