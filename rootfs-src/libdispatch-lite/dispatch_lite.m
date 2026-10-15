// libdispatch-lite — a compact Grand Central Dispatch for XEF-OSX, written as plain guest code
// (pthreads + blocks + the Objective-C runtime) so it runs unmodified on top of the HLE libSystem.
//
// It implements the part of the libdispatch ABI that CoreFoundation / Foundation / typical programs use:
// serial + concurrent + global + main queues, sync/async/after/apply/barrier, groups, semaphores,
// once, timer and fd sources, data objects, specifics.  Objects are real Objective-C objects
// (OS_dispatch_*), so ARC retain/release and CF toll-free uses work.
#import <objc/NSObject.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <time.h>
#include <unistd.h>
#include <poll.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/time.h>
#include <Block.h>
#include <mach/mach.h>
#include <mach/message.h>

#define EXPORT __attribute__((visibility("default")))

typedef void (^dispatch_block_t)(void);
typedef void (*dispatch_function_t)(void *);
typedef uint64_t dispatch_time_t;
typedef intptr_t dispatch_qos_class_t_;
typedef void *dispatch_object_t;

#define DISPATCH_TIME_NOW 0ull
#define DISPATCH_TIME_FOREVER (~0ull)

// ---------------------------------------------------------------------------------------------
// time
// ---------------------------------------------------------------------------------------------
static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}
static uint64_t wall_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}
// wall-clock times are encoded as the bitwise negation of the nanoseconds since the epoch
static uint64_t time_to_abs_mono(dispatch_time_t t) {
    if (t == DISPATCH_TIME_FOREVER) return UINT64_MAX;
    if ((int64_t)t < 0) {   // wall clock
        uint64_t wall = ~t;
        uint64_t w = wall_ns();
        return wall > w ? now_ns() + (wall - w) : now_ns();
    }
    return t;
}
EXPORT dispatch_time_t dispatch_time(dispatch_time_t when, int64_t delta) {
    if (when == DISPATCH_TIME_FOREVER) return when;
    if (when == DISPATCH_TIME_NOW) when = now_ns();
    if ((int64_t)when < 0) {   // wall
        uint64_t w = ~when;
        w = delta >= 0 ? w + delta : w - (uint64_t)(-delta);
        return ~w;
    }
    if (delta >= 0) { uint64_t r = when + (uint64_t)delta; return r < when ? DISPATCH_TIME_FOREVER : r; }
    return (uint64_t)(-delta) > when ? 1 : when - (uint64_t)(-delta);
}
EXPORT dispatch_time_t dispatch_walltime(const struct timespec *ts, int64_t delta) {
    uint64_t w;
    if (ts) w = (uint64_t)ts->tv_sec * 1000000000ull + ts->tv_nsec; else w = wall_ns();
    w = delta >= 0 ? w + delta : w - (uint64_t)(-delta);
    return ~w;
}

// ---------------------------------------------------------------------------------------------
// object model
// ---------------------------------------------------------------------------------------------
enum { Q_SERIAL = 0, Q_CONCURRENT = 1, Q_GLOBAL = 2, Q_MAIN = 3, Q_RUNLOOP = 4 };

typedef struct item {
    struct item *next;
    dispatch_block_t block;
    dispatch_function_t fn;
    void *ctx;
    int barrier;
    pthread_mutex_t *sync_lock;     // dispatch_sync waiter
    pthread_cond_t *sync_cond;
    int *sync_done;
} item_t;

@interface OS_dispatch_object : NSObject {
@public
    void *ctx;
    dispatch_function_t finalizer;
    int suspend;
    int inactive;
    void *target;
}
@end
@interface OS_dispatch_queue : OS_dispatch_object {
@public
    char label[96];
    int kind;
    int qos;
    pthread_mutex_t lock;
    item_t *head, *tail;
    int scheduled;      // queued in the ready list or being drained
    int running;        // items currently executing (concurrent)
    int barrier_run;    // a barrier item is executing
    struct spec { struct spec *next; const void *key; void *val; dispatch_function_t dtor; } *specifics;
    struct OS_dispatch_queue_ *unused;
    mach_port_t port;       // wake-up port (main / run loop queues)
}
@end
@interface OS_dispatch_queue_main : OS_dispatch_queue @end
@interface OS_dispatch_queue_global : OS_dispatch_queue @end
@interface OS_dispatch_group : OS_dispatch_object {
@public
    pthread_mutex_t lock;
    pthread_cond_t cond;
    long count;
    struct notify { struct notify *next; OS_dispatch_queue *q; dispatch_block_t blk; dispatch_function_t fn; void *ctx; } *notifies;
}
@end
@interface OS_dispatch_semaphore : OS_dispatch_object {
@public
    pthread_mutex_t lock;
    pthread_cond_t cond;
    long value;
    long orig;
    int waiters;
}
@end
@interface OS_dispatch_source : OS_dispatch_object {
@public
    const void *type;
    uintptr_t handle;
    uintptr_t mask;
    OS_dispatch_queue *queue;
    dispatch_block_t event, cancel, regist;
    dispatch_function_t event_f, cancel_f;
    pthread_mutex_t lock;
    uint64_t deadline, interval;
    unsigned long data;
    int armed, cancelled, pending, started, resumed;
    struct OS_dispatch_source_ *link;
}
@end
@interface OS_dispatch_data : OS_dispatch_object {
@public
    void *buf;
    size_t size;
    dispatch_block_t destructor;
    OS_dispatch_data *a, *b;     // concatenation
    size_t off;                  // subrange of a
    int owned;
}
@end

@implementation OS_dispatch_object
- (void)dealloc {
    if (finalizer) finalizer(ctx);
    [super dealloc];
}
@end
@implementation OS_dispatch_queue
@end
@implementation OS_dispatch_queue_main @end
@implementation OS_dispatch_queue_global @end
@implementation OS_dispatch_group @end
@implementation OS_dispatch_semaphore @end
@implementation OS_dispatch_source @end
@implementation OS_dispatch_data @end

static OS_dispatch_object *obj_new(Class c) {
    return (OS_dispatch_object *)class_createInstance(c, 0);
}

// ---------------------------------------------------------------------------------------------
// worker pool
// ---------------------------------------------------------------------------------------------
static pthread_mutex_t g_pool_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_pool_cond = PTHREAD_COND_INITIALIZER;
typedef struct ready { struct ready *next; OS_dispatch_queue *q; } ready_t;
static ready_t *g_ready_head, *g_ready_tail;
static int g_workers, g_idle, g_max_workers = 8;
static __thread OS_dispatch_queue *tl_cur_queue;    // innermost queue the thread is executing
static __thread struct qctx { struct qctx *prev; OS_dispatch_queue *q; } *tl_qstack;

void _xef_dispatch_wake_main(void);
static void run_item(OS_dispatch_queue *q, item_t *it);
static void *worker_main(void *arg);

static void ready_push(OS_dispatch_queue *q) {
    ready_t *r = malloc(sizeof *r);
    r->next = NULL; r->q = q;
    pthread_mutex_lock(&g_pool_lock);
    if (g_ready_tail) g_ready_tail->next = r; else g_ready_head = r;
    g_ready_tail = r;
    if (g_idle > 0) {
        pthread_cond_signal(&g_pool_cond);
    } else if (g_workers < g_max_workers) {
        g_workers++;
        pthread_t th;
        pthread_attr_t at; pthread_attr_init(&at); pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
        pthread_create(&th, &at, worker_main, NULL);
        pthread_attr_destroy(&at);
    }
    pthread_mutex_unlock(&g_pool_lock);
}

