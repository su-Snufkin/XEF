// NSSharingService / NSSharingServicePicker / NSInputManager, compared with macOS.
#import <Cocoa/Cocoa.h>
int main(void){ @autoreleasepool { [NSApplication sharedApplication];
 NSSharingService *s=[[NSSharingService alloc] initWithTitle:@"Share It" image:[NSImage imageNamed:NSImageNameInfo] alternateImage:nil handler:^{ printf("handler\n"); }];
 printf("title '%s' menu '%s' img %d alt %d sub %d body %d rec %d acct %d perm %d att %d del %d\n",[s.title UTF8String],[s.menuItemTitle UTF8String],s.image!=nil,s.alternateImage!=nil,s.subject!=nil,s.messageBody!=nil,s.recipients!=nil,s.accountName!=nil,s.permanentLink!=nil,s.attachmentFileURLs!=nil,s.delegate!=nil);
 printf("can %d %d\n",[s canPerformWithItems:@[@"x"]],[s canPerformWithItems:nil]);
 [s performWithItems:@[@"x"]];
 s.subject=@"Sub"; s.recipients=@[@"a@b.c"]; s.menuItemTitle=@"M"; printf("sub '%s' rec %lu menu '%s'\n",[s.subject UTF8String],(unsigned long)s.recipients.count,[s.menuItemTitle UTF8String]);
 NSArray *a=[NSSharingService sharingServicesForItems:@[@"hello"]]; printf("svcs>0 %d\n",a.count > 0);
 NSSharingService *m=[NSSharingService sharingServiceNamed:NSSharingServiceNameComposeEmail]; printf("named %d\n",m!=nil);
 NSSharingServicePicker *p=[[NSSharingServicePicker alloc] initWithItems:@[@"x"]]; printf("picker del %d menu %d\n",p.delegate!=nil,[p standardShareMenuItem]!=nil);
 if (p.standardShareMenuItem) printf("mi title '%s' sub %d\n",[p.standardShareMenuItem.title UTF8String],p.standardShareMenuItem.submenu!=nil);
 NSInputManager *im=[NSInputManager currentInputManager]; printf("im %d\n",im!=nil);
 if (im) { printf("name '%s' lang '%s' hasMarked %d markedRange %lu/%lu sel %lu valid %lu wantsAll %d mouse %d delay %d\n",[[im localizedInputManagerName] UTF8String],[[im language] UTF8String],[im hasMarkedText],(unsigned long)[im markedRange].location,(unsigned long)[im markedRange].length,(unsigned long)[im selectedRange].location,(unsigned long)[[im validAttributesForMarkedText] count],[im wantsToInterpretAllKeystrokes],[im wantsToHandleMouseEvents],[im wantsToDelayTextChangeNotifications]); }
 return 0;}}
