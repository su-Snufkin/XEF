/* Small model classes: NSUserInterfaceCompressionOptions, NSFontCollection, NSTitlebarAccessoryViewController, NSApplication extras.
   Behaviours matched against macOS (tests/darwin/mac/appkit_misc3.m). */
#import "AppKitMisc.h"
#include <objc/runtime.h>
#import "AppKitText.h"
@interface NSMutableFontCollection : NSFontCollection @end
@class CABasicAnimation, NSClickGestureRecognizer;

/* ---- compression options ---- */
@implementation NSUserInterfaceCompressionOptions
- (id)init { return [self initWithCompressionOptions:[NSSet set]]; }
- (id)initWithCoder:(NSCoder *)c { return [self init]; }
- (id)initWithIdentifier:(NSString *)i { return [self initWithCompressionOptions:[NSSet setWithObject:i]]; }
- (id)initWithCompressionOptions:(NSSet *)s {
  self = [super init]; NSMutableSet *ids = [NSMutableSet set];
  for (id o in s) { if ([o isKindOfClass:[NSUserInterfaceCompressionOptions class]]) [ids unionSet:((NSUserInterfaceCompressionOptions *)o)->_ids]; else if ([o isKindOfClass:[NSString class]]) [ids addObject:o]; }
  _ids = [ids copy]; return self; }