static void push_stack(OS_dispatch_queue *q, struct qctx *c) { c->prev = tl_qstack; c->q = q; tl_qstack = c; }
static void pop_stack(struct qctx *c) { tl_qstack = c->prev; }
static int in_stack(OS_dispatch_queue *q) {
    for (struct qctx *c = tl_qstack; c; c = c->prev) if (c->q == q) return 1;
    return 0;
}

static void finish_item(item_t *it) {
    if (it->sync_lock) {
        pthread_mutex_lock(it->sync_lock);
        *it->sync_done = 1;
        pthread_cond_signal(it->sync_cond);
        pthread_mutex_unlock(it->sync_lock);
    } else {
        if (it->block) Block_release(it->block);
        free(it);
    }
}

static void run_item(OS_dispatch_queue *q, item_t *it) {
    struct qctx c; push_stack(q, &c);
    if (it->block) it->block(); else if (it->fn) it->fn(it->ctx);
    pop_stack(&c);
    finish_item(it);
}

// Drain a queue on a worker. Serial queues run strictly one item at a time; concurrent queues hand one
// item to each worker (barriers wait for running items).
static void drain_queue(OS_dispatch_queue *q) {
    for (;;) {
        pthread_mutex_lock(&q->lock);
        item_t *it = q->head;
        int serial = (q->kind == Q_SERIAL || q->kind == Q_MAIN || q->kind == Q_RUNLOOP);
        if (!it || q->suspend > 0 || (q->kind == Q_MAIN && 0)) {
            if (serial || !it) q->scheduled = 0;
            pthread_mutex_unlock(&q->lock);
            return;
        }
        if (!serial) {
            if (q->barrier_run || (it->barrier && q->running > 0)) {
                q->scheduled = 0;       // the finishing item re-schedules
                pthread_mutex_unlock(&q->lock);
                return;
            }
        }
        q->head = it->next;
        if (!q->head) q->tail = NULL;
        if (!serial) {
            q->running++;
            if (it->barrier) q->barrier_run = 1;
            if (q->head && !it->barrier) {   // let another worker take the next independent item
                pthread_mutex_unlock(&q->lock);
                ready_push(q);
                pthread_mutex_lock(&q->lock);
            } else if (!q->head || it->barrier) {
                q->scheduled = 0;            // nothing left to hand out: later enqueues must schedule the queue again
            }
        }
        pthread_mutex_unlock(&q->lock);
        it->next = NULL;
        run_item(q, it);
        if (!serial) {
            int resched = 0;
            pthread_mutex_lock(&q->lock);
            q->running--;
            q->barrier_run = 0;
            if (q->head && !q->scheduled) { q->scheduled = 1; resched = 1; }
            pthread_mutex_unlock(&q->lock);
            if (resched) ready_push(q);
            return;
        }
    }
}

static void *worker_main(void *arg) {
    (void)arg;
    for (;;) {
        pthread_mutex_lock(&g_pool_lock);
        while (!g_ready_head) {
            g_idle++;
            struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts); ts.tv_sec += 20;
            int r = pthread_cond_timedwait(&g_pool_cond, &g_pool_lock, &ts);
            g_idle--;
            if (r == ETIMEDOUT && !g_ready_head && g_workers > 1) { g_workers--; pthread_mutex_unlock(&g_pool_lock); return NULL; }
        }
        ready_t *r = g_ready_head;
        g_ready_head = r->next;
        if (!g_ready_head) g_ready_tail = NULL;
        pthread_mutex_unlock(&g_pool_lock);
        OS_dispatch_queue *q = r->q;
        free(r);
        OS_dispatch_queue *t = (OS_dispatch_queue *)q->target;
        (void)t;
        drain_queue(q);
    }
    return NULL;
}

// ---------------------------------------------------------------------------------------------
// queues
// ---------------------------------------------------------------------------------------------
static OS_dispatch_queue *g_global[8];   // [qos index]
static OS_dispatch_queue *g_main;
EXPORT struct { uintptr_t pad[8]; } _dispatch_main_q_storage;   // unused placeholder (kept for ABI size)
EXPORT struct dispatch_queue_attr_s_ { uintptr_t kind, qos, inactive, pad; } _dispatch_queue_attr_concurrent = { 1, 0, 0, 0 };
struct dispatch_queue_attr_s_ g_attr_pool[64];
static pthread_mutex_t g_attr_lock = PTHREAD_MUTEX_INITIALIZER;
static int g_attr_n;

// _dispatch_main_q must be a statically allocated object; we reserve space and initialise its class at load.
EXPORT char _dispatch_main_q[512] __attribute__((aligned(16)));

static void queue_init_fields(OS_dispatch_queue *q, const char *label, int kind) {
    pthread_mutex_init(&q->lock, NULL);
    q->kind = kind;
    if (label) strlcpy(q->label, label, sizeof q->label);
}

static OS_dispatch_queue *global_queue(int qos_idx) {
    return g_global[qos_idx & 7];
}

__attribute__((constructor)) static void dispatch_lite_init(void) {
    for (int i = 0; i < 8; i++) {
        OS_dispatch_queue *q = (OS_dispatch_queue *)obj_new([OS_dispatch_queue_global class]);
        queue_init_fields(q, "com.apple.root.queue", Q_GLOBAL);
        q->qos = i;
        g_global[i] = q;
    }
    // static main queue object: lay an instance out in _dispatch_main_q
    Class mc = [OS_dispatch_queue_main class];
    size_t sz = class_getInstanceSize(mc);
    if (sz <= sizeof _dispatch_main_q) {
        memset(_dispatch_main_q, 0, sizeof _dispatch_main_q);
        *(Class *)_dispatch_main_q = mc;
        g_main = (OS_dispatch_queue *)_dispatch_main_q;
        queue_init_fields(g_main, "com.apple.main-thread", Q_MAIN);
    }
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    g_max_workers = n < 4 ? 4 : (n > 16 ? 16 : (int)n);
}

EXPORT dispatch_object_t dispatch_get_global_queue(intptr_t identifier, uintptr_t flags) {
    (void)flags;
    int idx = 2;    // default
    if (identifier == 0x21 || identifier == 2) idx = 3;          // user interactive / high
    else if (identifier == 0x19) idx = 3;
    else if (identifier == 0x15 || identifier == 0) idx = 2;
    else if (identifier == 0x11 || identifier == -2) idx = 1;
    else if (identifier == 0x09 || identifier == INT16_MIN) idx = 0;
    return global_queue(idx);
}

EXPORT dispatch_object_t dispatch_queue_attr_make_with_qos_class(dispatch_object_t attr, int qos, int rel) {
    (void)rel;
    pthread_mutex_lock(&g_attr_lock);
    struct dispatch_queue_attr_s_ *a = &g_attr_pool[g_attr_n++ % 64];
    a->kind = attr ? ((struct dispatch_queue_attr_s_ *)attr)->kind : 0;
    a->qos = qos;
    a->inactive = attr ? ((struct dispatch_queue_attr_s_ *)attr)->inactive : 0;
    pthread_mutex_unlock(&g_attr_lock);
    return a;
}
EXPORT dispatch_object_t dispatch_queue_attr_make_initially_inactive(dispatch_object_t attr) {
    pthread_mutex_lock(&g_attr_lock);
    struct dispatch_queue_attr_s_ *a = &g_attr_pool[g_attr_n++ % 64];
    a->kind = attr ? ((struct dispatch_queue_attr_s_ *)attr)->kind : 0;
    a->qos = attr ? ((struct dispatch_queue_attr_s_ *)attr)->qos : 0;
    a->inactive = 1;
    pthread_mutex_unlock(&g_attr_lock);
    return a;
}
EXPORT dispatch_object_t dispatch_queue_attr_make_with_autorelease_frequency(dispatch_object_t attr, long f) { (void)f; return attr; }

