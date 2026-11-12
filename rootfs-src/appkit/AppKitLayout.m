/* AppKit-lite Auto Layout: NSLayoutConstraint, NSLayoutAnchor, NSLayoutGuide, the visual format language and a
 * constraint solver.
 *
 * The solver is the Cassowary simplex method (Badros, Borning, Stuckey), in the tableau form used by the Kiwi
 * implementation. Priorities are not folded into weights: the objective keeps one coefficient per priority level and
 * compares them lexicographically, so a constraint of a higher priority always wins over any number of lower ones, as
 * in AppKit.
 *
 * A hierarchy is solved as a whole, in the coordinates of its topmost view with y growing downwards (the direction
 * constraint constants use). Views that translate their autoresizing mask contribute their frame as required
 * constraints; the others get their frame from the solution. Frames real AppKit computes are the reference:
 * tests/darwin/mac/appkit_layout.m. */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitLayout.h"
#include <objc/runtime.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

enum { kLeft = 1, kRight, kTop, kBottom, kLeading, kTrailing, kWidth, kHeight, kCenterX, kCenterY, kLastBaseline, kFirstBaseline };

/* ================================================================== solver */
#define KMAX 12                       /* priority levels of one solve */
enum { SYM_EXTERNAL = 1, SYM_SLACK, SYM_ERROR, SYM_DUMMY };
#define SYM(i, type) (((i) << 3) | (type))
#define SYM_TYPE(s) ((s) & 7)
#define EPS 1e-8
static BOOL near_zero(double v) { return v < 0 ? -v < EPS : v < EPS; }

typedef struct { int sym; double c; } Cell;
typedef struct { double constant; Cell *cells; int n, cap; } Row;
typedef struct { int sym; double w[KMAX]; } OCell;
typedef struct { OCell *cells; int n, cap; } Objective;
typedef struct { int sym; Row *row; } Basic;
typedef struct { Basic *rows; int n, cap; Objective obj; Row *artificial; int next; int levels; BOOL failed; } Solver;

static Row *row_new(double constant) { Row *r = calloc(1, sizeof(Row)); r->constant = constant; return r; }
static Row *row_copy(const Row *o) { Row *r = row_new(o->constant); r->n = r->cap = o->n; r->cells = malloc(sizeof(Cell) * (o->n ? o->n : 1)); memcpy(r->cells, o->cells, sizeof(Cell) * o->n); return r; }
static void row_free(Row *r) { if (r) { free(r->cells); free(r); } }
static int row_find(const Row *r, int sym) { for (int i = 0; i < r->n; i++) if (r->cells[i].sym == sym) return i; return -1; }
static double row_coef(const Row *r, int sym) { int i = row_find(r, sym); return i < 0 ? 0 : r->cells[i].c; }
static void row_remove(Row *r, int sym) { int i = row_find(r, sym); if (i >= 0) r->cells[i] = r->cells[--r->n]; }
static void row_add(Row *r, int sym, double c) {
  int i = row_find(r, sym);
  if (i >= 0) { r->cells[i].c += c; if (near_zero(r->cells[i].c)) r->cells[i] = r->cells[--r->n]; return; }
  if (near_zero(c)) return;
  if (r->n == r->cap) { r->cap = r->cap ? r->cap * 2 : 8; r->cells = realloc(r->cells, sizeof(Cell) * r->cap); }
  r->cells[r->n].sym = sym; r->cells[r->n++].c = c; }
static void row_add_row(Row *r, const Row *o, double c) { r->constant += o->constant * c; for (int i = 0; i < o->n; i++) row_add(r, o->cells[i].sym, o->cells[i].c * c); }
static void row_reverse(Row *r) { r->constant = -r->constant; for (int i = 0; i < r->n; i++) r->cells[i].c = -r->cells[i].c; }
/* the row is  0 = constant + cells; rewrite it as  sym = ... */
static void row_solve_for(Row *r, int sym) {
  double c = -1.0 / row_coef(r, sym); row_remove(r, sym);
  r->constant *= c; for (int i = 0; i < r->n; i++) r->cells[i].c *= c; }
static void row_solve_for_ex(Row *r, int lhs, int rhs) { row_add(r, lhs, -1.0); row_solve_for(r, rhs); }
static void row_substitute(Row *r, int sym, const Row *o) { int i = row_find(r, sym); if (i < 0) return; double c = r->cells[i].c; r->cells[i] = r->cells[--r->n]; row_add_row(r, o, c); }

static OCell *obj_cell(Objective *o, int sym, BOOL create) {
  for (int i = 0; i < o->n; i++) if (o->cells[i].sym == sym) return &o->cells[i];
  if (!create) return NULL;
  if (o->n == o->cap) { o->cap = o->cap ? o->cap * 2 : 16; o->cells = realloc(o->cells, sizeof(OCell) * o->cap); }
  OCell *c = &o->cells[o->n++]; memset(c, 0, sizeof *c); c->sym = sym; return c; }
static void obj_substitute(Objective *o, int sym, const Row *r, int levels) {
  OCell *c = obj_cell(o, sym, NO); if (!c) return;
  double w[KMAX]; memcpy(w, c->w, sizeof w);
  *c = o->cells[--o->n];
  for (int i = 0; i < r->n; i++) { OCell *t = obj_cell(o, r->cells[i].sym, YES); for (int k = 0; k < levels; k++) t->w[k] += w[k] * r->cells[i].c; } }
/* lexicographic sign of a coefficient: the highest priority level that is not zero decides */
static int obj_sign(const OCell *c, int levels) { for (int k = 0; k < levels; k++) { if (c->w[k] < -EPS) return -1; if (c->w[k] > EPS) return 1; } return 0; }

static Row *basic_row(Solver *s, int sym) { for (int i = 0; i < s->n; i++) if (s->rows[i].sym == sym) return s->rows[i].row; return NULL; }
static void basic_set(Solver *s, int sym, Row *r) {
  if (s->n == s->cap) { s->cap = s->cap ? s->cap * 2 : 64; s->rows = realloc(s->rows, sizeof(Basic) * s->cap); }
  s->rows[s->n].sym = sym; s->rows[s->n++].row = r; }
