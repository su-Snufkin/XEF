#include <sys/stat.h>
/* AppKit-lite document architecture: NSDocument, NSDocumentController and NSWindowController's document support,
 * plus the small NSPrintInfo / NSPrintOperation / NSWorkspace surface document apps touch. Document types come from
 * the main bundle's CFBundleDocumentTypes. File access is synchronous; "asynchronous" API runs its blocks in place.
 * There is no versions browser, iCloud or sharing. MRC. */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitControls.h"
#import "AppKitDocument.h"
#include <objc/runtime.h>
#include <objc/message.h>
#include <spawn.h>

NSString *const NSPrintJobDisposition = @"NSJobDisposition";
NSString *const NSPrintSpoolJob = @"NSPrintSpoolJob";
NSString *const NSPrintPreviewJob = @"NSPrintPreviewJob";
NSString *const NSPrintSaveJob = @"NSPrintSaveJob";
NSString *const NSPrintCancelJob = @"NSPrintCancelJob";
NSString *const NSWorkspaceDidLaunchApplicationNotification = @"NSWorkspaceDidLaunchApplicationNotification";
NSString *const NSWorkspaceDidTerminateApplicationNotification = @"NSWorkspaceDidTerminateApplicationNotification";
NSString *const NSWorkspaceDidActivateApplicationNotification = @"NSWorkspaceDidActivateApplicationNotification";
NSString *const NSWorkspaceWillPowerOffNotification = @"NSWorkspaceWillPowerOffNotification";
NSString *const NSWorkspaceDidWakeNotification = @"NSWorkspaceDidWakeNotification";
NSString *const NSWorkspaceWillSleepNotification = @"NSWorkspaceWillSleepNotification";
NSString *const NSWorkspaceActiveSpaceDidChangeNotification = @"NSWorkspaceActiveSpaceDidChangeNotification";
NSString *const NSWorkspaceApplicationKey = @"NSWorkspaceApplicationKey";

/* ================================================================== NSDocument */
@implementation NSDocument
+ (BOOL)autosavesInPlace { return NO; }
+ (BOOL)autosavesDrafts { return NO; }
+ (BOOL)preservesVersions { return NO; }
+ (BOOL)usesUbiquitousStorage { return NO; }
+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString *)t { return NO; }
+ (BOOL)isNativeType:(NSString *)t { return [[self readableTypes] containsObject:t]; }
+ (NSArray *)readableTypes { return [[NSDocumentController sharedDocumentController] _xefTypesForClass:self]; }
+ (NSArray *)writableTypes { return [self readableTypes]; }
+ (NSArray *)restorableStateKeyPaths { return @[]; }
- (id)init {
  if ((self = [super init])) { _wcs = [[NSMutableArray alloc] init]; _hasUndo = YES; _type = [[[NSDocumentController sharedDocumentController] defaultType] copy]; }
  return self; }
- (id)initWithType:(NSString *)t error:(NSError **)e { if ((self = [self init])) [self setFileType:t]; return self; }
- (id)initWithContentsOfURL:(NSURL *)u ofType:(NSString *)t error:(NSError **)e {
  if (!(self = [self init])) return nil;
  [self setFileType:t]; [self setFileURL:u];
  if (![self readFromURL:u ofType:t error:e]) { [self release]; return nil; }
  [self setFileModificationDate:[[[NSFileManager defaultManager] attributesOfItemAtPath:[u path] error:NULL] fileModificationDate]];
  return self; }
- (id)initForURL:(NSURL *)u withContentsOfURL:(NSURL *)c ofType:(NSString *)t error:(NSError **)e {
  if (!(self = [self init])) return nil;
  [self setFileType:t]; [self setFileURL:u];
  if (c && ![self readFromURL:c ofType:t error:e]) { [self release]; return nil; }
  return self; }
- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [_wcs release]; [_url release]; [_type release]; [_date release]; [_undo release]; [_printInfo release]; [_displayName release]; [super dealloc]; }
/* identity */
- (NSURL *)fileURL { return _url; } - (void)setFileURL:(NSURL *)u { [u retain]; [_url release]; _url = u; [self _xefSyncTitles]; }
- (NSString *)fileType { return _type; } - (void)setFileType:(NSString *)t { [_type release]; _type = [t copy]; }
- (NSDate *)fileModificationDate { return _date; } - (void)setFileModificationDate:(NSDate *)d { [d retain]; [_date release]; _date = d; }
- (NSString *)fileNameExtensionForType:(NSString *)t saveOperation:(NSInteger)op { return nil; }
- (BOOL)isDraft { return NO; } - (void)setDraft:(BOOL)f {}
- (BOOL)isLocked { return NO; } - (BOOL)isInViewingMode { return NO; } - (BOOL)isBrowsingVersions { return NO; }
- (NSURL *)autosavedContentsFileURL { return nil; } - (void)setAutosavedContentsFileURL:(NSURL *)u {}
- (NSString *)displayName {
  if (_displayName) return _displayName;
  if (_url) return [[[_url path] lastPathComponent] stringByDeletingPathExtension];
  NSUInteger n = [[NSDocumentController sharedDocumentController] _xefUntitledNumberFor:self];
  return n > 1 ? [NSString stringWithFormat:@"Untitled %lu", (unsigned long)n] : @"Untitled"; }
- (void)setDisplayName:(NSString *)n { [_displayName release]; _displayName = [n copy]; [self _xefSyncTitles]; }
- (NSString *)defaultDraftName { return @"Untitled"; }
- (void)_xefSyncTitles { for (NSWindowController *wc in _wcs) [wc synchronizeWindowTitleWithDocumentName]; }
/* windows */
- (NSString *)windowNibName { return nil; }
- (void)makeWindowControllers {
  NSString *nib = [self windowNibName];
  if (!nib) return;
  NSWindowController *wc = [[NSWindowController alloc] initWithWindowNibName:nib owner:self];
  [self addWindowController:wc]; [wc release]; }
- (NSArray *)windowControllers { return [[_wcs copy] autorelease]; }
- (void)addWindowController:(NSWindowController *)wc {
  if (!wc || [_wcs containsObject:wc]) return;
  [_wcs addObject:wc];
  if ([wc document] != self) [wc setDocument:self]; }
- (void)removeWindowController:(NSWindowController *)wc { [[wc retain] autorelease]; [_wcs removeObjectIdenticalTo:wc]; if ([wc document] == self) [wc setDocument:nil]; }
- (void)showWindows { for (NSWindowController *wc in [[_wcs copy] autorelease]) [wc showWindow:self]; }
- (void)windowControllerWillLoadNib:(NSWindowController *)wc {}
- (void)windowControllerDidLoadNib:(NSWindowController *)wc {}
- (void)setWindow:(NSWindow *)w { NSWindowController *wc = _loadingWC ? _loadingWC : [_wcs firstObject]; if (wc) [wc setWindow:w]; }
- (NSWindow *)windowForSheet { NSWindow *w = [[_wcs firstObject] window]; return w ? w : [NSApp mainWindow]; }
- (BOOL)shouldCloseWindowController:(NSWindowController *)wc { return YES; }
- (void)shouldCloseWindowController:(NSWindowController *)wc delegate:(id)d shouldCloseSelector:(SEL)s contextInfo:(void *)ci {
  if (d && s) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(d, s, self, YES, ci); }
