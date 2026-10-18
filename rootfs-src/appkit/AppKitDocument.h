/* AppKit-lite document architecture (AppKitDocument.m). */
#import "AppKitLite.h"

@class NSWindowController, NSPrintInfo, NSPrintOperation, NSSavePanel;

@interface NSDocument : NSObject {
@public
  NSMutableArray *_wcs; NSURL *_url; NSString *_type, *_displayName; NSDate *_date; NSUndoManager *_undo; NSPrintInfo *_printInfo;
  NSInteger _changes; BOOL _hasUndo; NSWindowController *_loadingWC;
}
- (id)initWithType:(NSString *)t error:(NSError **)e;
- (NSURL *)fileURL; - (void)setFileURL:(NSURL *)u; - (NSString *)fileType; - (void)setFileType:(NSString *)t;
- (NSString *)displayName; - (NSArray *)windowControllers; - (void)addWindowController:(NSWindowController *)wc;
- (void)makeWindowControllers; - (void)showWindows; - (void)close; - (void)saveDocument:(id)s;
- (BOOL)readFromURL:(NSURL *)u ofType:(NSString *)t error:(NSError **)e; - (BOOL)isDocumentEdited;
- (void)setFileModificationDate:(NSDate *)d; - (void)updateChangeCount:(NSInteger)c; - (NSUndoManager *)undoManager;
- (void)windowControllerWillLoadNib:(NSWindowController *)wc; - (void)windowControllerDidLoadNib:(NSWindowController *)wc;
- (void)_xefSetLoadingWindowController:(NSWindowController *)wc;
@end

@interface NSDocumentController : NSObject {
@public
  NSMutableArray *_docs, *_recent, *_untitled; NSArray *_types;
}
+ (id)sharedDocumentController;
- (NSString *)defaultType; - (NSArray *)_xefTypesForClass:(Class)c; - (NSUInteger)_xefUntitledNumberFor:(NSDocument *)d;
- (void)addDocument:(NSDocument *)d; - (void)removeDocument:(NSDocument *)d; - (id)documentForWindow:(NSWindow *)w;
- (void)noteNewRecentDocument:(NSDocument *)d; - (void)noteNewRecentDocumentURL:(NSURL *)u; - (BOOL)shouldCreateUI;
- (NSInteger)runModalOpenPanel:(NSOpenPanel *)p forTypes:(NSArray *)t; - (void)openDocumentWithContentsOfURL:(NSURL *)u display:(BOOL)d completionHandler:(void (^)(NSDocument *, BOOL, NSError *))h;
- (BOOL)presentError:(NSError *)e;
@end

@interface NSWindowController : NSResponder {
@public
  NSWindow *_window; id _content; id _storyboard; NSString *_nibName; id _owner; BOOL _loaded;
}
- (id)initWithWindowNibName:(NSString *)n owner:(id)o; - (NSWindow *)window; - (void)setWindow:(NSWindow *)w;
- (void)showWindow:(id)s; - (void)close; - (BOOL)isWindowLoaded; - (id)document; - (void)setDocument:(id)d;
- (void)synchronizeWindowTitleWithDocumentName;
@end

@interface NSWindow (XEFDocument)
- (id)windowController; - (void)setDocumentEdited:(BOOL)f;
@end

@interface NSPrintInfo : NSObject <NSCopying, NSCoding> { NSMutableDictionary *_dict; }
+ (NSPrintInfo *)sharedPrintInfo;
@end
@interface NSPrintOperation : NSObject
@end
@interface NSWorkspace : NSObject
@end