static Row *basic_take(Solver *s, int sym) { for (int i = 0; i < s->n; i++) if (s->rows[i].sym == sym) { Row *r = s->rows[i].row; s->rows[i] = s->rows[--s->n]; return r; } return NULL; }
static void substitute(Solver *s, int sym, const Row *r) {
  for (int i = 0; i < s->n; i++) row_substitute(s->rows[i].row, sym, r);
  obj_substitute(&s->obj, sym, r, s->levels);
  if (s->artificial) row_substitute(s->artificial, sym, r); }
/* the basic variable that reaches zero first when `entering` grows */
static int leaving_row(Solver *s, int entering) {
  double best = 1e300; int found = -1;
  for (int i = 0; i < s->n; i++) {
    if (SYM_TYPE(s->rows[i].sym) == SYM_EXTERNAL) continue;
    double c = row_coef(s->rows[i].row, entering);
    if (c < 0) { double ratio = -s->rows[i].row->constant / c; if (ratio < best) { best = ratio; found = i; } } }
  return found; }
static void pivot(Solver *s, int rowIndex, int entering) {
  int leaving = s->rows[rowIndex].sym; Row *r = s->rows[rowIndex].row;
  s->rows[rowIndex] = s->rows[--s->n];
  row_solve_for_ex(r, leaving, entering);
  substitute(s, entering, r);
  basic_set(s, entering, r); }
static void optimize(Solver *s) {
  for (int guard = 0; guard < 100000; guard++) {
    int entering = 0;
    for (int i = 0; i < s->obj.n; i++) if (SYM_TYPE(s->obj.cells[i].sym) != SYM_DUMMY && obj_sign(&s->obj.cells[i], s->levels) < 0) { entering = s->obj.cells[i].sym; break; }
    if (!entering) return;
    int li = leaving_row(s, entering);
    if (li < 0) return;                         /* unbounded: cannot happen with error variables only */
    pivot(s, li, entering); } }
static void optimize_artificial(Solver *s) {
  for (int guard = 0; guard < 100000; guard++) {
    int entering = 0;
    for (int i = 0; i < s->artificial->n; i++) if (SYM_TYPE(s->artificial->cells[i].sym) != SYM_DUMMY && s->artificial->cells[i].c < 0) { entering = s->artificial->cells[i].sym; break; }
    if (!entering) return;
    int li = leaving_row(s, entering);
    if (li < 0) return;
    pivot(s, li, entering); } }
static BOOL add_with_artificial(Solver *s, Row *row) {
  int art = SYM(s->next++, SYM_SLACK);
  basic_set(s, art, row_copy(row));
  s->artificial = row_copy(row);
  optimize_artificial(s);
  BOOL ok = near_zero(s->artificial->constant);
  row_free(s->artificial); s->artificial = NULL;
  Row *r = basic_take(s, art);
  if (r) {
    if (r->n == 0) { row_free(r); row_free(row); return ok; }
    int entering = 0;
    for (int i = 0; i < r->n; i++) { int t = SYM_TYPE(r->cells[i].sym); if (t == SYM_SLACK || t == SYM_ERROR) { entering = r->cells[i].sym; break; } }
    if (!entering) { row_free(r); row_free(row); return NO; }
    row_solve_for_ex(r, art, entering);
    substitute(s, entering, r);
    basic_set(s, entering, r); }
  for (int i = 0; i < s->n; i++) row_remove(s->rows[i].row, art);
  OCell *oc = obj_cell(&s->obj, art, NO); if (oc) *oc = s->obj.cells[--s->obj.n];
  row_free(row);
  return ok; }
/* terms: var index, coefficient pairs;  sum + constant  (op: -1 <=, 0 ==, 1 >=)  0;  level < 0: required */
static BOOL solver_add(Solver *s, const int *vars, const double *coefs, int nterms, double constant, int op, int level) {
  Row *row = row_new(constant);
  for (int i = 0; i < nterms; i++) {
    if (near_zero(coefs[i])) continue;
    int sym = SYM(vars[i], SYM_EXTERNAL); Row *b = basic_row(s, sym);
    if (b) row_add_row(row, b, coefs[i]); else row_add(row, sym, coefs[i]); }
  int marker = 0, other = 0;
  if (op != 0) {
    double coeff = op < 0 ? 1.0 : -1.0;
    marker = SYM(s->next++, SYM_SLACK); row_add(row, marker, coeff);
    if (level >= 0) { other = SYM(s->next++, SYM_ERROR); row_add(row, other, -coeff); obj_cell(&s->obj, other, YES)->w[level] += 1; }
  } else if (level >= 0) {
    marker = SYM(s->next++, SYM_ERROR); other = SYM(s->next++, SYM_ERROR);
    row_add(row, marker, -1.0); row_add(row, other, 1.0);
    obj_cell(&s->obj, marker, YES)->w[level] += 1; obj_cell(&s->obj, other, YES)->w[level] += 1;
  } else { marker = SYM(s->next++, SYM_DUMMY); row_add(row, marker, 1.0); }
  if (row->constant < 0) row_reverse(row);
  int subject = 0;
  for (int i = 0; i < row->n; i++) if (SYM_TYPE(row->cells[i].sym) == SYM_EXTERNAL) { subject = row->cells[i].sym; break; }
  if (!subject && (SYM_TYPE(marker) == SYM_SLACK || SYM_TYPE(marker) == SYM_ERROR) && row_coef(row, marker) < 0) subject = marker;
  if (!subject && other && (SYM_TYPE(other) == SYM_SLACK || SYM_TYPE(other) == SYM_ERROR) && row_coef(row, other) < 0) subject = other;
  if (!subject) {
    BOOL dummies = YES; for (int i = 0; i < row->n; i++) if (SYM_TYPE(row->cells[i].sym) != SYM_DUMMY) dummies = NO;
    if (dummies) { if (!near_zero(row->constant)) { row_free(row); return NO; } subject = marker; } }
  if (!subject) { if (!add_with_artificial(s, row)) return NO; }
  else { row_solve_for(row, subject); substitute(s, subject, row); basic_set(s, subject, row); }
  optimize(s);
  return YES; }
