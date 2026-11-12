// NSIndexSet / NSMutableIndexSet for the rootfs Foundation, in place of darling-foundation's src/NSIndexSet.m, whose
// range list is not kept sorted (count, lastIndex, containsIndex: and the enumeration order go wrong as soon as an
// index is added below an existing one). Reference: tests/darwin/mac/indexset.m.
//
// The set is an array of ranges kept sorted, disjoint and not adjacent. It lives behind the first pointer of the
// instance-variable union declared in darling-foundation's NSIndexSet.h, so the object layout is unchanged.
#import <stdlib.h>
#import <string.h>
#import <Foundation/NSString.h>
#import <Foundation/NSIndexSet.h>
#import <Foundation/NSException.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSData.h>

typedef struct { NSRange *r; NSUInteger n, cap; } Ranges;
#define RS(set) ((Ranges *)(set)->_internal._multipleRanges._data)

static Ranges *ranges_of(NSIndexSet *s) {
    if (!s->_internal._multipleRanges._data) s->_internal._multipleRanges._data = calloc(1, sizeof(Ranges));
    return RS(s);
}
static void reserve(Ranges *a, NSUInteger n) {
    if (n <= a->cap) return;
    a->cap = n < 8 ? 8 : n * 2;
    a->r = realloc(a->r, a->cap * sizeof(NSRange));
}
// index of the first range whose end is beyond v (the range containing v, or the next one)
static NSUInteger lower(const Ranges *a, NSUInteger v) {
    NSUInteger lo = 0, hi = a ? a->n : 0;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if (a->r[mid].location + a->r[mid].length <= v) lo = mid + 1; else hi = mid;
    }
    return lo;
}
static void add_range(NSIndexSet *s, NSRange g) {
    if (!g.length) return;
    Ranges *a = ranges_of(s);
    NSUInteger start = g.location, end = g.location + g.length;
    NSUInteger i = lower(a, start ? start - 1 : 0);          // first range touching or after [start, end)
    while (i < a->n && a->r[i].location + a->r[i].length < start) i++;
    NSUInteger j = i;
    while (j < a->n && a->r[j].location <= end) {              // merge every range that overlaps or touches
        if (a->r[j].location < start) start = a->r[j].location;
        if (a->r[j].location + a->r[j].length > end) end = a->r[j].location + a->r[j].length;
        j++;
    }
    if (j == i) { reserve(a, a->n + 1); memmove(a->r + i + 1, a->r + i, (a->n - i) * sizeof(NSRange)); a->n++; }
    else if (j > i + 1) { memmove(a->r + i + 1, a->r + j, (a->n - j) * sizeof(NSRange)); a->n -= j - i - 1; }
    a->r[i] = NSMakeRange(start, end - start);
}
static void remove_range(NSIndexSet *s, NSRange g) {
    Ranges *a = RS(s);
    if (!a || !g.length) return;
    NSUInteger start = g.location, end = g.location + g.length;
    if (end < start) end = NSNotFound;                       // overflow: up to the largest index
    for (NSUInteger i = lower(a, start); i < a->n && a->r[i].location < end;) {
        NSUInteger rs = a->r[i].location, re = rs + a->r[i].length;
        if (rs < start && re > end) {                         // split
            reserve(a, a->n + 1);
            memmove(a->r + i + 2, a->r + i + 1, (a->n - i - 1) * sizeof(NSRange)); a->n++;
            a->r[i] = NSMakeRange(rs, start - rs); a->r[i + 1] = NSMakeRange(end, re - end);
            return;
        }
        if (rs < start) { a->r[i].length = start - rs; i++; }
        else if (re > end) { a->r[i] = NSMakeRange(end, re - end); return; }
        else { memmove(a->r + i, a->r + i + 1, (a->n - i - 1) * sizeof(NSRange)); a->n--; }
    }
}
static void put_varint(NSMutableData *d, NSUInteger v) {
    do { unsigned char b = v & 0x7f; v >>= 7; if (v) b |= 0x80; [d appendBytes:&b length:1]; } while (v);
}