- (void)close {
  [[self retain] autorelease];
  for (NSWindowController *wc in [[_wcs copy] autorelease]) { [wc close]; [self removeWindowController:wc]; }
  [[NSDocumentController sharedDocumentController] removeDocument:self]; }
- (void)canCloseDocumentWithDelegate:(id)d shouldCloseSelector:(SEL)s contextInfo:(void *)ci {
  if (d && s) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(d, s, self, YES, ci); }
- (void)performClose:(id)s { [self close]; }
- (IBAction)performCloseDocument:(id)s { [self close]; }
/* reading */
- (BOOL)readFromURL:(NSURL *)u ofType:(NSString *)t error:(NSError **)e {
  NSFileWrapper *fw = [[[NSFileWrapper alloc] initWithURL:u options:0 error:e] autorelease];
  return fw ? [self readFromFileWrapper:fw ofType:t error:e] : NO; }
- (BOOL)readFromFileWrapper:(NSFileWrapper *)fw ofType:(NSString *)t error:(NSError **)e {
  NSData *d = [fw isRegularFile] ? [fw regularFileContents] : nil;
  return d ? [self readFromData:d ofType:t error:e] : NO; }
- (BOOL)readFromData:(NSData *)d ofType:(NSString *)t error:(NSError **)e {
  if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:259 userInfo:nil]; return NO; }
- (BOOL)revertToContentsOfURL:(NSURL *)u ofType:(NSString *)t error:(NSError **)e { BOOL ok = [self readFromURL:u ofType:t error:e]; if (ok) [self updateChangeCount:2 /*cleared*/]; return ok; }
- (void)revertDocumentToSaved:(id)s { if (_url) [self revertToContentsOfURL:_url ofType:_type error:NULL]; }
/* writing */
- (NSData *)dataOfType:(NSString *)t error:(NSError **)e { if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:513 userInfo:nil]; return nil; }
- (NSFileWrapper *)fileWrapperOfType:(NSString *)t error:(NSError **)e {
  NSData *d = [self dataOfType:t error:e]; return d ? [[[NSFileWrapper alloc] initRegularFileWithContents:d] autorelease] : nil; }
- (BOOL)writeToURL:(NSURL *)u ofType:(NSString *)t error:(NSError **)e {
  NSFileWrapper *fw = [self fileWrapperOfType:t error:e];
  return fw ? [fw writeToURL:u options:NSFileWrapperWritingAtomic originalContentsURL:nil error:e] : NO; }
- (BOOL)writeToURL:(NSURL *)u ofType:(NSString *)t forSaveOperation:(NSInteger)op originalContentsURL:(NSURL *)o error:(NSError **)e {
  return [self writeToURL:u ofType:t error:e]; }
- (BOOL)writeSafelyToURL:(NSURL *)u ofType:(NSString *)t forSaveOperation:(NSInteger)op error:(NSError **)e {
  return [self writeToURL:u ofType:t forSaveOperation:op originalContentsURL:_url error:e]; }
- (NSDictionary *)fileAttributesToWriteToURL:(NSURL *)u ofType:(NSString *)t forSaveOperation:(NSInteger)op originalContentsURL:(NSURL *)o error:(NSError **)e { return @{}; }
- (BOOL)keepBackupFile { return NO; }
- (void)saveToURL:(NSURL *)u ofType:(NSString *)t forSaveOperation:(NSInteger)op completionHandler:(void (^)(NSError *))h {
  NSError *err = nil;
  BOOL ok = [self writeSafelyToURL:u ofType:t forSaveOperation:op error:&err];
  if (ok && op != 2 /*NSSaveToOperation*/ && op != 3 /*autosave elsewhere*/) {
    [self setFileURL:u]; [self setFileType:t];
    [self setFileModificationDate:[NSDate date]];
    [self updateChangeCount:2 /*NSChangeCleared*/]; }
  if (h) h(ok ? nil : (err ?: [NSError errorWithDomain:NSCocoaErrorDomain code:512 userInfo:nil])); }
- (void)saveToURL:(NSURL *)u ofType:(NSString *)t forSaveOperation:(NSInteger)op delegate:(id)d didSaveSelector:(SEL)s contextInfo:(void *)ci {
  [self saveToURL:u ofType:t forSaveOperation:op completionHandler:^(NSError *err) {
    if (d && s) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(d, s, self, err == nil, ci); }]; }
- (BOOL)saveToURL:(NSURL *)u ofType:(NSString *)t forSaveOperation:(NSInteger)op error:(NSError **)e {
  __block NSError *err = nil; [self saveToURL:u ofType:t forSaveOperation:op completionHandler:^(NSError *x) { err = [x retain]; }];
  if (e) *e = [err autorelease]; else [err release]; return err == nil; }
- (void)saveDocumentWithDelegate:(id)d didSaveSelector:(SEL)s contextInfo:(void *)ci {
  if (_url) [self saveToURL:_url ofType:_type forSaveOperation:0 delegate:d didSaveSelector:s contextInfo:ci];
  else [self runModalSavePanelForSaveOperation:1 delegate:d didSaveSelector:s contextInfo:ci]; }
- (IBAction)saveDocument:(id)s { [self saveDocumentWithDelegate:nil didSaveSelector:NULL contextInfo:NULL]; }
- (IBAction)saveDocumentAs:(id)s { [self runModalSavePanelForSaveOperation:1 delegate:nil didSaveSelector:NULL contextInfo:NULL]; }
- (IBAction)saveDocumentTo:(id)s { [self runModalSavePanelForSaveOperation:2 delegate:nil didSaveSelector:NULL contextInfo:NULL]; }
- (IBAction)duplicateDocument:(id)s {}
- (IBAction)renameDocument:(id)s {} - (IBAction)moveDocument:(id)s {} - (IBAction)lockDocument:(id)s {} - (IBAction)unlockDocument:(id)s {}
- (IBAction)browseDocumentVersions:(id)s {}
- (BOOL)prepareSavePanel:(NSSavePanel *)p { return YES; }
- (BOOL)shouldRunSavePanelWithAccessoryView { return YES; }
- (void)runModalSavePanelForSaveOperation:(NSInteger)op delegate:(id)d didSaveSelector:(SEL)s contextInfo:(void *)ci {
  NSSavePanel *p = [NSSavePanel savePanel];
  [p setNameFieldStringValue:[self displayName]];
  if (![self prepareSavePanel:p] || [p runModal] != NSModalResponseOK || ![p URL]) {
    if (d && s) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(d, s, self, NO, ci);
    return; }
  [self saveToURL:[p URL] ofType:_type forSaveOperation:op delegate:d didSaveSelector:s contextInfo:ci]; }
