// NSUserDefaultsController, NSDictionaryController, NSPDFInfo, NSSliderCell/NSControl/NSFont/NSPasteboard/NSSpeechRecognizer extras - compared with macOS.
#import <Cocoa/Cocoa.h>
static const char *S(id s){ return s?[[s description] UTF8String]:"(nil)"; }
int main(void){ @autoreleasepool { [NSApplication sharedApplication];
 NSUserDefaultsController *u=[NSUserDefaultsController sharedUserDefaultsController];
 printf("udc shared %d same %d defaults %d init %d applies %d unapplied %d values %d\n",u!=nil,u==[NSUserDefaultsController sharedUserDefaultsController],u.defaults==[NSUserDefaults standardUserDefaults],u.initialValues!=nil,u.appliesImmediately,u.hasUnappliedChanges,u.values!=nil);
 NSUserDefaults *ud=[[NSUserDefaults alloc] initWithSuiteName:@"xef.test.suite"]; [ud removePersistentDomainForName:@"xef.test.suite"];
 NSUserDefaultsController *u2=[[NSUserDefaultsController alloc] initWithDefaults:ud initialValues:@{@"k":@"init"}];
 printf("u2 applies %d init %s values k=%s\n",u2.appliesImmediately,S(u2.initialValues[@"k"]),S([u2.values valueForKey:@"k"]));
 [u2.values setValue:@"v1" forKey:@"k"]; printf("set -> ud %s unapplied %d\n",S([ud objectForKey:@"k"]),u2.hasUnappliedChanges);
 u2.appliesImmediately=NO; [u2.values setValue:@"v2" forKey:@"k"]; printf("noapply ud %s vals %s unapplied %d\n",S([ud objectForKey:@"k"]),S([u2.values valueForKey:@"k"]),u2.hasUnappliedChanges);
 NSDictionaryController *dc=[[NSDictionaryController alloc] init];
 printf("dc ik '%s' iv '%s' inc %lu exc %lu lkd %d lkt %d\n",S(dc.initialKey),S(dc.initialValue),(unsigned long)dc.includedKeys.count,(unsigned long)dc.excludedKeys.count,dc.localizedKeyDictionary!=nil,dc.localizedKeyTable!=nil);
 dc.content=[@{@"a":@1,@"b":@2,@"c":@3} mutableCopy]; NSArray *ao=dc.arrangedObjects; printf("dc ao %lu\n",(unsigned long)ao.count);
 for(NSDictionaryControllerKeyValuePair *p in ao) printf(" kv %s=%s loc=%s inc=%d\n",S([p key]),S([p value]),S([p localizedKey]),[p isExplicitlyIncluded]);
 NSPDFInfo *pi=[[NSPDFInfo alloc] init]; printf("pdf url %d hide %d tags %lu orient %ld paper %g,%g attrs %d\n",pi.URL!=nil,pi.isFileExtensionHidden,(unsigned long)pi.tagNames.count,(long)pi.orientation,pi.paperSize.width,pi.paperSize.height,pi.attributes!=nil);
 pi.URL=[NSURL fileURLWithPath:@"/tmp/x.pdf"]; pi.fileExtensionHidden=YES; pi.tagNames=@[@"t"]; pi.orientation=NSPaperOrientationLandscape; pi.paperSize=NSMakeSize(100,200); printf("pdf2 %s %d %lu %ld %g,%g\n",S(pi.URL.path),pi.isFileExtensionHidden,(unsigned long)pi.tagNames.count,(long)pi.orientation,pi.paperSize.width,pi.paperSize.height);
 NSSliderCell *sc=[[NSSliderCell alloc] init]; printf("sc title %d color %d font %d\n",sc.titleCell!=nil,sc.titleColor!=nil,sc.titleFont!=nil);
 printf("tick %ld\n",(long)[sc indexOfTickMarkAtPoint:NSMakePoint(0,0)]);
 NSControl *c=[[NSControl alloc] initWithFrame:NSMakeRect(0,0,10,10)]; printf("ctl bwd %ld\n",(long)c.baseWritingDirection);
 [c setNeedsDisplay]; [c invalidateIntrinsicContentSizeForCell:c.cell];
 NSFont *f=[NSFont fontWithName:@"Helvetica" size:12]; NSFont *f2=[f fontWithSize:20]; printf("font %s %g\n",S(f2.fontName),f2.pointSize);
 NSFont *sw=[NSFont systemFontOfSize:12 weight:NSFontWeightBold width:NSFontWidthStandard]; printf("sysw %d\n",sw!=nil);
 NSFont *mf=[NSFont fontWithName:@"Helvetica" matrix:(CGFloat[]){12,0,0,12,0,0}]; printf("matrix %d\n",mf!=nil);
 CGGlyph gl=[f glyphWithName:@"A"]; printf("glyph named %d\n",gl!=0); NSRect br=[f boundingRectForCGGlyph:gl]; NSSize adv=[f advancementForCGGlyph:gl]; printf("br %d adv %d\n",br.size.width>0,adv.width>0);
 NSPasteboard *pb=[NSPasteboard pasteboardWithUniqueName]; printf("pb ab %ld\n",(long)pb.accessBehavior);
 NSPasteboardItem *it=[[NSPasteboardItem alloc] init]; [it setString:@"x" forType:NSPasteboardTypeString]; [pb clearContents]; [pb writeObjects:@[it]]; printf("idx %lu\n",(unsigned long)[pb indexOfPasteboardItem:pb.pasteboardItems[0]]);
 printf("filt %d\n",[NSPasteboard pasteboardByFilteringData:[@"x" dataUsingEncoding:NSUTF8StringEncoding] ofType:NSPasteboardTypeString]!=nil);
 NSImageView *iv=[[NSImageView alloc] initWithFrame:NSMakeRect(0,0,10,10)]; printf("iv dyn %ld\n",(long)[NSImageView defaultPreferredImageDynamicRange]);
 NSDocumentController *dcn=[NSDocumentController sharedDocumentController]; printf("dcn ok %d\n",dcn!=nil);
 NSSpeechRecognizer *sr=[[NSSpeechRecognizer alloc] init]; printf("sr cmds %d title %d fg %d block %d del %d\n",sr.commands!=nil,sr.displayedCommandsTitle!=nil,sr.listensInForegroundOnly,sr.blocksOtherRecognizers,sr.delegate!=nil);
 [sr startListening]; [sr stopListening];
 return 0;}}