EXPORT dispatch_object_t dispatch_queue_create_with_target(const char *label, dispatch_object_t attr, dispatch_object_t target) {
    OS_dispatch_queue *q = (OS_dispatch_queue *)obj_new([OS_dispatch_queue class]);
    int kind = attr && ((struct dispatch_queue_attr_s_ *)attr)->kind == 1 ? Q_CONCURRENT : Q_SERIAL;
    queue_init_fields(q, label, kind);
    q->target = target;
    if (attr && ((struct dispatch_queue_attr_s_ *)attr)->inactive) { q->inactive = 1; q->suspend = 1; }
    return q;
}
EXPORT dispatch_object_t dispatch_queue_create(const char *label, dispatch_object_t attr) {
    return dispatch_queue_create_with_target(label, attr, NULL);
}
EXPORT dispatch_object_t dispatch_get_main_queue_(void) { return g_main; }
EXPORT const char *dispatch_queue_get_label(dispatch_object_t qo) {
    OS_dispatch_queue *q = qo ? qo : tl_cur_queue ? tl_cur_queue : (tl_qstack ? tl_qstack->q : NULL);
    return q ? q->label : "";
}
EXPORT dispatch_object_t dispatch_get_current_queue(void) { return tl_qstack ? tl_qstack->q : NULL; }
EXPORT dispatch_qos_class_t_ dispatch_queue_get_qos_class(dispatch_object_t q, int *rel) { if (rel) *rel = 0; return 0x15; }
EXPORT void dispatch_set_target_queue(dispatch_object_t o, dispatch_object_t t) { ((OS_dispatch_object *)o)->target = t; }

// effective queue to run on: follow target chain to a root (global/main) queue
static OS_dispatch_queue *root_of(OS_dispatch_queue *q) {
    int guard = 0;
    while (q->target && guard++ < 16) q = (OS_dispatch_queue *)q->target;
    return q;
}