static double solver_value(Solver *s, int var) { Row *r = basic_row(s, SYM(var, SYM_EXTERNAL)); return r ? r->constant : 0; }
static void solver_free(Solver *s) { for (int i = 0; i < s->n; i++) row_free(s->rows[i].row); free(s->rows); free(s->obj.cells); }

/* ================================================================== constraints */
static unsigned long g_generation = 1;        /* bumped by anything that can change a solution */
static BOOL g_in_engine;
static NSMutableArray *g_active;               /* every active constraint (not retained: holders retain them) */
void XEFLayoutInvalidate(void) { if (!g_in_engine) g_generation++; }

static NSView *view_of(id item) { return [item isKindOfClass:[NSLayoutGuide class]] ? ((NSLayoutGuide *)item)->_owner : (NSView *)item; }
static NSMutableArray *held(NSView *v, BOOL create) {
  NSMutableArray *a = v->_extra[@"constraints"];
  if (!a && create) { a = [NSMutableArray array]; [v _xefExtra][@"constraints"] = a; }
  return a; }

@implementation NSLayoutConstraint
+ (id)constraintWithItem:(id)a attribute:(NSInteger)aa relatedBy:(NSInteger)rel toItem:(id)b attribute:(NSInteger)ba multiplier:(CGFloat)m constant:(CGFloat)c {
  NSLayoutConstraint *k = [[[self alloc] init] autorelease];
  k->_first = a; k->_firstAttr = aa; k->_relation = rel; k->_second = b; k->_secondAttr = b ? ba : 0; k->_multiplier = m; k->_constant = c;
  return k; }
- (id)init { if ((self = [super init])) { _multiplier = 1; _priority = 1000; _archived = NO; } return self; }
/* Interface Builder's keys */
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [self init])) {
    _first = [c decodeObjectForKey:@"NSFirstItem"]; _second = [c decodeObjectForKey:@"NSSecondItem"];
    _firstAttr = [c decodeIntegerForKey:@"NSFirstAttribute"]; _secondAttr = [c decodeIntegerForKey:@"NSSecondAttribute"]; _relation = [c decodeIntegerForKey:@"NSRelation"];
    if ([c containsValueForKey:@"NSMultiplier"]) _multiplier = [c decodeDoubleForKey:@"NSMultiplier"];
    _constant = [c decodeDoubleForKey:@"NSConstant"];
    if ([c containsValueForKey:@"NSPriority"]) _priority = [c decodeIntegerForKey:@"NSPriority"];
    _identifier = [[c decodeObjectForKey:@"NSLayoutIdentifier"] copy]; }
  return self; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc { if (_active) [g_active removeObjectIdenticalTo:self]; [_identifier release]; [super dealloc]; }
- (id)firstItem { return _first; } - (id)secondItem { return _second; }
- (NSInteger)firstAttribute { return _firstAttr; } - (NSInteger)secondAttribute { return _secondAttr; }
- (NSInteger)relation { return _relation; } - (CGFloat)multiplier { return _multiplier; }
- (CGFloat)constant { return _constant; } - (void)setConstant:(CGFloat)c { if (c != _constant) { _constant = c; XEFLayoutInvalidate(); [view_of(_first) setNeedsLayout:YES]; } }
- (float)priority { return _priority; } - (void)setPriority:(float)p { if (p != _priority) { _priority = p; XEFLayoutInvalidate(); } }
- (BOOL)shouldBeArchived { return _archived; } - (void)setShouldBeArchived:(BOOL)f { _archived = f; }
- (NSString *)identifier { return _identifier; } - (void)setIdentifier:(NSString *)i { [_identifier release]; _identifier = [i copy]; }
static Class anchor_class(NSInteger attr);
- (NSLayoutAnchor *)_anchor:(id)item attr:(NSInteger)attr {
  if (!item || !attr) return nil;
  NSLayoutAnchor *a = [[[anchor_class(attr) alloc] init] autorelease]; a->_item = item; a->_attr = attr; return a; }
- (NSLayoutAnchor *)firstAnchor { return [self _anchor:_first attr:_firstAttr]; } - (NSLayoutAnchor *)secondAnchor { return [self _anchor:_second attr:_secondAttr]; }
- (BOOL)isActive { return _active; }
/* an active constraint is held by the closest ancestor its items share */
- (void)setActive:(BOOL)f {
  if (f == _active) return;
  if (f) {
    NSView *a = view_of(_first), *b = _second ? view_of(_second) : a;
    NSView *holder = a && b ? [a ancestorSharedWithView:b] : nil;
    if (!holder) holder = a ?: b;
    if (!holder) return;
    [self _xefInstallIn:holder];
  } else {
    [[self retain] autorelease];
    _active = NO; [g_active removeObjectIdenticalTo:self];
    NSView *h = _holder; _holder = nil;
    [held(h, NO) removeObjectIdenticalTo:self];
    [h setNeedsLayout:YES]; }
  XEFLayoutInvalidate(); }
- (void)_xefInstallIn:(NSView *)holder {
  if (_active) return;
  if (!g_active) g_active = (NSMutableArray *)CFArrayCreateMutable(NULL, 0, NULL);
  _active = YES; _holder = holder;
  [held(holder, YES) addObject:self]; [g_active addObject:self];
  [holder setNeedsLayout:YES]; XEFLayoutInvalidate(); }
