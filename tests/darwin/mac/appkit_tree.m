// NSTreeController / NSTreeNode: tree built from a childrenKeyPath, index paths, selection, edits. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *path(NSIndexPath *p) { NSMutableArray *a = [NSMutableArray array]; for (NSUInteger i = 0; i < p.length; i++) [a addObject:@([p indexAtPosition:i])]; return [[NSString stringWithFormat:@"[%@]", [a componentsJoinedByString:@","]] UTF8String]; }
static void dump(NSTreeNode *n, int depth) {
  for (NSTreeNode *k in n.childNodes) {
    P("%*s%s leaf=%d path=%s parent=%d\n", depth * 2, "", [[k.representedObject valueForKey:@"name"] UTF8String], k.isLeaf, path(k.indexPath), depth == 0 ? -1 : k.parentNode == n);
    dump(k, depth + 1); } }
static NSMutableDictionary *node(NSString *name, NSArray *kids) { return [NSMutableDictionary dictionaryWithObjectsAndKeys:name, @"name", [NSMutableArray arrayWithArray:kids ?: @[]], @"children", nil]; }
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSMutableDictionary *a1 = node(@"a1", nil), *a2 = node(@"a2", nil), *a = node(@"a", @[a1, a2]), *b = node(@"b", nil), *c1 = node(@"c1", nil), *c = node(@"c", @[c1]);
  NSTreeController *t = [[NSTreeController alloc] initWithContent:[NSMutableArray arrayWithObjects:a, b, c, nil]];
  t.childrenKeyPath = @"children";
  P("childrenKeyPath %s\n", [t.childrenKeyPath UTF8String]);
  NSTreeNode *root = t.arrangedObjects;
  P("root children %lu, root path %s, root rep %d\n", (unsigned long)root.childNodes.count, path(root.indexPath), root.representedObject == nil);
  dump(root, 0);
  NSTreeNode *n = [root descendantNodeAtIndexPath:[NSIndexPath indexPathWithIndexes:(NSUInteger[]){0, 1} length:2]];
  P("descendant [0,1] = %s\n", [[n.representedObject valueForKey:@"name"] UTF8String]);
  P("out of range %d\n", [root descendantNodeAtIndexPath:[NSIndexPath indexPathWithIndexes:(NSUInteger[]){5} length:1]] == nil);
  P("== selection\n");
  P("initial selection %lu\n", (unsigned long)t.selectionIndexPaths.count);
  BOOL ok = [t setSelectionIndexPath:[NSIndexPath indexPathWithIndexes:(NSUInteger[]){0, 0} length:2]];
  P("set ok %d selectedObjects %lu first %s selectionIndexPath %s\n", ok, (unsigned long)t.selectedObjects.count, [[[t.selectedObjects firstObject] valueForKey:@"name"] UTF8String], path(t.selectionIndexPath));
  P("selectedNodes %lu\n", (unsigned long)t.selectedNodes.count);
  ok = [t setSelectionIndexPath:[NSIndexPath indexPathWithIndexes:(NSUInteger[]){9} length:1]];
  P("invalid set ok %d selection %s\n", ok, path(t.selectionIndexPath));
  [t setSelectionIndexPaths:@[[NSIndexPath indexPathWithIndex:1], [NSIndexPath indexPathWithIndex:2]]];
  P("multi selection %lu\n", (unsigned long)t.selectionIndexPaths.count);
  P("== edits\n");
  [t setSelectionIndexPath:[NSIndexPath indexPathWithIndex:1]];
  [t insertObject:node(@"d", nil) atArrangedObjectIndexPath:[NSIndexPath indexPathWithIndex:1]];
  P("after insert: top %lu, a children %lu\n", (unsigned long)t.arrangedObjects.childNodes.count, (unsigned long)[[a valueForKey:@"children"] count]);
  dump(t.arrangedObjects, 0);
  P("selection after insert %s\n", path(t.selectionIndexPath));
  [t removeObjectAtArrangedObjectIndexPath:[NSIndexPath indexPathWithIndex:1]];
  P("after remove: top %lu\n", (unsigned long)t.arrangedObjects.childNodes.count);
  [t insertObject:node(@"a3", nil) atArrangedObjectIndexPath:[NSIndexPath indexPathWithIndexes:(NSUInteger[]){0, 2} length:2]];
  P("a children %lu\n", (unsigned long)[[a valueForKey:@"children"] count]);
  [t removeObjectsAtArrangedObjectIndexPaths:@[[NSIndexPath indexPathWithIndexes:(NSUInteger[]){0, 0} length:2], [NSIndexPath indexPathWithIndexes:(NSUInteger[]){0, 2} length:2]]];
  P("a children after removing two: %s\n", [[[[a valueForKey:@"children"] valueForKey:@"name"] componentsJoinedByString:@","] UTF8String]);
  P("== sorting\n");
  t.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:NO]];
  for (NSTreeNode *k in t.arrangedObjects.childNodes) P("%s ", [[k.representedObject valueForKey:@"name"] UTF8String]);
  P("\n");
  t.sortDescriptors = nil;
  P("== node\n");
  NSTreeNode *tn = [NSTreeNode treeNodeWithRepresentedObject:@"x"];
  P("standalone: rep %s children %lu leaf %d parent %d path %s\n", [tn.representedObject UTF8String], (unsigned long)tn.childNodes.count, tn.isLeaf, tn.parentNode == nil, path(tn.indexPath));
  NSTreeNode *tc = [NSTreeNode treeNodeWithRepresentedObject:@"y"];
  [tn.mutableChildNodes addObject:tc];
  P("after add: children %lu leaf %d child parent %d child path %s\n", (unsigned long)tn.childNodes.count, tn.isLeaf, tc.parentNode == tn, path(tc.indexPath));
  P("flags: preserves %d selectsInserted %d avoidsEmpty %d\n", t.preservesSelection, t.selectsInsertedObjects, t.avoidsEmptySelection);
  P("PASS appkit_tree\n");
} return 0; }