/* autosave: in place, when the document has a file */
- (BOOL)hasUnautosavedChanges { return _changes != 0; }
- (void)autosaveWithImplicitCancellability:(BOOL)c completionHandler:(void (^)(NSError *))h {
  if (_url && _changes) [self saveToURL:_url ofType:_type forSaveOperation:4 /*NSAutosaveInPlaceOperation*/ completionHandler:h];
  else if (h) h(nil); }
- (void)autosaveDocumentWithDelegate:(id)d didAutosaveSelector:(SEL)s contextInfo:(void *)ci {
  [self autosaveWithImplicitCancellability:NO completionHandler:^(NSError *e) { if (d && s) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(d, s, self, e == nil, ci); }]; }
- (NSString *)autosavingFileType { return _type; }
- (BOOL)autosavingIsImplicitlyCancellable { return NO; }
- (void)scheduleAutosaving {}
/* change tracking */
- (BOOL)isDocumentEdited { return _changes != 0; }
- (void)updateChangeCount:(NSInteger)c {
  switch (c & 0xff) {
  case 0: _changes++; break;                              /* NSChangeDone */
  case 1: if (_changes > 0) _changes--; else _changes = 1; break;   /* NSChangeUndone */
  case 2: _changes = 0; break;                            /* NSChangeCleared */
  case 4: _changes = 1; break;                            /* NSChangeReadOtherContents */
  case 5: _changes++; break;                              /* NSChangeRedone */
  default: break; }
  for (NSWindowController *wc in _wcs) [[wc window] setDocumentEdited:_changes != 0]; }
- (void)updateChangeCountWithToken:(id)t forSaveOperation:(NSInteger)op { [self updateChangeCount:2]; }
- (id)changeCountTokenForSaveOperation:(NSInteger)op { return @(_changes); }
- (BOOL)hasUndoManager { return _hasUndo; }
- (void)setHasUndoManager:(BOOL)f { _hasUndo = f; if (!f) [self setUndoManager:nil]; }
- (NSUndoManager *)undoManager {
  if (!_undo && _hasUndo) {
    NSUndoManager *u = [[[NSUndoManager alloc] init] autorelease];
    [self setUndoManager:u]; }
  return _undo; }
- (void)_xefUndoChange:(NSNotification *)n {
  NSString *name = [n name];
  if ([name isEqualToString:NSUndoManagerDidUndoChangeNotification]) [self updateChangeCount:1];
  else if ([name isEqualToString:NSUndoManagerDidRedoChangeNotification]) [self updateChangeCount:5];
  else if (![_undo isUndoing] && ![_undo isRedoing]) [self updateChangeCount:0]; }
- (void)setUndoManager:(NSUndoManager *)u {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  if (_undo) [nc removeObserver:self name:nil object:_undo];
  [u retain]; [_undo release]; _undo = u;
  if (u) {
    [nc addObserver:self selector:@selector(_xefUndoChange:) name:NSUndoManagerDidUndoChangeNotification object:u];
    [nc addObserver:self selector:@selector(_xefUndoChange:) name:NSUndoManagerDidRedoChangeNotification object:u];
    /* Darling's undo manager posts only the "will close" form */
    [nc addObserver:self selector:@selector(_xefUndoChange:) name:NSUndoManagerWillCloseUndoGroupNotification object:u]; } }
/* printing */
- (NSPrintInfo *)printInfo { if (!_printInfo) _printInfo = [[NSPrintInfo sharedPrintInfo] copy]; return _printInfo; }
- (void)setPrintInfo:(NSPrintInfo *)p { [p retain]; [_printInfo release]; _printInfo = p; }
- (IBAction)printDocument:(id)s {} - (IBAction)runPageLayout:(id)s {}
- (void)printDocumentWithSettings:(NSDictionary *)s showPrintPanel:(BOOL)f delegate:(id)d didPrintSelector:(SEL)sel contextInfo:(void *)ci {}
- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)s error:(NSError **)e { return nil; }
- (IBAction)saveDocumentToPDF:(id)s {}
/* errors */
- (BOOL)presentError:(NSError *)e { NSLog(@"%@: %@", [self class], e); return NO; }
- (NSError *)willPresentError:(NSError *)e { return e; }
- (void)presentError:(NSError *)e modalForWindow:(NSWindow *)w delegate:(id)d didPresentSelector:(SEL)s contextInfo:(void *)ci {
  BOOL r = [self presentError:e]; if (d && s) ((void (*)(id, SEL, BOOL, void *))objc_msgSend)(d, s, r, ci); }
/* coordination: everything is synchronous here */
- (void)performActivityWithSynchronousWaiting:(BOOL)w usingBlock:(void (^)(void (^)(void)))b { if (b) b(^{}); }
- (void)continueActivityUsingBlock:(void (^)(void))b { if (b) b(); }
- (void)continueAsynchronousWorkOnMainThreadUsingBlock:(void (^)(void))b { if (b) b(); }
- (void)performSynchronousFileAccessUsingBlock:(void (^)(void))b { if (b) b(); }
- (void)performAsynchronousFileAccessUsingBlock:(void (^)(void (^)(void)))b { if (b) b(^{}); }
- (BOOL)checkAutosavingSafetyAndReturnError:(NSError **)e { return YES; }
- (void)stopBrowsingVersionsWithCompletionHandler:(void (^)(void))h { if (h) h(); }
- (NSURL *)presentedItemURL { return _url; }
- (NSOperationQueue *)presentedItemOperationQueue { return [NSOperationQueue mainQueue]; }
- (void)encodeRestorableStateWithCoder:(NSCoder *)c {} - (void)restoreStateWithCoder:(NSCoder *)c {}
- (void)invalidateRestorableState {}
- (BOOL)validateMenuItem:(NSMenuItem *)i { return [self validateUserInterfaceItem:(id)i]; }
- (BOOL)validateUserInterfaceItem:(id)i {
  SEL a = [i action];
  if (a == @selector(revertDocumentToSaved:)) return _url && _changes;
  if (a == @selector(saveDocument:)) return YES;
  return YES; }
- (NSString *)description { return [NSString stringWithFormat:@"<%@ %p %@>", [self class], self, [self displayName]]; }
/* AppKit-lite: window controller being loaded (nib outlets to File's Owner's "window" go to it) */
- (void)_xefSetLoadingWindowController:(NSWindowController *)wc { _loadingWC = wc; }
@end

/* ================================================================== NSDocumentController */
static NSDocumentController *g_doc_controller;
@implementation NSDocumentController
+ (id)sharedDocumentController {
  if (!g_doc_controller) [[self alloc] init];   /* init registers the instance */
  return g_doc_controller; }
