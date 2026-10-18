#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>

OSStatus PasteboardCreate(CFStringRef inName, PasteboardRef *outPasteboard) {
  if (outPasteboard) {
    *outPasteboard = (PasteboardRef)CFRetain(inName ? (CFTypeRef)inName : (CFTypeRef)CFSTR("com.apple.pasteboard.clipboard"));
  }
  return noErr;
}

OSStatus PasteboardClear(PasteboardRef inPasteboard) {
  (void)inPasteboard;
  return noErr;
}

PasteboardSyncFlags PasteboardSynchronize(PasteboardRef inPasteboard) {
  (void)inPasteboard;
  return 0;
}

OSStatus PasteboardGetItemCount(PasteboardRef inPasteboard, ItemCount *outItemCount) {
  (void)inPasteboard;
  if (outItemCount) *outItemCount = 0;
  return noErr;
}

OSStatus PasteboardGetItemIdentifier(PasteboardRef inPasteboard, CFIndex inIndex, PasteboardItemID *outItem) {
  (void)inPasteboard; (void)inIndex;
  if (outItem) *outItem = (PasteboardItemID)(uintptr_t)1;
  return noErr;
}

OSStatus PasteboardCopyItemFlavors(PasteboardRef inPasteboard, PasteboardItemID inItem, CFArrayRef *outFlavors) {
  (void)inPasteboard; (void)inItem;
  if (outFlavors) *outFlavors = CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
  return noErr;
}

OSStatus PasteboardCopyItemFlavorData(PasteboardRef inPasteboard, PasteboardItemID inItem, CFStringRef inFlavor, CFDataRef *outData) {
  (void)inPasteboard; (void)inItem; (void)inFlavor;
  if (outData) *outData = NULL;
  return -25102; /* badPasteboardFlavorErr */
}

OSStatus PasteboardPutItemFlavor(PasteboardRef inPasteboard, PasteboardItemID inItem, CFStringRef inFlavor, CFDataRef inData, PasteboardFlavorFlags inFlags) {
  (void)inPasteboard; (void)inItem; (void)inFlavor; (void)inData; (void)inFlags;
  return noErr;
}

OSStatus PasteboardResolvePromises(PasteboardRef inPasteboard) {
  (void)inPasteboard;
  return noErr;
}

OSStatus PasteboardSetPromiseKeeper(PasteboardRef inPasteboard, PasteboardPromiseKeeperProcPtr inPromiseKeeper, void *inContext) {
  (void)inPasteboard; (void)inPromiseKeeper; (void)inContext;
  return noErr;
}

OSStatus PasteboardCopyName(PasteboardRef inPasteboard, CFStringRef *outName) {
  if (outName) *outName = CFSTR("com.apple.pasteboard.clipboard");
  return noErr;
}

OSStatus PasteboardGetItemFlavorFlags(PasteboardRef inPasteboard, PasteboardItemID inItem, CFStringRef inFlavor, PasteboardFlavorFlags *outFlags) {
  (void)inPasteboard; (void)inItem; (void)inFlavor;
  if (outFlags) *outFlags = 0;
  return noErr;
}
