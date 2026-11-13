/* Methods AppKit adds to classes of other frameworks (Core Image, Core Data, Foundation); added at load through the runtime because
   those classes have no interface here. Matched against macOS by tests/darwin/mac/appkit_misc13.m. */
#import "AppKitMisc8.h"
#include <objc/runtime.h>
#include <objc/message.h>

static void Add(const char *cls, BOOL meta, const char *sel, IMP imp, const char *types) {
  Class c = objc_getClass(cls); if (!c) return; if (meta) c = object_getClass(c);
  class_replaceMethod(c, sel_registerName(sel), imp, types); }   /* replaces the generated placeholder, if it was installed first */

static id imp_self(id s, SEL c) { return s; }
static id imp_self1(id s, SEL c, id a) { return s; }
static id imp_nil(id s, SEL c) { return nil; }
static BOOL imp_yes(id s, SEL c) { return YES; }
static BOOL imp_yes_err(id s, SEL c, NSError **e) { return YES; }
static void imp_void(id s, SEL c) {}
static void imp_draw_in_rect(id s, SEL c, NSRect d, NSRect f, NSUInteger op, CGFloat fr) {}
static void imp_draw_at(id s, SEL c, NSPoint p, NSRect f, NSUInteger op, CGFloat fr) {}
static id imp_color_catalog(id s, SEL c, NSString *cat, NSString *name) {
  SEL sel = NSSelectorFromString([name hasSuffix:@"Color"] ? name : [name stringByAppendingString:@"Color"]);
  return [s respondsToSelector:sel] ? [s performSelector:sel] : nil; }
static id imp_default_fm(id s, SEL c, id auth) { if (!auth) [NSException raise:NSInvalidArgumentException format:@"NSWorkspaceAuthorization parameter is nil"]; return [NSFileManager defaultManager]; }
static NSRect imp_zero_rect(id s, SEL c) { return NSZeroRect; }
static NSSize imp_zero_size(id s, SEL c) { return NSZeroSize; }
static void imp_ck1(id s, SEL c, id a) {} static void imp_ck2(id s, SEL c, id a, id b) {}
static void imp_commit_delegate(id s, SEL c, id d, SEL sel, void *ci) { if (d && sel && [d respondsToSelector:sel]) { void (*f)(id, SEL, id, BOOL, void *) = (void (*)(id, SEL, id, BOOL, void *))objc_msgSend; f(d, sel, s, YES, ci); } }
static id imp_cirep_make(id cls, SEL c, id img) { return [[[cls alloc] init] autorelease]; }
static id imp_cirep_init(id s, SEL c, id img) { return [s init]; }
static BOOL imp_pdoc_cfg2(id s, SEL c, id u, id t, NSError **e) { return YES; }
static id imp_pdoc_type(id s, SEL c, id t) { return @"SQLite"; }
static BOOL imp_pdoc_cfg(id s, SEL c, id u, id t, id mc, id so, NSError **e) { return YES; }

__attribute__((constructor)) static void xef_misc9(void) {
  Add("CIColor", NO, "initWithColor:", (IMP)imp_self1, "@@:@");
  Add("CIImage", NO, "initWithBitmapImageRep:", (IMP)imp_self1, "@@:@");
  Add("CIImage", NO, "drawInRect:fromRect:operation:fraction:", (IMP)imp_draw_in_rect, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}{CGRect={CGPoint=dd}{CGSize=dd}}Qd");
  Add("CIImage", NO, "drawAtPoint:fromRect:operation:fraction:", (IMP)imp_draw_at, "v@:{CGPoint=dd}{CGRect={CGPoint=dd}{CGSize=dd}}Qd");
  Add("NSCIImageRep", YES, "imageRepWithCIImage:", (IMP)imp_cirep_make, "@@:@"); Add("NSCIImageRep", NO, "initWithCIImage:", (IMP)imp_cirep_init, "@@:@"); Add("NSCIImageRep", NO, "CIImage", (IMP)imp_nil, "@@:");
  Add("NSAppleScript", NO, "richTextSource", (IMP)imp_nil, "@@:");
  Add("NSCoder", NO, "decodeNXColor", (IMP)imp_nil, "@@:");
  Add("NSColor", YES, "colorWithCatalogName:colorName:", (IMP)imp_color_catalog, "@@:@@");
  Add("NSFileManager", YES, "fileManagerWithAuthorization:", (IMP)imp_default_fm, "@@:@");
  Add("NSItemProvider", NO, "sourceFrame", (IMP)imp_zero_rect, "{CGRect={CGPoint=dd}{CGSize=dd}}@:"); Add("NSItemProvider", NO, "containerFrame", (IMP)imp_zero_rect, "{CGRect={CGPoint=dd}{CGSize=dd}}@:");
  Add("NSItemProvider", NO, "preferredPresentationSize", (IMP)imp_zero_size, "{CGSize=dd}@:");
  Add("NSItemProvider", NO, "registerCloudKitShareWithPreparationHandler:", (IMP)imp_ck1, "v@:@"); Add("NSItemProvider", NO, "registerCloudKitShare:container:", (IMP)imp_ck2, "v@:@@");
  Add("NSManagedObjectContext", NO, "discardEditing", (IMP)imp_void, "v@:"); Add("NSManagedObjectContext", NO, "commitEditing", (IMP)imp_yes, "c@:");
  Add("NSManagedObjectContext", NO, "commitEditingWithDelegate:didCommitSelector:contextInfo:", (IMP)imp_commit_delegate, "v@:@:^v"); Add("NSManagedObjectContext", NO, "commitEditingAndReturnError:", (IMP)imp_yes_err, "c@:^@");
  Add("NSPersistentDocument", NO, "managedObjectContext", (IMP)imp_nil, "@@:"); Add("NSPersistentDocument", NO, "setManagedObjectContext:", (IMP)imp_ck1, "v@:@"); Add("NSPersistentDocument", NO, "managedObjectModel", (IMP)imp_nil, "@@:");
  Add("NSPersistentDocument", NO, "persistentStoreTypeForFileType:", (IMP)imp_pdoc_type, "@@:@");
  Add("NSPersistentDocument", NO, "configurePersistentStoreCoordinatorForURL:ofType:modelConfiguration:storeOptions:error:", (IMP)imp_pdoc_cfg, "c@:@@@@^@");
  Add("NSPersistentDocument", NO, "configurePersistentStoreCoordinatorForURL:ofType:error:", (IMP)imp_pdoc_cfg2, "c@:@@^@");
}