- (id)init {
  if (g_doc_controller && g_doc_controller != self) { [self release]; return [g_doc_controller retain]; }
  if ((self = [super init])) {
    g_doc_controller = self;
    _docs = [[NSMutableArray alloc] init]; _recent = [[NSMutableArray alloc] init];
    _untitled = [[NSMutableArray alloc] init];
    _types = [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDocumentTypes"] retain]; }
  return self; }
- (id)initWithCoder:(NSCoder *)c { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (NSArray *)documents { return [[_docs copy] autorelease]; }
- (void)addDocument:(NSDocument *)d { if (d && ![_docs containsObject:d]) { [_docs addObject:d]; if (![d fileURL]) [_untitled addObject:[NSValue valueWithNonretainedObject:d]]; } }
- (void)removeDocument:(NSDocument *)d {
  for (NSValue *v in [[_untitled copy] autorelease]) if ([v nonretainedObjectValue] == d) [_untitled removeObject:v];
  [_docs removeObjectIdenticalTo:d]; }
- (NSUInteger)_xefUntitledNumberFor:(NSDocument *)d {
  NSUInteger i = 0; for (NSValue *v in _untitled) { i++; if ([v nonretainedObjectValue] == d) return i; } return 1; }
- (id)currentDocument {
  NSWindow *w = [NSApp keyWindow] ?: [NSApp mainWindow];
  return [self documentForWindow:w]; }
- (id)documentForWindow:(NSWindow *)w {
  if (!w) return nil;
  for (NSDocument *d in _docs) for (NSWindowController *wc in [d windowControllers]) if ([wc window] == w) return d;
  id wc = [w windowController]; return [wc document]; }
- (id)documentForURL:(NSURL *)u { for (NSDocument *d in _docs) if ([[d fileURL] isEqual:u]) return d; return nil; }
- (BOOL)hasEditedDocuments { for (NSDocument *d in _docs) if ([d isDocumentEdited]) return YES; return NO; }
/* types */
- (NSArray *)documentClassNames {
  NSMutableArray *a = [NSMutableArray array];
  for (NSDictionary *t in _types) { NSString *c = [t objectForKey:@"NSDocumentClass"]; if (c && ![a containsObject:c]) [a addObject:c]; }
  return a; }
- (NSString *)defaultType {
  for (NSDictionary *t in _types) {
    NSString *role = [t objectForKey:@"CFBundleTypeRole"];
    if (role && ![role isEqualToString:@"Editor"]) continue;
    NSArray *ct = [t objectForKey:@"LSItemContentTypes"];
    return [ct count] ? [ct objectAtIndex:0] : [t objectForKey:@"CFBundleTypeName"]; }
  return nil; }
- (NSDictionary *)_xefTypeEntry:(NSString *)type {
  for (NSDictionary *t in _types) if ([[t objectForKey:@"CFBundleTypeName"] isEqualToString:type] || [[t objectForKey:@"LSItemContentTypes"] containsObject:type]) return t;
  return nil; }
- (NSArray *)_xefTypesForClass:(Class)c {
  NSMutableArray *a = [NSMutableArray array];
  for (NSDictionary *t in _types) {
    if (![[t objectForKey:@"NSDocumentClass"] isEqualToString:NSStringFromClass(c)]) continue;
    NSArray *ct = [t objectForKey:@"LSItemContentTypes"];
    if ([ct count]) [a addObjectsFromArray:ct]; else if ([t objectForKey:@"CFBundleTypeName"]) [a addObject:[t objectForKey:@"CFBundleTypeName"]]; }
  return a; }
- (Class)documentClassForType:(NSString *)type {
  NSString *cn = [[self _xefTypeEntry:type] objectForKey:@"NSDocumentClass"];
  if (!cn && [_types count]) cn = [[_types objectAtIndex:0] objectForKey:@"NSDocumentClass"];
  return cn ? NSClassFromString(cn) : nil; }
- (NSString *)displayNameForType:(NSString *)type { return [[self _xefTypeEntry:type] objectForKey:@"CFBundleTypeName"] ?: type; }
- (NSString *)typeForContentsOfURL:(NSURL *)u error:(NSError **)e {
  NSString *ext = [[u pathExtension] lowercaseString];
  for (NSDictionary *t in _types) {
    for (NSString *x in [t objectForKey:@"CFBundleTypeExtensions"]) if ([[x lowercaseString] isEqualToString:ext]) {
      NSArray *ct = [t objectForKey:@"LSItemContentTypes"]; return [ct count] ? [ct objectAtIndex:0] : [t objectForKey:@"CFBundleTypeName"]; } }
  return [self defaultType]; }
- (NSArray *)fileExtensionsFromType:(NSString *)t { return [[self _xefTypeEntry:t] objectForKey:@"CFBundleTypeExtensions"] ?: @[]; }
- (NSString *)typeFromFileExtension:(NSString *)x { return [self typeForContentsOfURL:[NSURL fileURLWithPath:[@"x." stringByAppendingString:x ?: @""]] error:NULL]; }
/* creating and opening */
- (id)makeUntitledDocumentOfType:(NSString *)t error:(NSError **)e {
  Class c = [self documentClassForType:t];
  if (!c) { if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:256 userInfo:nil]; return nil; }
  return [[[c alloc] initWithType:t error:e] autorelease]; }
- (id)openUntitledDocumentAndDisplay:(BOOL)display error:(NSError **)e {
  NSDocument *d = [self makeUntitledDocumentOfType:[self defaultType] error:e];
  if (!d) return nil;
  [self addDocument:d];
  if ([self shouldCreateUI]) { [d makeWindowControllers]; if (display) [d showWindows]; }
  return d; }
- (BOOL)shouldCreateUI { return YES; }
- (IBAction)newDocument:(id)s { NSError *e = nil; if (![self openUntitledDocumentAndDisplay:YES error:&e] && e) [self presentError:e]; }
- (id)makeDocumentWithContentsOfURL:(NSURL *)u ofType:(NSString *)t error:(NSError **)e {
  Class c = [self documentClassForType:t];
  return c ? [[[c alloc] initWithContentsOfURL:u ofType:t error:e] autorelease] : nil; }
- (id)makeDocumentForURL:(NSURL *)u withContentsOfURL:(NSURL *)c ofType:(NSString *)t error:(NSError **)e {
  Class cl = [self documentClassForType:t];
  return cl ? [[[cl alloc] initForURL:u withContentsOfURL:c ofType:t error:e] autorelease] : nil; }
- (void)openDocumentWithContentsOfURL:(NSURL *)u display:(BOOL)display completionHandler:(void (^)(NSDocument *, BOOL, NSError *))h {
  NSDocument *d = [self documentForURL:u]; BOOL already = d != nil; NSError *e = nil;
  if (!d) {
    d = [self makeDocumentWithContentsOfURL:u ofType:[self typeForContentsOfURL:u error:NULL] error:&e];
    if (d) { [self addDocument:d]; if ([self shouldCreateUI]) [d makeWindowControllers]; [self noteNewRecentDocument:d]; } }
  if (d && display) [d showWindows];
  if (h) h(d, already, e); }
- (id)openDocumentWithContentsOfURL:(NSURL *)u display:(BOOL)display error:(NSError **)e {
  __block NSDocument *res = nil; __block NSError *err = nil;
  [self openDocumentWithContentsOfURL:u display:display completionHandler:^(NSDocument *d, BOOL a, NSError *x) { res = d; err = x; }];
  if (e) *e = err; return res; }
- (void)reopenDocumentForURL:(NSURL *)u withContentsOfURL:(NSURL *)c display:(BOOL)display completionHandler:(void (^)(NSDocument *, BOOL, NSError *))h {
  NSError *e = nil; NSDocument *d = [self makeDocumentForURL:u withContentsOfURL:c ofType:[self typeForContentsOfURL:c error:NULL] error:&e];
  if (d) { [self addDocument:d]; [d makeWindowControllers]; if (display) [d showWindows]; }
  if (h) h(d, NO, e); }
- (NSArray *)URLsFromRunningOpenPanel {
  NSOpenPanel *p = [NSOpenPanel openPanel]; [p setAllowsMultipleSelection:YES];
  return [self runModalOpenPanel:p forTypes:nil] == NSModalResponseOK ? [p URLs] : nil; }
- (NSInteger)runModalOpenPanel:(NSOpenPanel *)p forTypes:(NSArray *)t { return [p runModal]; }
- (void)beginOpenPanelWithCompletionHandler:(void (^)(NSArray *))h { if (h) h([self URLsFromRunningOpenPanel]); }
- (IBAction)openDocument:(id)s {
  for (NSURL *u in [self URLsFromRunningOpenPanel]) [self openDocumentWithContentsOfURL:u display:YES completionHandler:nil]; }
- (IBAction)saveAllDocuments:(id)s { for (NSDocument *d in [[_docs copy] autorelease]) if ([d isDocumentEdited]) [d saveDocument:s]; }
- (IBAction)clearRecentDocuments:(id)s { [_recent removeAllObjects]; }
- (void)noteNewRecentDocument:(NSDocument *)d { if ([d fileURL]) [self noteNewRecentDocumentURL:[d fileURL]]; }
- (void)noteNewRecentDocumentURL:(NSURL *)u { if (!u) return; [_recent removeObject:u]; [_recent insertObject:u atIndex:0]; while ([_recent count] > 10) [_recent removeLastObject]; }
- (NSArray *)recentDocumentURLs { return [[_recent copy] autorelease]; }
- (NSUInteger)maximumRecentDocumentCount { return 10; }
- (NSTimeInterval)autosavingDelay { return 0; } - (void)setAutosavingDelay:(NSTimeInterval)d {}
- (BOOL)allowsAutomaticShareMenu { return NO; }
- (void)closeAllDocumentsWithDelegate:(id)d didCloseAllSelector:(SEL)s contextInfo:(void *)ci {
  for (NSDocument *doc in [[_docs copy] autorelease]) [doc close];
  if (d && s) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(d, s, self, YES, ci); }
- (void)reviewUnsavedDocumentsWithAlertTitle:(NSString *)t cancellable:(BOOL)c delegate:(id)d didReviewAllSelector:(SEL)s contextInfo:(void *)ci {
  if (d && s) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(d, s, self, YES, ci); }
- (BOOL)presentError:(NSError *)e { NSLog(@"%@", e); return NO; }
- (NSError *)willPresentError:(NSError *)e { return e; }
- (BOOL)validateMenuItem:(NSMenuItem *)i { return YES; }
- (BOOL)validateUserInterfaceItem:(id)i { return YES; }
- (void)dealloc { if (g_doc_controller == self) g_doc_controller = nil; [_docs release]; [_recent release]; [_untitled release]; [_types release]; [super dealloc]; }
@end

/* ================================================================== NSWindowController document support */
@implementation NSWindowController (XEFDocument)
- (id)document { return objc_getAssociatedObject(self, "xef.document"); }
- (void)setDocument:(id)d {
  objc_setAssociatedObject(self, "xef.document", d, OBJC_ASSOCIATION_ASSIGN);
  if (d && [d respondsToSelector:@selector(windowControllers)] && ![[d windowControllers] containsObject:self]) [d addWindowController:self];
  if ([self isWindowLoaded]) [self synchronizeWindowTitleWithDocumentName]; }
- (id)owner { return _owner; }
- (NSString *)windowNibName { return _nibName; }
- (NSString *)windowNibPath { return [[NSBundle mainBundle] pathForResource:_nibName ofType:@"nib"]; }
- (BOOL)shouldCloseDocument { return [objc_getAssociatedObject(self, "xef.shouldClose") boolValue]; }
- (void)setShouldCloseDocument:(BOOL)f { objc_setAssociatedObject(self, "xef.shouldClose", @(f), OBJC_ASSOCIATION_RETAIN); }
- (BOOL)shouldCascadeWindows { return YES; } - (void)setShouldCascadeWindows:(BOOL)f {}
- (NSString *)windowFrameAutosaveName { return @""; } - (void)setWindowFrameAutosaveName:(NSString *)n {}
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)n { return n; }
- (void)synchronizeWindowTitleWithDocumentName {
  id d = [self document];
  if (d && _window) [_window setTitle:[self windowTitleForDocumentDisplayName:[d displayName]]]; }
- (void)setDocumentEdited:(BOOL)f { [_window setDocumentEdited:f]; }
- (IBAction)dismissController:(id)s { [self close]; }
@end

/* ================================================================== printing / workspace (minimal) */
@implementation NSPrintInfo
+ (NSPrintInfo *)sharedPrintInfo { static NSPrintInfo *p; if (!p) p = [[NSPrintInfo alloc] init]; return p; }
+ (void)setSharedPrintInfo:(NSPrintInfo *)p {}
- (id)init { if ((self = [super init])) _dict = [[NSMutableDictionary alloc] init]; return self; }
- (id)initWithDictionary:(NSDictionary *)d { if ((self = [self init])) [_dict addEntriesFromDictionary:d]; return self; }
- (id)copyWithZone:(NSZone *)z { return [[NSPrintInfo allocWithZone:z] initWithDictionary:_dict]; }
- (NSMutableDictionary *)dictionary { return _dict; }
- (NSSize)paperSize { return NSMakeSize(612, 792); } - (void)setPaperSize:(NSSize)s {}
- (NSString *)paperName { return @"na-letter"; }
- (NSInteger)orientation { return 0; } - (void)setOrientation:(NSInteger)o {}
- (CGFloat)leftMargin { return 72; } - (CGFloat)rightMargin { return 72; } - (CGFloat)topMargin { return 90; } - (CGFloat)bottomMargin { return 90; }
- (void)setLeftMargin:(CGFloat)m {} - (void)setRightMargin:(CGFloat)m {} - (void)setTopMargin:(CGFloat)m {} - (void)setBottomMargin:(CGFloat)m {}
- (NSRect)imageablePageBounds { return NSMakeRect(18, 18, 576, 756); }
- (NSInteger)horizontalPagination { return 0; } - (void)setHorizontalPagination:(NSInteger)p {}
- (NSInteger)verticalPagination { return 0; } - (void)setVerticalPagination:(NSInteger)p {}
- (BOOL)isHorizontallyCentered { return YES; } - (void)setHorizontallyCentered:(BOOL)f {}
- (BOOL)isVerticallyCentered { return YES; } - (void)setVerticallyCentered:(BOOL)f {}
- (CGFloat)scalingFactor { return 1; } - (void)setScalingFactor:(CGFloat)f {}
- (NSString *)jobDisposition { return NSPrintSpoolJob; } - (void)setJobDisposition:(NSString *)d {}
- (NSMutableDictionary *)printSettings { return _dict; }
- (void)setUpPrintOperationDefaultValues {}
- (void)updateFromPMPrintSettings {} - (void)updateFromPMPageFormat {}
- (BOOL)isSelectionOnly { return NO; } - (void)setSelectionOnly:(BOOL)f {}
- (void)encodeWithCoder:(NSCoder *)c {} - (id)initWithCoder:(NSCoder *)c { return [self init]; }
- (void)dealloc { [_dict release]; [super dealloc]; }
@end

/* printing is not available: operations "run" without output */
@implementation NSPrintOperation
+ (NSPrintOperation *)printOperationWithView:(NSView *)v printInfo:(NSPrintInfo *)p { return [[[self alloc] init] autorelease]; }
+ (NSPrintOperation *)printOperationWithView:(NSView *)v { return [[[self alloc] init] autorelease]; }
+ (NSPrintOperation *)PDFOperationWithView:(NSView *)v insideRect:(NSRect)r toData:(NSMutableData *)d printInfo:(NSPrintInfo *)p { return [[[self alloc] init] autorelease]; }
+ (NSPrintOperation *)currentOperation { return nil; }
- (BOOL)runOperation { NSLog(@"xef: printing is not supported"); return NO; }
- (void)runOperationModalForWindow:(NSWindow *)w delegate:(id)d didRunSelector:(SEL)s contextInfo:(void *)ci {
  BOOL ok = [self runOperation]; if (d && s) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(d, s, self, ok, ci); }
- (void)setShowsPrintPanel:(BOOL)f {} - (void)setShowsProgressPanel:(BOOL)f {} - (void)setJobTitle:(NSString *)t {}
- (NSPrintInfo *)printInfo { return [NSPrintInfo sharedPrintInfo]; } - (void)setPrintInfo:(NSPrintInfo *)p {}
- (id)printPanel { return nil; } - (NSView *)view { return nil; }
@end

@implementation NSWorkspace
+ (NSWorkspace *)sharedWorkspace { static NSWorkspace *w; if (!w) w = [[NSWorkspace alloc] init]; return w; }
- (NSNotificationCenter *)notificationCenter { static NSNotificationCenter *c; if (!c) c = [[NSNotificationCenter alloc] init]; return c; }
/* hands URLs and files to the host desktop (xdg-open, a Linux program run through the loader's exec path) */
- (BOOL)_xefXdgOpen:(NSString *)arg {
  if (!arg) return NO;
  pid_t pid; const char *argv[] = { "/usr/bin/xdg-open", [arg fileSystemRepresentation], NULL };
  return posix_spawn(&pid, argv[0], NULL, NULL, (char *const *)argv, NULL) == 0; }
- (BOOL)openURL:(NSURL *)u { return [self _xefXdgOpen:[u isFileURL] ? [u path] : [u absoluteString]]; }
- (void)openURL:(NSURL *)u configuration:(id)c completionHandler:(void (^)(id, NSError *))h { [self openURL:u]; if (h) h(nil, nil); }
- (BOOL)openFile:(NSString *)p { return [self _xefXdgOpen:p]; }
- (BOOL)selectFile:(NSString *)p inFileViewerRootedAtPath:(NSString *)r { return [self _xefXdgOpen:[p stringByDeletingLastPathComponent]]; }
- (void)activateFileViewerSelectingURLs:(NSArray *)u { if ([u count]) [self selectFile:[[u objectAtIndex:0] path] inFileViewerRootedAtPath:@""]; }
- (NSArray *)runningApplications { return @[[NSRunningApplication currentApplication]]; }
- (NSRunningApplication *)frontmostApplication { return [NSRunningApplication currentApplication]; }
- (NSRunningApplication *)menuBarOwningApplication { return [NSRunningApplication currentApplication]; }
- (BOOL)setIcon:(NSImage *)i forFile:(NSString *)p options:(NSUInteger)o { return NO; }
- (void)recycleURLs:(NSArray *)u completionHandler:(void (^)(NSDictionary *, NSError *))h { if (h) h(@{}, nil); }
- (BOOL)accessibilityDisplayShouldReduceMotion { return NO; } - (BOOL)accessibilityDisplayShouldReduceTransparency { return NO; }
- (BOOL)accessibilityDisplayShouldIncreaseContrast { return NO; } - (BOOL)accessibilityDisplayShouldDifferentiateWithoutColor { return NO; }
- (BOOL)accessibilityDisplayShouldInvertColors { return NO; } - (BOOL)isVoiceOverEnabled { return NO; } - (BOOL)isSwitchControlEnabled { return NO; }
@end

/* ---- NSWorkspace: type identifiers, volumes, applications, labels ---- */
typedef struct { const char *uti, *exts, *desc, *parent; } XEFType;
static const XEFType kTypes[] = {
  {"public.item", "", "item", ""}, {"public.data", "", "data", "public.item"}, {"public.content", "", "content", "public.item"},
  {"public.text", "", "text", "public.data"}, {"public.plain-text", "txt text", "text", "public.text"}, {"public.utf8-plain-text", "txt", "text", "public.plain-text"},
  {"public.html", "html htm", "HTML text", "public.text"}, {"public.xml", "xml", "XML text", "public.text"}, {"public.json", "json", "JSON", "public.text"},
  {"public.rtf", "rtf", "Rich Text Format (RTF)", "public.text"}, {"public.csv", "csv", "comma-separated values", "public.text"},
  {"public.source-code", "", "source code", "public.text"}, {"public.c-source", "c", "C source code", "public.source-code"}, {"public.objective-c-source", "m", "Objective-C source code", "public.source-code"},
  {"public.python-script", "py", "Python script", "public.source-code"}, {"public.shell-script", "sh", "shell script", "public.source-code"},
  {"public.image", "", "image", "public.data"}, {"public.png", "png", "PNG image", "public.image"}, {"public.jpeg", "jpeg jpg jpe", "JPEG image", "public.image"},
  {"public.tiff", "tiff tif", "TIFF image", "public.image"}, {"com.compuserve.gif", "gif", "GIF image", "public.image"}, {"com.microsoft.bmp", "bmp", "Windows bitmap image", "public.image"},
  {"public.heic", "heic", "HEIF image", "public.image"}, {"org.webmproject.webp", "webp", "WebP image", "public.image"}, {"public.svg-image", "svg", "SVG image", "public.image"},
  {"com.adobe.pdf", "pdf", "PDF document", "public.data"}, {"public.audio", "", "audio", "public.data"}, {"public.mp3", "mp3", "MP3 audio", "public.audio"},
  {"com.microsoft.waveform-audio", "wav", "Waveform audio", "public.audio"}, {"public.movie", "", "movie", "public.data"}, {"public.mpeg-4", "mp4", "MPEG-4 movie", "public.movie"},
  {"public.zip-archive", "zip", "ZIP archive", "public.data"}, {"public.folder", "", "folder", "public.directory"}, {"public.directory", "", "folder", "public.item"},
  {"public.symlink", "", "symbolic link", "public.item"}, {"com.apple.application-bundle", "app", "application", "public.directory"}, {"com.apple.bundle", "bundle", "bundle", "public.directory"},
  {NULL, NULL, NULL, NULL} };
static const XEFType *XEFTypeNamed(NSString *u) { for (const XEFType *t = kTypes; t->uti; t++) if (u && !strcmp(t->uti, [u UTF8String])) return t; return NULL; }
static const XEFType *XEFTypeForExt(NSString *e) {
  const char *x = [[e lowercaseString] UTF8String]; if (!x || !*x) return NULL;
  for (const XEFType *t = kTypes; t->uti; t++) { char buf[64]; strlcpy(buf, t->exts, sizeof buf); for (char *sv = NULL, *w = strtok_r(buf, " ", &sv); w; w = strtok_r(NULL, " ", &sv)) if (!strcmp(w, x)) return t; }
  return NULL; }
@implementation NSWorkspace (XEFTypes)
- (BOOL)type:(NSString *)a conformsToType:(NSString *)b {
  for (const XEFType *t = XEFTypeNamed(a); t; t = t->parent[0] ? XEFTypeNamed(@(t->parent)) : NULL) if (!strcmp(t->uti, [b UTF8String])) return YES;
  return [a isEqualToString:b]; }
- (NSString *)preferredFilenameExtensionForType:(NSString *)u { const XEFType *t = XEFTypeNamed(u); if (!t || !t->exts[0]) return nil; char buf[64]; strlcpy(buf, t->exts, sizeof buf); char *sp = strchr(buf, ' '); if (sp) *sp = 0; return @(buf); }
- (NSString *)localizedDescriptionForType:(NSString *)u { const XEFType *t = XEFTypeNamed(u); return t ? @(t->desc) : nil; }
- (BOOL)filenameExtension:(NSString *)e isValidForType:(NSString *)u { const XEFType *t = XEFTypeForExt(e), *want = XEFTypeNamed(u); return t && want && (t == want || [self type:@(t->uti) conformsToType:u]); }
- (NSString *)typeOfFile:(NSString *)p error:(NSError **)err {
  BOOL dir = NO; NSFileManager *fm = [NSFileManager defaultManager];
  struct stat st; if (p && lstat([p fileSystemRepresentation], &st) == 0 && S_ISLNK(st.st_mode)) return @"public.symlink";
  if (![fm fileExistsAtPath:p isDirectory:&dir]) { if (err) *err = [NSError errorWithDomain:NSCocoaErrorDomain code:260 userInfo:@{ NSFilePathErrorKey: p ?: @"" }]; return nil; }
  const XEFType *t = XEFTypeForExt([p pathExtension]);
  if (dir) return t && [self type:@(t->uti) conformsToType:@"public.directory"] ? @(t->uti) : @"public.folder";
  return t ? @(t->uti) : @"public.data"; }
- (BOOL)isFilePackageAtPath:(NSString *)p { BOOL d = NO; if (![[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&d] || !d) return NO; return [@[@"app", @"bundle", @"framework", @"plugin", @"rtfd", @"kext", @"xpc"] containsObject:[[p pathExtension] lowercaseString]]; }
- (NSArray *)fileLabels { return @[@"None", @"Gray", @"Green", @"Purple", @"Blue", @"Yellow", @"Red", @"Orange"]; }
- (NSArray *)fileLabelColors {
  return @[[NSColor clearColor], [NSColor colorWithRed:.66 green:.66 blue:.66 alpha:1], [NSColor colorWithRed:.4 green:.8 blue:.3 alpha:1], [NSColor colorWithRed:.7 green:.4 blue:.8 alpha:1],
           [NSColor colorWithRed:.2 green:.5 blue:.95 alpha:1], [NSColor colorWithRed:.95 green:.8 blue:.2 alpha:1], [NSColor colorWithRed:.95 green:.3 blue:.3 alpha:1], [NSColor colorWithRed:.95 green:.6 blue:.2 alpha:1]]; }
/* volumes come from /proc/mounts: the root and every device-backed mount point */
- (NSArray *)_xefMounts {
  NSMutableArray *r = [NSMutableArray array]; NSString *t = [NSString stringWithContentsOfFile:@"/proc/mounts" encoding:NSUTF8StringEncoding error:NULL];
  for (NSString *line in [t componentsSeparatedByString:@"\n"]) { NSArray *f = [line componentsSeparatedByString:@" "]; if ([f count] >= 3) [r addObject:@{ @"dev": f[0], @"path": [f[1] stringByReplacingOccurrencesOfString:@"\\040" withString:@" "], @"type": f[2] }]; }
  return r; }
- (NSArray *)mountedLocalVolumePaths {
  NSMutableArray *r = [NSMutableArray arrayWithObject:@"/"];
  for (NSDictionary *m in [self _xefMounts]) if ([m[@"dev"] hasPrefix:@"/dev/"] && ![r containsObject:m[@"path"]]) [r addObject:m[@"path"]];
  return r; }
- (NSArray *)mountedRemovableMedia { return @[]; }
- (BOOL)getFileSystemInfoForPath:(NSString *)path isRemovable:(BOOL *)rem isWritable:(BOOL *)wr isUnmountable:(BOOL *)un description:(NSString **)d type:(NSString **)t {
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;
  NSString *best = @"/"; NSDictionary *bm = nil; NSString *full = [path stringByStandardizingPath];
  for (NSDictionary *m in [self _xefMounts]) { NSString *mp = m[@"path"]; if (([full isEqualToString:mp] || [full hasPrefix:[mp hasSuffix:@"/"] ? mp : [mp stringByAppendingString:@"/"]]) && [mp length] >= [best length]) { best = mp; bm = m; } }
  if (rem) *rem = NO; if (wr) *wr = access([path fileSystemRepresentation], W_OK) == 0; if (un) *un = ![best isEqualToString:@"/"];
  if (d) *d = bm[@"type"] ?: @"local"; if (t) *t = bm[@"type"] ?: @"local"; return YES; }
- (BOOL)unmountAndEjectDeviceAtPath:(NSString *)p { return NO; }
- (BOOL)unmountAndEjectDeviceAtURL:(NSURL *)u error:(NSError **)e { if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:3328 userInfo:nil]; return NO; }
/* applications are the .app bundles of /Applications and ~/Applications */
- (NSArray *)_xefApps {
  NSMutableArray *r = [NSMutableArray array];
  for (NSString *dir in @[@"/Applications", [NSHomeDirectory() stringByAppendingPathComponent:@"Applications"]])
    for (NSString *n in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) if ([[n pathExtension] isEqualToString:@"app"]) [r addObject:[dir stringByAppendingPathComponent:n]];
  return r; }
- (NSArray *)URLsForApplicationsWithBundleIdentifier:(NSString *)b {
  NSMutableArray *r = [NSMutableArray array];
  for (NSString *p in [self _xefApps]) if ([[[NSBundle bundleWithPath:p] bundleIdentifier] isEqualToString:b]) [r addObject:[NSURL fileURLWithPath:p]];
  return r; }
- (NSURL *)URLForApplicationWithBundleIdentifier:(NSString *)b { return [[self URLsForApplicationsWithBundleIdentifier:b] firstObject]; }
- (NSString *)absolutePathForAppBundleWithIdentifier:(NSString *)b { return [[[self URLsForApplicationsWithBundleIdentifier:b] firstObject] path]; }
- (NSString *)fullPathForApplication:(NSString *)n {
  NSString *want = [[n pathExtension] length] ? n : [n stringByAppendingPathExtension:@"app"];
  for (NSString *p in [self _xefApps]) if ([[p lastPathComponent] caseInsensitiveCompare:want] == NSOrderedSame) return p;
  return nil; }
- (NSURL *)URLForApplicationToOpenURL:(NSURL *)u { return nil; }
- (NSArray *)URLsForApplicationsToOpenURL:(NSURL *)u { return @[]; } - (NSArray *)URLsForApplicationsToOpenContentType:(id)t { return @[]; } - (NSURL *)URLForApplicationToOpenContentType:(id)t { return nil; }
- (BOOL)launchApplication:(NSString *)n { NSString *p = [self fullPathForApplication:n]; return p ? [self openFile:p] : NO; }
- (BOOL)openFile:(NSString *)p withApplication:(NSString *)a { return [self openFile:p]; }
- (BOOL)openFile:(NSString *)p withApplication:(NSString *)a andDeactivate:(BOOL)d { return [self openFile:p]; }
- (void)openURLs:(NSArray *)urls withApplicationAtURL:(NSURL *)app configuration:(id)c completionHandler:(void (^)(id, NSError *))h { for (NSURL *u in urls) [self openURL:u]; if (h) h(nil, nil); }
- (void)openApplicationAtURL:(NSURL *)app configuration:(id)c completionHandler:(void (^)(id, NSError *))h { if (h) h(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:256 userInfo:nil]); }
- (BOOL)openURLs:(NSArray *)urls withAppBundleIdentifier:(NSString *)b options:(NSUInteger)o additionalEventParamDescriptor:(id)d launchIdentifiers:(NSArray **)ids { for (NSURL *u in urls) [self openURL:u]; return YES; }
- (void)hideOtherApplications { } - (void)noteFileSystemChanged:(NSString *)p {} - (void)noteFileSystemChanged {} - (void)showSearchResultsForQueryString:(NSString *)q {}
- (NSDictionary *)activeApplication { return @{ @"NSApplicationName": [[NSProcessInfo processInfo] processName], @"NSApplicationProcessIdentifier": @([[NSProcessInfo processInfo] processIdentifier]) }; }
- (NSArray *)launchedApplications { return @[[self activeApplication]]; }
- (void)duplicateURLs:(NSArray *)urls completionHandler:(void (^)(NSDictionary *, NSError *))h {
  NSMutableDictionary *m = [NSMutableDictionary dictionary]; NSError *err = nil; NSFileManager *fm = [NSFileManager defaultManager];
  for (NSURL *u in urls) {
    NSString *p = [u path], *base = [p stringByDeletingPathExtension], *ext = [p pathExtension], *dst = nil;
    for (int i = 1; i < 1000; i++) { dst = [NSString stringWithFormat:@"%@ copy%@%@", base, i > 1 ? [NSString stringWithFormat:@" %d", i] : @"", [ext length] ? [@"." stringByAppendingString:ext] : @""]; if (![fm fileExistsAtPath:dst]) break; }
    if ([fm copyItemAtPath:p toPath:dst error:&err]) m[u] = [NSURL fileURLWithPath:dst]; else break; }
  if (h) h(m, err); }