static void enqueue(OS_dispatch_queue *q, item_t *it) {
    pthread_mutex_lock(&q->lock);
    it->next = NULL;
    if (q->tail) q->tail->next = it; else q->head = it;
    q->tail = it;
    int sched = 0;
    if (!q->scheduled && q->suspend <= 0 && q->kind != Q_MAIN && q->kind != Q_RUNLOOP) { q->scheduled = 1; sched = 1; }
    pthread_mutex_unlock(&q->lock);
    if (sched) ready_push(q);
    if (q->kind == Q_MAIN || q->kind == Q_RUNLOOP) {
        if (q->kind == Q_MAIN) _xef_dispatch_wake_main();
        if (q->port) {
            mach_msg_header_t h = {0};
            h.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
            h.msgh_size = sizeof h;
            h.msgh_remote_port = q->port;
            mach_msg(&h, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof h, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
        }
    }
}

static item_t *item_new(dispatch_block_t b, dispatch_function_t f, void *ctx, int barrier) {
    item_t *it = calloc(1, sizeof *it);
    it->block = b ? Block_copy(b) : NULL;
    it->fn = f; it->ctx = ctx; it->barrier = barrier;
    return it;
}

// Queues that target another (non-root) queue funnel through the target; items keep running on the root.
static void submit(OS_dispatch_queue *q, item_t *it) {
    OS_dispatch_queue *t = q;
    if (q->target && q->kind != Q_GLOBAL) {
        // a serial queue with a target is drained through that target: wrap the drain as an item on it
        OS_dispatch_queue *root = root_of(q);
        if (root != q && (q->kind == Q_SERIAL)) {
            pthread_mutex_lock(&q->lock);
            it->next = NULL;
            if (q->tail) q->tail->next = it; else q->head = it;
            q->tail = it;
            int sched = !q->scheduled && q->suspend <= 0;
            if (sched) q->scheduled = 1;
            pthread_mutex_unlock(&q->lock);
            if (sched) {
                item_t *d = item_new(NULL, (dispatch_function_t)drain_queue, q, 0);
                enqueue(root, d);
            }
            return;
        }
        t = root;
    }
    enqueue(t, it);
}

EXPORT void dispatch_async(dispatch_object_t q, dispatch_block_t b) { submit(q, item_new(b, NULL, NULL, 0)); }
EXPORT void dispatch_async_f(dispatch_object_t q, void *ctx, dispatch_function_t f) { submit(q, item_new(NULL, f, ctx, 0)); }
EXPORT void dispatch_barrier_async(dispatch_object_t q, dispatch_block_t b) { submit(q, item_new(b, NULL, NULL, 1)); }
EXPORT void dispatch_barrier_async_f(dispatch_object_t q, void *ctx, dispatch_function_t f) { submit(q, item_new(NULL, f, ctx, 1)); }

static void sync_run(OS_dispatch_queue *q, dispatch_block_t b, dispatch_function_t f, void *ctx, int barrier) {
    int serial = (q->kind == Q_SERIAL || q->kind == Q_MAIN);
    if (in_stack(q) || (tl_qstack && tl_qstack->q == q)) {
        // re-entrant sync on a queue the thread already runs: run inline
        struct qctx c; push_stack(q, &c);
        if (b) b(); else f(ctx);
        pop_stack(&c);
        return;
    }
    if (q->kind == Q_GLOBAL || (q->kind == Q_CONCURRENT && !barrier)) {
        struct qctx c; push_stack(q, &c);
        if (b) b(); else f(ctx);
        pop_stack(&c);
        return;
    }
    // serial (or barrier on concurrent): fast path if the queue is idle
    pthread_mutex_lock(&q->lock);
    if (!q->scheduled && !q->head && q->suspend <= 0 && q->running == 0 && q->kind != Q_MAIN && !q->target) {
        q->scheduled = 1;
        pthread_mutex_unlock(&q->lock);
        struct qctx c; push_stack(q, &c);
        if (b) b(); else f(ctx);
        pop_stack(&c);
        pthread_mutex_lock(&q->lock);
        if (q->head) { pthread_mutex_unlock(&q->lock); ready_push(q); }
        else { q->scheduled = 0; pthread_mutex_unlock(&q->lock); }
        return;
    }
    pthread_mutex_unlock(&q->lock);
    pthread_mutex_t lk = PTHREAD_MUTEX_INITIALIZER;
    pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
    int done = 0;
    item_t *it = calloc(1, sizeof *it);
    it->block = b; it->fn = f; it->ctx = ctx; it->barrier = barrier;
    it->sync_lock = &lk; it->sync_cond = &cv; it->sync_done = &done;
    (void)serial;
    submit(q, it);
    pthread_mutex_lock(&lk);
    while (!done) pthread_cond_wait(&cv, &lk);
    pthread_mutex_unlock(&lk);
    free(it);
}
EXPORT void dispatch_sync(dispatch_object_t q, dispatch_block_t b) { sync_run(q, b, NULL, NULL, 0); }
EXPORT void dispatch_sync_f(dispatch_object_t q, void *ctx, dispatch_function_t f) { sync_run(q, NULL, f, ctx, 0); }
EXPORT void dispatch_barrier_sync(dispatch_object_t q, dispatch_block_t b) { sync_run(q, b, NULL, NULL, 1); }
EXPORT void dispatch_barrier_sync_f(dispatch_object_t q, void *ctx, dispatch_function_t f) { sync_run(q, NULL, f, ctx, 1); }
EXPORT void dispatch_async_and_wait(dispatch_object_t q, dispatch_block_t b) { sync_run(q, b, NULL, NULL, 0); }
EXPORT void dispatch_async_and_wait_f(dispatch_object_t q, void *ctx, dispatch_function_t f) { sync_run(q, NULL, f, ctx, 0); }

EXPORT void dispatch_apply(size_t n, dispatch_object_t q, void (^b)(size_t)) {
    (void)q;
    if (n == 0) return;
    // the synchronisation objects must be shared by pointer: a block copies captured C structs by value
    struct apply_state { size_t next, done; pthread_mutex_t lk; pthread_cond_t cv; } st = { 0, 0, PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER };
    struct apply_state *sp = &st;
    size_t workers = g_max_workers < (int)n ? (size_t)g_max_workers : n;
    void (^body)(void) = ^{
        for (;;) {
            size_t i = __atomic_fetch_add(&sp->next, 1, __ATOMIC_SEQ_CST);
            if (i >= n) break;
            b(i);
            pthread_mutex_lock(&sp->lk);
            if (++sp->done == n) pthread_cond_broadcast(&sp->cv);
            pthread_mutex_unlock(&sp->lk);
        }
    };
    for (size_t w = 1; w < workers; w++) dispatch_async(global_queue(2), body);
    body();
    pthread_mutex_lock(&st.lk);
    while (st.done < n) pthread_cond_wait(&st.cv, &st.lk);
    pthread_mutex_unlock(&st.lk);
}
struct apply_ctx { size_t n; void *ctx; void (*f)(void *, size_t); size_t next, done; pthread_mutex_t lk; pthread_cond_t cv; };
static void apply_worker(void *p) {
    struct apply_ctx *a = p;
    for (;;) {
        size_t i = __atomic_fetch_add(&a->next, 1, __ATOMIC_SEQ_CST);
        if (i >= a->n) break;
        a->f(a->ctx, i);
        pthread_mutex_lock(&a->lk);
        if (++a->done == a->n) pthread_cond_broadcast(&a->cv);
        pthread_mutex_unlock(&a->lk);
    }
}
EXPORT void dispatch_apply_f(size_t n, dispatch_object_t q, void *ctx, void (*f)(void *, size_t)) {
    (void)q;
    if (!n) return;
    struct apply_ctx a = { n, ctx, f, 0, 0, PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER };
    size_t workers = g_max_workers < (int)n ? (size_t)g_max_workers : n;
    for (size_t w = 1; w < workers; w++) dispatch_async_f(global_queue(2), &a, apply_worker);
    apply_worker(&a);
    pthread_mutex_lock(&a.lk);
    while (a.done < n) pthread_cond_wait(&a.cv, &a.lk);
    pthread_mutex_unlock(&a.lk);
}

// ---- timers (one scheduler thread) ----------------------------------------------------------------
typedef struct timer_ent {
    struct timer_ent *next;
    uint64_t when;
    OS_dispatch_queue *q;
    dispatch_block_t blk; dispatch_function_t fn; void *ctx;
    OS_dispatch_source *src;
} timer_ent_t;
static pthread_mutex_t g_timer_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_timer_cond = PTHREAD_COND_INITIALIZER;
static timer_ent_t *g_timers;
static int g_timer_thread;

static void source_fire(OS_dispatch_source *s);

static void *timer_thread(void *arg) {
    (void)arg;
    pthread_mutex_lock(&g_timer_lock);
    for (;;) {
        if (!g_timers) { pthread_cond_wait(&g_timer_cond, &g_timer_lock); continue; }
        uint64_t now = now_ns();
        timer_ent_t *t = g_timers;
        if (t->when > now) {
            uint64_t d = t->when - now;
            struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
            uint64_t ns = (uint64_t)ts.tv_nsec + (d % 1000000000ull);
            ts.tv_sec += d / 1000000000ull + ns / 1000000000ull; ts.tv_nsec = ns % 1000000000ull;
            pthread_cond_timedwait(&g_timer_cond, &g_timer_lock, &ts);
            continue;
        }
        g_timers = t->next;
        pthread_mutex_unlock(&g_timer_lock);
        if (t->src) source_fire(t->src);
        else if (t->blk) { dispatch_async(t->q, t->blk); Block_release(t->blk); }
        else dispatch_async_f(t->q, t->ctx, t->fn);
        free(t);
        pthread_mutex_lock(&g_timer_lock);
    }
    return NULL;
}
static void timer_insert(timer_ent_t *t) {
    pthread_mutex_lock(&g_timer_lock);
    if (!g_timer_thread) {
        g_timer_thread = 1;
        pthread_t th; pthread_attr_t at; pthread_attr_init(&at); pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
        pthread_create(&th, &at, timer_thread, NULL);
    }
    timer_ent_t **p = &g_timers;
    while (*p && (*p)->when <= t->when) p = &(*p)->next;
    t->next = *p; *p = t;
    pthread_cond_signal(&g_timer_cond);
    pthread_mutex_unlock(&g_timer_lock);
}
static void timer_remove_source(OS_dispatch_source *s) {
    pthread_mutex_lock(&g_timer_lock);
    for (timer_ent_t **p = &g_timers; *p;) {
        if ((*p)->src == s) { timer_ent_t *d = *p; *p = d->next; free(d); } else p = &(*p)->next;
    }
    pthread_mutex_unlock(&g_timer_lock);
}

EXPORT void dispatch_after(dispatch_time_t when, dispatch_object_t q, dispatch_block_t b) {
    timer_ent_t *t = calloc(1, sizeof *t);
    t->when = time_to_abs_mono(when); t->q = q; t->blk = Block_copy(b);
    timer_insert(t);
}
EXPORT void dispatch_after_f(dispatch_time_t when, dispatch_object_t q, void *ctx, dispatch_function_t f) {
    timer_ent_t *t = calloc(1, sizeof *t);
    t->when = time_to_abs_mono(when); t->q = q; t->fn = f; t->ctx = ctx;
    timer_insert(t);
}

// ---------------------------------------------------------------------------------------------
// generic object calls
// ---------------------------------------------------------------------------------------------
EXPORT void dispatch_retain(dispatch_object_t o) { if (o && o != g_main && o != (void *)_dispatch_main_q) [(id)o retain]; }
EXPORT void dispatch_release(dispatch_object_t o) { if (o && o != g_main && o != (void *)_dispatch_main_q) [(id)o release]; }
EXPORT void *dispatch_get_context(dispatch_object_t o) { return ((OS_dispatch_object *)o)->ctx; }
EXPORT void dispatch_set_context(dispatch_object_t o, void *c) { ((OS_dispatch_object *)o)->ctx = c; }
EXPORT void dispatch_set_finalizer_f(dispatch_object_t o, dispatch_function_t f) { ((OS_dispatch_object *)o)->finalizer = f; }
EXPORT void dispatch_suspend(dispatch_object_t o) {
    OS_dispatch_object *obj = o;
    if ([obj isKindOfClass:[OS_dispatch_queue class]]) {
        OS_dispatch_queue *q = o;
        pthread_mutex_lock(&q->lock); q->suspend++; pthread_mutex_unlock(&q->lock);
    } else obj->suspend++;
}
static void source_resume_locked(OS_dispatch_source *s);
EXPORT void dispatch_resume(dispatch_object_t o) {
    OS_dispatch_object *obj = o;
    if ([obj isKindOfClass:[OS_dispatch_queue class]]) {
        OS_dispatch_queue *q = o;
        int sched = 0;
        pthread_mutex_lock(&q->lock);
        if (q->suspend > 0) q->suspend--;
        if (q->suspend <= 0 && q->head && !q->scheduled && q->kind != Q_MAIN) { q->scheduled = 1; sched = 1; }
        pthread_mutex_unlock(&q->lock);
        if (sched) ready_push(q);
    } else if ([obj isKindOfClass:[OS_dispatch_source class]]) {
        OS_dispatch_source *s = o;
        if (s->suspend > 0) s->suspend--;
        if (s->suspend <= 0) source_resume_locked(s);
    } else if (obj->suspend > 0) obj->suspend--;
}
EXPORT void dispatch_activate(dispatch_object_t o) {
    OS_dispatch_object *obj = o;
    if (obj->inactive) { obj->inactive = 0; dispatch_resume(o); }
    else if ([obj isKindOfClass:[OS_dispatch_source class]]) dispatch_resume(o);
}

// ---------------------------------------------------------------------------------------------
// specifics
// ---------------------------------------------------------------------------------------------
EXPORT void dispatch_queue_set_specific(dispatch_object_t qo, const void *key, void *val, dispatch_function_t dtor) {
    OS_dispatch_queue *q = qo;
    pthread_mutex_lock(&q->lock);
    for (struct spec *s = q->specifics; s; s = s->next)
        if (s->key == key) { if (s->dtor && s->val) s->dtor(s->val); s->val = val; s->dtor = dtor; pthread_mutex_unlock(&q->lock); return; }
    struct spec *s = calloc(1, sizeof *s);
    s->key = key; s->val = val; s->dtor = dtor; s->next = q->specifics; q->specifics = s;
    pthread_mutex_unlock(&q->lock);
}
EXPORT void *dispatch_queue_get_specific(dispatch_object_t qo, const void *key) {
    OS_dispatch_queue *q = qo;
    void *r = NULL;
    pthread_mutex_lock(&q->lock);
    for (struct spec *s = q->specifics; s; s = s->next) if (s->key == key) { r = s->val; break; }
    pthread_mutex_unlock(&q->lock);
    return r;
}
EXPORT void *dispatch_get_specific(const void *key) {
    for (struct qctx *c = tl_qstack; c; c = c->prev) {
        void *v = dispatch_queue_get_specific(c->q, key);
        if (v) return v;
    }
    return NULL;
}
EXPORT void dispatch_assert_queue(dispatch_object_t q) { (void)q; }
EXPORT void dispatch_assert_queue_not(dispatch_object_t q) { (void)q; }
EXPORT void dispatch_assert_queue_barrier(dispatch_object_t q) { (void)q; }

// ---------------------------------------------------------------------------------------------
// once
// ---------------------------------------------------------------------------------------------
static pthread_mutex_t g_once_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_once_cond = PTHREAD_COND_INITIALIZER;
EXPORT void dispatch_once_f(intptr_t *pred, void *ctx, dispatch_function_t f) {
    if (__atomic_load_n(pred, __ATOMIC_ACQUIRE) == ~(intptr_t)0) return;
    pthread_mutex_lock(&g_once_lock);
    if (*pred == 0) {
        *pred = 1;      // running
        pthread_mutex_unlock(&g_once_lock);
        f(ctx);
        pthread_mutex_lock(&g_once_lock);
        __atomic_store_n(pred, ~(intptr_t)0, __ATOMIC_RELEASE);
        pthread_cond_broadcast(&g_once_cond);
    } else {
        while (*pred != ~(intptr_t)0) pthread_cond_wait(&g_once_cond, &g_once_lock);
    }
    pthread_mutex_unlock(&g_once_lock);
}
static void once_block_tramp(void *c) { ((dispatch_block_t)c)(); }
EXPORT void dispatch_once(intptr_t *pred, dispatch_block_t b) { dispatch_once_f(pred, b, once_block_tramp); }

// ---------------------------------------------------------------------------------------------
// semaphores & groups
// ---------------------------------------------------------------------------------------------
EXPORT dispatch_object_t dispatch_semaphore_create(long value) {
    if (value < 0) return NULL;
    OS_dispatch_semaphore *s = (OS_dispatch_semaphore *)obj_new([OS_dispatch_semaphore class]);
    pthread_mutex_init(&s->lock, NULL); pthread_cond_init(&s->cond, NULL);
    s->value = s->orig = value;
    return s;
}
EXPORT long dispatch_semaphore_signal(dispatch_object_t so) {
    OS_dispatch_semaphore *s = so;
    pthread_mutex_lock(&s->lock);
    s->value++;
    int woke = s->waiters > 0;
    if (woke) pthread_cond_signal(&s->cond);
    pthread_mutex_unlock(&s->lock);
    return woke;
}
EXPORT long dispatch_semaphore_wait(dispatch_object_t so, dispatch_time_t timeout) {
    OS_dispatch_semaphore *s = so;
    pthread_mutex_lock(&s->lock);
    while (s->value <= 0) {
        if (timeout == DISPATCH_TIME_NOW) { pthread_mutex_unlock(&s->lock); return 49; }
        s->waiters++;
        if (timeout == DISPATCH_TIME_FOREVER) {
            pthread_cond_wait(&s->cond, &s->lock);
            s->waiters--;
        } else {
            uint64_t abs = time_to_abs_mono(timeout), now = now_ns();
            if (abs <= now) { s->waiters--; pthread_mutex_unlock(&s->lock); return 49; }
            uint64_t d = abs - now;
            struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
            uint64_t ns = (uint64_t)ts.tv_nsec + (d % 1000000000ull);
            ts.tv_sec += d / 1000000000ull + ns / 1000000000ull; ts.tv_nsec = ns % 1000000000ull;
            int r = pthread_cond_timedwait(&s->cond, &s->lock, &ts);
            s->waiters--;
            if (r == ETIMEDOUT && s->value <= 0) { pthread_mutex_unlock(&s->lock); return 49; }
        }
    }
    s->value--;
    pthread_mutex_unlock(&s->lock);
    return 0;
}

EXPORT dispatch_object_t dispatch_group_create(void) {
    OS_dispatch_group *g = (OS_dispatch_group *)obj_new([OS_dispatch_group class]);
    pthread_mutex_init(&g->lock, NULL); pthread_cond_init(&g->cond, NULL);
    return g;
}
EXPORT void dispatch_group_enter(dispatch_object_t go) {
    OS_dispatch_group *g = go;
    pthread_mutex_lock(&g->lock); g->count++; pthread_mutex_unlock(&g->lock);
}
EXPORT void dispatch_group_leave(dispatch_object_t go) {
    OS_dispatch_group *g = go;
    pthread_mutex_lock(&g->lock);
    if (--g->count == 0) {
        pthread_cond_broadcast(&g->cond);
        struct notify *n = g->notifies; g->notifies = NULL;
        pthread_mutex_unlock(&g->lock);
        while (n) {
            struct notify *nx = n->next;
            if (n->blk) { dispatch_async(n->q, n->blk); Block_release(n->blk); }
            else dispatch_async_f(n->q, n->ctx, n->fn);
            free(n);
            n = nx;
        }
        return;
    }
    pthread_mutex_unlock(&g->lock);
}
EXPORT long dispatch_group_wait(dispatch_object_t go, dispatch_time_t timeout) {
    OS_dispatch_group *g = go;
    pthread_mutex_lock(&g->lock);
    while (g->count > 0) {
        if (timeout == DISPATCH_TIME_NOW) { pthread_mutex_unlock(&g->lock); return 49; }
        if (timeout == DISPATCH_TIME_FOREVER) { pthread_cond_wait(&g->cond, &g->lock); continue; }
        uint64_t abs = time_to_abs_mono(timeout), now = now_ns();
        if (abs <= now) { pthread_mutex_unlock(&g->lock); return 49; }
        uint64_t d = abs - now;
        struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
        uint64_t ns = (uint64_t)ts.tv_nsec + (d % 1000000000ull);
        ts.tv_sec += d / 1000000000ull + ns / 1000000000ull; ts.tv_nsec = ns % 1000000000ull;
        pthread_cond_timedwait(&g->cond, &g->lock, &ts);
    }
    pthread_mutex_unlock(&g->lock);
    return 0;
}
static void group_notify(OS_dispatch_group *g, OS_dispatch_queue *q, dispatch_block_t b, dispatch_function_t f, void *ctx) {
    pthread_mutex_lock(&g->lock);
    if (g->count == 0) {
        pthread_mutex_unlock(&g->lock);
        if (b) dispatch_async(q, b); else dispatch_async_f(q, ctx, f);
        return;
    }
    struct notify *n = calloc(1, sizeof *n);
    n->q = q; n->blk = b ? Block_copy(b) : NULL; n->fn = f; n->ctx = ctx;
    n->next = g->notifies; g->notifies = n;
    pthread_mutex_unlock(&g->lock);
}
EXPORT void dispatch_group_notify(dispatch_object_t g, dispatch_object_t q, dispatch_block_t b) { group_notify(g, q, b, NULL, NULL); }
EXPORT void dispatch_group_notify_f(dispatch_object_t g, dispatch_object_t q, void *ctx, dispatch_function_t f) { group_notify(g, q, NULL, f, ctx); }
EXPORT void dispatch_group_async(dispatch_object_t g, dispatch_object_t q, dispatch_block_t b) {
    dispatch_group_enter(g);
    dispatch_async(q, ^{ b(); dispatch_group_leave(g); });
}
EXPORT void dispatch_group_async_f(dispatch_object_t g, dispatch_object_t q, void *ctx, dispatch_function_t f) {
    dispatch_group_enter(g);
    dispatch_async(q, ^{ f(ctx); dispatch_group_leave(g); });
}

// ---------------------------------------------------------------------------------------------
// sources
// ---------------------------------------------------------------------------------------------
EXPORT char _dispatch_source_type_timer[64], _dispatch_source_type_read[64], _dispatch_source_type_write[64],
            _dispatch_source_type_signal[64], _dispatch_source_type_proc[64], _dispatch_source_type_vnode[64],
            _dispatch_source_type_data_add[64], _dispatch_source_type_data_or[64], _dispatch_source_type_data_replace[64],
            _dispatch_source_type_mach_send[64], _dispatch_source_type_mach_recv[64], _dispatch_source_type_memorypressure[64];

static pthread_mutex_t g_io_lock = PTHREAD_MUTEX_INITIALIZER;
static OS_dispatch_source *g_io_sources[256];
static int g_io_n, g_io_thread, g_io_pipe[2];

static void source_fire(OS_dispatch_source *s) {
    pthread_mutex_lock(&s->lock);
    if (s->cancelled || !s->resumed) { pthread_mutex_unlock(&s->lock); return; }
    int dec = (s->type == _dispatch_source_type_timer);
    s->data += dec ? 1 : 1;
    if (s->pending) { pthread_mutex_unlock(&s->lock); return; }
    s->pending = 1;
    pthread_mutex_unlock(&s->lock);
    [(id)s retain];
    dispatch_async(s->queue, ^{
        pthread_mutex_lock(&s->lock);
        s->pending = 0;
        int cancelled = s->cancelled;
        pthread_mutex_unlock(&s->lock);
        if (!cancelled) { if (s->event) s->event(); else if (s->event_f) s->event_f(s->ctx); }
        pthread_mutex_lock(&s->lock);
        s->data = 0;
        pthread_mutex_unlock(&s->lock);
        [(id)s release];
    });
}

static void *io_thread(void *arg) {
    (void)arg;
    for (;;) {
        struct pollfd pfds[257];
        OS_dispatch_source *srcs[257];
        int n = 0;
        pfds[n].fd = g_io_pipe[0]; pfds[n].events = POLLIN; srcs[n] = NULL; n++;
        pthread_mutex_lock(&g_io_lock);
        for (int i = 0; i < g_io_n; i++) {
            OS_dispatch_source *s = g_io_sources[i];
            if (!s->resumed || s->cancelled) continue;
            pfds[n].fd = (int)s->handle;
            pfds[n].events = s->type == _dispatch_source_type_read ? POLLIN : POLLOUT;
            srcs[n] = s; n++;
        }
        pthread_mutex_unlock(&g_io_lock);
        int r = poll(pfds, n, 500);
        if (r <= 0) continue;
        if (pfds[0].revents) { char b[64]; read(g_io_pipe[0], b, sizeof b); }
        for (int i = 1; i < n; i++)
            if (pfds[i].revents & (POLLIN | POLLOUT | POLLHUP | POLLERR)) { source_fire(srcs[i]); usleep(1000); }
    }
    return NULL;
}

static void source_start_timer(OS_dispatch_source *s) {
    timer_ent_t *t = calloc(1, sizeof *t);
    t->when = s->deadline; t->src = s; t->q = s->queue;
    timer_insert(t);
}

static void source_resume_locked(OS_dispatch_source *s) {
    if (s->resumed) return;
    s->resumed = 1;
    if (s->type == _dispatch_source_type_timer) {
        if (s->deadline) source_start_timer(s);
    } else if (s->type == _dispatch_source_type_read || s->type == _dispatch_source_type_write) {
        pthread_mutex_lock(&g_io_lock);
        if (!g_io_thread) {
            g_io_thread = 1; pipe(g_io_pipe);
            pthread_t th; pthread_attr_t at; pthread_attr_init(&at); pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
            pthread_create(&th, &at, io_thread, NULL);
        }
        if (g_io_n < 256) g_io_sources[g_io_n++] = s;
        pthread_mutex_unlock(&g_io_lock);
        write(g_io_pipe[1], "x", 1);
    }
    if (s->regist) { dispatch_async(s->queue, s->regist); }
}

EXPORT dispatch_object_t dispatch_source_create(const void *type, uintptr_t handle, uintptr_t mask, dispatch_object_t queue) {
    OS_dispatch_source *s = (OS_dispatch_source *)obj_new([OS_dispatch_source class]);
    pthread_mutex_init(&s->lock, NULL);
    s->type = type; s->handle = handle; s->mask = mask;
    s->queue = queue ? queue : global_queue(2);
    s->suspend = 1;     // sources start suspended
    return s;
}
EXPORT void dispatch_source_set_event_handler(dispatch_object_t so, dispatch_block_t b) {
    OS_dispatch_source *s = so; if (s->event) Block_release(s->event); s->event = b ? Block_copy(b) : NULL;
}
EXPORT void dispatch_source_set_event_handler_f(dispatch_object_t so, dispatch_function_t f) { ((OS_dispatch_source *)so)->event_f = f; }
EXPORT void dispatch_source_set_cancel_handler(dispatch_object_t so, dispatch_block_t b) {
    OS_dispatch_source *s = so; if (s->cancel) Block_release(s->cancel); s->cancel = b ? Block_copy(b) : NULL;
}
EXPORT void dispatch_source_set_cancel_handler_f(dispatch_object_t so, dispatch_function_t f) { ((OS_dispatch_source *)so)->cancel_f = f; }
EXPORT void dispatch_source_set_registration_handler(dispatch_object_t so, dispatch_block_t b) {
    OS_dispatch_source *s = so; if (s->regist) Block_release(s->regist); s->regist = b ? Block_copy(b) : NULL;
}
EXPORT void dispatch_source_set_timer(dispatch_object_t so, dispatch_time_t start, uint64_t interval, uint64_t leeway) {
    (void)leeway;
    OS_dispatch_source *s = so;
    timer_remove_source(s);
    s->deadline = time_to_abs_mono(start);
    s->interval = interval;
    if (s->resumed && s->deadline) source_start_timer(s);
}
EXPORT void dispatch_source_cancel(dispatch_object_t so) {
    OS_dispatch_source *s = so;
    pthread_mutex_lock(&s->lock);
    if (s->cancelled) { pthread_mutex_unlock(&s->lock); return; }
    s->cancelled = 1;
    pthread_mutex_unlock(&s->lock);
    timer_remove_source(s);
    pthread_mutex_lock(&g_io_lock);
    for (int i = 0; i < g_io_n; i++) if (g_io_sources[i] == s) { g_io_sources[i] = g_io_sources[--g_io_n]; break; }
    pthread_mutex_unlock(&g_io_lock);
    if (s->cancel || s->cancel_f) {
        [(id)s retain];
        dispatch_async(s->queue, ^{
            if (s->cancel) s->cancel(); else s->cancel_f(s->ctx);
            [(id)s release];
        });
    }
}
EXPORT long dispatch_source_testcancel(dispatch_object_t so) { return ((OS_dispatch_source *)so)->cancelled; }
EXPORT unsigned long dispatch_source_get_data(dispatch_object_t so) { return ((OS_dispatch_source *)so)->data; }
EXPORT uintptr_t dispatch_source_get_handle(dispatch_object_t so) { return ((OS_dispatch_source *)so)->handle; }
EXPORT uintptr_t dispatch_source_get_mask(dispatch_object_t so) { return ((OS_dispatch_source *)so)->mask; }
EXPORT void dispatch_source_merge_data(dispatch_object_t so, unsigned long v) {
    OS_dispatch_source *s = so;
    pthread_mutex_lock(&s->lock); s->data += v; pthread_mutex_unlock(&s->lock);
    source_fire(s);
}

// ---------------------------------------------------------------------------------------------
// main queue / CoreFoundation hooks
// ---------------------------------------------------------------------------------------------
static pthread_mutex_t g_main_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_main_cond = PTHREAD_COND_INITIALIZER;
static int g_main_wake;
void _xef_dispatch_wake_main(void) {
    pthread_mutex_lock(&g_main_lock);
    g_main_wake = 1;
    pthread_cond_broadcast(&g_main_cond);
    pthread_mutex_unlock(&g_main_lock);
}
static int drain_main(OS_dispatch_queue *q) {
    int ran = 0;
    for (;;) {
        pthread_mutex_lock(&q->lock);
        item_t *it = q->head;
        if (!it) { pthread_mutex_unlock(&q->lock); return ran; }
        q->head = it->next; if (!q->head) q->tail = NULL;
        pthread_mutex_unlock(&q->lock);
        it->next = NULL;
        run_item(q, it);
        ran = 1;
    }
}
EXPORT void dispatch_main(void) {
    for (;;) {
        drain_main(g_main);
        pthread_mutex_lock(&g_main_lock);
        while (!g_main_wake) pthread_cond_wait(&g_main_cond, &g_main_lock);
        g_main_wake = 0;
        pthread_mutex_unlock(&g_main_lock);
    }
}
static mach_port_t queue_port(OS_dispatch_queue *q) {
    pthread_mutex_lock(&q->lock);
    if (!q->port) {
        mach_port_t p = MACH_PORT_NULL;
        if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &p) == KERN_SUCCESS) {
            mach_port_insert_right(mach_task_self(), p, p, MACH_MSG_TYPE_MAKE_SEND);
            q->port = p;
        }
    }
    mach_port_t r = q->port;
    pthread_mutex_unlock(&q->lock);
    return r;
}
EXPORT unsigned int _dispatch_get_main_queue_port_4CF(void) { return queue_port(g_main); }
EXPORT void _dispatch_main_queue_callback_4CF(void *msg) { (void)msg; drain_main(g_main); }
EXPORT dispatch_object_t _dispatch_runloop_root_queue_create_4CF(const char *label, unsigned long flags) {
    (void)flags;
    OS_dispatch_queue *q = (OS_dispatch_queue *)obj_new([OS_dispatch_queue class]);
    queue_init_fields(q, label, Q_RUNLOOP);
    return q;
}
EXPORT unsigned int _dispatch_runloop_root_queue_get_port_4CF(dispatch_object_t q) { return queue_port(q); }
EXPORT int _dispatch_runloop_root_queue_perform_4CF(dispatch_object_t q) { return drain_main(q); }
EXPORT void _dispatch_source_set_runloop_timer_4CF(dispatch_object_t s, dispatch_time_t start, uint64_t interval, uint64_t leeway) {
    dispatch_source_set_timer(s, start, interval, leeway);
}
EXPORT void _dispatch_runloop_root_queue_wakeup_4CF(dispatch_object_t q) { (void)q; _xef_dispatch_wake_main(); }
EXPORT int _dispatch_runloop_root_queue_perform_4CF_(dispatch_object_t q) { return drain_main(q); }