@implementation NSIndexSet
+ (id)indexSet { return [[[self alloc] init] autorelease]; }
+ (id)indexSetWithIndex:(NSUInteger)v { return [[[self alloc] initWithIndex:v] autorelease]; }
+ (id)indexSetWithIndexesInRange:(NSRange)g { return [[[self alloc] initWithIndexesInRange:g] autorelease]; }
- (id)init { return [super init]; }
- (id)initWithIndex:(NSUInteger)v { return [self initWithIndexesInRange:NSMakeRange(v, 1)]; }
- (id)initWithIndexesInRange:(NSRange)g { if ((self = [self init])) add_range(self, g); return self; }
- (id)initWithIndexSet:(NSIndexSet *)o {
    if ((self = [self init]) && o && RS(o) && RS(o)->n) {
        Ranges *a = ranges_of(self); reserve(a, RS(o)->n);
        memcpy(a->r, RS(o)->r, RS(o)->n * sizeof(NSRange)); a->n = RS(o)->n;
    }
    return self;
}
- (void)dealloc { Ranges *a = RS(self); if (a) { free(a->r); free(a); } [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [[NSIndexSet allocWithZone:z] initWithIndexSet:self]; }
- (id)mutableCopyWithZone:(NSZone *)z { return [[NSMutableIndexSet allocWithZone:z] initWithIndexSet:self]; }
+ (BOOL)supportsSecureCoding { return YES; }
// keyed archives as Apple writes them: one range inline, more as variable-length integers in NSRangeData
- (void)encodeWithCoder:(NSCoder *)c {
    Ranges *a = RS(self); NSUInteger n = a ? a->n : 0;
    [c encodeInt64:n forKey:@"NSRangeCount"];
    if (n == 1) { [c encodeInt64:a->r[0].location forKey:@"NSLocation"]; [c encodeInt64:a->r[0].length forKey:@"NSLength"]; }
    else if (n > 1) {
        NSMutableData *d = [NSMutableData data];
        for (NSUInteger i = 0; i < n; i++) { put_varint(d, a->r[i].location); put_varint(d, a->r[i].length); }
        [c encodeObject:d forKey:@"NSRangeData"];
    }
}
- (id)initWithCoder:(NSCoder *)c {
    if (!(self = [self init])) return nil;
    NSUInteger n = (NSUInteger)[c decodeInt64ForKey:@"NSRangeCount"];
    if (n == 1) add_range(self, NSMakeRange((NSUInteger)[c decodeInt64ForKey:@"NSLocation"], (NSUInteger)[c decodeInt64ForKey:@"NSLength"]));
    else if (n > 1) {
        NSData *d = [c decodeObjectForKey:@"NSRangeData"];
        const unsigned char *p = [d bytes], *end = p + [d length];
        NSUInteger vals[2]; int k = 0;
        while (p < end) {
            NSUInteger v = 0; int shift = 0;
            while (p < end) { unsigned char b = *p++; v |= (NSUInteger)(b & 0x7f) << shift; shift += 7; if (!(b & 0x80)) break; }
            vals[k++] = v;
            if (k == 2) { add_range(self, NSMakeRange(vals[0], vals[1])); k = 0; }
        }
    }
    return self;
}
- (NSUInteger)hash { Ranges *a = RS(self); return a && a->n ? a->r[0].location * 31 + a->n : 0; }
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSIndexSet class]] && [self isEqualToIndexSet:o]); }
- (BOOL)isEqualToIndexSet:(NSIndexSet *)o {
    if (!o) return NO;
    Ranges *a = RS(self), *b = RS(o); NSUInteger na = a ? a->n : 0, nb = b ? b->n : 0;
    return na == nb && (!na || memcmp(a->r, b->r, na * sizeof(NSRange)) == 0);
}
- (NSUInteger)count { Ranges *a = RS(self); NSUInteger c = 0; for (NSUInteger i = 0; a && i < a->n; i++) c += a->r[i].length; return c; }
- (NSUInteger)rangeCount { Ranges *a = RS(self); return a ? a->n : 0; }
- (NSRange)rangeAtIndex:(NSUInteger)i { Ranges *a = RS(self); return a && i < a->n ? a->r[i] : NSMakeRange(NSNotFound, 0); }
- (NSUInteger)firstIndex { Ranges *a = RS(self); return a && a->n ? a->r[0].location : NSNotFound; }
- (NSUInteger)lastIndex { Ranges *a = RS(self); return a && a->n ? a->r[a->n - 1].location + a->r[a->n - 1].length - 1 : NSNotFound; }
- (NSUInteger)indexGreaterThanOrEqualToIndex:(NSUInteger)v {
    Ranges *a = RS(self); NSUInteger i = lower(a, v);
    if (!a || i >= a->n) return NSNotFound;
    return a->r[i].location > v ? a->r[i].location : v;
}
- (NSUInteger)indexGreaterThanIndex:(NSUInteger)v { return v >= NSNotFound - 1 ? NSNotFound : [self indexGreaterThanOrEqualToIndex:v + 1]; }
- (NSUInteger)indexLessThanOrEqualToIndex:(NSUInteger)v {
    Ranges *a = RS(self); if (!a || !a->n) return NSNotFound;
    NSUInteger i = lower(a, v);
    if (i < a->n && a->r[i].location <= v) return v;
    return i ? a->r[i - 1].location + a->r[i - 1].length - 1 : NSNotFound;
}
- (NSUInteger)indexLessThanIndex:(NSUInteger)v { return v ? [self indexLessThanOrEqualToIndex:v - 1] : NSNotFound; }
- (BOOL)containsIndex:(NSUInteger)v { Ranges *a = RS(self); NSUInteger i = lower(a, v); return a && i < a->n && a->r[i].location <= v; }
- (BOOL)containsIndexesInRange:(NSRange)g {
    if (!g.length) return NO;
    Ranges *a = RS(self); NSUInteger i = lower(a, g.location);
    return a && i < a->n && a->r[i].location <= g.location && a->r[i].location + a->r[i].length >= g.location + g.length;
}
- (BOOL)containsIndexes:(NSIndexSet *)o {
    Ranges *b = RS(o);
    for (NSUInteger i = 0; b && i < b->n; i++) if (![self containsIndexesInRange:b->r[i]]) return NO;
    return YES;
}
- (BOOL)intersectsIndexesInRange:(NSRange)g {
    if (!g.length) return NO;
    Ranges *a = RS(self); NSUInteger i = lower(a, g.location);
    return a && i < a->n && a->r[i].location < g.location + g.length;
}
- (NSUInteger)countOfIndexesInRange:(NSRange)g {
    Ranges *a = RS(self); NSUInteger c = 0, end = g.location + g.length;
    for (NSUInteger i = lower(a, g.location); a && i < a->n && a->r[i].location < end; i++) {
        NSUInteger s = a->r[i].location > g.location ? a->r[i].location : g.location, e = a->r[i].location + a->r[i].length;
        c += (e < end ? e : end) - s;
    }
    return c;
}
- (NSUInteger)getIndexes:(NSUInteger *)buf maxCount:(NSUInteger)max inIndexRange:(NSRangePointer)range {
    Ranges *a = RS(self); NSUInteger n = 0, start = range ? range->location : 0, end = range ? range->location + range->length : NSNotFound;
    NSUInteger last = NSNotFound;
    for (NSUInteger i = lower(a, start); a && i < a->n && n < max && a->r[i].location < end; i++) {
        NSUInteger s = a->r[i].location > start ? a->r[i].location : start, e = a->r[i].location + a->r[i].length;
        if (e > end) e = end;
        for (NSUInteger v = s; v < e && n < max; v++) { buf[n++] = v; last = v; }
    }
    if (range && n) { NSUInteger consumed = last + 1 - range->location; range->location = last + 1; range->length -= consumed; }
    return n;
}
- (NSString *)description {
    Ranges *a = RS(self); NSUInteger n = a ? a->n : 0;
    if (!n) return [NSString stringWithFormat:@"<%@: %p>(no indexes)", [self class], self];
    NSMutableString *s = [NSMutableString stringWithFormat:@"<%@: %p>[number of indexes: %lu (in %lu ranges), indexes: (", [self class], self, (unsigned long)[self count], (unsigned long)n];
    for (NSUInteger i = 0; i < n; i++) {
        if (i) [s appendString:@" "];
        if (a->r[i].length == 1) [s appendFormat:@"%lu", (unsigned long)a->r[i].location];
        else [s appendFormat:@"%lu-%lu", (unsigned long)a->r[i].location, (unsigned long)(a->r[i].location + a->r[i].length - 1)];
    }
    [s appendString:@")]"];
    return s;
}

