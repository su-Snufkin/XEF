// TextKit 2 model (NSTextRange, NSTextContentStorage, NSTextLayoutManager, selection/navigation), compared with macOS.
#import <Cocoa/Cocoa.h>
static void P(NSString *s){ printf("%s\n",[s UTF8String]); }
static void partA(void){ @autoreleasepool { 
 NSTextContentStorage *cs=[[NSTextContentStorage alloc] init];
 P([NSString stringWithFormat:@"cs attr=%@ ts=%d", cs.attributedString?@"set":@"nil", cs.textStorage!=nil]);
 cs.attributedString=[[NSAttributedString alloc] initWithString:@"Hello world\nSecond line\nThird"];
 P([NSString stringWithFormat:@"len=%lu ts=%d", (unsigned long)cs.attributedString.length, cs.textStorage!=nil]);
 NSTextRange *dr=cs.documentRange;
 P([NSString stringWithFormat:@"doc loc=%@ end=%@ empty=%d", NSStringFromClass([dr.location class]), NSStringFromClass([dr.endLocation class]), dr.isEmpty]);
 P([NSString stringWithFormat:@"desc: %@", [dr description]]);
 id l5=[cs locationFromLocation:dr.location withOffset:5];
 P([NSString stringWithFormat:@"off=%ld", (long)[cs offsetFromLocation:dr.location toLocation:l5]]);
 P([NSString stringWithFormat:@"cmp=%ld %ld", (long)[dr.location compare:l5], (long)[l5 compare:dr.location]]);
 id bad=[cs locationFromLocation:dr.location withOffset:999]; P([NSString stringWithFormat:@"beyond=%@", bad?@"loc":@"nil"]);
 id neg=[cs locationFromLocation:dr.location withOffset:-1]; P([NSString stringWithFormat:@"neg=%@", neg?@"loc":@"nil"]);
 NSTextRange *r1=[[NSTextRange alloc] initWithLocation:dr.location endLocation:l5];
 id l8=[cs locationFromLocation:dr.location withOffset:8]; id l3=[cs locationFromLocation:dr.location withOffset:3];
 NSTextRange *r2=[[NSTextRange alloc] initWithLocation:l3 endLocation:l8];
 P([NSString stringWithFormat:@"contains5=%d containsLoc3=%d inter=%d", [r1 containsRange:r2],[r1 containsLocation:l3],[r1 intersectsWithTextRange:r2]]);
 NSTextRange *i=[r1 textRangeByIntersectingWithTextRange:r2], *u=[r1 textRangeByFormingUnionWithTextRange:r2];
 P([NSString stringWithFormat:@"i=%ld..%ld u=%ld..%ld", (long)[cs offsetFromLocation:dr.location toLocation:i.location],(long)[cs offsetFromLocation:dr.location toLocation:i.endLocation],(long)[cs offsetFromLocation:dr.location toLocation:u.location],(long)[cs offsetFromLocation:dr.location toLocation:u.endLocation]]);
 NSTextRange *e=[[NSTextRange alloc] initWithLocation:l3]; P([NSString stringWithFormat:@"emptyinit empty=%d end=%@ eq=%d", e.isEmpty, e.endLocation==l3?@"same":@"diff", [e isEqualToTextRange:e]]);
 NSTextRange *nr=[[NSTextRange alloc] initWithLocation:l8 endLocation:l3]; P([NSString stringWithFormat:@"reversed=%@", nr?@"obj":@"nil"]);
 P([NSString stringWithFormat:@"disjoint=%@", [r1 textRangeByIntersectingWithTextRange:[[NSTextRange alloc] initWithLocation:[cs locationFromLocation:dr.location withOffset:9] endLocation:[cs locationFromLocation:dr.location withOffset:10]]]?@"obj":@"nil"]);
 NSMutableArray *a=[NSMutableArray array];
 [cs enumerateTextElementsFromLocation:nil options:0 usingBlock:^BOOL(NSTextElement *el){ [a addObject:[NSString stringWithFormat:@"%@ [%ld..%ld] '%@' sep=%@ content=%@ parent=%d rep=%d children=%lu", NSStringFromClass([el class]), (long)[cs offsetFromLocation:dr.location toLocation:el.elementRange.location],(long)[cs offsetFromLocation:dr.location toLocation:el.elementRange.endLocation],[[(NSTextParagraph*)el attributedString] string], @"x", @"y", el.parentElement!=nil, el.isRepresentedElement, (unsigned long)el.childElements.count]]; return YES; }];
 for(NSString*s in a) P(s);
 NSTextParagraph *tp=(NSTextParagraph*)[cs textElementsForRange:dr].firstObject; 
 P([NSString stringWithFormat:@"para sepR=%@ contentR=%@", NSStringFromRange(NSMakeRange(0,0)), @""]);
 P([NSString stringWithFormat:@"para content=%ld..%ld sep=%@", (long)[cs offsetFromLocation:dr.location toLocation:tp.paragraphContentRange.endLocation],(long)[cs offsetFromLocation:dr.location toLocation:tp.paragraphContentRange.location], tp.paragraphSeparatorRange?@"obj":@"nil"]);
 NSTextParagraph *p2=[[NSTextParagraph alloc] initWithAttributedString:[[NSAttributedString alloc] initWithString:@"abc"]];
 P([NSString stringWithFormat:@"p2 str=%@ contentR=%@ sepR=%@ cm=%d er=%@", [p2.attributedString string], p2.paragraphContentRange?@"obj":@"nil", p2.paragraphSeparatorRange?@"obj":@"nil", p2.textContentManager!=nil, p2.elementRange?@"obj":@"nil"]);
 NSTextSelection *sel=[[NSTextSelection alloc] initWithRange:r1 affinity:NSTextSelectionAffinityDownstream granularity:NSTextSelectionGranularityCharacter];
 P([NSString stringWithFormat:@"sel ranges=%lu gran=%ld aff=%ld transient=%d logical=%d anchor=%g sec=%@ typing=%@", (unsigned long)sel.textRanges.count,(long)sel.granularity,(long)sel.affinity,sel.isTransient,sel.isLogical,sel.anchorPositionOffset, sel.secondarySelectionLocation?@"obj":@"nil", sel.typingAttributes]);
 NSTextSelection *s2=[[NSTextSelection alloc] initWithLocation:l5 affinity:NSTextSelectionAffinityUpstream];
 P([NSString stringWithFormat:@"s2 ranges=%lu r0empty=%d gran=%ld aff=%ld", (unsigned long)s2.textRanges.count, s2.textRanges.count?[s2.textRanges[0] isEmpty]:-1,(long)s2.granularity,(long)s2.affinity]);
 NSTextSelection *s3=[sel textSelectionWithTextRanges:@[r2]]; P([NSString stringWithFormat:@"s3 gran=%ld aff=%ld", (long)s3.granularity,(long)s3.affinity]);
}}
static void partB(void){ @autoreleasepool { 
 NSTextContentStorage *cs=[[NSTextContentStorage alloc] init];
 NSTextLayoutManager *lm=[[NSTextLayoutManager alloc] init];
 [cs addTextLayoutManager:lm];
 NSTextContainer *tc=[[NSTextContainer alloc] initWithSize:NSMakeSize(200,1e6)]; lm.textContainer=tc;
 P([NSString stringWithFormat:@"added: cm=%d prim=%d lms=%lu tc.lm=%d vlc=%d", lm.textContentManager==cs, cs.primaryTextLayoutManager==lm,(unsigned long)cs.textLayoutManagers.count, tc.textLayoutManager==lm, lm.textViewportLayoutController!=nil]);
 cs.attributedString=[[NSAttributedString alloc] initWithString:@"Hello world\nSecond line\nThird" attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:14]}];
 P([NSString stringWithFormat:@"lm docrange eq=%d", [lm.documentRange isEqualToTextRange:cs.documentRange]]);
 [lm ensureLayoutForRange:lm.documentRange];
 NSMutableArray *fr=[NSMutableArray array];
 [lm enumerateTextLayoutFragmentsFromLocation:nil options:NSTextLayoutFragmentEnumerationOptionsEnsuresLayout usingBlock:^BOOL(NSTextLayoutFragment *f){ NSRect fr2=f.layoutFragmentFrame; long a=(long)[cs offsetFromLocation:cs.documentRange.location toLocation:f.rangeInElement.location]; long b=(long)[cs offsetFromLocation:cs.documentRange.location toLocation:f.rangeInElement.endLocation]; NSString *d=[NSString stringWithFormat:@"frag %@ state=%ld lines=%lu elem=%@ y>0=%d h>0=%d w>0=%d tlm=%d range=%ld..%ld",NSStringFromClass([f class]),(long)f.state,(unsigned long)f.textLineFragments.count,NSStringFromClass([f.textElement class]),fr2.origin.y>0,fr2.size.height>0,fr2.size.width>0,f.textLayoutManager==lm,a,b]; [fr addObject:d]; return YES;}];
 for(NSString*s in fr) P(s);
 P([NSString stringWithFormat:@"usage h>0=%d w>0=%d", [lm usageBoundsForTextContainer].size.height>0,[lm usageBoundsForTextContainer].size.width>0]);
 NSTextLayoutFragment *f0=[lm textLayoutFragmentForPosition:CGPointMake(5,5)];
 P([NSString stringWithFormat:@"frag at pt %d", f0!=nil]);
 NSTextLayoutFragment *f1=[lm textLayoutFragmentForLocation:[cs locationFromLocation:cs.documentRange.location withOffset:15]];
 P([NSString stringWithFormat:@"frag for loc15 %ld..%ld", (long)[cs offsetFromLocation:cs.documentRange.location toLocation:f1.rangeInElement.location],(long)[cs offsetFromLocation:cs.documentRange.location toLocation:f1.rangeInElement.endLocation]]);
 for (NSTextLineFragment *l in f1.textLineFragments) P([NSString stringWithFormat:@"line range=%@ w>0=%d h>0=%d glyphOrigin=%g,%g bounds.origin=%g,%g", NSStringFromRange(l.characterRange), l.typographicBounds.size.width>0, l.typographicBounds.size.height>0, l.glyphOrigin.x,l.glyphOrigin.y,l.typographicBounds.origin.x,l.typographicBounds.origin.y]);
 P([NSString stringWithFormat:@"fragframe x=%g y>0=%d w>0=%d h>0=%d rsb h>0=%d lp=%g tp=%g tm=%g bm=%g", f1.layoutFragmentFrame.origin.x, f1.layoutFragmentFrame.origin.y>0, f1.layoutFragmentFrame.size.width>0, f1.layoutFragmentFrame.size.height>0, f1.renderingSurfaceBounds.size.height>0, f1.leadingPadding,f1.trailingPadding,f1.topMargin,f1.bottomMargin]);
 NSTextLineFragment *lfx=[f1 textLineFragmentForTextLocation:f1.rangeInElement.location isUpstreamAffinity:NO]; P([NSString stringWithFormat:@"lf for loc %d", lfx!=nil]);
 NSTextLineFragment *lfy=[f1 textLineFragmentForVerticalOffset:2 requiresExactMatch:YES]; P([NSString stringWithFormat:@"lf for vert %d", lfy!=nil]);
 // attributes
 NSTextRange *rg=[[NSTextRange alloc] initWithLocation:cs.documentRange.location endLocation:[cs locationFromLocation:cs.documentRange.location withOffset:5]];
 [lm addRenderingAttribute:NSForegroundColorAttributeName value:[NSColor redColor] forTextRange:rg];
 __block int n=0; [lm enumerateRenderingAttributesFromLocation:cs.documentRange.location reverse:NO usingBlock:^BOOL(NSTextLayoutManager*m,NSDictionary*a,NSTextRange*r){ n++; printf("ra %lu %ld..%ld\n",(unsigned long)a.count,(long)[cs offsetFromLocation:cs.documentRange.location toLocation:r.location],(long)[cs offsetFromLocation:cs.documentRange.location toLocation:r.endLocation]); return YES;}];
 [lm removeRenderingAttribute:NSForegroundColorAttributeName forTextRange:rg];
 [lm setRenderingAttributes:@{NSBackgroundColorAttributeName:[NSColor blueColor]} forTextRange:rg];
 // segments
 [lm enumerateTextSegmentsInRange:rg type:NSTextLayoutManagerSegmentTypeStandard options:0 usingBlock:^BOOL(NSTextRange*r,CGRect fr,CGFloat bl,NSTextContainer*c){ printf("seg %ld..%ld w>0=%d h>0=%d\n",(long)[cs offsetFromLocation:cs.documentRange.location toLocation:r.location],(long)[cs offsetFromLocation:cs.documentRange.location toLocation:r.endLocation],fr.size.width>0,fr.size.height>0); return YES;}];
 NSTextRange *g=[lm textRangeForSelectionGranularity:NSTextSelectionGranularityWord enclosingLocation:[cs locationFromLocation:cs.documentRange.location withOffset:7]];
 P([NSString stringWithFormat:@"word range %ld..%ld", (long)[cs offsetFromLocation:cs.documentRange.location toLocation:g.location],(long)[cs offsetFromLocation:cs.documentRange.location toLocation:g.endLocation]]);
 NSTextRange *gp=[lm textRangeForSelectionGranularity:NSTextSelectionGranularityParagraph enclosingLocation:[cs locationFromLocation:cs.documentRange.location withOffset:15]];
 P([NSString stringWithFormat:@"para range %ld..%ld", (long)[cs offsetFromLocation:cs.documentRange.location toLocation:gp.location],(long)[cs offsetFromLocation:cs.documentRange.location toLocation:gp.endLocation]]);
 NSTextRange *gl=[lm textRangeForSelectionGranularity:NSTextSelectionGranularityLine enclosingLocation:[cs locationFromLocation:cs.documentRange.location withOffset:15]];
 P([NSString stringWithFormat:@"line range %ld..%ld", (long)[cs offsetFromLocation:cs.documentRange.location toLocation:gl.location],(long)[cs offsetFromLocation:cs.documentRange.location toLocation:gl.endLocation]]);
 P([NSString stringWithFormat:@"dir=%ld", (long)[lm baseWritingDirectionAtLocation:cs.documentRange.location]]);
 [lm replaceContentsInRange:rg withAttributedString:[[NSAttributedString alloc] initWithString:@"HELLO"]];
 P([NSString stringWithFormat:@"after replace: %@", [cs.attributedString.string substringToIndex:12]]);
 __block NSMutableString *ss=[NSMutableString string];
 [lm enumerateSubstringsFromLocation:cs.documentRange.location options:NSStringEnumerationByWords usingBlock:^(NSString*sub,NSTextRange*r,NSTextRange*er,BOOL*stop){ [ss appendFormat:@"[%@]",sub]; if (ss.length>40)*stop=YES; }];
 P(ss);
 NSTextSelectionNavigation *nav=lm.textSelectionNavigation; P([NSString stringWithFormat:@"nav ds=%d noncontig=%d rot=%d", nav.textSelectionDataSource==lm, nav.allowsNonContiguousRanges, nav.rotatesCoordinateSystemForLayoutOrientation]);
 NSTextSelection *sel=[[NSTextSelection alloc] initWithLocation:[cs locationFromLocation:cs.documentRange.location withOffset:3] affinity:NSTextSelectionAffinityDownstream];
 NSTextSelection *r=[nav destinationSelectionForTextSelection:sel direction:NSTextSelectionNavigationDirectionRight destination:NSTextSelectionNavigationDestinationCharacter extending:NO confined:NO];
 P([NSString stringWithFormat:@"nav right -> %ld", (long)[cs offsetFromLocation:cs.documentRange.location toLocation:r.textRanges[0].location]]);
 r=[nav destinationSelectionForTextSelection:sel direction:NSTextSelectionNavigationDirectionRight destination:NSTextSelectionNavigationDestinationWord extending:NO confined:NO];
 P([NSString stringWithFormat:@"nav right word -> %ld..%ld", (long)[cs offsetFromLocation:cs.documentRange.location toLocation:r.textRanges[0].location],(long)[cs offsetFromLocation:cs.documentRange.location toLocation:r.textRanges[0].endLocation]]);
 r=[nav destinationSelectionForTextSelection:sel direction:NSTextSelectionNavigationDirectionLeft destination:NSTextSelectionNavigationDestinationCharacter extending:YES confined:NO];
 P([NSString stringWithFormat:@"nav left ext -> %ld..%ld", (long)[cs offsetFromLocation:cs.documentRange.location toLocation:r.textRanges[0].location],(long)[cs offsetFromLocation:cs.documentRange.location toLocation:r.textRanges[0].endLocation]]);
}}
static void partC(void){ @autoreleasepool { 
 NSTextContentStorage *cs=[[NSTextContentStorage alloc] init];
 NSTextLayoutManager *lm=[[NSTextLayoutManager alloc] init]; [cs addTextLayoutManager:lm];
 cs.attributedString=[[NSAttributedString alloc] initWithString:@"Hello world\nSecond"];
 NSTextRange *rg=[[NSTextRange alloc] initWithLocation:cs.documentRange.location endLocation:[cs locationFromLocation:cs.documentRange.location withOffset:5]];
 [lm replaceContentsInRange:rg withAttributedString:[[NSAttributedString alloc] initWithString:@"HI"]];
 P([NSString stringWithFormat:@"cs replace: %@ ts=%d", cs.attributedString.string, cs.textStorage!=nil]);
 [cs performEditingTransactionUsingBlock:^{ [lm replaceContentsInRange:rg withAttributedString:[[NSAttributedString alloc] initWithString:@"YO"]]; }];
 P([NSString stringWithFormat:@"txn replace: %@", cs.attributedString.string]);
 NSTextStorage *ts=[[NSTextStorage alloc] initWithString:@"abc\ndef"]; cs.textStorage=ts;
 P([NSString stringWithFormat:@"ts set: %@ same=%d doc=%ld", cs.attributedString.string, cs.textStorage==ts, (long)[cs offsetFromLocation:cs.documentRange.location toLocation:cs.documentRange.endLocation]]);
 [ts replaceCharactersInRange:NSMakeRange(0,1) withString:@"XYZ"];
 P([NSString stringWithFormat:@"ts edit doc=%ld", (long)[cs offsetFromLocation:cs.documentRange.location toLocation:cs.documentRange.endLocation]]);
 NSArray *els=[cs textElementsForRange:cs.documentRange]; P([NSString stringWithFormat:@"els=%lu", (unsigned long)els.count]);
 NSTextRange *half=[[NSTextRange alloc] initWithLocation:[cs locationFromLocation:cs.documentRange.location withOffset:5] endLocation:[cs locationFromLocation:cs.documentRange.location withOffset:6]];
 els=[cs textElementsForRange:half]; P([NSString stringWithFormat:@"els half=%lu", (unsigned long)els.count]);
 id s=[cs attributedStringForTextElement:[cs textElementsForRange:cs.documentRange][0]]; P([NSString stringWithFormat:@"attrForElem=%@", [s string]]);
 id e=[cs textElementForAttributedString:[[NSAttributedString alloc] initWithString:@"zz"]]; P([NSString stringWithFormat:@"elemForAttr=%@", NSStringFromClass([e class])]);
 NSTextRange *adj=[cs adjustedRangeFromRange:half forEditingTextSelection:YES]; P([NSString stringWithFormat:@"adj=%@", adj?@"obj":@"nil"]); NSTextRange *adj2=[cs adjustedRangeFromRange:cs.documentRange forEditingTextSelection:NO]; P([NSString stringWithFormat:@"adj2=%@", adj2?@"obj":@"nil"]);
 P([NSString stringWithFormat:@"incl=%d", cs.includesTextListMarkers]);
 NSMutableArray *rev=[NSMutableArray array];
 [cs enumerateTextElementsFromLocation:nil options:NSTextContentManagerEnumerationOptionsReverse usingBlock:^BOOL(NSTextElement *el){ [rev addObject:[[(NSTextParagraph*)el attributedString] string]]; return YES;}];
 P([rev description]);
}}
int main(void){ [NSApplication sharedApplication]; partA(); partB(); partC(); return 0; }
