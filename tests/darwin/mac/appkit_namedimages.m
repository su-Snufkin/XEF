// System images behind NSImageName* (present, size) - compared with macOS.
#import <Cocoa/Cocoa.h>
int main(void){ @autoreleasepool { [NSApplication sharedApplication];
 const char *n[]={"NSInfo","NSCaution","NSApplicationIcon","NSUser","NSFolder","NSActionTemplate","NSAddTemplate","NSComputer","NSNetwork","NSBonjour","NSMultipleDocuments","NSEnterFullScreenTemplate","NSGoLeftTemplate","NSGoRightTemplate","NSRefreshTemplate","NSInvalidDataFreestandingTemplate","NSMenuOnStateTemplate","NSQuickLookTemplate","NSShareTemplate","NSStatusAvailable","NSTrashEmpty","NSTrashFull","NSPreferencesGeneral","NSAdvanced","NSColorPanel","NSFontPanel","NSSlideshowTemplate",0};
 for(int i=0;n[i];i++){ NSImage*im=[NSImage imageNamed:[NSString stringWithUTF8String:n[i]]]; printf("%s %d %g\n",n[i],im!=nil,im?im.size.width:0);} return 0;}}
