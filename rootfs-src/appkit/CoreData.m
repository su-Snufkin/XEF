/*
 * CoreData implementation for XEF
 * Based on Darling / Apple CoreData specifications
 */

#import <Foundation/Foundation.h>

NSString *const NSAffectedObjectsErrorKey = @"NSAffectedObjectsErrorKey";
NSString *const NSAffectedStoresErrorKey = @"NSAffectedStoresErrorKey";
NSString *const NSDeletedObjectsKey = @"NSDeletedObjectsKey";
NSString *const NSDetailedErrorsKey = @"NSDetailedErrorsKey";
NSString *const NSInferMappingModelAutomaticallyOption = @"NSInferMappingModelAutomaticallyOption";
NSString *const NSInsertedObjectsKey = @"NSInsertedObjectsKey";
NSString *const NSInvalidatedObjectsKey = @"NSInvalidatedObjectsKey";
NSString *const NSManagedObjectContextDidSaveNotification = @"NSManagedObjectContextDidSaveNotification";
NSString *const NSMergeByPropertyStoreTrumpMergePolicy = @"NSMergeByPropertyStoreTrumpMergePolicy";
NSString *const NSMigratePersistentStoresAutomaticallyOption = @"NSMigratePersistentStoresAutomaticallyOption";
NSString *const NSOverwriteMergePolicy = @"NSOverwriteMergePolicy";
NSString *const NSPersistentStoreSaveConflictsErrorKey = @"NSPersistentStoreSaveConflictsErrorKey";
NSString *const NSRefreshedObjectsKey = @"NSRefreshedObjectsKey";
NSString *const NSRollbackMergePolicy = @"NSRollbackMergePolicy";
NSString *const NSSQLiteStoreType = @"NSSQLiteStoreType";
NSString *const NSStoreModelVersionHashesKey = @"NSStoreModelVersionHashesKey";
NSString *const NSUpdatedObjectsKey = @"NSUpdatedObjectsKey";
NSString *const NSValidationKeyErrorKey = @"NSValidationKeyErrorKey";
NSString *const NSValidationObjectErrorKey = @"NSValidationObjectErrorKey";
NSString *const NSValidationPredicateErrorKey = @"NSValidationPredicateErrorKey";
NSString *const NSValidationValueErrorKey = @"NSValidationValueErrorKey";
NSString *const NSXMLStoreType = @"NSXMLStoreType";

#define XEF_CD_STUB(name) \
@interface name : NSObject @end \
@implementation name \
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector { \
    return [NSMethodSignature signatureWithObjCTypes: "v@:"]; \
} \
- (void)forwardInvocation:(NSInvocation *)anInvocation { \
    /* no-op stub forwarder */ \
} \
@end

XEF_CD_STUB(NSPropertyDescription)
XEF_CD_STUB(NSAttributeDescription)
XEF_CD_STUB(NSEntityDescription)
XEF_CD_STUB(NSEntityMapping)
XEF_CD_STUB(NSFetchRequest)
XEF_CD_STUB(NSFetchRequestExpression)
XEF_CD_STUB(NSFetchedPropertyDescription)
XEF_CD_STUB(NSManagedObject)
XEF_CD_STUB(NSManagedObjectContext)
XEF_CD_STUB(NSManagedObjectID)
XEF_CD_STUB(NSManagedObjectModel)
XEF_CD_STUB(NSMappingModel)
XEF_CD_STUB(NSPersistentStoreCoordinator)
XEF_CD_STUB(NSPropertyMapping)
XEF_CD_STUB(_NSPersistenceUtilities)