+ (void)activateConstraints:(NSArray *)a { for (NSLayoutConstraint *k in a) [k setActive:YES]; }
+ (void)deactivateConstraints:(NSArray *)a { for (NSLayoutConstraint *k in a) [k setActive:NO]; }
- (NSString *)description {
  static const char *names[] = { "?", "left", "right", "top", "bottom", "leading", "trailing", "width", "height", "centerX", "centerY", "lastBaseline", "firstBaseline" };
  const char *rel = _relation < 0 ? "<=" : _relation > 0 ? ">=" : "==";
  NSString *lhs = [NSString stringWithFormat:@"%@:%p.%s", [_first class], _first, names[_firstAttr >= 0 && _firstAttr <= 12 ? _firstAttr : 0]];
  if (!_second) return [NSString stringWithFormat:@"<NSLayoutConstraint:%p %@ %s %g @%g>", self, lhs, rel, _constant, _priority];
  return [NSString stringWithFormat:@"<NSLayoutConstraint:%p %@ %s %g*%@:%p.%s + %g @%g>", self, lhs, rel, _multiplier, [_second class], _second, names[_secondAttr >= 0 && _secondAttr <= 12 ? _secondAttr : 0], _constant, _priority]; }
- (id)animator { return self; } - (id)animationForKey:(NSString *)k { return nil; } + (id)defaultAnimationForKey:(NSString *)k { return nil; }
- (NSDictionary *)animations { return @{}; } - (void)setAnimations:(NSDictionary *)d {}

/* ---- visual format language */
typedef struct { const char *p; NSDictionary *metrics, *views; BOOL bad; } VFL;
static void vfl_ws(VFL *v) { while (*v->p == ' ') v->p++; }
static NSString *vfl_name(VFL *v) {
  const char *s = v->p; while ((*v->p >= 'a' && *v->p <= 'z') || (*v->p >= 'A' && *v->p <= 'Z') || (*v->p >= '0' && *v->p <= '9') || *v->p == '_') v->p++;
  return [[[NSString alloc] initWithBytes:s length:v->p - s encoding:NSUTF8StringEncoding] autorelease]; }
static double vfl_number(VFL *v, BOOL *isNumber) {
  if ((*v->p >= '0' && *v->p <= '9') || *v->p == '-' || *v->p == '.') { char *e; double d = strtod(v->p, &e); v->p = e; *isNumber = YES; return d; }
  *isNumber = NO; return 0; }
typedef struct { NSInteger rel; double value; id view; float priority; } Pred;
/* [==|>=|<=] (number | metric | view) [@priority] */
static Pred vfl_pred(VFL *v) {
  Pred p = { 0, 0, nil, 1000 };
  vfl_ws(v);
  if (v->p[0] == '=' && v->p[1] == '=') v->p += 2; else if (v->p[0] == '>' && v->p[1] == '=') { p.rel = 1; v->p += 2; } else if (v->p[0] == '<' && v->p[1] == '=') { p.rel = -1; v->p += 2; }
  vfl_ws(v);
  BOOL num; p.value = vfl_number(v, &num);
  if (!num) {
    NSString *n = vfl_name(v);
    if (v->metrics[n]) p.value = [v->metrics[n] doubleValue]; else if (v->views[n]) p.view = v->views[n]; else v->bad = YES; }
  vfl_ws(v);
  if (*v->p == '@') { v->p++; BOOL pn; double pr = vfl_number(v, &pn); if (!pn) { NSString *n = vfl_name(v); pr = [v->metrics[n] doubleValue]; } p.priority = pr; }
  return p; }
+ (NSArray *)constraintsWithVisualFormat:(NSString *)format options:(NSUInteger)opts metrics:(NSDictionary *)metrics views:(NSDictionary *)views {
  NSMutableArray *out = [NSMutableArray array];
  VFL v = { [format UTF8String], metrics, views, NO };
  BOOL vertical = NO;
  if (v.p[0] == 'V' && v.p[1] == ':') { vertical = YES; v.p += 2; } else if (v.p[0] == 'H' && v.p[1] == ':') v.p += 2;
  NSInteger aStart = vertical ? kTop : ((opts & 0x20000) ? kLeft : kLeading), aEnd = vertical ? kBottom : ((opts & 0x20000) ? kRight : kTrailing), aSize = vertical ? kHeight : kWidth;
  id prev = nil; BOOL prevIsSuper = NO, pending = NO; Pred gaps[8]; int ngaps = 0; id superview = nil;
  for (id view in [views allValues]) if ([view isKindOfClass:[NSView class]] && [view superview]) { superview = [view superview]; break; }
  #define CONNECT(next, nextIsSuper) \
    if (prev || prevIsSuper) { \
      if (!ngaps) { gaps[0] = (Pred){ 0, pending ? ((prevIsSuper || nextIsSuper) ? 20 : 8) : 0, nil, 1000 }; ngaps = 1; } \
      for (int g = 0; g < ngaps; g++) { \
        NSLayoutConstraint *k = prevIsSuper ? [self constraintWithItem:next attribute:aStart relatedBy:gaps[g].rel toItem:superview attribute:aStart multiplier:1 constant:gaps[g].value] \
          : nextIsSuper ? [self constraintWithItem:superview attribute:aEnd relatedBy:gaps[g].rel toItem:prev attribute:aEnd multiplier:1 constant:gaps[g].value] \
          : [self constraintWithItem:next attribute:aStart relatedBy:gaps[g].rel toItem:prev attribute:aEnd multiplier:1 constant:gaps[g].value]; \
        k->_priority = gaps[g].priority; [out addObject:k]; } }
  while (*v.p && !v.bad) {
    vfl_ws(&v);
    if (*v.p == '|') {
      v.p++;
      if (prev) { CONNECT(nil, YES) prev = nil; }
      prevIsSuper = YES; pending = NO; ngaps = 0;
    } else if (*v.p == '-') {
      v.p++; pending = YES; ngaps = 0;
      vfl_ws(&v);
      if (*v.p == '(') {
        v.p++;
        do { if (*v.p == ',') v.p++; if (ngaps < 8) gaps[ngaps++] = vfl_pred(&v); vfl_ws(&v); } while (*v.p == ',');
        if (*v.p == ')') v.p++; else v.bad = YES;
        if (*v.p == '-') v.p++;
      } else if (*v.p != '[' && *v.p != '|') {
        gaps[0] = vfl_pred(&v); ngaps = 1;
        if (*v.p == '-') v.p++; }
    } else if (*v.p == '[') {
      v.p++; NSString *n = vfl_name(&v); id view = views[n]; if (!view) { v.bad = YES; break; }
      if ([view isKindOfClass:[NSView class]] && [view superview]) superview = [view superview];
      CONNECT(view, NO)
      if (prev && !prevIsSuper) for (NSInteger attr = 1; attr <= 12; attr++) if (opts & (1u << attr))
        [out addObject:[self constraintWithItem:view attribute:attr relatedBy:0 toItem:prev attribute:attr multiplier:1 constant:0]];
      if (*v.p == '(') {
        v.p++;
        do { if (*v.p == ',') v.p++;
          Pred p = vfl_pred(&v);
          NSLayoutConstraint *k = p.view ? [self constraintWithItem:view attribute:aSize relatedBy:p.rel toItem:p.view attribute:aSize multiplier:1 constant:0]
                                         : [self constraintWithItem:view attribute:aSize relatedBy:p.rel toItem:nil attribute:0 multiplier:1 constant:p.value];
          k->_priority = p.priority; [out addObject:k]; vfl_ws(&v);
        } while (*v.p == ',');
        if (*v.p == ')') v.p++; else v.bad = YES; }
      if (*v.p == ']') v.p++; else v.bad = YES;
      prev = view; prevIsSuper = NO; pending = NO; ngaps = 0;
    } else v.bad = YES; }
  #undef CONNECT
  if (v.bad) [NSException raise:NSInvalidArgumentException format:@"Unable to parse constraint format: %@ (at '%s')", format, v.p];
  return out; }
