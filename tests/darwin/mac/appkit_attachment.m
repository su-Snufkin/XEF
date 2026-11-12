// NSTextAttachment: contents, file type, image, bounds, layout hooks, attributed string integration. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSTextAttachment *a = [[NSTextAttachment alloc] init];
  P("defaults: contents nil %d fileType nil %d image nil %d bounds %s padding %g wrapper nil %d allowsView %d\n", a.contents == nil, a.fileType == nil, a.image == nil, [NSStringFromRect(a.bounds) UTF8String], a.lineLayoutPadding, a.fileWrapper == nil, a.allowsTextAttachmentView);
  NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(20, 10)]; a.image = img; P("image set %d size %s\n", a.image == img, [NSStringFromSize(a.image.size) UTF8String]);
  NSRect b = [a attachmentBoundsForAttributes:@{} location:nil textContainer:nil proposedLineFragment:NSMakeRect(0, 0, 100, 14) position:NSZeroPoint];
  P("layout bounds (no explicit): %s\n", [NSStringFromRect(b) UTF8String]);
  a.bounds = NSMakeRect(1, 2, 30, 15); b = [a attachmentBoundsForAttributes:@{} location:nil textContainer:nil proposedLineFragment:NSMakeRect(0, 0, 100, 14) position:NSZeroPoint];
  P("layout bounds (explicit): %s\n", [NSStringFromRect(b) UTF8String]);
  P("imageForBounds same %d\n", [a imageForBounds:NSMakeRect(0, 0, 20, 10) textContainer:nil characterIndex:0] == img);
  NSData *d = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
  NSTextAttachment *b2 = [[NSTextAttachment alloc] initWithData:d ofType:@"public.plain-text"]; P("withData: contents %lu type %s image nil %d wrapper %d\n", (unsigned long)b2.contents.length, [b2.fileType UTF8String], b2.image == nil, b2.fileWrapper != nil);
  NSFileWrapper *fw = [[NSFileWrapper alloc] initRegularFileWithContents:d]; fw.preferredFilename = @"x.txt";
  NSTextAttachment *b3 = [[NSTextAttachment alloc] initWithFileWrapper:fw]; P("withWrapper: wrapper same %d contents %lu\n", b3.fileWrapper == fw, (unsigned long)b3.contents.length);
  NSAttributedString *as = [NSAttributedString attributedStringWithAttachment:a];
  NSTextAttachment *got = [as attribute:NSAttachmentAttributeName atIndex:0 effectiveRange:NULL]; P("attributed string attachment same %d char %04x\n", got == a, [as.string characterAtIndex:0]);
  a.lineLayoutPadding = 2; P("padding %g\n", a.lineLayoutPadding);
  P("PASS appkit_attachment\n");
  fflush(stdout); _exit(0);
} return 0; }
