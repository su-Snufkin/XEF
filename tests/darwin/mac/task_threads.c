// task_threads lists the process's threads (CPython warns about fork() with other threads running this way)
#include <mach/mach.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

static volatile int stop;
static void* idle(void* a) { (void)a; while (!stop) usleep(1000); return NULL; }

static unsigned count(void) {
    thread_act_array_t list; mach_msg_type_number_t n = 0;
    if (task_threads(mach_task_self(), &list, &n) != KERN_SUCCESS) return 0;
    int self_found = 0;
    thread_t me = mach_thread_self();
    for (unsigned i = 0; i < n; i++) { if (list[i] == me) self_found = 1; mach_port_deallocate(mach_task_self(), list[i]); }
    mach_port_deallocate(mach_task_self(), me);
    vm_deallocate(mach_task_self(), (vm_address_t)list, n * sizeof *list);
    return n * 10 + self_found;
}

int main(void) {
    mach_port_t own = 0, other = 0;
    kern_return_t kr = task_for_pid(mach_task_self(), getpid(), &own);
    thread_act_array_t l; mach_msg_type_number_t n = 0;
    printf("task_for_pid(self): kr=%d threads_ok=%d\n", kr, kr == 0 && task_threads(own, &l, &n) == 0 && n == 1);
    kr = task_for_pid(mach_task_self(), 1, &other);
    printf("task_for_pid(1): kr=%d port=%u\n", kr, other);
    printf("alone: %u\n", count());
    pthread_t t[3];
    for (int i = 0; i < 3; i++) pthread_create(&t[i], NULL, idle, NULL);
    printf("with 3 more: %u\n", count());
    stop = 1;
    for (int i = 0; i < 3; i++) pthread_join(t[i], NULL);
    usleep(20000);
    printf("after join: %u\n", count());
    return 0;
}
