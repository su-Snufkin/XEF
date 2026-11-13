// NSUserInterfaceCompressionOptions, NSTitlebarAccessoryViewController, NSFontCollection, NSApplication extras - compared with macOS.
#import <Cocoa/Cocoa.h>
int main(void){ @autoreleasepool { [NSApplication sharedApplication];
 NSUserInterfaceCompressionOptions *h=NSUserInterfaceCompressionOptions.hideImagesOption,*t=NSUserInterfaceCompressionOptions.hideTextOption,*r=NSUserInterfaceCompressionOptions.reduceMetricsOption,*b=NSUserInterfaceCompressionOptions.breakEqualWidthsOption,*s=NSUserInterfaceCompressionOptions.standardOptions;
 printf("empty h %d t %d std %d\n",h.isEmpty,t.isEmpty,s.isEmpty);
 NSUserInterfaceCompressionOptions *u=[h optionsByAddingOptions:t];
 printf("u contains h %d t %d r %d inter(h) %d inter(r) %d empty %d\n",[u containsOptions:h],[u containsOptions:t],[u containsOptions:r],[u intersectsOptions:h],[u intersectsOptions:r],u.isEmpty);
 NSUserInterfaceCompressionOptions *d=[u optionsByRemovingOptions:h]; printf("d contains h %d t %d eq t %d\n",[d containsOptions:h],[d containsOptions:t],[d isEqual:t]);
 printf("std contains all %d %d %d %d\n",[s containsOptions:h],[s containsOptions:t],[s containsOptions:r],[s containsOptions:b]);
 NSUserInterfaceCompressionOptions *e=[[NSUserInterfaceCompressionOptions alloc] init]; printf("init empty %d\n",e.isEmpty);
 NSUserInterfaceCompressionOptions *c=[[NSUserInterfaceCompressionOptions alloc] initWithIdentifier:@"x.y"]; printf("id empty %d contains self %d eq %d\n",c.isEmpty,[c containsOptions:c],[c isEqual:[[NSUserInterfaceCompressionOptions alloc] initWithIdentifier:@"x.y"]]);
 NSUserInterfaceCompressionOptions *w=[[NSUserInterfaceCompressionOptions alloc] initWithCompressionOptions:[NSSet setWithObjects:h,t,nil]]; printf("set contains h %d eq u %d\n",[w containsOptions:h],[w isEqual:u]);
 printf("sub same %d\n",[[NSUserInterfaceCompressionOptions hideImagesOption] isEqual:h]);
 NSTitlebarAccessoryViewController *v=[[NSTitlebarAccessoryViewController alloc] init];
 printf("tav layout %ld fsmin %g hidden %d autosize %d anim %d view %d\n",(long)v.layoutAttribute,v.fullScreenMinHeight,v.isHidden,v.automaticallyAdjustsSize,v.animations!=nil,v.isViewLoaded);
 v.layoutAttribute=NSLayoutAttributeRight; v.hidden=YES; v.fullScreenMinHeight=22; v.automaticallyAdjustsSize=NO; printf("tav2 %ld %d %g %d\n",(long)v.layoutAttribute,v.isHidden,v.fullScreenMinHeight,v.automaticallyAdjustsSize);
 printf("anim key %d\n",[NSTitlebarAccessoryViewController defaultAnimationForKey:@"hidden"]!=nil);
 NSFontCollection *fc=[NSFontCollection fontCollectionWithAllAvailableDescriptors]; printf("fc all %d match>0 %d\n",fc!=nil,fc.matchingDescriptors.count>0);
 printf("names>0 %d std %d\n",[NSFontCollection allFontCollectionNames].count>0,[NSFontCollection fontCollectionWithName:NSFontCollectionAllFonts]!=nil);
 NSFontCollection *loc=[NSFontCollection fontCollectionWithLocale:[NSLocale localeWithLocaleIdentifier:@"en"]]; printf("loc %d\n",loc!=nil);
 NSFontCollection *dc=[NSFontCollection fontCollectionWithDescriptors:@[[NSFontDescriptor fontDescriptorWithName:@"Helvetica" size:12]]]; printf("dc query %lu excl %lu match>=1 %d\n",(unsigned long)dc.queryDescriptors.count,(unsigned long)dc.exclusionDescriptors.count,dc.matchingDescriptors.count>=1);
 printf("fam %d\n",[dc matchingDescriptorsForFamily:@"Helvetica"].count>=1);
 NSRange fr2; printf("search2 %d %lu %lu\n",[NSApp searchString:@"WORLD" inUserInterfaceItemString:@"hello world" searchRange:NSMakeRange(0,11) foundRange:&fr2],(unsigned long)fr2.location,(unsigned long)fr2.length);
 NSApplication *a=NSApp; printf("remote %d types %lu ctx %d autoTB %d\n",a.isRegisteredForRemoteNotifications,(unsigned long)a.enabledRemoteNotificationTypes,a.context!=nil,a.automaticCustomizeTouchBarMenuItemEnabled);
 [a setAutomaticCustomizeTouchBarMenuItemEnabled:YES]; printf("autoTB %d\n",a.automaticCustomizeTouchBarMenuItemEnabled);
 [a registerForRemoteNotifications]; printf("remote2 %d\n",a.isRegisteredForRemoteNotifications);
 NSRange fr; printf("search %d\n",[a searchString:@"WORLD" inUserInterfaceItemString:@"hello world" searchRange:NSMakeRange(0,11) foundRange:&fr]);
    printf("%s|%s|%s|%s\n",[NSFontCollectionAllFonts UTF8String],[NSFontCollectionUser UTF8String],[NSFontCollectionFavorites UTF8String],[NSFontCollectionRecentlyUsed UTF8String]);
 for(NSString*n in @[NSFontCollectionAllFonts,NSFontCollectionUser,NSFontCollectionFavorites,NSFontCollectionRecentlyUsed]) printf("%s %d\n",[n UTF8String],[NSFontCollection fontCollectionWithName:n]!=nil); printf("names>=4 %d\n",[NSFontCollection allFontCollectionNames].count>=4);
 printf("none %d\n",[NSFontCollection fontCollectionWithName:@"zzz"]!=nil);
 {  NSError*err2=nil; BOOL ok=[NSFontCollection showFontCollection:[NSFontCollection fontCollectionWithAllAvailableDescriptors] withName:@"MyXef" visibility:NSFontCollectionVisibilityProcess error:&err2]; printf("show %d\n",ok);
 printf("has %d\n",[[NSFontCollection allFontCollectionNames] containsObject:@"MyXef"]);
 ok=[NSFontCollection renameFontCollectionWithName:@"MyXef" visibility:NSFontCollectionVisibilityProcess toName:@"MyXef2" error:&err2]; printf("rename %d has2 %d\n",ok,[[NSFontCollection allFontCollectionNames] containsObject:@"MyXef2"]);
 ok=[NSFontCollection hideFontCollectionWithName:@"MyXef2" visibility:NSFontCollectionVisibilityProcess error:&err2]; printf("hide %d\n",ok);
 printf("mut %d\n",[[[NSFontCollection fontCollectionWithAllAvailableDescriptors] mutableCopy] isKindOfClass:[NSMutableFontCollection class]]);
 } return 0;}}