@end

@interface NSAutoresizingMaskLayoutConstraint : NSLayoutConstraint
@end
@implementation NSAutoresizingMaskLayoutConstraint
@end
@interface NSContentSizeLayoutConstraint : NSLayoutConstraint
@end
@implementation NSContentSizeLayoutConstraint
@end
@interface NSIBPrototypingLayoutConstraint : NSLayoutConstraint
@end
@implementation NSIBPrototypingLayoutConstraint
@end

/* ================================================================== anchors and guides */
static Class anchor_class(NSInteger attr) {
  if (attr == kWidth || attr == kHeight) return [NSLayoutDimension class];
  if (attr == kTop || attr == kBottom || attr == kCenterY || attr == kLastBaseline || attr == kFirstBaseline) return [NSLayoutYAxisAnchor class];
  return [NSLayoutXAxisAnchor class]; }
static id anchor(id item, NSInteger attr) { NSLayoutAnchor *a = [[[anchor_class(attr) alloc] init] autorelease]; a->_item = item; a->_attr = attr; return a; }
static NSLayoutConstraint *relate(NSLayoutAnchor *a, NSInteger rel, NSLayoutAnchor *b, CGFloat m, CGFloat c) {
  return [NSLayoutConstraint constraintWithItem:a->_item attribute:a->_attr relatedBy:rel toItem:b ? b->_item : nil attribute:b ? b->_attr : 0 multiplier:m constant:c]; }

@implementation NSLayoutAnchor
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (id)initWithCoder:(NSCoder *)c { return [self init]; } - (void)encodeWithCoder:(NSCoder *)c {}
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSLayoutAnchor class]] && ((NSLayoutAnchor *)o)->_item == _item && ((NSLayoutAnchor *)o)->_attr == _attr; }
- (NSUInteger)hash { return (NSUInteger)_item ^ (NSUInteger)_attr; }
- (id)item { return _item; } - (NSString *)name { return [NSString stringWithFormat:@"%ld", (long)_attr]; }
- (BOOL)hasAmbiguousLayout { return NO; } - (NSArray *)constraintsAffectingLayout { return @[]; }
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a { return relate(self, 0, a, 1, 0); }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)a { return relate(self, 1, a, 1, 0); }
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)a { return relate(self, -1, a, 1, 0); }
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c { return relate(self, 0, a, 1, c); }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c { return relate(self, 1, a, 1, c); }
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c { return relate(self, -1, a, 1, c); }
@end
@implementation NSLayoutXAxisAnchor
- (NSLayoutDimension *)anchorWithOffsetToAnchor:(NSLayoutXAxisAnchor *)a { return nil; }
- (NSLayoutConstraint *)constraintEqualToSystemSpacingAfterAnchor:(NSLayoutAnchor *)a multiplier:(CGFloat)m { return relate(self, 0, a, 1, 8 * m); }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToSystemSpacingAfterAnchor:(NSLayoutAnchor *)a multiplier:(CGFloat)m { return relate(self, 1, a, 1, 8 * m); }
- (NSLayoutConstraint *)constraintLessThanOrEqualToSystemSpacingAfterAnchor:(NSLayoutAnchor *)a multiplier:(CGFloat)m { return relate(self, -1, a, 1, 8 * m); }
@end
@implementation NSLayoutYAxisAnchor
- (NSLayoutDimension *)anchorWithOffsetToAnchor:(NSLayoutYAxisAnchor *)a { return nil; }
- (NSLayoutConstraint *)constraintEqualToSystemSpacingBelowAnchor:(NSLayoutAnchor *)a multiplier:(CGFloat)m { return relate(self, 0, a, 1, 8 * m); }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToSystemSpacingBelowAnchor:(NSLayoutAnchor *)a multiplier:(CGFloat)m { return relate(self, 1, a, 1, 8 * m); }
- (NSLayoutConstraint *)constraintLessThanOrEqualToSystemSpacingBelowAnchor:(NSLayoutAnchor *)a multiplier:(CGFloat)m { return relate(self, -1, a, 1, 8 * m); }
@end
@implementation NSLayoutDimension
- (NSLayoutConstraint *)constraintEqualToConstant:(CGFloat)c { return relate(self, 0, nil, 1, c); }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToConstant:(CGFloat)c { return relate(self, 1, nil, 1, c); }
- (NSLayoutConstraint *)constraintLessThanOrEqualToConstant:(CGFloat)c { return relate(self, -1, nil, 1, c); }
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a multiplier:(CGFloat)m { return relate(self, 0, a, m, 0); }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)a multiplier:(CGFloat)m { return relate(self, 1, a, m, 0); }
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)a multiplier:(CGFloat)m { return relate(self, -1, a, m, 0); }
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a multiplier:(CGFloat)m constant:(CGFloat)c { return relate(self, 0, a, m, c); }
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)a multiplier:(CGFloat)m constant:(CGFloat)c { return relate(self, 1, a, m, c); }
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)a multiplier:(CGFloat)m constant:(CGFloat)c { return relate(self, -1, a, m, c); }
@end

