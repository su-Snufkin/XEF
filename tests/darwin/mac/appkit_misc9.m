// NSDockTile, NSMenuItemBadge, NSGlyphInfo, accessibility actions/rotors, attachment cell/provider, predicate row templates, token/popup/pasteboard-item extras - compared with macOS.
#import <Cocoa/Cocoa.h>
static const char *S(id s){ return s?[[s description] UTF8String]:"(nil)"; }
@interface RD : NSObject <NSAccessibilityElementLoading> @end @implementation RD @end
static void p1(void){ @autoreleasepool { 
 NSTokenFieldCell *tc=[[NSTokenFieldCell alloc] initTextCell:@""]; printf("tfc style %ld delay %g def %g cs %d del %d\n",(long)tc.tokenStyle,tc.completionDelay,[NSTokenFieldCell defaultCompletionDelay],tc.tokenizingCharacterSet!=nil,tc.delegate!=nil);
 tc.tokenStyle=NSTokenStyleRounded; tc.completionDelay=0.7; tc.tokenizingCharacterSet=[NSCharacterSet characterSetWithCharactersInString:@";"]; printf("tfc2 %ld %g semi %d\n",(long)tc.tokenStyle,tc.completionDelay,[tc.tokenizingCharacterSet characterIsMember:';']);
 printf("canInit %d\n",[NSSound canInitWithPasteboard:[NSPasteboard pasteboardWithUniqueName]]);
 NSMenu *m=[[NSMenu alloc] initWithTitle:@""]; [m addItemWithTitle:@"A" action:NULL keyEquivalent:@""]; [m addItemWithTitle:@"B" action:@selector(description) keyEquivalent:@""];
 NSPopUpButton *pu=[NSPopUpButton popUpButtonWithMenu:m target:nil action:NULL]; printf("pu items %ld pulls %d uses %d alters %d title %s\n",(long)pu.numberOfItems,pu.pullsDown,pu.usesItemFromMenu,pu.altersStateOfSelectedItem,S(pu.titleOfSelectedItem));
 NSPopUpButton *pi=[NSPopUpButton pullDownButtonWithImage:[NSImage imageNamed:NSImageNameInfo] menu:m]; printf("pi pulls %d\n",pi.pullsDown);
 NSPopUpButton *pti=[NSPopUpButton pullDownButtonWithTitle:@"T" image:[NSImage imageNamed:NSImageNameInfo] menu:m]; printf("pti %d\n",pti.pullsDown);
 pu.usesItemFromMenu=NO; pu.altersStateOfSelectedItem=NO; printf("pu2 %d %d\n",pu.usesItemFromMenu,pu.altersStateOfSelectedItem);
 printf("idx %ld none %ld\n",(long)[pu indexOfItemWithTarget:nil andAction:@selector(description)],(long)[pu indexOfItemWithTarget:nil andAction:@selector(copy)]);
 NSPasteboardItem *it=[[NSPasteboardItem alloc] init]; [it setString:@"x" forType:NSPasteboardTypeString];
 [it setPropertyList:@{@"a":@1} forType:@"public.xef"]; printf("pl %s\n",S([it propertyListForType:@"public.xef"][@"a"]));
 NSMenuItemBadge *b1=[[NSMenuItemBadge alloc] initWithCount:5]; printf("badge %ld type %ld str %s\n",(long)b1.itemCount,(long)b1.type,S(b1.stringValue));
 NSMenuItemBadge *b2=[[NSMenuItemBadge alloc] initWithCount:3 type:NSMenuItemBadgeTypeAlerts]; printf("b2 %ld %ld %s\n",(long)b2.itemCount,(long)b2.type,S(b2.stringValue));
 NSMenuItemBadge *b3=[[NSMenuItemBadge alloc] initWithString:@"New"]; printf("b3 %ld %ld %s\n",(long)b3.itemCount,(long)b3.type,S(b3.stringValue));
 printf("upd %ld new %ld al %ld\n",(long)[NSMenuItemBadge updatesWithCount:2].type,(long)[NSMenuItemBadge newItemsWithCount:2].type,(long)[NSMenuItemBadge alertsWithCount:2].type);
 NSFont *f=[NSFont systemFontOfSize:12];
 NSGlyphInfo *gn=[NSGlyphInfo glyphInfoWithGlyphName:@"A" forFont:f baseString:@"A"]; printf("gn %d name %s\n",gn!=nil,S(gn.glyphName));
 NSGlyphInfo *gc=[NSGlyphInfo glyphInfoWithCharacterIdentifier:5 collection:NSAdobeJapan1CharacterCollection baseString:@"x"]; printf("gc %d cid %lu coll %ld\n",gc!=nil,(unsigned long)gc.characterIdentifier,(long)gc.characterCollection);
 NSDockTile *dt=[NSApp dockTile]; printf("dock %d size %g,%g cv %d disp badge %d lab %s owner %d\n",dt!=nil,dt.size.width,dt.size.height,dt.contentView!=nil,dt.showsApplicationBadge,S(dt.badgeLabel),dt.owner==NSApp);
 dt.badgeLabel=@"5"; dt.showsApplicationBadge=NO; [dt display]; printf("dock2 %s %d\n",S(dt.badgeLabel),dt.showsApplicationBadge);
 NSView *dv=[[NSView alloc] initWithFrame:NSMakeRect(0,0,10,10)]; dt.contentView=dv; printf("dock cv %d\n",dt.contentView==dv);
 NSAccessibilityCustomAction *ca=[[NSAccessibilityCustomAction alloc] initWithName:@"Do" handler:^BOOL{ return YES; }]; printf("ca name %s h %d tgt %d sel %d\n",S(ca.name),ca.handler!=nil,ca.target!=nil,ca.selector!=NULL);
 NSAccessibilityCustomAction *ca2=[[NSAccessibilityCustomAction alloc] initWithName:@"Go" target:NSApp selector:@selector(description)]; printf("ca2 %s h %d tgt %d sel %d\n",S(ca2.name),ca2.handler!=nil,ca2.target==NSApp,ca2.selector==@selector(description));
 ca2.name=@"X"; printf("ca3 %s\n",S(ca2.name));
 NSAccessibilityCustomRotor *cr=[[NSAccessibilityCustomRotor alloc] initWithLabel:@"R" itemSearchDelegate:(id)nil]; printf("cr label %s type %ld del %d load %d\n",S(cr.label),(long)cr.type,cr.itemSearchDelegate!=nil,cr.itemLoadingDelegate!=nil);
 NSAccessibilityCustomRotor *cr2=[[NSAccessibilityCustomRotor alloc] initWithRotorType:NSAccessibilityCustomRotorTypeHeading itemSearchDelegate:(id)nil]; printf("cr2 %ld label %s\n",(long)cr2.type,S(cr2.label)); cr2.label=@"L"; cr2.type=NSAccessibilityCustomRotorTypeLink; printf("cr3 %s %ld\n",S(cr2.label),(long)cr2.type);
 NSTextAttachment *ta=[[NSTextAttachment alloc] init]; NSTextAttachmentCell *tac=[[NSTextAttachmentCell alloc] initImageCell:[NSImage imageNamed:NSImageNameInfo]]; printf("tac att %d track %d base %g\n",tac.attachment!=nil,[tac wantsToTrackMouse],[tac cellBaselineOffset].y);
 tac.attachment=ta; printf("tac2 %d\n",tac.attachment==ta);
 NSTextAttachmentViewProvider *vp=[[NSTextAttachmentViewProvider alloc] initWithTextAttachment:ta parentView:nil textLayoutManager:nil location:nil]; printf("vp att %d tlm %d loc %d view %d tracks %d\n",vp.textAttachment==ta,vp.textLayoutManager!=nil,vp.location!=nil,vp.view!=nil,vp.tracksTextAttachmentViewBounds);
 vp.tracksTextAttachmentViewBounds=YES; printf("vp2 %d\n",vp.tracksTextAttachmentViewBounds);
 NSView *vv=[[NSView alloc] init]; vp.view=vv; printf("vp3 %d\n",vp.view==vv); [vp loadView];
 NSOpenGLLayer *gl=[[NSOpenGLLayer alloc] init]; printf("gl view %d pf %d ctx %d\n",gl.view!=nil,gl.openGLPixelFormat!=nil,gl.openGLContext!=nil);
 NSColorPanel *cp=[NSColorPanel sharedColorPanel];
}}
static void p2(void){ @autoreleasepool { 
 NSExpression *l=[NSExpression expressionForKeyPath:@"name"]; NSExpression *r=[NSExpression expressionForConstantValue:@"x"];
 NSPredicateEditorRowTemplate *t=[[NSPredicateEditorRowTemplate alloc] initWithLeftExpressions:@[l] rightExpressions:@[r] modifier:NSDirectPredicateModifier operators:@[@(NSEqualToPredicateOperatorType),@(NSBeginsWithPredicateOperatorType)] options:0];
 printf("rt left %lu right %lu mod %ld ops %lu opts %lu rtype %ld views %lu compound %d\n",(unsigned long)t.leftExpressions.count,(unsigned long)t.rightExpressions.count,(long)t.modifier,(unsigned long)t.operators.count,(unsigned long)t.options,(long)t.rightExpressionAttributeType,(unsigned long)t.templateViews.count,t.compoundTypes!=nil);
 NSPredicate *p=[NSComparisonPredicate predicateWithLeftExpression:l rightExpression:r modifier:NSDirectPredicateModifier type:NSEqualToPredicateOperatorType options:0];
 printf("match %g\n",[t matchForPredicate:p]);
 NSComparisonPredicate *p2=[NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForKeyPath:@"zzz"] rightExpression:r modifier:NSDirectPredicateModifier type:NSEqualToPredicateOperatorType options:0]; printf("match2 %g\n",[t matchForPredicate:p2]);
 [t setPredicate:p]; printf("after set views %lu\n",(unsigned long)t.templateViews.count);
 NSPredicate *pp=[t predicateWithSubpredicates:nil]; printf("pred %d %s\n",pp!=nil,S(pp));
 printf("disp %lu\n",(unsigned long)[t displayableSubpredicatesOfPredicate:p].count);
 NSPredicateEditorRowTemplate *t2=[[NSPredicateEditorRowTemplate alloc] initWithLeftExpressions:@[l] rightExpressionAttributeType:NSStringAttributeType modifier:NSDirectPredicateModifier operators:@[@(NSEqualToPredicateOperatorType)] options:0]; printf("t2 rtype %ld right %lu\n",(long)t2.rightExpressionAttributeType,(unsigned long)t2.rightExpressions.count);
 NSPredicateEditorRowTemplate *c=[[NSPredicateEditorRowTemplate alloc] initWithCompoundTypes:@[@(NSAndPredicateType),@(NSOrPredicateType)]]; printf("c types %lu left %lu ops %lu\n",(unsigned long)c.compoundTypes.count,(unsigned long)c.leftExpressions.count,(unsigned long)c.operators.count);
 printf("cmatch %g\n",[c matchForPredicate:[NSCompoundPredicate andPredicateWithSubpredicates:@[p]]]);
 printf("cmatch2 %g\n",[c matchForPredicate:p]);
}}
int main(void){ [NSApplication sharedApplication]; p1(); p2(); return 0; }