// ---- enumeration: over a snapshot, so the block may change the set
- (void)enumerateRangesInRange:(NSRange)g options:(NSEnumerationOptions)opts usingBlock:(void (^)(NSRange, BOOL *))block {
    Ranges *a = RS(self); if (!a || !a->n || !block) return;
    NSUInteger n = a->n; NSRange *copy = malloc(n * sizeof(NSRange)); memcpy(copy, a->r, n * sizeof(NSRange));
    NSUInteger start = g.location, end = g.location + g.length; if (end < start) end = NSNotFound;
    BOOL stop = NO, reverse = (opts & NSEnumerationReverse) != 0;
    for (NSUInteger k = 0; k < n && !stop; k++) {
        NSRange r = copy[reverse ? n - 1 - k : k];
        NSUInteger s = r.location > start ? r.location : start, e = r.location + r.length < end ? r.location + r.length : end;
        if (s < e) block(NSMakeRange(s, e - s), &stop);
    }
    free(copy);
}
- (void)enumerateRangesWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(NSRange, BOOL *))block { [self enumerateRangesInRange:NSMakeRange(0, NSNotFound) options:opts usingBlock:block]; }
- (void)enumerateRangesUsingBlock:(void (^)(NSRange, BOOL *))block { [self enumerateRangesInRange:NSMakeRange(0, NSNotFound) options:0 usingBlock:block]; }
- (void)enumerateIndexesInRange:(NSRange)g options:(NSEnumerationOptions)opts usingBlock:(void (^)(NSUInteger, BOOL *))block {
    if (!block) return;
    BOOL reverse = (opts & NSEnumerationReverse) != 0;
    [self enumerateRangesInRange:g options:opts usingBlock:^(NSRange r, BOOL *stop) {
        for (NSUInteger k = 0; k < r.length && !*stop; k++) block(reverse ? r.location + r.length - 1 - k : r.location + k, stop);
    }];
}
- (void)enumerateIndexesWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(NSUInteger, BOOL *))block { [self enumerateIndexesInRange:NSMakeRange(0, NSNotFound) options:opts usingBlock:block]; }
- (void)enumerateIndexesUsingBlock:(void (^)(NSUInteger, BOOL *))block { [self enumerateIndexesInRange:NSMakeRange(0, NSNotFound) options:0 usingBlock:block]; }
- (NSUInteger)indexInRange:(NSRange)g options:(NSEnumerationOptions)opts passingTest:(BOOL (^)(NSUInteger, BOOL *))test {
    __block NSUInteger found = NSNotFound;
    [self enumerateIndexesInRange:g options:opts usingBlock:^(NSUInteger i, BOOL *stop) { if (test(i, stop)) { found = i; *stop = YES; } }];
    return found;
}
- (NSUInteger)indexWithOptions:(NSEnumerationOptions)opts passingTest:(BOOL (^)(NSUInteger, BOOL *))test { return [self indexInRange:NSMakeRange(0, NSNotFound) options:opts passingTest:test]; }
- (NSUInteger)indexPassingTest:(BOOL (^)(NSUInteger, BOOL *))test { return [self indexInRange:NSMakeRange(0, NSNotFound) options:0 passingTest:test]; }
- (NSIndexSet *)indexesInRange:(NSRange)g options:(NSEnumerationOptions)opts passingTest:(BOOL (^)(NSUInteger, BOOL *))test {
    NSMutableIndexSet *out = [NSMutableIndexSet indexSet];
    [self enumerateIndexesInRange:g options:opts usingBlock:^(NSUInteger i, BOOL *stop) { if (test(i, stop)) add_range(out, NSMakeRange(i, 1)); }];
    return out;
}
- (NSIndexSet *)indexesWithOptions:(NSEnumerationOptions)opts passingTest:(BOOL (^)(NSUInteger, BOOL *))test { return [self indexesInRange:NSMakeRange(0, NSNotFound) options:opts passingTest:test]; }
- (NSIndexSet *)indexesPassingTest:(BOOL (^)(NSUInteger, BOOL *))test { return [self indexesInRange:NSMakeRange(0, NSNotFound) options:0 passingTest:test]; }
@end