#define ANCHORS \
- (NSLayoutXAxisAnchor *)leadingAnchor { return anchor(self, kLeading); } - (NSLayoutXAxisAnchor *)trailingAnchor { return anchor(self, kTrailing); } \
- (NSLayoutXAxisAnchor *)leftAnchor { return anchor(self, kLeft); } - (NSLayoutXAxisAnchor *)rightAnchor { return anchor(self, kRight); } \
- (NSLayoutYAxisAnchor *)topAnchor { return anchor(self, kTop); } - (NSLayoutYAxisAnchor *)bottomAnchor { return anchor(self, kBottom); } \
- (NSLayoutDimension *)widthAnchor { return anchor(self, kWidth); } - (NSLayoutDimension *)heightAnchor { return anchor(self, kHeight); } \
- (NSLayoutXAxisAnchor *)centerXAnchor { return anchor(self, kCenterX); } - (NSLayoutYAxisAnchor *)centerYAnchor { return anchor(self, kCenterY); }

@implementation NSLayoutGuide
- (id)initWithCoder:(NSCoder *)c { return [self init]; } - (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc { [_identifier release]; [super dealloc]; }
- (NSView *)owningView { return _owner; }
- (void)setOwningView:(NSView *)v { if (v == _owner) return; if (_owner) [_owner removeLayoutGuide:self]; if (v) [v addLayoutGuide:self]; }
- (NSString *)identifier { return _identifier; } - (void)setIdentifier:(NSString *)i { [_identifier release]; _identifier = [i copy]; }
- (NSRect)frame { XEFLayoutSolveIfNeeded(_owner); return _frame; }
- (BOOL)hasAmbiguousLayout { return NO; } - (NSArray *)constraintsAffectingLayoutForOrientation:(NSInteger)o { return @[]; }
ANCHORS
@end

@implementation NSView (XEFLayout)
ANCHORS
- (NSLayoutYAxisAnchor *)firstBaselineAnchor { return anchor(self, kFirstBaseline); } - (NSLayoutYAxisAnchor *)lastBaselineAnchor { return anchor(self, kLastBaseline); }
- (NSArray *)constraints { return [[held(self, NO) copy] autorelease] ?: @[]; }
- (void)addConstraint:(NSLayoutConstraint *)k { if (k && !k->_active) [k _xefInstallIn:self]; }
- (void)addConstraints:(NSArray *)a { for (NSLayoutConstraint *k in a) [self addConstraint:k]; }
- (void)removeConstraint:(NSLayoutConstraint *)k { if (k && k->_active && k->_holder == self) [k setActive:NO]; }
- (void)removeConstraints:(NSArray *)a { for (NSLayoutConstraint *k in a) [self removeConstraint:k]; }
- (NSArray *)layoutGuides { return [[_extra[@"guides"] copy] autorelease] ?: @[]; }
- (void)addLayoutGuide:(NSLayoutGuide *)g {
  if (!g || g->_owner == self) return;
  if (g->_owner) [g->_owner removeLayoutGuide:g];
  NSMutableArray *a = _extra[@"guides"]; if (!a) { a = [NSMutableArray array]; [self _xefExtra][@"guides"] = a; }
  [a addObject:g]; g->_owner = self; XEFLayoutInvalidate(); }
- (void)removeLayoutGuide:(NSLayoutGuide *)g {
  NSMutableArray *a = _extra[@"guides"]; if (![a containsObject:g]) return;
  for (NSLayoutConstraint *k in [NSArray arrayWithArray:g_active]) if (k->_first == g || k->_second == g) [k setActive:NO];
  g->_owner = nil; [a removeObject:g]; XEFLayoutInvalidate(); }
/* guides that follow the view's edges */
- (NSLayoutGuide *)_xefEdgeGuide:(NSString *)key {
  NSLayoutGuide *g = _extra[key];
  if (!g) {
    g = [[[NSLayoutGuide alloc] init] autorelease]; [self _xefExtra][key] = g; [self addLayoutGuide:g];
    [NSLayoutConstraint activateConstraints:@[relate(anchor(g, kLeft), 0, anchor(self, kLeft), 1, 0), relate(anchor(g, kRight), 0, anchor(self, kRight), 1, 0),
                                              relate(anchor(g, kTop), 0, anchor(self, kTop), 1, 0), relate(anchor(g, kBottom), 0, anchor(self, kBottom), 1, 0)]]; }
  return g; }
- (NSLayoutGuide *)safeAreaLayoutGuide { return [self _xefEdgeGuide:@"safeAreaGuide"]; }
- (NSLayoutGuide *)layoutMarginsGuide { return [self _xefEdgeGuide:@"marginsGuide"]; }
- (NSLayoutGuide *)layoutGuideForLayoutRegion:(id)r { return [self _xefEdgeGuide:@"safeAreaGuide"]; }
@end

/* ================================================================== engine */
void XEFLayoutViewGone(NSView *v) {
  if (![g_active count]) return;
  NSArray *guides = v->_extra[@"guides"];
  for (NSLayoutConstraint *k in [NSArray arrayWithArray:g_active]) {
    BOOL touches = k->_first == v || k->_second == v || k->_holder == v;
    for (id g in guides) if (k->_first == g || k->_second == g) touches = YES;
    if (!touches) continue;
    k->_active = NO; [g_active removeObjectIdenticalTo:k];
    if (k->_holder && k->_holder != v) [held(k->_holder, NO) removeObjectIdenticalTo:k];
    k->_holder = nil; if (k->_first == v) k->_first = nil; if (k->_second == v) k->_second = nil; }
  for (NSLayoutGuide *g in guides) g->_owner = nil;
  g_generation++; }

typedef struct { id item; int var; BOOL isGuide; } Item;      /* var: x, y (top, y down), width, height */
typedef struct { Item *items; int n, cap; } Items;
static int item_index(Items *t, id item) { for (int i = 0; i < t->n; i++) if (t->items[i].item == item) return i; return -1; }
static int item_add(Items *t, id item) {
  int i = item_index(t, item); if (i >= 0) return i;
  if (t->n == t->cap) { t->cap = t->cap ? t->cap * 2 : 32; t->items = realloc(t->items, sizeof(Item) * t->cap); }
  t->items[t->n].item = item; t->items[t->n].var = 1 + t->n * 4; t->items[t->n].isGuide = [item isKindOfClass:[NSLayoutGuide class]];
  return t->n++; }
/* an item and, for a view, its ancestors up to the root */
static BOOL item_add_chain(Items *t, id item, NSView *root) {
  NSView *v = view_of(item); if (!v) return NO;
  BOOL inside = NO; for (NSView *a = v; a; a = a->_superview) if (a == root) inside = YES;
  if (!inside) return NO;
  item_add(t, item);
  for (NSView *a = v; a; a = a->_superview) { item_add(t, a); if (a == root) break; }
  return YES; }
/* attribute -> terms over the item's variables; returns the number of terms */
static int attr_terms(Items *t, id item, NSInteger attr, double scale, int *vars, double *coefs) {
  int v = t->items[item_index(t, item)].var, n = 0;
  #define T(var, c) do { vars[n] = (var); coefs[n++] = (c) * scale; } while (0)
  switch (attr) {
    case kLeft: case kLeading: T(v, 1); break;
    case kRight: case kTrailing: T(v, 1); T(v + 2, 1); break;
    case kTop: case kFirstBaseline: T(v + 1, 1); break;
    case kBottom: case kLastBaseline: T(v + 1, 1); T(v + 3, 1); break;
    case kWidth: T(v + 2, 1); break;
    case kHeight: T(v + 3, 1); break;
    case kCenterX: T(v, 1); T(v + 2, 0.5); break;
    case kCenterY: T(v + 1, 1); T(v + 3, 0.5); break;
    default: break; }
  #undef T
  return n; }

static void collect_flexible(NSView *v, Items *t, NSView *root) {
  if (v->_noTranslates && v != root) item_add_chain(t, v, root);
  for (NSView *s in v->_subviews) collect_flexible(s, t, root); }

/* builds and solves the system of `root`'s hierarchy; fitting: the root's size is what is asked for */
static BOOL solve(NSView *root, BOOL fitting, NSSize *fit) {
  Items t = { 0 };
  NSMutableArray *constraints = [NSMutableArray array];
  item_add(&t, root);
  for (NSLayoutConstraint *k in g_active) {
    if (!k->_first) continue;
    NSView *a = view_of(k->_first), *b = k->_second ? view_of(k->_second) : a;
    BOOL in = NO, in2 = NO;
    for (NSView *x = a; x; x = x->_superview) if (x == root) in = YES;
    for (NSView *x = b; x; x = x->_superview) if (x == root) in2 = YES;
    if (!in || !in2) continue;
    item_add_chain(&t, k->_first, root); if (k->_second) item_add_chain(&t, k->_second, root);
    [constraints addObject:k]; }
  if (![constraints count] && !fitting) { free(t.items); return NO; }
  collect_flexible(root, &t, root);

  /* priority levels of this solve, highest first */
  float levels[KMAX]; int nlevels = 0;
  #define LEVEL(p) do { float q = (p); if (q < 1000) { int f = 0; for (int i = 0; i < nlevels; i++) if (levels[i] == q) f = 1; if (!f && nlevels < KMAX) levels[nlevels++] = q; } } while (0)
  LEVEL(490); if (fitting) LEVEL(50);
  for (NSLayoutConstraint *k in constraints) LEVEL(k->_priority);
  for (int i = 0; i < t.n; i++) {
    NSView *v = t.items[i].item; if (t.items[i].isGuide || !v->_noTranslates) continue;
    LEVEL([v contentHuggingPriorityForOrientation:0]); LEVEL([v contentHuggingPriorityForOrientation:1]);
    LEVEL([v contentCompressionResistancePriorityForOrientation:0]); LEVEL([v contentCompressionResistancePriorityForOrientation:1]); }
  #undef LEVEL
  for (int i = 0; i < nlevels; i++) for (int j = i + 1; j < nlevels; j++) if (levels[j] > levels[i]) { float x = levels[i]; levels[i] = levels[j]; levels[j] = x; }
  #define LV(p) ({ float q = (p); int r = -1; if (q < 1000) { r = nlevels - 1; for (int i = 0; i < nlevels; i++) if (levels[i] <= q) { r = i; break; } } r; })

  Solver s = { 0 }; s.next = 1 + t.n * 4; s.levels = nlevels ? nlevels : 1;
  int vars[8]; double coefs[8];
  #define ADD1(var, value, op, lv) do { vars[0] = (var); coefs[0] = 1; solver_add(&s, vars, coefs, 1, -(value), op, lv); } while (0)
  for (int i = 0; i < t.n; i++) {
    int v = t.items[i].var;
    if (t.items[i].isGuide) { ADD1(v + 2, 0, 1, -1); ADD1(v + 3, 0, 1, -1); continue; }
    NSView *view = t.items[i].item;
    if (view == root) {
      ADD1(v, 0, 0, -1); ADD1(v + 1, 0, 0, -1);
      if (fitting) { ADD1(v + 2, 0, 1, -1); ADD1(v + 3, 0, 1, -1); ADD1(v + 2, 0, 0, LV(50)); ADD1(v + 3, 0, 0, LV(50)); }
      else { int lv = view->_window && view->_window->_content == view ? -1 : LV(490); ADD1(v + 2, view->_frame.size.width, 0, lv); ADD1(v + 3, view->_frame.size.height, 0, lv); }
    } else if (!view->_noTranslates) {
      /* the frame as it is: x and width, and the distance from the superview's top (or bottom edge when it is not flipped) */
      NSView *sup = view->_superview; int sv = t.items[item_index(&t, sup)].var; NSRect f = view->_frame;
      vars[0] = v; coefs[0] = 1; vars[1] = sv; coefs[1] = -1; solver_add(&s, vars, coefs, 2, -f.origin.x, 0, -1);
      ADD1(v + 2, f.size.width, 0, -1); ADD1(v + 3, f.size.height, 0, -1);
      if ([sup isFlipped]) { vars[0] = v + 1; coefs[0] = 1; vars[1] = sv + 1; coefs[1] = -1; solver_add(&s, vars, coefs, 2, -f.origin.y, 0, -1); }
      else { vars[0] = v + 1; coefs[0] = 1; vars[1] = sv + 1; coefs[1] = -1; vars[2] = sv + 3; coefs[2] = -1; solver_add(&s, vars, coefs, 3, f.origin.y + f.size.height, 0, -1); }
    } else {
      ADD1(v + 2, 0, 1, -1); ADD1(v + 3, 0, 1, -1);
      NSSize ic = [view intrinsicContentSize];
      if (ic.width >= 0) { ADD1(v + 2, ic.width, -1, LV([view contentHuggingPriorityForOrientation:0])); ADD1(v + 2, ic.width, 1, LV([view contentCompressionResistancePriorityForOrientation:0])); }
      if (ic.height >= 0) { ADD1(v + 3, ic.height, -1, LV([view contentHuggingPriorityForOrientation:1])); ADD1(v + 3, ic.height, 1, LV([view contentCompressionResistancePriorityForOrientation:1])); } } }
  for (NSLayoutConstraint *k in constraints) {
    int n = attr_terms(&t, k->_first, k->_firstAttr, 1, vars, coefs);
    if (k->_second && k->_secondAttr) n += attr_terms(&t, k->_second, k->_secondAttr, -k->_multiplier, vars + n, coefs + n);
    if (!solver_add(&s, vars, coefs, n, -k->_constant, k->_relation < 0 ? -1 : k->_relation > 0 ? 1 : 0, LV(k->_priority)) && getenv("XEF_APPKIT_DEBUG"))
      NSLog(@"xef: unable to satisfy %@", k); }
  #undef ADD1
  #undef LV

  if (fitting) { int v = t.items[0].var; if (fit) *fit = NSMakeSize(solver_value(&s, v + 2), solver_value(&s, v + 3)); }
  else {
    g_in_engine = YES;
    /* a frame is relative to its superview's solved rectangle (the root keeps the size it has) */
    for (int pass = 0; pass < t.n; pass++) {
      int i = pass;
      int v = t.items[i].var; double x = solver_value(&s, v), y = solver_value(&s, v + 1), w = solver_value(&s, v + 2), h = solver_value(&s, v + 3);
      NSView *sup = t.items[i].isGuide ? ((NSLayoutGuide *)t.items[i].item)->_owner : ((NSView *)t.items[i].item)->_superview;
      if (!t.items[i].isGuide && (t.items[i].item == (id)root || !((NSView *)t.items[i].item)->_noTranslates)) continue;
      int si = item_index(&t, sup); if (si < 0) continue;
      int sv = t.items[si].var; double sx = solver_value(&s, sv), sy = solver_value(&s, sv + 1), sh = sup == root ? root->_frame.size.height : solver_value(&s, sv + 3);
      NSRect f = NSMakeRect(x - sx, [sup isFlipped] ? y - sy : sh - (y - sy) - h, w, h);
      if (t.items[i].isGuide) ((NSLayoutGuide *)t.items[i].item)->_frame = f;
      else if (!NSEqualRects(((NSView *)t.items[i].item)->_frame, f)) [(NSView *)t.items[i].item setFrame:f]; }
    g_in_engine = NO; }
  solver_free(&s); free(t.items);
  return YES; }

void XEFLayoutSolveIfNeeded(NSView *v) {
  if (!v || g_in_engine || ![g_active count]) return;
  NSView *root = v; while (root->_superview) root = root->_superview;
  NSString *stamp = [NSString stringWithFormat:@"%lu %g %g", g_generation, root->_frame.size.width, root->_frame.size.height];
  if ([root->_extra[@"layoutStamp"] isEqual:stamp]) return;
  solve(root, NO, NULL);
  [root _xefExtra][@"layoutStamp"] = [NSString stringWithFormat:@"%lu %g %g", g_generation, root->_frame.size.width, root->_frame.size.height]; }

BOOL XEFLayoutFittingSize(NSView *v, NSSize *out) {
  if (!v || g_in_engine) return NO;
  BOOL any = NO;
  for (NSLayoutConstraint *k in g_active) { for (NSView *x = view_of(k->_first); x && !any; x = x->_superview) if (x == v) any = YES; if (any) break; }
  if (!any && !(v->_noTranslates && ([v intrinsicContentSize].width >= 0 || [v intrinsicContentSize].height >= 0))) return NO;
  /* as its own root the view is measured through its constraints and content size */
  NSView *sup = v->_superview; v->_superview = nil;
  BOOL saved = v->_noTranslates; NSSize ic = [v intrinsicContentSize];
  BOOL ok = solve(v, YES, out);
  if (ok && out) { if (ic.width >= 0 && out->width < ic.width) out->width = ic.width; if (ic.height >= 0 && out->height < ic.height) out->height = ic.height; }
  v->_noTranslates = saved; v->_superview = sup;
  return ok; }

/* NSDictionaryOfVariableBindings(a, b) expands to this: the names as written, then the values */
NSDictionary *_NSDictionaryOfVariableBindings(NSString *names, id first, ...) {
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  va_list ap; va_start(ap, first);
  id value = first;
  for (NSString *raw in [names componentsSeparatedByString:@","]) {
    NSString *key = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value && [key length]) d[key] = value;
    value = va_arg(ap, id); }
  va_end(ap);
  return d; }
