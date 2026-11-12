// NSRuleEditor: rows from delegate criteria, nesting, display values, predicate, selection, defaults. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface D : NSObject <NSRuleEditorDelegate> { @public int calls; } @end
@implementation D
- (NSInteger)ruleEditor:(NSRuleEditor *)e numberOfChildrenForCriterion:(id)c withRowType:(NSRuleEditorRowType)t {
  if (c == nil) return 2; if ([c isEqual:@"name"]) return 2; return 0; }
- (id)ruleEditor:(NSRuleEditor *)e child:(NSInteger)i forCriterion:(id)c withRowType:(NSRuleEditorRowType)t {
  if (c == nil) return i == 0 ? @"name" : @"size"; if ([c isEqual:@"name"]) return i == 0 ? @"contains" : @"is"; return nil; }
- (id)ruleEditor:(NSRuleEditor *)e displayValueForCriterion:(id)c inRow:(NSInteger)r { calls++; return c; }
- (NSDictionary *)ruleEditor:(NSRuleEditor *)e predicatePartsForCriterion:(id)c withDisplayValue:(id)v inRow:(NSInteger)r {
  if ([c isEqual:@"name"]) return @{ NSRuleEditorPredicateLeftExpression: [NSExpression expressionForKeyPath:@"name"] };
  if ([c isEqual:@"contains"]) return @{ NSRuleEditorPredicateOperatorType: @(NSContainsPredicateOperatorType), NSRuleEditorPredicateRightExpression: [NSExpression expressionForConstantValue:@"x"] };
  return nil; }
@end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSRuleEditor *e = [[NSRuleEditor alloc] initWithFrame:NSMakeRect(0, 0, 500, 200)];
  P("defaults: nesting %ld rowHeight %g editable %d canRemoveAll %d rows %ld delegate nil %d rowClass %s\n", (long)e.nestingMode, e.rowHeight, e.isEditable, e.canRemoveAllRows, (long)e.numberOfRows, e.delegate == nil, [NSStringFromClass(e.rowClass) UTF8String]);
  P("keypaths: %s %s %s %s\n", [e.rowTypeKeyPath UTF8String], [e.subrowsKeyPath UTF8String], [e.criteriaKeyPath UTF8String], [e.displayValuesKeyPath UTF8String]);
  D *d = [D new]; e.delegate = d;
  [e reloadCriteria]; P("after reload: rows %ld\n", (long)e.numberOfRows);
  [e addRow:nil]; P("after addRow: rows %ld\n", (long)e.numberOfRows);
  P("row0: type %ld parent %ld criteria %s display %s subrows %lu\n", (long)[e rowTypeForRow:0], (long)[e parentRowForRow:0], [[[e criteriaForRow:0] componentsJoinedByString:@"|"] UTF8String], [[[e displayValuesForRow:0] componentsJoinedByString:@"|"] UTF8String], (unsigned long)[e subrowIndexesForRow:0].count);
  [e insertRowAtIndex:1 withType:NSRuleEditorRowTypeCompound asSubrowOfRow:-1 animate:NO]; P("after insert compound: rows %ld type1 %ld\n", (long)e.numberOfRows, (long)[e rowTypeForRow:1]);
  [e insertRowAtIndex:2 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:1 animate:NO]; P("after subrow: rows %ld parent2 %ld subrows(1) %lu\n", (long)e.numberOfRows, (long)[e parentRowForRow:2], (unsigned long)[e subrowIndexesForRow:1].count);
  [e setCriteria:@[@"size"] andDisplayValues:@[@"size"] forRowAtIndex:0]; P("set criteria row0: %s\n", [[[e criteriaForRow:0] componentsJoinedByString:@"|"] UTF8String]);
  [e selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO]; P("selected %lu first %lu\n", (unsigned long)e.selectedRowIndexes.count, (unsigned long)e.selectedRowIndexes.firstIndex);
  [e removeRowAtIndex:2]; P("after remove: rows %ld\n", (long)e.numberOfRows);
  [e removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:1] includeSubrows:YES]; P("after remove compound: rows %ld\n", (long)e.numberOfRows);
  e.nestingMode = NSRuleEditorNestingModeSimple; P("nesting now %ld\n", (long)e.nestingMode);
  e.editable = NO; e.rowHeight = 30; P("editable %d rowHeight %g\n", e.isEditable, e.rowHeight);
  P("predicate nil %d\n", e.predicate == nil);
  P("PASS appkit_ruleeditor\n");
  fflush(stdout); _exit(0);
} return 0; }