@implementation NSMutableIndexSet
- (id)copyWithZone:(NSZone *)z { return [[NSIndexSet allocWithZone:z] initWithIndexSet:self]; }
- (void)addIndex:(NSUInteger)v { add_range(self, NSMakeRange(v, 1)); }
- (void)removeIndex:(NSUInteger)v { remove_range(self, NSMakeRange(v, 1)); }
- (void)addIndexesInRange:(NSRange)g { add_range(self, g); }
- (void)removeIndexesInRange:(NSRange)g { remove_range(self, g); }
- (void)addIndexes:(NSIndexSet *)o {
    Ranges *b = RS(o); if (!b || o == self) return;
    NSUInteger n = b->n; NSRange *copy = malloc((n ? n : 1) * sizeof(NSRange)); memcpy(copy, b->r, n * sizeof(NSRange));
    for (NSUInteger i = 0; i < n; i++) add_range(self, copy[i]);
    free(copy);
}
- (void)removeIndexes:(NSIndexSet *)o {
    Ranges *b = RS(o); if (!b) return;
    if (o == self) { [self removeAllIndexes]; return; }
    for (NSUInteger i = 0; i < b->n; i++) remove_range(self, b->r[i]);
}
- (void)removeAllIndexes { Ranges *a = RS(self); if (a) a->n = 0; }
// delta > 0: the indexes from `index` on move up; delta < 0: they move down, over the indexes just below `index`
- (void)shiftIndexesStartingAtIndex:(NSUInteger)index by:(NSInteger)delta {
    Ranges *a = RS(self); if (!a || !a->n || !delta) return;
    if (delta < 0) { NSUInteger d = (NSUInteger)-delta; remove_range(self, NSMakeRange(index > d ? index - d : 0, index > d ? d : index)); }
    a = RS(self);
    NSUInteger n = a->n; NSRange *old = malloc((n ? n : 1) * sizeof(NSRange)); memcpy(old, a->r, n * sizeof(NSRange));
    a->n = 0;
    for (NSUInteger i = 0; i < n; i++) {
        NSUInteger s = old[i].location, e = s + old[i].length;
        if (e <= index) { add_range(self, old[i]); continue; }
        if (s < index) { add_range(self, NSMakeRange(s, index - s)); s = index; }
        if (delta > 0) add_range(self, NSMakeRange(s + delta, e - s));
        else { NSUInteger d = (NSUInteger)-delta; NSUInteger ns = s > d ? s - d : 0, ne = e > d ? e - d : 0; if (ne > ns) add_range(self, NSMakeRange(ns, ne - ns)); }
    }
    free(old);
}
@end
