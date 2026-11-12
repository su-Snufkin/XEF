// NSAttributedString (AppKit additions): HTML/RTF readers, attachments, line breaks, text types. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSData *html = [@"<p>Hello <b>bold</b> world</p>" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *da = nil; NSError *e = nil;
  NSAttributedString *a = [[NSAttributedString alloc] initWithData:html options:@{ NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType, NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding) } documentAttributes:&da error:&e];
  P("html: %d string '%s'\n", a != nil, [[a.string stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"] UTF8String]);
  NSRange r; NSFont *f = [a attribute:NSFontAttributeName atIndex:6 effectiveRange:&r]; P("bold run: %s traits bold %d\n", [NSStringFromRange(r) UTF8String], (int)(([[NSFontManager sharedFontManager] traitsOfFont:f] & NSBoldFontMask) != 0));
  NSData *rtf = [@"{\\rtf1\\ansi Hello {\\b bold} rtf}" dataUsingEncoding:NSUTF8StringEncoding];
  NSAttributedString *b = [[NSAttributedString alloc] initWithRTF:rtf documentAttributes:NULL]; P("rtf: %d string '%s'\n", b != nil, [[b.string stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"] UTF8String]);
  NSData *plain = [@"just text" dataUsingEncoding:NSUTF8StringEncoding];
  NSAttributedString *c = [[NSAttributedString alloc] initWithData:plain options:@{ NSDocumentTypeDocumentAttribute: NSPlainTextDocumentType } documentAttributes:NULL error:&e]; P("plain: %d '%s'\n", c != nil, [c.string UTF8String]);
  NSAttributedString *bad = [[NSAttributedString alloc] initWithData:[NSData dataWithBytes:"\x00\x01" length:2] options:@{ NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType } documentAttributes:NULL error:&e]; P("bad rtf %d error %d\n", bad != nil, e != nil);
  NSTextAttachment *att = [[NSTextAttachment alloc] init];
  NSAttributedString *as = [NSAttributedString attributedStringWithAttachment:att]; P("attachment string length %lu char %04x attr %d\n", (unsigned long)as.length, [as.string characterAtIndex:0], [as attribute:NSAttachmentAttributeName atIndex:0 effectiveRange:NULL] == att);
  NSAttributedString *t = [[NSAttributedString alloc] initWithString:@"hello wonderful world"];
  P("lineBreakBefore(10) %lu inRange(0,21)\n", (unsigned long)[t lineBreakBeforeIndex:10 withinRange:NSMakeRange(0, 21)]);
  P("lineBreakBefore(3) %lu\n", (unsigned long)[t lineBreakBeforeIndex:3 withinRange:NSMakeRange(0, 21)]);
  P("rangeOfTextBlock none %s\n", [NSStringFromRange([t rangeOfTextBlock:nil atIndex:0]) UTF8String]);
  P("textTypes >0 %d\n", [NSAttributedString textTypes].count > 0);
  P("PASS appkit_attrstr\n");
  fflush(stdout); _exit(0);
} return 0; }
