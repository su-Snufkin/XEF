// Touch Bar items (color picker/stepper/popover/candidate list), NSWritingToolsCoordinator, NSTextFinder, NSTextCheckingController, NSSpellChecker extras, NSInputServer - compared with macOS.
#import <Cocoa/Cocoa.h>
#define NP(x) printf("%s\n",[[NSString stringWithFormat:x] UTF8String])
@interface D : NSObject <NSWritingToolsCoordinatorDelegate> @end
@implementation D @end
static void p1(void){ @autoreleasepool { 
 NSColorPickerTouchBarItem *c=[NSColorPickerTouchBarItem colorPickerWithIdentifier:@"c1"];
 printf("cp id %s color %d alpha %d spaces %d list %d enabled %d target %d action %d label %d super %s\n",[c.identifier UTF8String],c.color!=nil,c.showsAlpha,c.allowedColorSpaces!=nil,c.colorList!=nil,c.isEnabled,c.target!=nil,c.action!=NULL,c.customizationLabel!=nil,[NSStringFromClass([c superclass]) UTF8String]);
 NSColorPickerTouchBarItem *t=[NSColorPickerTouchBarItem textColorPickerWithIdentifier:@"c2"]; NSColorPickerTouchBarItem *s=[NSColorPickerTouchBarItem strokeColorPickerWithIdentifier:@"c3"]; NSColorPickerTouchBarItem *i=[NSColorPickerTouchBarItem colorPickerWithIdentifier:@"c4" buttonImage:[NSImage imageNamed:NSImageNameInfo]];
 printf("t color %d s color %d i color %d\n",t.color!=nil,s.color!=nil,i.color!=nil);
 c.color=[NSColor redColor]; c.showsAlpha=YES; c.enabled=NO; c.customizationLabel=@"L"; printf("cp2 %d %d %d %s\n",c.color!=nil,c.showsAlpha,c.isEnabled,[c.customizationLabel UTF8String]);
 NSStepperTouchBarItem *st=[NSStepperTouchBarItem stepperTouchBarItemWithIdentifier:@"s1" formatter:[[NSNumberFormatter alloc] init]];
 printf("st max %g min %g inc %g val %g target %d action %d enabled?\n",st.maxValue,st.minValue,st.increment,st.value,st.target!=nil,st.action!=NULL);
 st.maxValue=50; st.minValue=5; st.increment=2; st.value=7; printf("st2 %g %g %g %g\n",st.maxValue,st.minValue,st.increment,st.value);
 st.value=100; printf("clamp %g\n",st.value);
 NSStepperTouchBarItem *sd=[NSStepperTouchBarItem stepperTouchBarItemWithIdentifier:@"s2" drawingHandler:^(NSRect r,double v){ }]; printf("sd %d\n",sd!=nil);
 NSPopoverTouchBarItem *p=[[NSPopoverTouchBarItem alloc] initWithIdentifier:@"p1"];
 printf("pop tb %d coll %d img %d lab %d hold %d close %d label %d\n",p.popoverTouchBar!=nil,p.collapsedRepresentation!=nil,p.collapsedRepresentationImage!=nil,p.collapsedRepresentationLabel!=nil,p.pressAndHoldTouchBar!=nil,p.showsCloseButton,p.customizationLabel!=nil);
 p.showsCloseButton=YES; p.collapsedRepresentationLabel=@"Lab"; printf("pop2 %d [%s] rep %d\n",p.showsCloseButton,[p.collapsedRepresentationLabel UTF8String],p.collapsedRepresentation!=nil);
 printf("gr %d\n",[p makeStandardActivatePopoverGestureRecognizer]!=nil);
 NSTouchBar *tb=[[NSTouchBar alloc] init]; p.popoverTouchBar=tb; [p showPopover:nil]; [p dismissPopover:nil]; printf("pop3 %d\n",p.popoverTouchBar==tb);
 NSCandidateListTouchBarItem *cl=[[NSCandidateListTouchBarItem alloc] initWithIdentifier:@"cl"];
 printf("cl client %d del %d coll %d allowsColl %d vis %d tic %d attr %d cands %lu label %d\n",cl.client!=nil,cl.delegate!=nil,cl.isCollapsed,cl.allowsCollapsing,cl.isCandidateListVisible,cl.allowsTextInputContextCandidates,cl.attributedStringForCandidate!=nil,(unsigned long)cl.candidates.count,cl.customizationLabel!=nil);
 [cl setCandidates:@[@"a",@"b"] forSelectedRange:NSMakeRange(0,1) inString:@"x"]; printf("cl2 %lu\n",(unsigned long)cl.candidates.count);
 cl.collapsed=YES; cl.allowsCollapsing=NO; printf("cl3 %d %d\n",cl.isCollapsed,cl.allowsCollapsing);
 [cl updateWithInsertionPointVisibility:YES];
 printf("wt avail %d\n",[NSWritingToolsCoordinator isWritingToolsAvailable]);
 NSInputServer *is=[[NSInputServer alloc] initWithDelegate:nil name:@"x"]; printf("is %d wants %d mouse %d delay %d disable %d\n",is!=nil,[is wantsToInterpretAllKeystrokes],[is wantsToHandleMouseEvents],[is wantsToDelayTextChangeNotifications],[is canBeDisabled]);
}}
static void p2(void){ @autoreleasepool { 
 D *d=[D new]; NSWritingToolsCoordinator *w=[[NSWritingToolsCoordinator alloc] initWithDelegate:d];
 printf("wt del %d view %d eff %d dec %d state %ld pref %ld beh %ld prefopt %ld opts %ld list %d\n",w.delegate==d,w.view!=nil,w.effectContainerView!=nil,w.decorationContainerView!=nil,(long)w.state,(long)w.preferredBehavior,(long)w.behavior,(long)w.preferredResultOptions,(long)w.resultOptions,w.includesTextListMarkers);
 w.preferredBehavior=NSWritingToolsBehaviorLimited; w.preferredResultOptions=NSWritingToolsResultPlainText; w.includesTextListMarkers=YES; printf("wt2 %ld %ld %d beh %ld\n",(long)w.preferredBehavior,(long)w.preferredResultOptions,w.includesTextListMarkers,(long)w.behavior);
 NSView *v=[[NSView alloc] init]; w.effectContainerView=v; w.decorationContainerView=v; printf("wt3 %d %d\n",w.effectContainerView==v,w.decorationContainerView==v);
 [w stopWritingTools];
 NSTextFinder *f=[[NSTextFinder alloc] init];
 printf("tf client %d bar %d ind %d incr %d dim %d ranges %lu\n",f.client!=nil,f.findBarContainer!=nil,f.isIncrementalSearchingEnabled,f.isIncrementalSearchingEnabled,f.incrementalSearchingShouldDimContentView,(unsigned long)f.incrementalMatchRanges.count);
 f.incrementalSearchingEnabled=YES; f.incrementalSearchingShouldDimContentView=YES; f.findIndicatorNeedsUpdate=YES; printf("tf2 %d %d %d\n",f.isIncrementalSearchingEnabled,f.incrementalSearchingShouldDimContentView,f.findIndicatorNeedsUpdate);
 printf("tf validate %d %d\n",[f validateAction:NSTextFinderActionShowFindInterface],[f validateAction:NSTextFinderActionNextMatch]);
 [f cancelFindIndicator]; [f noteClientStringWillChange]; [f performAction:NSTextFinderActionHideFindInterface];
 NSTextCheckingController *tc=[[NSTextCheckingController alloc] initWithClient:nil]; printf("tcc client %d tag %ld valid %lu\n",tc.client!=nil,(long)tc.spellCheckerDocumentTag,(unsigned long)tc.validAnnotations.count);
 NSSpellChecker *sc=[NSSpellChecker sharedSpellChecker];
 printf("sc panel %d subs %d acc %d\n",sc.spellingPanel!=nil,sc.substitutionsPanel!=nil,sc.substitutionsPanelAccessoryViewController!=nil);
 printf("auto %d %d %d %d %d %d %d %d\n",NSSpellChecker.isAutomaticTextReplacementEnabled,NSSpellChecker.isAutomaticSpellingCorrectionEnabled,NSSpellChecker.isAutomaticQuoteSubstitutionEnabled,NSSpellChecker.isAutomaticDashSubstitutionEnabled,NSSpellChecker.isAutomaticCapitalizationEnabled,NSSpellChecker.isAutomaticPeriodSubstitutionEnabled,NSSpellChecker.isAutomaticTextCompletionEnabled,NSSpellChecker.isAutomaticInlinePredictionEnabled);
 printf("guess %lu\n",(unsigned long)[sc guessesForWord:@"helo"].count>0);
 [sc forgetWord:@"zzzq"]; [sc setWordFieldStringValue:@"x"];
}}
int main(void){ [NSApplication sharedApplication]; p1(); p2(); return 0; }
