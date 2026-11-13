// The last odds and ends (deprecated NSOpenPanel/NSTabViewController/NSSplitViewController hooks, binding placeholders, colour catalog, ...) - compared with macOS.
#import <Cocoa/Cocoa.h>
static const char *S(id s){ return s?[[s description] UTF8String]:"(nil)"; }
int main(void){ @autoreleasepool { [NSApplication sharedApplication];
 NSColor *c=[NSColor colorWithCatalogName:@"System" colorName:@"redColor"]; printf("cat %d\n",c!=nil);
 @try { [NSFileManager fileManagerWithAuthorization:nil]; } @catch(NSException*ex){ printf("fmauth raises %s\n",[ex.name UTF8String]); }
 NSTabViewController *tvc=[[NSTabViewController alloc] init]; printf("tvc should %d defaults %lu allowed %lu\n",[tvc tabView:nil shouldSelectTabViewItem:nil],(unsigned long)[tvc toolbarDefaultItemIdentifiers:nil].count,(unsigned long)[tvc toolbarAllowedItemIdentifiers:nil].count);
 NSSplitViewController *svc=[[NSSplitViewController alloc] init]; printf("svc min %g hide %d coll %d\n",svc.minimumThicknessForInlineSidebars,[svc splitView:nil shouldHideDividerAtIndex:0],[svc splitView:nil shouldCollapseSubview:nil forDoubleClickOnDividerAtIndex:0]);
 svc.minimumThicknessForInlineSidebars=120; printf("svc2 %g\n",svc.minimumThicknessForInlineSidebars);
 [NSBindingSelectionMarker setDefaultPlaceholder:@"ph" forMarker:NSMultipleValuesMarker onClass:[NSTextField class] withBinding:NSValueBinding]; printf("ph %s\n",S([NSBindingSelectionMarker defaultPlaceholderForMarker:NSMultipleValuesMarker onClass:[NSTextField class] withBinding:NSValueBinding]));
 NSObjectController *oc=[[NSObjectController alloc] init]; [oc commitEditingWithDelegate:nil didCommitSelector:NULL contextInfo:NULL]; printf("commit ok\n"); [NSObject setDefaultPlaceholder:@"p" forMarker:NSNoSelectionMarker withBinding:NSValueBinding]; printf("objph %s %d\n",S([NSObject defaultPlaceholderForMarker:NSNoSelectionMarker withBinding:NSValueBinding]),[NSObject defaultPlaceholderForMarker:NSMultipleValuesMarker withBinding:NSValueBinding]!=nil);
 NSEvent *e=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"a" charactersIgnoringModifiers:@"a" isARepeat:NO keyCode:0]; printf("evctx %d\n",e.context==nil);
 NSPopover *p=[[NSPopover alloc] init]; printf("pop %d\n",p!=nil);
 NSAttributedString *as=[NSAttributedString attributedStringWithAdaptiveImageGlyph:nil attributes:@{}] ; printf("adaptive %d\n",1);
 NSMovie *mv=nil; printf("movie %d\n",NSClassFromString(@"NSMovie")!=nil);
 printf("tableheader tip %d\n",[[[NSTableHeaderView alloc] init] view:nil stringForToolTip:0 point:NSZeroPoint userData:NULL]==nil);
 { NSMovie *m=[[NSMovie alloc] init]; printf("movie init %d\n",m!=nil); NSPICTImageRep *pr=[NSPICTImageRep imageRepWithData:[@"junk" dataUsingEncoding:NSUTF8StringEncoding]]; printf("pict garbage %d\n",pr!=nil); }
 return 0;}}
