// libclosure's block classes only implement retain/release; Apple's CoreFoundation adds the NSBlock
// copying behaviour, which [block copy] and collections copying blocks rely on.
#import <objc/runtime.h>
#include <Block.h>

static id xef_block_copy(id self, SEL _cmd) { return (id)_Block_copy((const void *)self); }
static id xef_block_copy_zone(id self, SEL _cmd, void *zone) { return (id)_Block_copy((const void *)self); }

__attribute__((constructor)) static void xef_block_copy_methods(void) {
  static const char *names[] = {"__NSStackBlock__", "__NSMallocBlock__", "__NSGlobalBlock__", "__NSAutoBlock__", "__NSFinalizingBlock__"};
  for (unsigned i = 0; i < sizeof names / sizeof names[0]; i++) {
    Class c = objc_getClass(names[i]);
    if (!c) continue;
    class_addMethod(c, sel_registerName("copy"), (IMP)xef_block_copy, "@@:");
    class_addMethod(c, sel_registerName("copyWithZone:"), (IMP)xef_block_copy_zone, "@@:^v");
  }
}
