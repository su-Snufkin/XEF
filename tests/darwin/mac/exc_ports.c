// task/thread exception ports: set, get back (grouped by identical registration), swap; faults still arrive as signals
#include <mach/mach.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>

static sigjmp_buf jb;
static void on_segv(int s) { (void)s; siglongjmp(jb, 1); }

int main(void) {
    exception_mask_t masks[EXC_TYPES_COUNT];
    mach_port_t ports[EXC_TYPES_COUNT];
    exception_behavior_t beh[EXC_TYPES_COUNT];
    thread_state_flavor_t fl[EXC_TYPES_COUNT];
    mach_msg_type_number_t n = EXC_TYPES_COUNT;
    kern_return_t kr = task_set_exception_ports(mach_task_self(), EXC_MASK_BAD_ACCESS | EXC_MASK_BAD_INSTRUCTION | EXC_MASK_ARITHMETIC,
                                                MACH_PORT_NULL, EXCEPTION_STATE_IDENTITY, ARM_THREAD_STATE64);
    printf("task set kr=%d\n", kr);
    kr = task_get_exception_ports(mach_task_self(), EXC_MASK_BAD_ACCESS | EXC_MASK_ARITHMETIC, masks, &n, ports, beh, fl);
    printf("task get kr=%d n=%u", kr, n);
    for (unsigned i = 0; i < n; i++) printf(" [mask %#x port %u behavior %#x flavor %d]", masks[i], ports[i], beh[i], fl[i]);
    printf("\n");
    n = EXC_TYPES_COUNT;
    kr = thread_set_exception_ports(mach_thread_self(), EXC_MASK_BAD_ACCESS, MACH_PORT_NULL, EXCEPTION_DEFAULT, THREAD_STATE_NONE);
    printf("thread set kr=%d\n", kr);
    kr = task_set_exception_ports(mach_task_self(), 1u << 30, MACH_PORT_NULL, EXCEPTION_DEFAULT, THREAD_STATE_NONE);
    printf("bad mask kr=%d\n", kr);
    signal(SIGSEGV, on_segv);
    signal(SIGBUS, on_segv);
    if (!sigsetjmp(jb, 1)) { *(volatile int*)8 = 1; printf("no fault?\n"); }
    else printf("fault delivered as a signal\n");
    return 0;
}
