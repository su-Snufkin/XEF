// NSIndexSet / NSMutableIndexSet: order of enumeration, merging of ranges, shifting, counting.
#import <Foundation/Foundation.h>
static const char *IS(NSIndexSet *s) {
  NSMutableArray *a = [NSMutableArray array];
  [s enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [a addObject:@(i)]; }];
  NSMutableArray *r = [NSMutableArray array];
  [s enumerateRangesUsingBlock:^(NSRange g, BOOL *stop) { [r addObject:[NSString stringWithFormat:@"%lu+%lu", (unsigned long)g.location, (unsigned long)g.length]]; }];
  return [[NSString stringWithFormat:@"[%@] ranges %@ count %lu first %ld last %ld", [a componentsJoinedByString:@","], [r componentsJoinedByString:@" "], (unsigned long)s.count,
           (long)(s.count ? s.firstIndex : -1), (long)(s.count ? s.lastIndex : -1)] UTF8String]; }
int main(void) {
  @autoreleasepool {
    NSMutableIndexSet *s = [NSMutableIndexSet indexSet];
    [s addIndex:1]; [s addIndex:3]; printf("1,3: %s\n", IS(s));
    [s addIndex:0]; printf("+0: %s\n", IS(s));
    [s addIndex:4]; printf("+4: %s\n", IS(s));
    [s addIndex:2]; printf("+2 (merges all): %s\n", IS(s));
    [s removeIndex:2]; printf("-2: %s\n", IS(s));
    NSMutableIndexSet *t = [NSMutableIndexSet indexSetWithIndex:10]; [t addIndex:7]; [t addIndex:8];
    printf("10,7,8: %s\n", IS(t));
    [s addIndexes:t]; printf("union: %s\n", IS(s));
    NSMutableIndexSet *u = [NSMutableIndexSet indexSetWithIndex:1]; [u addIndex:3];
    NSMutableIndexSet *v = [NSMutableIndexSet indexSetWithIndex:0]; [v addIndex:4];
    [u addIndexes:v]; printf("{1,3}+{0,4}: %s\n", IS(u));
    [u addIndexesInRange:NSMakeRange(2, 5)]; printf("+range 2..6: %s\n", IS(u));
    [u removeIndexesInRange:NSMakeRange(3, 2)]; printf("-range 3..4: %s\n", IS(u));
    [u shiftIndexesStartingAtIndex:2 by:3]; printf("shift from 2 by 3: %s\n", IS(u));
    [u shiftIndexesStartingAtIndex:6 by:-2]; printf("shift from 6 by -2: %s\n", IS(u));
    [u removeIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]]; printf("-{0,1}: %s\n", IS(u));
    printf("contains 5 %d, 9 %d, range 5+2 %d, intersects 0+6 %d\n", [u containsIndex:5], [u containsIndex:9], [u containsIndexesInRange:NSMakeRange(5, 2)], [u intersectsIndexesInRange:NSMakeRange(0, 6)]);
    printf("greater than 5: %ld, less than 5: %ld, >= 100: %d\n", (long)[u indexGreaterThanIndex:5], (long)[u indexLessThanIndex:5], [u indexGreaterThanOrEqualToIndex:100] == NSNotFound);
    printf("count in 0+7: %lu\n", (unsigned long)[u countOfIndexesInRange:NSMakeRange(0, 7)]);
    NSIndexSet *c = [u copy]; NSMutableIndexSet *m = [u mutableCopy]; [m addIndex:50];
    printf("copy equal %d, mutable copy differs %d\n", [c isEqualToIndexSet:u], ![m isEqualToIndexSet:u]);
    NSMutableArray *rev = [NSMutableArray array];
    [m enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger i, BOOL *stop) { [rev addObject:@(i)]; }];
    printf("reverse %s\n", [[rev componentsJoinedByString:@","] UTF8String]);
    NSUInteger buf[8]; NSRange rg = NSMakeRange(0, 100); NSUInteger n = [m getIndexes:buf maxCount:8 inIndexRange:&rg];
    printf("getIndexes %lu first %lu\n", (unsigned long)n, (unsigned long)(n ? buf[0] : 0));
    NSIndexSet *p = [m indexesPassingTest:^BOOL(NSUInteger i, BOOL *stop) { return i % 2 == 0; }]; printf("even: %s\n", IS(p));
    [m removeAllIndexes]; printf("empty: %s\n", IS(m));
  }
  return 0;
}
