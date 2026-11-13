// NSBitmapImageRep compression/properties/colour space, NSBrowser, NSDocument, NSLayoutManager glyph extras - compared with macOS.
#import <Cocoa/Cocoa.h>
static void p1(void){ @autoreleasepool { 
 NSBitmapImageRep *r=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:4 pixelsHigh:4 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
 NSTIFFCompression c; float f=-1; [r getCompression:&c factor:&f]; printf("comp %ld %g\n",(long)c,f);
 [r setCompression:NSTIFFCompressionLZW factor:0.5]; [r getCompression:&c factor:&f]; printf("comp2 %ld %g\n",(long)c,f);
 printf("can %d %d %d\n",[r canBeCompressedUsing:NSTIFFCompressionLZW],[r canBeCompressedUsing:NSTIFFCompressionJPEG],[r canBeCompressedUsing:NSTIFFCompressionCCITTFAX3]);
 const NSTIFFCompression *types; NSInteger n; [NSBitmapImageRep getTIFFCompressionTypes:&types count:&n]; printf("types %ld:",(long)n); for(NSInteger i=0;i<n;i++) printf(" %ld",(long)types[i]); printf("\n");
 for(NSInteger i=0;i<n;i++) printf("name %ld '%s'\n",(long)types[i],[[NSBitmapImageRep localizedNameForTIFFCompressionType:types[i]] UTF8String]);
 printf("cs %s\n",[[[r colorSpace] localizedName] UTF8String]);
 NSBitmapImageRep *g=[r bitmapImageRepByConvertingToColorSpace:[NSColorSpace genericGrayColorSpace] renderingIntent:NSColorRenderingIntentDefault]; printf("gray conv %d spp %ld\n",g!=nil,g?(long)g.samplesPerPixel:0);
 NSBitmapImageRep *t=[r bitmapImageRepByRetaggingWithColorSpace:[NSColorSpace sRGBColorSpace]]; printf("retag %d\n",t!=nil);
 printf("prop none %d\n",[r valueForProperty:NSImageGamma]!=nil);
 [r setProperty:NSImageGamma withValue:@2.2]; printf("prop %g\n",[[r valueForProperty:NSImageGamma] doubleValue]);
 [r setProperty:NSImageCompressionFactor withValue:@0.7]; printf("prop2 %g\n",[[r valueForProperty:NSImageCompressionFactor] doubleValue]);
 printf("fallback %d\n",[r valueForProperty:NSImageFallbackBackgroundColor]!=nil);
 NSData *d=[NSBitmapImageRep TIFFRepresentationOfImageRepsInArray:@[r] usingCompression:NSTIFFCompressionNone factor:0]; printf("tiff %d\n",d.length>0);
 NSBitmapImageRep *inc=[[NSBitmapImageRep alloc] initForIncrementalLoad]; printf("inc %d\n",inc!=nil);
 NSData *png=[r representationUsingType:NSBitmapImageFileTypePNG properties:@{}]; NSInteger st=[inc incrementalLoadFromData:png complete:YES]; printf("load %ld\n",(long)st);
 NSBitmapImageRep *tinted=[r copy]; [tinted colorizeByMappingGray:0.5 toColor:[NSColor redColor] blackMapping:[NSColor blackColor] whiteMapping:[NSColor whiteColor]]; printf("colorize ok\n");
}}
static void p2(void){ @autoreleasepool { 
 NSBrowser *b=[[NSBrowser alloc] initWithFrame:NSMakeRect(0,0,400,200)];
 printf("pref %d autosave %d\n",b.prefersAllColumnUserResizing,b.columnsAutosaveName!=nil);
 b.prefersAllColumnUserResizing=YES; b.columnsAutosaveName=@"xefcols"; printf("pref2 %d auto '%s'\n",b.prefersAllColumnUserResizing,[b.columnsAutosaveName UTF8String]);
 [NSBrowser removeSavedColumnsWithAutosaveName:@"xefcols"]; printf("removed\n");
 [b validateVisibleColumns]; [b scrollColumnsRightBy:1]; [b scrollColumnsLeftBy:1];
 printf("drag %d\n",[b canDragRowsWithIndexes:[NSIndexSet indexSetWithIndex:0] inColumn:0 withEvent:nil]);
 [b setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
 [b scrollViaScroller:nil];
 NSDocument *d=[[NSDocument alloc] init];
 printf("doc pa %d sh %d\n",d.previewRepresentableActivityItems!=nil,0);
 d.previewRepresentableActivityItems=@[@"x"]; printf("pra %lu\n",(unsigned long)d.previewRepresentableActivityItems.count);
 printf("shouldChange %d\n",[d shouldChangePrintInfo:[NSPrintInfo sharedPrintInfo]]);
 printf("objspec %d\n",[d objectSpecifier]!=nil);
 NSLayoutManager *lm=[[NSLayoutManager alloc] init]; NSTextStorage *ts=[[NSTextStorage alloc] initWithString:@"Hello"]; [ts addLayoutManager:lm]; NSTextContainer *tc=[[NSTextContainer alloc] initWithSize:NSMakeSize(200,100)]; [lm addTextContainer:tc];
 [lm ensureLayoutForTextContainer:tc];
 NSFont *f=[NSFont systemFontOfSize:12]; printf("subst %d\n",[lm substituteFontForFont:f]==f);
 NSGlyph gl[8]; NSUInteger ci[8]; NSGlyphInscription in[8]; unsigned char el[8]; NSRange rg=NSMakeRange(0,5);
 NSUInteger n=[lm getGlyphsInRange:rg glyphs:gl characterIndexes:ci glyphInscriptions:in elasticBits:el]; printf("glyphs %lu ci %lu %lu in %d el %d\n",(unsigned long)n,(unsigned long)ci[0],(unsigned long)ci[4],(int)in[0],el[0]);
 unsigned char bd[8]; n=[lm getGlyphsInRange:rg glyphs:gl characterIndexes:ci glyphInscriptions:in elasticBits:el bidiLevels:bd]; printf("bidi %lu %d\n",(unsigned long)n,bd[0]);
 printf("intattr %ld\n",(long)[lm intAttribute:1 forGlyphAtIndex:0]);
 [lm setIntAttribute:1 value:7 forGlyphAtIndex:0]; printf("intattr2 %ld\n",(long)[lm intAttribute:1 forGlyphAtIndex:0]);
 CGFloat pos[8]; NSUInteger idx[8]; NSUInteger cnt=[lm getLineFragmentInsertionPointsForCharacterAtIndex:2 alternatePositions:NO inDisplayOrder:NO positions:pos characterIndexes:idx]; printf("ins %lu\n",(unsigned long)cnt);
 for(NSUInteger i=0;i<cnt;i++) printf(" pos>=0 %d idx %lu\n",pos[i]>=0,(unsigned long)idx[i]);
}}
int main(void){ [NSApplication sharedApplication]; p1(); p2(); return 0; }
