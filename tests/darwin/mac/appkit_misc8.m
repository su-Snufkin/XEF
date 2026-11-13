// Compositional layout model, NSTextList, tab group, combo button, invalidation context, scrubber layout, help manager, font collections, print info, open panel - compared with macOS.
#import <Cocoa/Cocoa.h>
static const char *S(id s){ return s?[[s description] UTF8String]:"(nil)"; }
static void p1(void){ @autoreleasepool { 
 NSTextList *tl=[[NSTextList alloc] initWithMarkerFormat:NSTextListMarkerDecimal options:0]; printf("tl fmt %s opts %lu start %ld ordered %d m1 '%s' m3 '%s'\n",S(tl.markerFormat),(unsigned long)tl.listOptions,(long)tl.startingItemNumber,tl.isOrdered,S([tl markerForItemNumber:1]),S([tl markerForItemNumber:3]));
 tl.startingItemNumber=5; printf("start %ld\n",(long)tl.startingItemNumber);
 for (NSString *f in @[NSTextListMarkerDisc,NSTextListMarkerCircle,NSTextListMarkerSquare,NSTextListMarkerLowercaseAlpha,NSTextListMarkerUppercaseAlpha,NSTextListMarkerLowercaseRoman,NSTextListMarkerUppercaseRoman,NSTextListMarkerHyphen,NSTextListMarkerCheck,NSTextListMarkerBox,NSTextListMarkerDiamond,@"{lower-hexadecimal}",@"{octal}",@"abc"]){ NSTextList *t=[[NSTextList alloc] initWithMarkerFormat:f options:0]; printf("fmt %s ord %d m2 '%s' m27 '%s'\n",S(f),t.isOrdered,S([t markerForItemNumber:2]),S([t markerForItemNumber:27])); }
 NSTextList *t2=[[NSTextList alloc] initWithMarkerFormat:NSTextListMarkerDecimal options:NSTextListPrependEnclosingMarker]; printf("opts %lu\n",(unsigned long)t2.listOptions);
 printf("incl %d\n",[NSTextList includesTextListMarkers]);
 NSWindow *w1=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,100,100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
 NSWindowTabGroup *g=w1.tabGroup; printf("tg %d id %d wins %lu overview %d bar %d sel %d\n",g!=nil,g.identifier!=nil,(unsigned long)g.windows.count,g.isOverviewVisible,g.isTabBarVisible,g.selectedWindow==w1);
 NSWindow *w2=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,100,100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES]; [g addWindow:w2]; printf("tg2 %lu\n",(unsigned long)g.windows.count);
 NSButton *b=[NSButton buttonWithTitle:@"x" target:nil action:NULL];
 NSMenu *m=[[NSMenu alloc] initWithTitle:@"m"];
 NSComboButton *cb=[NSComboButton comboButtonWithTitle:@"Go" menu:m target:nil action:NULL]; printf("cb title %s img %d scaling %ld style %ld super %s\n",S(cb.title),cb.image!=nil,(long)cb.imageScaling,(long)cb.style,S(NSStringFromClass([cb superclass])));
 cb.title=@"T2"; cb.style=NSComboButtonStyleUnified; cb.imageScaling=NSImageScaleAxesIndependently; printf("cb2 %s %ld %ld\n",S(cb.title),(long)cb.style,(long)cb.imageScaling);
 NSComboButton *ci=[NSComboButton comboButtonWithImage:[NSImage imageNamed:NSImageNameInfo] menu:m target:nil action:NULL]; printf("ci %d title %s\n",ci.image!=nil,S(ci.title));
 NSCollectionLayoutSize *sz=[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1] heightDimension:[NSCollectionLayoutDimension absoluteDimension:50]];
 NSCollectionLayoutItem *it=[NSCollectionLayoutItem itemWithLayoutSize:sz];
 NSCollectionLayoutGroup *hg=[NSCollectionLayoutGroup horizontalGroupWithLayoutSize:sz subitems:@[it,it]]; printf("hg subs %lu supp %lu inter %d desc %d\n",(unsigned long)hg.subitems.count,(unsigned long)hg.supplementaryItems.count,hg.interItemSpacing!=nil,hg.visualDescription!=nil);
 NSCollectionLayoutGroup *vg=[NSCollectionLayoutGroup verticalGroupWithLayoutSize:sz subitem:it count:3]; printf("vg subs %lu\n",(unsigned long)vg.subitems.count);
 NSCollectionLayoutGroup *hg2=[NSCollectionLayoutGroup horizontalGroupWithLayoutSize:sz subitem:it count:2]; printf("hg2 %lu\n",(unsigned long)hg2.subitems.count);
 hg.interItemSpacing=[NSCollectionLayoutSpacing fixedSpacing:4]; printf("inter %d\n",hg.interItemSpacing!=nil);
 NSCollectionLayoutGroup *cg=[NSCollectionLayoutGroup customGroupWithLayoutSize:sz itemProvider:^NSArray*(id<NSCollectionLayoutEnvironment> e){ return @[]; }]; printf("cg %d\n",cg!=nil);
 NSCollectionViewLayoutInvalidationContext *ic=[[NSCollectionViewLayoutInvalidationContext alloc] init];
 printf("ic all %d counts %d items %lu supp %lu dec %lu coff %g,%g csz %g,%g\n",ic.invalidateEverything,ic.invalidateDataSourceCounts,(unsigned long)ic.invalidatedItemIndexPaths.count,(unsigned long)ic.invalidatedSupplementaryIndexPaths.count,(unsigned long)ic.invalidatedDecorationIndexPaths.count,ic.contentOffsetAdjustment.x,ic.contentOffsetAdjustment.y,ic.contentSizeAdjustment.width,ic.contentSizeAdjustment.height);
 [ic invalidateItemsAtIndexPaths:[NSSet setWithObject:[NSIndexPath indexPathForItem:0 inSection:0]]]; [ic invalidateSupplementaryElementsOfKind:@"h" atIndexPaths:[NSSet setWithObject:[NSIndexPath indexPathForItem:1 inSection:0]]]; [ic invalidateDecorationElementsOfKind:@"d" atIndexPaths:[NSSet setWithObject:[NSIndexPath indexPathForItem:2 inSection:0]]]; [ic invalidateDataSourceCounts]; [ic invalidateEverything];
 ic.contentOffsetAdjustment=NSMakePoint(1,2); ic.contentSizeAdjustment=NSMakeSize(3,4);
 printf("ic2 all %d counts %d items %lu supp %lu dec %lu %g %g %g %g\n",ic.invalidateEverything,ic.invalidateDataSourceCounts,(unsigned long)ic.invalidatedItemIndexPaths.count,(unsigned long)ic.invalidatedSupplementaryIndexPaths.count,(unsigned long)ic.invalidatedDecorationIndexPaths.count,ic.contentOffsetAdjustment.x,ic.contentOffsetAdjustment.y,ic.contentSizeAdjustment.width,ic.contentSizeAdjustment.height);
 NSScrubberLayout *sl=[[NSScrubberLayout alloc] init]; printf("sl cls %s scrubber %d vis %g,%g,%g,%g content %g,%g shouldSel %d shouldHi %d mirror %d\n",S(NSStringFromClass([NSScrubberLayout layoutAttributesClass])),sl.scrubber!=nil,sl.visibleRect.origin.x,sl.visibleRect.origin.y,sl.visibleRect.size.width,sl.visibleRect.size.height,sl.scrubberContentSize.width,sl.scrubberContentSize.height,sl.shouldInvalidateLayoutForSelectionChange,sl.shouldInvalidateLayoutForHighlightChange,sl.automaticallyMirrorsInRightToLeftLayout);
 printf("sl attr %d in-rect %lu invvis %d\n",[sl layoutAttributesForItemAtIndex:0]!=nil,(unsigned long)[sl layoutAttributesForItemsInRect:NSMakeRect(0,0,10,10)].count,[sl shouldInvalidateLayoutForChangeFromVisibleRect:NSMakeRect(0,0,1,1) toVisibleRect:NSMakeRect(0,0,2,2)]);
 [sl prepareLayout]; [sl invalidateLayout];
 NSHelpManager *hm=[NSHelpManager sharedHelpManager]; printf("hm %d ctx %d\n",hm!=nil,[NSHelpManager isContextHelpModeActive]);
 NSView *v=[[NSView alloc] init]; [hm setContextHelp:[[NSAttributedString alloc] initWithString:@"help"] forObject:v]; printf("help '%s'\n",S([[hm contextHelpForObject:v] string])); [hm removeContextHelpForObject:v]; printf("removed %d\n",[hm contextHelpForObject:v]!=nil);
 printf("show %d\n",[hm showContextHelpForObject:v locationHint:NSZeroPoint]);
 NSFontManager *fm=[NSFontManager sharedFontManager]; printf("fm cols>0 %d\n",[fm collectionNames].count>0);
 printf("addcol %d\n",[fm addCollection:@"xefcol" options:0]); printf("has %d\n",[[fm collectionNames] containsObject:@"xefcol"]);
 NSFontDescriptor *fd=[NSFontDescriptor fontDescriptorWithName:@"Helvetica" size:12]; [fm addFontDescriptors:@[fd] toCollection:@"xefcol"]; printf("descs %lu\n",(unsigned long)[fm fontDescriptorsInCollection:@"xefcol"].count);
 [fm removeFontDescriptor:fd fromCollection:@"xefcol"]; printf("descs2 %lu\n",(unsigned long)[fm fontDescriptorsInCollection:@"xefcol"].count);
 printf("rem %d\n",[fm removeCollection:@"xefcol"]);
 printf("match %d\n",[fm availableFontNamesMatchingFontDescriptor:fd].count>0);
 printf("attrs %lu\n",(unsigned long)[fm convertAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12]}].count);
 printf("ctraits %d\n",[fm convertFontTraits:NSBoldFontMask]);
 printf("validate %d\n",[fm validateMenuItem:[[NSMenuItem alloc] initWithTitle:@"x" action:@selector(addFontTrait:) keyEquivalent:@""]]);
 NSPrintInfo *pi=[NSPrintInfo sharedPrintInfo]; printf("pi name %s local %s printer %d\n",S([pi paperName]),S([pi localizedPaperName]),pi.printer!=nil);
 NSSize ps=[NSPrintInfo sizeForPaperName:@"A4"]; printf("A4 %g %g\n",ps.width,ps.height); ps=[NSPrintInfo sizeForPaperName:@"Letter"]; printf("Letter %g %g\n",ps.width,ps.height);
 printf("pm %d %d %d\n",[pi PMPrintSession]!=NULL,[pi PMPageFormat]!=NULL,[pi PMPrintSettings]!=NULL);
 NSOpenPanel *op=[NSOpenPanel openPanel]; printf("op resolves %d ubq %d dl %d disc %d\n",op.resolvesAliases,op.canResolveUbiquitousConflicts,op.canDownloadUbiquitousContents,op.isAccessoryViewDisclosed);
 op.resolvesAliases=NO; op.accessoryViewDisclosed=YES; printf("op2 %d %d\n",op.resolvesAliases,op.isAccessoryViewDisclosed);
}}
static void p2(void){ @autoreleasepool { 
 NSCollectionLayoutDimension *fw=[NSCollectionLayoutDimension fractionalWidthDimension:0.5],*fh=[NSCollectionLayoutDimension fractionalHeightDimension:0.25],*ab=[NSCollectionLayoutDimension absoluteDimension:44],*es=[NSCollectionLayoutDimension estimatedDimension:80];
 for(NSCollectionLayoutDimension*d in @[fw,fh,ab,es]) printf("dim fw %d fh %d abs %d est %d val %g\n",d.isFractionalWidth,d.isFractionalHeight,d.isAbsolute,d.isEstimated,d.dimension);
 NSCollectionLayoutSize *sz=[NSCollectionLayoutSize sizeWithWidthDimension:fw heightDimension:ab]; printf("size %d %d %g %g\n",sz.widthDimension==fw,sz.heightDimension==ab,sz.widthDimension.dimension,sz.heightDimension.dimension);
 NSCollectionLayoutSpacing *fl=[NSCollectionLayoutSpacing flexibleSpacing:8],*fx=[NSCollectionLayoutSpacing fixedSpacing:4]; printf("sp %d %d %g | %d %d %g\n",fl.isFlexibleSpacing,fl.isFixedSpacing,fl.spacing,fx.isFlexibleSpacing,fx.isFixedSpacing,fx.spacing);
 NSCollectionLayoutEdgeSpacing *es2=[NSCollectionLayoutEdgeSpacing spacingForLeading:fl top:nil trailing:fx bottom:nil]; printf("edge %d %d %d %d\n",es2.leading!=nil,es2.top!=nil,es2.trailing!=nil,es2.bottom!=nil);
 NSCollectionLayoutItem *it=[NSCollectionLayoutItem itemWithLayoutSize:sz]; printf("item ls %d ci %g,%g,%g,%g es %d sup %lu\n",it.layoutSize==sz,it.contentInsets.top,it.contentInsets.leading,it.contentInsets.bottom,it.contentInsets.trailing,it.edgeSpacing!=nil,(unsigned long)it.supplementaryItems.count);
 it.contentInsets=NSDirectionalEdgeInsetsMake(1,2,3,4); it.edgeSpacing=es2; printf("item2 %g %g %g %g es %d\n",it.contentInsets.top,it.contentInsets.leading,it.contentInsets.bottom,it.contentInsets.trailing,it.edgeSpacing==es2);
 NSCollectionLayoutAnchor *an=[NSCollectionLayoutAnchor layoutAnchorWithEdges:NSDirectionalRectEdgeTop|NSDirectionalRectEdgeTrailing]; printf("anchor edges %lu off %g,%g abs %d frac %d\n",(unsigned long)an.edges,an.offset.x,an.offset.y,an.isAbsoluteOffset,an.isFractionalOffset);
 NSCollectionLayoutAnchor *an2=[NSCollectionLayoutAnchor layoutAnchorWithEdges:NSDirectionalRectEdgeBottom absoluteOffset:NSMakePoint(3,4)]; printf("anchor2 %lu %g,%g abs %d frac %d\n",(unsigned long)an2.edges,an2.offset.x,an2.offset.y,an2.isAbsoluteOffset,an2.isFractionalOffset);
 NSCollectionLayoutAnchor *an3=[NSCollectionLayoutAnchor layoutAnchorWithEdges:NSDirectionalRectEdgeLeading fractionalOffset:NSMakePoint(0.5,0.5)]; printf("anchor3 %g abs %d frac %d\n",an3.offset.x,an3.isAbsoluteOffset,an3.isFractionalOffset);
 NSCollectionLayoutSupplementaryItem *si=[NSCollectionLayoutSupplementaryItem supplementaryItemWithLayoutSize:sz elementKind:@"badge" containerAnchor:an]; printf("supp kind %s z %ld ca %d ia %d ls %d\n",S(si.elementKind),(long)si.zIndex,si.containerAnchor==an,si.itemAnchor!=nil,si.layoutSize==sz);
 NSCollectionLayoutSupplementaryItem *si2=[NSCollectionLayoutSupplementaryItem supplementaryItemWithLayoutSize:sz elementKind:@"b2" containerAnchor:an itemAnchor:an2]; printf("supp2 ia %d\n",si2.itemAnchor==an2); si2.zIndex=5; printf("z %ld\n",(long)si2.zIndex);
 NSCollectionLayoutItem *it2=[NSCollectionLayoutItem itemWithLayoutSize:sz supplementaryItems:@[si]]; printf("item supp %lu\n",(unsigned long)it2.supplementaryItems.count);
 NSCollectionLayoutBoundarySupplementaryItem *bs=[NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:sz elementKind:@"hdr" alignment:NSRectAlignmentTop]; printf("bs kind %s align %ld off %g,%g extends %d pin %d z %ld super %s\n",S(bs.elementKind),(long)bs.alignment,bs.offset.x,bs.offset.y,bs.extendsBoundary,bs.pinToVisibleBounds,(long)bs.zIndex,S(NSStringFromClass([bs superclass])));
 NSCollectionLayoutBoundarySupplementaryItem *bs2=[NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:sz elementKind:@"ftr" alignment:NSRectAlignmentBottom absoluteOffset:NSMakePoint(1,2)]; printf("bs2 off %g,%g\n",bs2.offset.x,bs2.offset.y); bs2.extendsBoundary=NO; bs2.pinToVisibleBounds=YES; printf("bs3 %d %d\n",bs2.extendsBoundary,bs2.pinToVisibleBounds);
 NSCollectionLayoutDecorationItem *di=[NSCollectionLayoutDecorationItem backgroundDecorationItemWithElementKind:@"bg"]; printf("dec kind %s z %ld\n",S(di.elementKind),(long)di.zIndex); di.zIndex=-2; printf("dec z %ld\n",(long)di.zIndex);
 NSCollectionLayoutGroup *hg=[NSCollectionLayoutGroup horizontalGroupWithLayoutSize:sz subitems:@[it,it2]]; printf("group subs %lu ls %d supp %lu inter %d desc %d super %s\n",(unsigned long)hg.subitems.count,hg.layoutSize==sz,(unsigned long)hg.supplementaryItems.count,hg.interItemSpacing!=nil,hg.visualDescription!=nil,S(NSStringFromClass([hg superclass])));
 hg.supplementaryItems=@[si]; printf("gsupp %lu\n",(unsigned long)hg.supplementaryItems.count);
 hg.interItemSpacing=fx; printf("ginter %d\n",hg.interItemSpacing==fx);
 NSCollectionLayoutGroupCustomItem *ci=[NSCollectionLayoutGroupCustomItem customItemWithFrame:NSMakeRect(1,2,3,4)]; printf("cust frame %g,%g,%g,%g z %ld\n",ci.frame.origin.x,ci.frame.origin.y,ci.frame.size.width,ci.frame.size.height,(long)ci.zIndex);
 NSCollectionLayoutGroupCustomItem *ci2=[NSCollectionLayoutGroupCustomItem customItemWithFrame:NSMakeRect(1,2,3,4) zIndex:7]; printf("cust2 z %ld\n",(long)ci2.zIndex);
 NSCollectionLayoutSection *sec=[NSCollectionLayoutSection sectionWithGroup:hg]; sec.boundarySupplementaryItems=@[bs]; sec.decorationItems=@[di]; printf("sec %lu %lu\n",(unsigned long)sec.boundarySupplementaryItems.count,(unsigned long)sec.decorationItems.count);
 NSCollectionViewCompositionalLayout *lay=[[NSCollectionViewCompositionalLayout alloc] initWithSection:sec]; printf("comp %d\n",lay!=nil);
 NSCollectionViewCompositionalLayoutConfiguration *cfg=[[NSCollectionViewCompositionalLayoutConfiguration alloc] init]; printf("cfg scroll %ld gap %g bound %lu\n",(long)cfg.scrollDirection,cfg.interSectionSpacing,(unsigned long)cfg.boundarySupplementaryItems.count);
 NSCollectionViewCompositionalLayout *l2=[[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection*(NSInteger i,id<NSCollectionLayoutEnvironment> e){ return sec; }]; printf("comp2 %d\n",l2!=nil);
}}
int main(void){ [NSApplication sharedApplication]; p1(); p2(); return 0; }