- (NSURL *)desktopImageURLForScreen:(NSScreen *)s { return objc_getAssociatedObject(self, "xef.desktop"); }
- (BOOL)setDesktopImageURL:(NSURL *)u forScreen:(NSScreen *)s options:(NSDictionary *)o error:(NSError **)e { objc_setAssociatedObject(self, "xef.desktop", u, OBJC_ASSOCIATION_RETAIN); return YES; }
- (NSDictionary *)desktopImageOptionsForScreen:(NSScreen *)s { return @{}; }
/* icons: a drawn generic page / folder badge (size 32 like AppKit's file icons) */
- (NSImage *)_xefIconForKind:(int)kind label:(NSString *)label {
  NSImage *i = [[[NSImage alloc] initWithSize:NSMakeSize(32, 32)] autorelease]; [i lockFocus];
  if (kind == 1) { [[NSColor colorWithRed:.35 green:.65 blue:.95 alpha:1] setFill]; NSRectFill(NSMakeRect(2, 4, 28, 22)); [[NSColor colorWithRed:.25 green:.55 blue:.9 alpha:1] setFill]; NSRectFill(NSMakeRect(2, 22, 12, 6)); }
  else { [[NSColor whiteColor] setFill]; NSRectFill(NSMakeRect(6, 2, 20, 28)); [[NSColor grayColor] setStroke]; NSFrameRect(NSMakeRect(6, 2, 20, 28)); }
  [i unlockFocus]; return i; }
- (NSImage *)iconForFile:(NSString *)p { BOOL d = NO; [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&d]; return [self _xefIconForKind:d ? 1 : 0 label:[p pathExtension]]; }
- (NSImage *)iconForFiles:(NSArray *)fs { return [self iconForFile:[fs firstObject]]; }
- (NSImage *)iconForFileType:(NSString *)t { return [self _xefIconForKind:[t isEqualToString:@"public.folder"] ? 1 : 0 label:t]; }
- (NSImage *)iconForContentType:(id)t { return [self iconForFileType:[t respondsToSelector:@selector(identifier)] ? [t identifier] : nil]; }
@end