// ---------------------------------------------------------------------------------------------
// blocks
// ---------------------------------------------------------------------------------------------
EXPORT dispatch_block_t dispatch_block_create(unsigned long flags, dispatch_block_t b) { (void)flags; return Block_copy(b); }
EXPORT void dispatch_block_perform(unsigned long flags, dispatch_block_t b) { (void)flags; b(); }
EXPORT void dispatch_block_cancel(dispatch_block_t b) { (void)b; }
EXPORT long dispatch_block_testcancel(dispatch_block_t b) { (void)b; return 0; }
EXPORT long dispatch_block_wait(dispatch_block_t b, dispatch_time_t t) { (void)b; (void)t; return 0; }
EXPORT void dispatch_block_notify(dispatch_block_t b, dispatch_object_t q, dispatch_block_t n) { (void)b; dispatch_async(q, n); }

// ---------------------------------------------------------------------------------------------
// data
// ---------------------------------------------------------------------------------------------
EXPORT struct { uintptr_t pad[8]; } _dispatch_data_empty;
EXPORT void *_dispatch_data_destructor_free = 0, *_dispatch_data_destructor_munmap = 0;
static OS_dispatch_data *data_new(void) { return (OS_dispatch_data *)obj_new([OS_dispatch_data class]); }
EXPORT dispatch_object_t dispatch_data_create(const void *buf, size_t size, dispatch_object_t q, dispatch_block_t destructor) {
    (void)q;
    OS_dispatch_data *d = data_new();
    d->size = size;
    if (destructor == NULL) { d->buf = malloc(size ? size : 1); memcpy(d->buf, buf, size); d->owned = 1; }
    else { d->buf = (void *)buf; d->destructor = Block_copy(destructor); }
    return d;
}
EXPORT size_t dispatch_data_get_size(dispatch_object_t d) { return d ? ((OS_dispatch_data *)d)->size : 0; }
static void data_flatten(OS_dispatch_data *d, uint8_t *out) {
    if (d->a) {
        if (d->b) { data_flatten(d->a, out); data_flatten(d->b, out + d->a->size); }
        else { uint8_t *tmp = malloc(d->a->size ? d->a->size : 1); data_flatten(d->a, tmp); memcpy(out, tmp + d->off, d->size); free(tmp); }
    } else memcpy(out, d->buf, d->size);
}
EXPORT dispatch_object_t dispatch_data_create_concat(dispatch_object_t x, dispatch_object_t y) {
    OS_dispatch_data *d = data_new();
    d->a = x; d->b = y; d->size = ((OS_dispatch_data *)x)->size + ((OS_dispatch_data *)y)->size;
    [(id)x retain]; [(id)y retain];
    return d;
}
EXPORT dispatch_object_t dispatch_data_create_subrange(dispatch_object_t x, size_t off, size_t len) {
    OS_dispatch_data *d = data_new();
    d->a = x; d->off = off; d->size = len;
    [(id)x retain];
    return d;
}
EXPORT dispatch_object_t dispatch_data_create_map(dispatch_object_t x, const void **buf, size_t *size) {
    OS_dispatch_data *s = x, *d = data_new();
    d->size = s->size; d->buf = malloc(s->size ? s->size : 1); d->owned = 1;
    data_flatten(s, d->buf);
    if (buf) *buf = d->buf;
    if (size) *size = d->size;
    return d;
}
EXPORT int dispatch_data_apply(dispatch_object_t x, int (^applier)(dispatch_object_t, size_t, const void *, size_t)) {
    OS_dispatch_data *s = x;
    if (!s->size) return 1;
    OS_dispatch_data *m = dispatch_data_create_map(x, NULL, NULL);
    int r = applier(x, 0, m->buf, m->size);
    [(id)m release];
    return r;
}
EXPORT dispatch_object_t dispatch_data_copy_region(dispatch_object_t x, size_t loc, size_t *off) {
    if (off) *off = 0;
    [(id)x retain];
    (void)loc;
    return x;
}

