// NSCollectionViewGridLayout, NSCollectionLayoutSection, NSPathCell extras, NSPageLayout, NSImageSymbolConfiguration, NSTableViewDiffableDataSource - compared with macOS.
#import <Cocoa/Cocoa.h>
static const char *S(NSString *s){ return s?[s UTF8String]:"(nil)"; }
int main(void){ @autoreleasepool { [NSApplication sharedApplication];
 NSCollectionViewGridLayout *g=[[NSCollectionViewGridLayout alloc] init];
 printf("grid m %g %g %g %g inter %g line %g rows %ld cols %ld min %g,%g max %g,%g bg %lu\n",g.margins.top,g.margins.left,g.margins.bottom,g.margins.right,g.minimumInteritemSpacing,g.minimumLineSpacing,(long)g.maximumNumberOfRows,(long)g.maximumNumberOfColumns,g.minimumItemSize.width,g.minimumItemSize.height,g.maximumItemSize.width,g.maximumItemSize.height,(unsigned long)g.backgroundColors.count);
 g.margins=NSEdgeInsetsMake(1,2,3,4); g.minimumLineSpacing=5; g.maximumNumberOfColumns=3; g.minimumItemSize=NSMakeSize(10,20); printf("grid2 %g %g %g %g line %g cols %ld min %g,%g\n",g.margins.top,g.margins.left,g.margins.bottom,g.margins.right,g.minimumLineSpacing,(long)g.maximumNumberOfColumns,g.minimumItemSize.width,g.minimumItemSize.height);
 NSCollectionLayoutSize *sz=[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1] heightDimension:[NSCollectionLayoutDimension absoluteDimension:50]];
 NSCollectionLayoutItem *it=[NSCollectionLayoutItem itemWithLayoutSize:sz]; NSCollectionLayoutGroup *gr=[NSCollectionLayoutGroup horizontalGroupWithLayoutSize:sz subitems:@[it]];
 NSCollectionLayoutSection *sec=[NSCollectionLayoutSection sectionWithGroup:gr];
 printf("sec ins %g %g %g %g gap %g orth %ld bound %lu follow %d dec %lu handler %d\n",sec.contentInsets.top,sec.contentInsets.leading,sec.contentInsets.bottom,sec.contentInsets.trailing,sec.interGroupSpacing,(long)sec.orthogonalScrollingBehavior,(unsigned long)sec.boundarySupplementaryItems.count,sec.supplementariesFollowContentInsets,(unsigned long)sec.decorationItems.count,sec.visibleItemsInvalidationHandler!=nil);
 sec.interGroupSpacing=8; sec.orthogonalScrollingBehavior=NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuous; sec.supplementariesFollowContentInsets=NO; sec.contentInsets=NSDirectionalEdgeInsetsMake(1,2,3,4); printf("sec2 %g %ld %d %g\n",sec.interGroupSpacing,(long)sec.orthogonalScrollingBehavior,sec.supplementariesFollowContentInsets,sec.contentInsets.trailing);
 NSPathCell *pc=[[NSPathCell alloc] init]; printf("pc types %d da %d bg %d clicked %d\n",pc.allowedTypes!=nil,pc.doubleAction!=NULL,pc.backgroundColor!=nil,pc.clickedPathComponentCell!=nil);
 printf("pcc %s\n",S(NSStringFromClass([NSPathCell pathComponentCellClass])));
 pc.allowedTypes=@[@"public.jpeg"]; pc.backgroundColor=[NSColor redColor]; pc.doubleAction=@selector(description); printf("pc2 %lu %d %d\n",(unsigned long)pc.allowedTypes.count,pc.backgroundColor!=nil,pc.doubleAction==@selector(description));
 NSPageLayout *pl=[NSPageLayout pageLayout]; printf("pl %d acc %lu av %d pi %d\n",pl!=nil,(unsigned long)pl.accessoryControllers.count,pl.accessoryView!=nil,pl.printInfo!=nil);
 NSImageSymbolConfiguration *c=[NSImageSymbolConfiguration configurationWithPointSize:20 weight:NSFontWeightBold scale:NSImageSymbolScaleLarge]; printf("sym %d\n",c!=nil);
 NSImageSymbolConfiguration *c2=[c configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithScale:NSImageSymbolScaleSmall]]; printf("sym2 %d\n",c2!=nil);
 printf("sym3 %d %d %d %d %d %d %d\n",[NSImageSymbolConfiguration configurationPreferringMonochrome]!=nil,[NSImageSymbolConfiguration configurationPreferringHierarchical]!=nil,[NSImageSymbolConfiguration configurationPreferringMulticolor]!=nil,[NSImageSymbolConfiguration configurationWithHierarchicalColor:[NSColor redColor]]!=nil,[NSImageSymbolConfiguration configurationWithPaletteColors:@[[NSColor redColor]]]!=nil,[NSImageSymbolConfiguration configurationWithTextStyle:NSFontTextStyleBody]!=nil,[NSImageSymbolConfiguration configurationWithTextStyle:NSFontTextStyleBody scale:NSImageSymbolScaleMedium]!=nil);
 NSTableView *tv=[[NSTableView alloc] initWithFrame:NSMakeRect(0,0,100,100)];
 NSTableViewDiffableDataSource *ds=[[NSTableViewDiffableDataSource alloc] initWithTableView:tv cellProvider:^NSView*(NSTableView*t,NSTableColumn*c,NSInteger r,id ident){ return nil; }];
 NSDiffableDataSourceSnapshot *sn=[[NSDiffableDataSourceSnapshot alloc] init]; [sn appendSectionsWithIdentifiers:@[@"s"]]; [sn appendItemsWithIdentifiers:@[@"a",@"b"]];
 [ds applySnapshot:sn animatingDifferences:NO]; printf("ds snap %lu rows %ld id1 %s row(b) %ld sec %s anim %ld\n",(unsigned long)[ds snapshot].numberOfItems,(long)[tv numberOfRows],S([ds itemIdentifierForRow:1]),(long)[ds rowForItemIdentifier:@"b"],S([ds sectionIdentifierForRow:0]),(long)ds.defaultRowAnimation);
 printf("rvp %d shp %d\n",ds.rowViewProvider!=nil,ds.sectionHeaderViewProvider!=nil);
 printf("ds row sec %ld\n",(long)[ds rowForSectionIdentifier:@"s"]);
 return 0;}}