- (void)dealloc { [_ids release]; [super dealloc]; }
- (BOOL)containsOptions:(NSUserInterfaceCompressionOptions *)o { return [o->_ids isSubsetOfSet:_ids]; }
- (BOOL)intersectsOptions:(NSUserInterfaceCompressionOptions *)o { return [_ids intersectsSet:o->_ids]; }
- (BOOL)isEmpty { return [_ids count] == 0; }
- (NSUserInterfaceCompressionOptions *)optionsByAddingOptions:(NSUserInterfaceCompressionOptions *)o { NSMutableSet *s = [NSMutableSet setWithSet:_ids]; [s unionSet:o->_ids]; return [[[NSUserInterfaceCompressionOptions alloc] initWithCompressionOptions:s] autorelease]; }
- (NSUserInterfaceCompressionOptions *)optionsByRemovingOptions:(NSUserInterfaceCompressionOptions *)o { NSMutableSet *s = [NSMutableSet setWithSet:_ids]; [s minusSet:o->_ids]; return [[[NSUserInterfaceCompressionOptions alloc] initWithCompressionOptions:s] autorelease]; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSUserInterfaceCompressionOptions class]] && [_ids isEqualToSet:((NSUserInterfaceCompressionOptions *)o)->_ids]; }
- (NSUInteger)hash { return [_ids hash]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
+ (NSUserInterfaceCompressionOptions *)_opt:(NSString *)i { return [[[self alloc] initWithIdentifier:i] autorelease]; }
+ (NSUserInterfaceCompressionOptions *)hideImagesOption { return [self _opt:@"NSUserInterfaceCompressionHideImages"]; }
+ (NSUserInterfaceCompressionOptions *)hideTextOption { return [self _opt:@"NSUserInterfaceCompressionHideText"]; }
+ (NSUserInterfaceCompressionOptions *)reduceMetricsOption { return [self _opt:@"NSUserInterfaceCompressionReduceMetrics"]; }
+ (NSUserInterfaceCompressionOptions *)breakEqualWidthsOption { return [self _opt:@"NSUserInterfaceCompressionBreakEqualWidths"]; }
+ (NSUserInterfaceCompressionOptions *)standardOptions { return [[[self alloc] initWithCompressionOptions:[NSSet setWithObjects:@"NSUserInterfaceCompressionHideImages", @"NSUserInterfaceCompressionHideText", @"NSUserInterfaceCompressionReduceMetrics", @"NSUserInterfaceCompressionBreakEqualWidths", nil]] autorelease]; }
@end

/* ---- font collections ---- */
static NSMutableDictionary *g_fc_named;
static NSArray *StdCollectionNames(void) { return [NSArray arrayWithObjects:@"com.apple.AllFonts", @"com.apple.UserFonts", @"com.apple.Favorites", @"com.apple.Recents", @"Fun", @"Web", @"Modern", @"PDF", @"Fixed Width", @"Traditional", nil]; }
@implementation NSFontCollection
+ (NSFontCollection *)fontCollectionWithDescriptors:(NSArray *)d { NSFontCollection *c = [[[self alloc] init] autorelease]; c->_query = [d copy]; return c; }
+ (NSFontCollection *)fontCollectionWithAllAvailableDescriptors { NSFontCollection *c = [[[self alloc] init] autorelease]; c->_all = YES; return c; }
+ (NSFontCollection *)fontCollectionWithLocale:(NSLocale *)l { return [self fontCollectionWithAllAvailableDescriptors]; }
+ (BOOL)showFontCollection:(NSFontCollection *)c withName:(NSString *)n visibility:(NSInteger)v error:(NSError **)e { if (!g_fc_named) g_fc_named = [[NSMutableDictionary alloc] init]; [g_fc_named setObject:c forKey:n]; return YES; }
+ (BOOL)hideFontCollectionWithName:(NSString *)n visibility:(NSInteger)v error:(NSError **)e { if (![g_fc_named objectForKey:n]) return NO; [g_fc_named removeObjectForKey:n]; return YES; }
+ (BOOL)renameFontCollectionWithName:(NSString *)n visibility:(NSInteger)v toName:(NSString *)t error:(NSError **)e { id c = [g_fc_named objectForKey:n]; if (!c) return NO; [c retain]; [g_fc_named removeObjectForKey:n]; [g_fc_named setObject:c forKey:t]; [c release]; return YES; }
+ (NSArray *)allFontCollectionNames { NSMutableArray *a = [NSMutableArray arrayWithArray:StdCollectionNames()]; [a addObjectsFromArray:[g_fc_named allKeys]]; return a; }
+ (NSFontCollection *)fontCollectionWithName:(NSString *)n { return [self fontCollectionWithName:n visibility:0]; }
+ (NSFontCollection *)fontCollectionWithName:(NSString *)n visibility:(NSInteger)v {
  NSFontCollection *c = [g_fc_named objectForKey:n]; if (c) return c;
  if ([StdCollectionNames() containsObject:n]) { c = [self fontCollectionWithAllAvailableDescriptors]; return c; }
  return nil; }
- (void)dealloc { [_query release]; [_excl release]; [_name release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (id)mutableCopyWithZone:(NSZone *)z { NSFontCollection *c = [[NSMutableFontCollection alloc] init]; c->_query = [_query copy]; c->_excl = [_excl copy]; c->_all = _all; return c; }
- (NSArray *)queryDescriptors { return _query; } - (NSArray *)exclusionDescriptors { return _excl; }
- (NSArray *)matchingDescriptors { return [self matchingDescriptorsWithOptions:nil]; }
- (NSArray *)matchingDescriptorsWithOptions:(NSDictionary *)o {
  NSMutableArray *out = [NSMutableArray array];
  if (_all) { for (NSString *n in [[NSFontManager sharedFontManager] availableFonts]) [out addObject:[NSFontDescriptor fontDescriptorWithName:n size:12]]; return out; }
  NSArray *all = [[NSFontManager sharedFontManager] availableFonts];
  for (NSFontDescriptor *q in _query) { NSString *n = [q postscriptName] ? [q postscriptName] : [[q fontAttributes] objectForKey:NSFontNameAttribute]; NSString *fam = [[q fontAttributes] objectForKey:NSFontFamilyAttribute];
    for (NSString *f in all) if ((n && [f isEqualToString:n]) || (fam && [f hasPrefix:fam]) || (!n && !fam)) [out addObject:[NSFontDescriptor fontDescriptorWithName:f size:12]]; }
  return out; }
- (NSArray *)matchingDescriptorsForFamily:(NSString *)f { return [self matchingDescriptorsForFamily:f options:nil]; }
- (NSArray *)matchingDescriptorsForFamily:(NSString *)f options:(NSDictionary *)o {
  NSMutableArray *out = [NSMutableArray array]; for (NSFontDescriptor *d in [self matchingDescriptorsWithOptions:o]) { NSString *n = [d postscriptName]; if (!n) n = [[d fontAttributes] objectForKey:NSFontNameAttribute]; if ([n hasPrefix:f]) [out addObject:d]; }
  return [out count] ? out : nil; }
@end

/* ---- titlebar accessory ---- */
@implementation NSTitlebarAccessoryViewController
- (id)initWithNibName:(NSString *)n bundle:(NSBundle *)b { self = [super initWithNibName:n bundle:b]; _la = 4; _auto = YES; return self; }
- (id)init { return [self initWithNibName:nil bundle:nil]; }
- (void)dealloc { [_anims release]; [super dealloc]; }
- (NSInteger)layoutAttribute { return _la; } - (void)setLayoutAttribute:(NSInteger)a { _la = a; }
- (CGFloat)fullScreenMinHeight { return _fsmin; } - (void)setFullScreenMinHeight:(CGFloat)h { _fsmin = h; }
- (BOOL)isHidden { return _hidden; } - (void)setHidden:(BOOL)f { _hidden = f; if ([self isViewLoaded]) [[self view] setHidden:f]; }
- (BOOL)automaticallyAdjustsSize { return _auto; } - (void)setAutomaticallyAdjustsSize:(BOOL)f { _auto = f; }
- (id)animator { return self; }
- (NSDictionary *)animations { return _anims ? _anims : [NSDictionary dictionary]; } - (void)setAnimations:(NSDictionary *)a { [a retain]; [_anims release]; _anims = a; }
- (id)animationForKey:(NSString *)k { id a = [_anims objectForKey:k]; return a ? a : [[self class] defaultAnimationForKey:k]; }
+ (id)defaultAnimationForKey:(NSString *)k { return [k isEqualToString:@"hidden"] ? [NSNull null] : nil; }
@end

/* ---- NSApplication extras ---- */
@implementation NSApplication (XEFMisc)
- (void)registerForRemoteNotifications {} - (void)unregisterForRemoteNotifications {} - (BOOL)isRegisteredForRemoteNotifications { return NO; }
- (void)registerForRemoteNotificationTypes:(NSUInteger)t {} - (NSUInteger)enabledRemoteNotificationTypes { return 0; }
- (void)beginSheet:(NSWindow *)s modalForWindow:(NSWindow *)w modalDelegate:(id)d didEndSelector:(SEL)sel contextInfo:(void *)ci {
  [w beginSheet:s completionHandler:^(NSModalResponse rc) { if (d && sel && [d respondsToSelector:sel]) { void (*f)(id, SEL, id, NSInteger, void *) = (void (*)(id, SEL, id, NSInteger, void *))objc_msgSend; f(d, sel, s, (NSInteger)rc, ci); } }]; }
- (void)endSheet:(NSWindow *)s { [self endSheet:s returnCode:0]; }
- (void)endSheet:(NSWindow *)s returnCode:(NSInteger)rc { NSWindow *p = [s sheetParent]; if (p) [p endSheet:s returnCode:rc]; else [s orderOut:nil]; }
- (void)makeWindowsPerform:(SEL)sel inOrder:(BOOL)o { for (NSWindow *w in [self orderedWindows]) if ([w respondsToSelector:sel] && [w performSelector:sel]) return; }
- (id)context { return nil; }
- (BOOL)isAutomaticCustomizeTouchBarMenuItemEnabled { return [objc_getAssociatedObject(self, "xef.autotb") boolValue]; }
- (void)setAutomaticCustomizeTouchBarMenuItemEnabled:(BOOL)f { objc_setAssociatedObject(self, "xef.autotb", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (void)toggleTouchBarCustomizationPalette:(id)s {} - (void)unregisterUserInterfaceItemSearchHandler:(id)h {}
- (BOOL)searchString:(NSString *)s inUserInterfaceItemString:(NSString *)i searchRange:(NSRange)r foundRange:(NSRange *)f {
  if (NSMaxRange(r) > [i length]) return NO; NSRange x = [i rangeOfString:s options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch range:r];
  if (x.location == NSNotFound) return NO; if (f) *f = x; return YES; }
- (void)restoreWindowWithIdentifier:(NSString *)i state:(NSCoder *)s completionHandler:(void (^)(NSWindow *, NSError *))h { if (h) h(nil, nil); }
@end

/* ---- Touch Bar items ---- */
@implementation NSColorPickerTouchBarItem
+ (id)_make:(NSString *)i { NSColorPickerTouchBarItem *c = [[[self alloc] initWithIdentifier:i] autorelease]; return c; }
+ (id)colorPickerWithIdentifier:(NSString *)i { return [self _make:i]; }
+ (id)textColorPickerWithIdentifier:(NSString *)i { return [self _make:i]; }
+ (id)strokeColorPickerWithIdentifier:(NSString *)i { return [self _make:i]; }
+ (id)colorPickerWithIdentifier:(NSString *)i buttonImage:(NSImage *)img { return [self _make:i]; }
- (id)initWithIdentifier:(NSString *)i { if ((self = [super initWithIdentifier:i])) { _color = [[NSColor blackColor] retain]; _alpha = YES; _enabled = YES; _colorList = [[NSObject alloc] init]; } return self; }
- (void)dealloc { [_color release]; [_colorList release]; [_spaces release]; [super dealloc]; }
- (NSColor *)color { return _color; } - (void)setColor:(NSColor *)c { [c retain]; [_color release]; _color = c; }
- (BOOL)showsAlpha { return _alpha; } - (void)setShowsAlpha:(BOOL)f { _alpha = f; }
- (id)allowedColorSpaces { return _spaces; } - (void)setAllowedColorSpaces:(id)s { [s retain]; [_spaces release]; _spaces = s; }
- (id)colorList { return _colorList; } - (void)setColorList:(id)l { [l retain]; [_colorList release]; _colorList = l; }
- (NSString *)customizationLabel { return _label ? _label : @""; } - (void)setCustomizationLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (id)target { return _target; } - (void)setTarget:(id)t { _target = t; } - (SEL)action { return _action; } - (void)setAction:(SEL)a { _action = a; }
- (BOOL)isEnabled { return _enabled; } - (void)setEnabled:(BOOL)f { _enabled = f; }
@end

@implementation NSStepperTouchBarItem
- (id)initWithIdentifier:(NSString *)i { if ((self = [super initWithIdentifier:i])) { _max = 59; _inc = 1; } return self; }
+ (id)stepperTouchBarItemWithIdentifier:(NSString *)i formatter:(NSFormatter *)f { return [[[self alloc] initWithIdentifier:i] autorelease]; }
+ (id)stepperTouchBarItemWithIdentifier:(NSString *)i drawingHandler:(void (^)(NSRect, double))h { return [[[self alloc] initWithIdentifier:i] autorelease]; }
- (double)maxValue { return _max; } - (void)setMaxValue:(double)v { _max = v; if (_val > v) _val = v; }
- (double)minValue { return _min; } - (void)setMinValue:(double)v { _min = v; if (_val < v) _val = v; }
- (double)increment { return _inc; } - (void)setIncrement:(double)v { _inc = v; }
- (double)value { return _val; } - (void)setValue:(double)v { _val = v < _min ? _min : (v > _max ? _max : v); }
- (id)target { return _target; } - (void)setTarget:(id)t { _target = t; } - (SEL)action { return _action; } - (void)setAction:(SEL)a { _action = a; }
- (NSString *)customizationLabel { return _label ? _label : @""; } - (void)setCustomizationLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
@end

@implementation NSPopoverTouchBarItem
- (id)initWithIdentifier:(NSString *)i { if ((self = [super initWithIdentifier:i])) { _pop = [[NSTouchBar alloc] init]; _close = YES; _coll = [[NSTouchBarItem alloc] initWithIdentifier:@"popover.collapsed"]; } return self; }
- (void)dealloc { [_pop release]; [_hold release]; [_coll release]; [_img release]; [_lab release]; [super dealloc]; }
- (NSTouchBar *)popoverTouchBar { return _pop; } - (void)setPopoverTouchBar:(NSTouchBar *)b { [b retain]; [_pop release]; _pop = b; }
- (NSString *)customizationLabel { return _label ? _label : @""; } - (void)setCustomizationLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (NSTouchBarItem *)collapsedRepresentation { return _coll; } - (void)setCollapsedRepresentation:(NSTouchBarItem *)i { [i retain]; [_coll release]; _coll = i; }
- (NSImage *)collapsedRepresentationImage { return _img; } - (void)setCollapsedRepresentationImage:(NSImage *)i { [i retain]; [_img release]; _img = i; }
- (NSString *)collapsedRepresentationLabel { return _lab; } - (void)setCollapsedRepresentationLabel:(NSString *)l { [l retain]; [_lab release]; _lab = l; }
- (NSTouchBar *)pressAndHoldTouchBar { return _hold; } - (void)setPressAndHoldTouchBar:(NSTouchBar *)b { [b retain]; [_hold release]; _hold = b; }
- (BOOL)showsCloseButton { return _close; } - (void)setShowsCloseButton:(BOOL)f { _close = f; }
- (void)showPopover:(id)s {} - (void)dismissPopover:(id)s {}
- (id)makeStandardActivatePopoverGestureRecognizer { return [[[objc_getClass("NSClickGestureRecognizer") alloc] init] autorelease]; }
@end

@implementation NSCandidateListTouchBarItem
- (id)initWithIdentifier:(NSString *)i { if ((self = [super initWithIdentifier:i])) { _allowsColl = YES; _ticc = YES; _cands = [[NSArray alloc] init]; } return self; }
- (void)dealloc { [_attr release]; [_cands release]; [super dealloc]; }
- (id)client { return _client; } - (void)setClient:(id)c { _client = c; } - (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)isCollapsed { return _coll; } - (void)setCollapsed:(BOOL)f { if (_allowsColl) _coll = f; }
- (BOOL)allowsCollapsing { return _allowsColl; } - (void)setAllowsCollapsing:(BOOL)f { _allowsColl = f; if (!f) _coll = NO; }
- (BOOL)isCandidateListVisible { return YES; } - (void)updateWithInsertionPointVisibility:(BOOL)f {}
- (BOOL)allowsTextInputContextCandidates { return _ticc; } - (void)setAllowsTextInputContextCandidates:(BOOL)f { _ticc = f; }
- (id)attributedStringForCandidate { return _attr; } - (void)setAttributedStringForCandidate:(id)b { id c = b ? Block_copy(b) : nil; [_attr release]; _attr = c; }
- (NSArray *)candidates { return _cands; } - (void)setCandidates:(NSArray *)c forSelectedRange:(NSRange)r inString:(NSString *)s { [c retain]; [_cands release]; _cands = c ? c : [[NSArray alloc] init]; }
- (NSString *)customizationLabel { return _label ? _label : @""; } - (void)setCustomizationLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
@end

/* ---- writing tools, text finder / checking, input server ---- */
@implementation NSWritingToolsCoordinator
+ (BOOL)isWritingToolsAvailable { return YES; }
- (id)initWithDelegate:(id)d { self = [super init]; _delegate = d; return self; }
- (void)dealloc { [_eff release]; [_dec release]; [super dealloc]; }
- (id)delegate { return _delegate; } - (NSView *)view { return nil; }
- (NSView *)effectContainerView { return _eff; } - (void)setEffectContainerView:(NSView *)v { [v retain]; [_eff release]; _eff = v; }
- (NSView *)decorationContainerView { return _dec; } - (void)setDecorationContainerView:(NSView *)v { [v retain]; [_dec release]; _dec = v; }
- (NSInteger)state { return 0; } - (void)stopWritingTools {}
- (NSInteger)preferredBehavior { return _pref; } - (void)setPreferredBehavior:(NSInteger)b { _pref = b; }
- (NSInteger)behavior { return _pref == 0 ? 1 : _pref; }
- (NSInteger)preferredResultOptions { return _prefopt; } - (void)setPreferredResultOptions:(NSInteger)o { _prefopt = o; }
- (NSInteger)resultOptions { return _prefopt == 0 ? 15 : _prefopt; }
- (BOOL)includesTextListMarkers { return _list; } - (void)setIncludesTextListMarkers:(BOOL)f { _list = f; }
- (void)updateRange:(NSRange)r withText:(id)t reason:(NSInteger)reason forContextWithIdentifier:(id)i {} - (void)updateForReflowedTextInContextWithIdentifier:(id)i {}
@end

@implementation NSTextFinder
- (id)initWithCoder:(NSCoder *)c { return [self init]; }
- (id)client { return _client; } - (void)setClient:(id)c { _client = c; }
- (void)performAction:(NSInteger)a {} - (BOOL)validateAction:(NSInteger)a { return _client != nil; }
- (id)findBarContainer { return _bar; } - (void)setFindBarContainer:(id)c { _bar = c; }
- (void)cancelFindIndicator {} - (BOOL)findIndicatorNeedsUpdate { return NO; } - (void)setFindIndicatorNeedsUpdate:(BOOL)f {}
- (BOOL)isIncrementalSearchingEnabled { return _incr; } - (void)setIncrementalSearchingEnabled:(BOOL)f { _incr = f; }
- (BOOL)incrementalSearchingShouldDimContentView { return _dim; } - (void)setIncrementalSearchingShouldDimContentView:(BOOL)f { _dim = f; }
- (NSArray *)incrementalMatchRanges { return [NSArray array]; } + (void)drawIncrementalMatchHighlightInRect:(NSRect)r {} - (void)noteClientStringWillChange {}
@end

@implementation NSTextCheckingController
- (id)initWithClient:(id)c { self = [super init]; _client = c; return self; }
- (id)client { return _client; } - (void)invalidate {} - (void)didChangeTextInRange:(NSRange)r {} - (void)insertedTextInRange:(NSRange)r {} - (void)didChangeSelectedRange {}
- (void)considerTextCheckingForRange:(NSRange)r {} - (void)checkTextInRange:(NSRange)r types:(NSUInteger)t options:(NSDictionary *)o {} - (void)checkTextInSelection:(id)s {} - (void)checkTextInDocument:(id)s {}
- (void)orderFrontSubstitutionsPanel:(id)s { [[[NSSpellChecker sharedSpellChecker] substitutionsPanel] orderFront:s]; }
- (void)checkSpelling:(id)s {} - (void)showGuessPanel:(id)s { [[[NSSpellChecker sharedSpellChecker] spellingPanel] orderFront:s]; } - (void)changeSpelling:(id)s {} - (void)ignoreSpelling:(id)s {} - (void)updateCandidates {}
- (NSArray *)validAnnotations {
  return [NSArray arrayWithObjects:@"NSAccessibilitySpellingState", @"NSCompletionString", @"NSDataDetection", @"NSDominantLanguageAttributeName", @"NSDominantScriptAttributeName", @"NSEmojiCheckingAttributeName", @"NSGrammarCorrections", @"NSGrammarLeftOffset", @"NSGrammarRightOffset", @"NSGrammarUserDescription", @"NSGrammarConfidenceScore", @"NSGrammarIssueType", @"NSGrammarTargetPair", @"NSGrammarSystemCategory", @"NSGrammarUserCategory", @"NSGrammarUUID", @"NSIgnoringSubstitution", @"NSLanguageMapAttributeName", @"NSLink", @"NSOrthography", @"NSPostEditingCorrection", @"NSReplacedString", @"NSSpellingState", @"NSTemporaryTextCorrection", @"NSTextAlternatives", @"NSTextChecked", @"NSTextCompleted", @"NSTextCompletion", @"NSTextCorrection", @"NSTextEdited", @"NSTextReplacementAttributeName", @"NSTextReverted", nil]; }
- (NSMenu *)menuAtIndex:(NSUInteger)i clickedOnSelection:(BOOL)s effectiveRange:(NSRange *)r { return nil; }
- (NSInteger)spellCheckerDocumentTag { return _tag; } - (void)setSpellCheckerDocumentTag:(NSInteger)t { _tag = t; }
@end

@implementation NSInputServer
- (id)initWithDelegate:(id)d name:(NSString *)n { self = [super init]; _delegate = d; _name = [n copy]; return self; }
- (void)dealloc { [_name release]; [super dealloc]; }
- (void)insertText:(id)s client:(id)c {} - (void)doCommandBySelector:(SEL)s client:(id)c {} - (void)markedTextAbandoned:(id)c {} - (void)markedTextSelectionChanged:(NSRange)r client:(id)c {}
- (void)terminate:(id)s {} - (BOOL)canBeDisabled { return YES; } - (BOOL)wantsToInterpretAllKeystrokes { return NO; } - (BOOL)wantsToHandleMouseEvents { return NO; } - (BOOL)wantsToDelayTextChangeNotifications { return NO; }
- (void)inputClientBecomeActive:(id)c {} - (void)inputClientResignActive:(id)c {} - (void)inputClientEnabled:(id)c {} - (void)inputClientDisabled:(id)c {}
- (void)activeConversationWillChange:(id)c fromOldConversation:(NSInteger)o {} - (void)activeConversationChanged:(id)c toNewConversation:(NSInteger)n {}
- (void)mouseDownOnCharacterIndex:(NSUInteger)i atCoordinate:(NSPoint)p withModifier:(NSUInteger)m client:(id)c {} - (void)mouseDraggedOnCharacterIndex:(NSUInteger)i atCoordinate:(NSPoint)p withModifier:(NSUInteger)m client:(id)c {}
- (void)mouseUpOnCharacterIndex:(NSUInteger)i atCoordinate:(NSPoint)p withModifier:(NSUInteger)m client:(id)c {}
@end

@implementation NSSpellChecker (XEFMisc)
- (NSMenu *)menuForResult:(id)r string:(NSString *)s options:(NSDictionary *)o atLocation:(NSPoint)p inView:(NSView *)v { return nil; }
- (NSPanel *)_xefPanel:(const char *)key title:(NSString *)t {
  NSPanel *p = objc_getAssociatedObject(self, key);
  if (!p) { p = [[[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 420, 300) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:YES] autorelease]; [p setTitle:t]; [p setReleasedWhenClosed:NO]; objc_setAssociatedObject(self, key, p, OBJC_ASSOCIATION_RETAIN); }
  return p; }
- (NSPanel *)spellingPanel { return [self _xefPanel:"xef.sp" title:@"Spelling and Grammar"]; }
- (NSPanel *)substitutionsPanel { return [self _xefPanel:"xef.sub" title:@"Substitutions"]; }
- (id)substitutionsPanelAccessoryViewController { return objc_getAssociatedObject(self, "xef.subacc"); } - (void)setSubstitutionsPanelAccessoryViewController:(id)c { objc_setAssociatedObject(self, "xef.subacc", c, OBJC_ASSOCIATION_RETAIN); }
- (void)setWordFieldStringValue:(NSString *)s {}
- (void)showCorrectionIndicatorOfType:(NSInteger)t primaryString:(NSString *)p alternativeStrings:(NSArray *)a forStringInRect:(NSRect)r view:(NSView *)v completionHandler:(void (^)(NSString *))h { if (h) h(nil); }
- (void)showInlinePredictionForCandidates:(NSArray *)c client:(id)cl {}
- (NSArray *)guessesForWord:(NSString *)w { return [self guessesForWordRange:NSMakeRange(0, [w length]) inString:w language:nil inSpellDocumentWithTag:0]; }
- (void)forgetWord:(NSString *)w { [self unlearnWord:w]; }
+ (BOOL)isAutomaticTextReplacementEnabled { return YES; } + (BOOL)isAutomaticSpellingCorrectionEnabled { return YES; } + (BOOL)isAutomaticQuoteSubstitutionEnabled { return YES; } + (BOOL)isAutomaticDashSubstitutionEnabled { return YES; }
+ (BOOL)isAutomaticCapitalizationEnabled { return YES; } + (BOOL)isAutomaticPeriodSubstitutionEnabled { return YES; } + (BOOL)isAutomaticTextCompletionEnabled { return YES; } + (BOOL)isAutomaticInlinePredictionEnabled { return YES; }
@end

/* ---- NSBitmapImageRep extras ---- */
@implementation NSBitmapImageRep (XEFMisc)
- (id)initWithFocusedViewRect:(NSRect)r { return [self initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)r.size.width pixelsHigh:(NSInteger)r.size.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:@"NSDeviceRGBColorSpace" bitmapFormat:0 bytesPerRow:0 bitsPerPixel:0]; }
- (id)initWithCIImage:(id)i { NSSize s = [i respondsToSelector:@selector(extent)] ? NSMakeSize(1, 1) : NSMakeSize(1, 1); return [self initWithFocusedViewRect:NSMakeRect(0, 0, s.width, s.height)]; }
- (void)getCompression:(NSUInteger *)c factor:(float *)f { NSNumber *n = objc_getAssociatedObject(self, "xef.cmp"), *x = objc_getAssociatedObject(self, "xef.cmpf"); if (c) *c = n ? [n unsignedIntegerValue] : 1; if (f) *f = x ? [x floatValue] : 0; }
- (void)setCompression:(NSUInteger)c factor:(float)f { objc_setAssociatedObject(self, "xef.cmp", [NSNumber numberWithUnsignedInteger:c], OBJC_ASSOCIATION_RETAIN); objc_setAssociatedObject(self, "xef.cmpf", [NSNumber numberWithFloat:c == 6 ? f : 0], OBJC_ASSOCIATION_RETAIN); }
+ (NSData *)TIFFRepresentationOfImageRepsInArray:(NSArray *)a usingCompression:(NSUInteger)c factor:(float)f { id r = [a firstObject]; return [r respondsToSelector:@selector(TIFFRepresentation)] ? [r TIFFRepresentation] : nil; }
+ (void)getTIFFCompressionTypes:(const NSUInteger **)t count:(NSInteger *)n { static const NSUInteger types[] = { 1, 5, 6, 32773, 3, 4 }; if (t) *t = types; if (n) *n = 6; }
+ (NSString *)localizedNameForTIFFCompressionType:(NSUInteger)t {
  switch (t) { case 1: return @"None"; case 5: return @"Lempel-Ziv & Welch"; case 6: return @"JPEG"; case 32773: return @"PackBits"; case 3: return @"CCITT Group 3"; case 4: return @"CCITT Group 4"; default: return nil; } }
- (BOOL)canBeCompressedUsing:(NSUInteger)c { if (c == 3 || c == 4) return [self bitsPerSample] == 1 && [self samplesPerPixel] == 1; return c == 1 || c == 5 || c == 6 || c == 32773; }
- (void)colorizeByMappingGray:(CGFloat)m toColor:(NSColor *)c blackMapping:(NSColor *)b whiteMapping:(NSColor *)w {}
- (id)initForIncrementalLoad { return [self initWithFocusedViewRect:NSMakeRect(0, 0, 1, 1)]; }
- (NSInteger)incrementalLoadFromData:(NSData *)d complete:(BOOL)c { NSBitmapImageRep *r = [NSBitmapImageRep imageRepWithData:d]; if (!r) return c ? -4 : -2; objc_setAssociatedObject(self, "xef.inc", d, OBJC_ASSOCIATION_RETAIN); return c ? -6 : -3; }
- (NSColorSpace *)colorSpace { return [[self colorSpaceName] rangeOfString:@"White"].location != NSNotFound ? [NSColorSpace genericGrayColorSpace] : [NSColorSpace deviceRGBColorSpace]; }
- (NSBitmapImageRep *)bitmapImageRepByConvertingToColorSpace:(NSColorSpace *)cs renderingIntent:(NSInteger)i {
  if ([cs colorSpaceModel] != 0) return [[self copy] autorelease];
  NSInteger w = _w, h = _h;
  NSBitmapImageRep *g = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:1 hasAlpha:NO isPlanar:NO colorSpaceName:@"NSCalibratedWhiteColorSpace" bitmapFormat:0 bytesPerRow:0 bitsPerPixel:8] autorelease];
  for (NSInteger y = 0; y < h; y++) for (NSInteger x = 0; x < w; x++) { NSColor *c = [[self colorAtX:x y:y] colorUsingColorSpaceName:@"NSCalibratedRGBColorSpace"]; CGFloat l = 0.299 * [c redComponent] + 0.587 * [c greenComponent] + 0.114 * [c blueComponent]; NSUInteger px[1] = { (NSUInteger)(l * 255 + 0.5) }; [g setPixel:px atX:x y:y]; }
  return g; }
- (NSBitmapImageRep *)bitmapImageRepByRetaggingWithColorSpace:(NSColorSpace *)cs { return [[self copy] autorelease]; }
- (void)setProperty:(NSString *)k withValue:(id)v { NSMutableDictionary *d = objc_getAssociatedObject(self, "xef.props"); if (!d) { d = [NSMutableDictionary dictionary]; objc_setAssociatedObject(self, "xef.props", d, OBJC_ASSOCIATION_RETAIN); } if (v) [d setObject:v forKey:k]; else [d removeObjectForKey:k]; }
- (id)valueForProperty:(NSString *)k { return [(NSDictionary *)objc_getAssociatedObject(self, "xef.props") objectForKey:k]; }
@end

/* ---- NSBrowser extras ---- */
static NSMutableDictionary *g_browser_saved;
@implementation NSBrowser (XEFMisc)
- (id)itemAtIndexPath:(NSIndexPath *)p {
  if ([self _xefClassic] || ![_delegate respondsToSelector:@selector(browser:numberOfChildrenOfItem:)]) [NSException raise:NSInternalInconsistencyException format:@"itemAtIndexPath: is not supported for browsers with matrix delegates."];
  id item = _root; for (NSUInteger i = 0; i < [p length]; i++) item = [_delegate browser:self child:(NSInteger)[p indexAtPosition:i] ofItem:item]; return item; }
- (void)validateVisibleColumns {} - (void)scrollColumnsRightBy:(NSInteger)n {} - (void)scrollColumnsLeftBy:(NSInteger)n {} - (void)drawTitleOfColumn:(NSInteger)c inRect:(NSRect)r {}
- (BOOL)prefersAllColumnUserResizing { return [objc_getAssociatedObject(self, "xef.pacur") boolValue]; } - (void)setPrefersAllColumnUserResizing:(BOOL)f { objc_setAssociatedObject(self, "xef.pacur", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)s inColumn:(NSInteger)c { if ([self _xefClassic] || ![_delegate respondsToSelector:@selector(browser:numberOfChildrenOfItem:)]) [NSException raise:NSInternalInconsistencyException format:@"noteHeightOfRowsWithIndexesChanged:inColumn: is not supported for browsers with matrix delegates."]; [self setNeedsDisplay:YES]; }
- (NSString *)columnsAutosaveName { NSString *n = objc_getAssociatedObject(self, "xef.cas"); return n ? n : @""; } - (void)setColumnsAutosaveName:(NSString *)n { objc_setAssociatedObject(self, "xef.cas", [[n copy] autorelease], OBJC_ASSOCIATION_RETAIN); }
+ (void)removeSavedColumnsWithAutosaveName:(NSString *)n { [g_browser_saved removeObjectForKey:n]; }
- (BOOL)canDragRowsWithIndexes:(NSIndexSet *)s inColumn:(NSInteger)c withEvent:(NSEvent *)e { return NO; }
- (NSImage *)draggingImageForRowsWithIndexes:(NSIndexSet *)s inColumn:(NSInteger)c withEvent:(NSEvent *)e offset:(NSPointPointer)o { if (o) *o = NSZeroPoint; return nil; }
- (void)setDraggingSourceOperationMask:(NSUInteger)m forLocal:(BOOL)l {}
- (BOOL)editItemAtIndexPath:(NSIndexPath *)p withEvent:(NSEvent *)e select:(BOOL)s { return NO; }
- (void)scrollViaScroller:(NSScroller *)s {}
@end

/* ---- NSDocument extras ---- */
@implementation NSDocument (XEFMisc)
- (void)runModalPageLayoutWithPrintInfo:(NSPrintInfo *)pi delegate:(id)d didRunSelector:(SEL)s contextInfo:(void *)ci { if (d && s && [d respondsToSelector:s]) { void (*f)(id, SEL, id, BOOL, void *) = (void (*)(id, SEL, id, BOOL, void *))objc_msgSend; f(d, s, self, NO, ci); } }
- (void)runModalPageLayoutWithPrintInfo:(NSPrintInfo *)pi { }
- (BOOL)preparePageLayout:(id)l { return YES; } - (BOOL)shouldChangePrintInfo:(NSPrintInfo *)pi { return YES; }
- (void)runModalPrintOperation:(id)op delegate:(id)d didRunSelector:(SEL)s contextInfo:(void *)ci { BOOL ok = [op runOperation]; if (d && s && [d respondsToSelector:s]) { void (*f)(id, SEL, id, BOOL, void *) = (void (*)(id, SEL, id, BOOL, void *))objc_msgSend; f(d, s, self, ok, ci); } }
- (id)PDFPrintOperation { return [self printOperationWithSettings:[NSDictionary dictionaryWithObject:@"NSPrintSaveJob" forKey:@"NSJobDisposition"] error:NULL]; }
- (void)shareDocumentWithSharingService:(id)s completionHandler:(void (^)(BOOL))h { if (h) h(YES); } - (void)prepareSharingServicePicker:(id)p {}
- (NSArray *)previewRepresentableActivityItems { return objc_getAssociatedObject(self, "xef.pra"); } - (void)setPreviewRepresentableActivityItems:(NSArray *)a { objc_setAssociatedObject(self, "xef.pra", a, OBJC_ASSOCIATION_RETAIN); }
- (void)printShowingPrintPanel:(BOOL)f { [self printDocument:nil]; }
- (void)saveToFile:(NSString *)f saveOperation:(NSUInteger)op delegate:(id)d didSaveSelector:(SEL)s contextInfo:(void *)ci { NSError *e = nil; BOOL ok = [self writeToURL:[NSURL fileURLWithPath:f] ofType:[self fileType] error:&e]; if (d && s && [d respondsToSelector:s]) { void (*fn)(id, SEL, id, BOOL, void *) = (void (*)(id, SEL, id, BOOL, void *))objc_msgSend; fn(d, s, self, ok, ci); } }
- (id)handleSaveScriptCommand:(id)c { return nil; } - (id)handleCloseScriptCommand:(id)c { [self close]; return nil; } - (id)handlePrintScriptCommand:(id)c { return nil; }
- (id)objectSpecifier { return [[[NSObject alloc] init] autorelease]; }
@end

/* ---- NSLayoutManager glyph-level extras (glyphs map 1:1 to characters here) ---- */
@implementation NSLayoutManager (XEFMisc)
- (NSUInteger)getLineFragmentInsertionPointsForCharacterAtIndex:(NSUInteger)i alternatePositions:(BOOL)a inDisplayOrder:(BOOL)d positions:(CGFloat *)p characterIndexes:(NSUInteger *)c {
  NSUInteger n = [_storage length]; if (!n) { if (p) p[0] = 0; if (c) c[0] = 0; return 1; }
  NSRange lr; [self lineFragmentRectForGlyphAtIndex:MIN(i, n - 1) effectiveRange:&lr]; NSUInteger cnt = 0, end = NSMaxRange(lr);
  for (NSUInteger k = lr.location; k <= end; k++) {
    if (k == end && end != n) break;
    NSTextContainer *tc0 = [_containers objectAtIndex:0]; NSRect br = [self boundingRectForGlyphRange:NSMakeRange(k < n ? k : n - 1, 1) inTextContainer:tc0]; CGFloat x = k < n ? br.origin.x : NSMaxX(br);
    if (p) p[cnt] = x; if (c) c[cnt] = k; cnt++; }
  return cnt; }
- (NSFont *)substituteFontForFont:(NSFont *)f { return f; }
- (void)insertGlyphs:(const NSGlyph *)g length:(NSUInteger)n forStartingGlyphAtIndex:(NSUInteger)i characterIndex:(NSUInteger)c {}
- (void)insertGlyph:(NSGlyph)g atGlyphIndex:(NSUInteger)i characterIndex:(NSUInteger)c {} - (void)replaceGlyphAtIndex:(NSUInteger)i withGlyph:(NSGlyph)g {} - (void)deleteGlyphsInRange:(NSRange)r {}
- (void)setCharacterIndex:(NSUInteger)c forGlyphAtIndex:(NSUInteger)i {}
- (void)setIntAttribute:(NSInteger)a value:(NSInteger)v forGlyphAtIndex:(NSUInteger)i { NSMutableDictionary *d = objc_getAssociatedObject(self, "xef.ia"); if (!d) { d = [NSMutableDictionary dictionary]; objc_setAssociatedObject(self, "xef.ia", d, OBJC_ASSOCIATION_RETAIN); } [d setObject:[NSNumber numberWithInteger:v ? 1 : 0] forKey:[NSString stringWithFormat:@"%ld/%lu", (long)a, (unsigned long)i]]; }
- (NSInteger)intAttribute:(NSInteger)a forGlyphAtIndex:(NSUInteger)i { return [[(NSDictionary *)objc_getAssociatedObject(self, "xef.ia") objectForKey:[NSString stringWithFormat:@"%ld/%lu", (long)a, (unsigned long)i]] integerValue]; }
- (void)invalidateGlyphsOnLayoutInvalidationForGlyphRange:(NSRange)r {}
- (NSUInteger)getGlyphsInRange:(NSRange)r glyphs:(NSGlyph *)g characterIndexes:(NSUInteger *)c glyphInscriptions:(NSInteger *)in elasticBits:(BOOL *)e {
  NSUInteger n = [_storage length]; NSUInteger k = 0; for (NSUInteger i = r.location; i < NSMaxRange(r) && i < n; i++, k++) { if (g) g[k] = (NSGlyph)[[_storage string] characterAtIndex:i]; if (c) c[k] = i; if (in) in[k] = 0; if (e) e[k] = 0; } return k; }
- (NSUInteger)getGlyphsInRange:(NSRange)r glyphs:(NSGlyph *)g characterIndexes:(NSUInteger *)c glyphInscriptions:(NSInteger *)in elasticBits:(BOOL *)e bidiLevels:(unsigned char *)b {
  NSUInteger k = [self getGlyphsInRange:r glyphs:g characterIndexes:c glyphInscriptions:in elasticBits:e]; if (b) for (NSUInteger i = 0; i < k; i++) b[i] = 0; return k; }
- (void)textStorage:(NSTextStorage *)s edited:(NSUInteger)m range:(NSRange)r changeInLength:(NSInteger)d invalidatedRange:(NSRange)i { [self _xefInvalidate]; }
- (void)setLocations:(NSPoint *)l startingGlyphIndexes:(NSUInteger *)s count:(NSUInteger)n forGlyphRange:(NSRange)r {}
- (void)showPackedGlyphs:(char *)g length:(NSUInteger)n glyphRange:(NSRange)r atPoint:(NSPoint)p font:(NSFont *)f color:(NSColor *)c printingAdjustment:(NSSize)a {}
- (void)showCGGlyphs:(const unsigned short *)g positions:(const NSPoint *)p count:(NSUInteger)n font:(NSFont *)f matrix:(NSAffineTransform *)m attributes:(NSDictionary *)a inContext:(NSGraphicsContext *)c {}
@end
