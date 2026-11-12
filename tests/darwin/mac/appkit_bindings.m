// Cocoa bindings on any object: bind:toObject:withKeyPath:options:, unbind:, infoForBinding:, exposed bindings, value transformers. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface Model : NSObject { NSString *_name; NSNumber *_flag; } @property (copy) NSString *name; @property (retain) NSNumber *flag; @end
@implementation Model @synthesize name = _name; @synthesize flag = _flag; @end
@interface Target : NSObject { NSString *_text; int sets; } @property (copy) NSString *text; - (int)sets; @end
@implementation Target @synthesize text = _text; - (void)setText:(NSString *)t { sets++; _text = [t copy]; } - (int)sets { return sets; } @end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  Model *m = [Model new]; m.name = @"first";
  Target *t = [Target new];
  [Target exposeBinding:@"text"]; P("exposed has text %d\n", [[t exposedBindings] containsObject:@"text"]);
  [t bind:@"text" toObject:m withKeyPath:@"name" options:nil];
  P("after bind: text '%s' sets %d\n", [t.text UTF8String], [t sets]);
  m.name = @"second"; P("model changed -> text '%s' sets %d\n", [t.text UTF8String], [t sets]);
  NSDictionary *info = [t infoForBinding:@"text"]; P("info: object same %d keyPath %s options %d\n", info[NSObservedObjectKey] == m, [info[NSObservedKeyPathKey] UTF8String], info[NSOptionsKey] != nil);
  P("valueClass nil? %d\n", [t valueClassForBinding:@"text"] == nil);
  [t unbind:@"text"]; m.name = @"third"; P("after unbind: text '%s' info nil %d\n", [t.text UTF8String], [t infoForBinding:@"text"] == nil);
  NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
  P("textfield exposes value %d\n", [[tf exposedBindings] containsObject:NSValueBinding]);
  [tf bind:NSValueBinding toObject:m withKeyPath:@"name" options:nil]; P("field value '%s'\n", [tf.stringValue UTF8String]);
  m.name = @"fourth"; P("field after change '%s'\n", [tf.stringValue UTF8String]);
  [tf bind:NSEnabledBinding toObject:m withKeyPath:@"flag" options:nil]; m.flag = @NO; P("enabled after flag NO: %d\n", tf.isEnabled);
  m.flag = @YES; P("enabled after flag YES: %d\n", tf.isEnabled);
  [tf bind:NSHiddenBinding toObject:m withKeyPath:@"flag" options:@{ NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName }]; P("hidden (negated flag YES): %d\n", tf.isHidden);
  [tf unbind:NSValueBinding]; [tf unbind:NSEnabledBinding]; [tf unbind:NSHiddenBinding];
  P("PASS appkit_bindings\n");
  fflush(stdout); _exit(0);
} return 0; }