// ---------------------------------------------------------------------------------------------
// dispatch_io (blocking reads/writes executed on the target queue)
// ---------------------------------------------------------------------------------------------
typedef void (^io_handler_t)(int done, dispatch_object_t data, int error);
typedef void (^io_cleanup_t)(int error);
@interface OS_dispatch_io : OS_dispatch_object { @public int fd; int owned; io_cleanup_t cleanup; OS_dispatch_queue *queue; } @end
@implementation OS_dispatch_io @end

EXPORT dispatch_object_t dispatch_io_create(unsigned long type, int fd, dispatch_object_t q, io_cleanup_t cleanup) {
    (void)type;
    OS_dispatch_io *io = (OS_dispatch_io *)obj_new([OS_dispatch_io class]);
    io->fd = fd; io->queue = q; io->cleanup = cleanup ? Block_copy(cleanup) : NULL;
    return io;
}
EXPORT dispatch_object_t dispatch_io_create_with_path(unsigned long type, const char *path, int oflag, unsigned mode, dispatch_object_t q, io_cleanup_t cleanup) {
    int fd = open(path, oflag, mode);
    if (fd < 0) { if (cleanup) dispatch_async(q, ^{ cleanup(errno); }); return NULL; }
    OS_dispatch_io *io = dispatch_io_create(type, fd, q, cleanup);
    io->owned = 1;
    return io;
}
EXPORT void dispatch_io_set_low_water(dispatch_object_t io, size_t n) { (void)io; (void)n; }
EXPORT void dispatch_io_set_high_water(dispatch_object_t io, size_t n) { (void)io; (void)n; }
EXPORT void dispatch_io_set_interval(dispatch_object_t io, uint64_t n, unsigned long f) { (void)io; (void)n; (void)f; }
EXPORT void dispatch_io_barrier(dispatch_object_t io, dispatch_block_t b) { dispatch_async(((OS_dispatch_io *)io)->queue, b); }
EXPORT void dispatch_io_close(dispatch_object_t o, unsigned long flags) {
    (void)flags;
    OS_dispatch_io *io = o;
    if (io->owned && io->fd >= 0) close(io->fd);
    io->fd = -1;
    if (io->cleanup) { io_cleanup_t c = io->cleanup; io->cleanup = NULL; dispatch_async(io->queue, ^{ c(0); Block_release(c); }); }
}
EXPORT void dispatch_io_read(dispatch_object_t o, off_t offset, size_t length, dispatch_object_t q, io_handler_t handler) {
    OS_dispatch_io *io = o;
    int fd = io->fd;
    io_handler_t h = Block_copy(handler);
    dispatch_async(q, ^{
        size_t cap = length == SIZE_MAX ? 65536 : length;
        uint8_t *buf = malloc(cap ? cap : 1);
        size_t got = 0; int err = 0;
        while (got < cap) {
            ssize_t r = offset >= 0 && 0 ? pread(fd, buf + got, cap - got, offset + got) : read(fd, buf + got, cap - got);
            if (r < 0) { err = errno; break; }
            if (r == 0) break;
            got += r;
            if (length == SIZE_MAX && got == cap) { cap *= 2; buf = realloc(buf, cap); }
        }
        __block uint8_t *b = buf;
        dispatch_object_t d = dispatch_data_create(buf, got, q, ^{ free(b); });
        h(1, d, err);
        [(id)d release];
        Block_release(h);
    });
}
EXPORT void dispatch_io_write(dispatch_object_t o, off_t offset, dispatch_object_t data, dispatch_object_t q, io_handler_t handler) {
    (void)offset;
    OS_dispatch_io *io = o;
    int fd = io->fd;
    io_handler_t h = Block_copy(handler);
    [(id)data retain];
    dispatch_async(q, ^{
        const void *p = NULL; size_t n = 0;
        dispatch_object_t m = dispatch_data_create_map(data, &p, &n);
        size_t done = 0; int err = 0;
        while (done < n) { ssize_t r = write(fd, (const char *)p + done, n - done); if (r < 0) { err = errno; break; } done += r; }
        [(id)m release];
        h(1, NULL, err);
        [(id)data release];
        Block_release(h);
    });
}
EXPORT void dispatch_read(int fd, size_t length, dispatch_object_t q, void (^handler)(dispatch_object_t, int)) {
    void (^h)(dispatch_object_t, int) = Block_copy(handler);
    dispatch_async(q, ^{
        uint8_t *buf = malloc(length ? length : 1);
        ssize_t r = read(fd, buf, length);
        int err = r < 0 ? errno : 0;
        __block uint8_t *b = buf;
        dispatch_object_t d = dispatch_data_create(buf, r > 0 ? r : 0, q, ^{ free(b); });
        h(d, err);
        [(id)d release];
        Block_release(h);
    });
}
EXPORT void dispatch_write(int fd, dispatch_object_t data, dispatch_object_t q, void (^handler)(dispatch_object_t, int)) {
    void (^h)(dispatch_object_t, int) = Block_copy(handler);
    [(id)data retain];
    dispatch_async(q, ^{
        const void *p = NULL; size_t n = 0;
        dispatch_object_t m = dispatch_data_create_map(data, &p, &n);
        size_t done = 0; int err = 0;
        while (done < n) { ssize_t r = write(fd, (const char *)p + done, n - done); if (r < 0) { err = errno; break; } done += r; }
        [(id)m release];
        h(NULL, err);
        [(id)data release];
        Block_release(h);
    });
}
