// thread_info: THREAD_BASIC_INFO / THREAD_IDENTIFIER_INFO write only their own size and set the count
#include <mach/mach.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    volatile double x = 0;
    for (long i = 0; i < 30000000; i++) x += i * 0.5;      // some user time
    struct { thread_basic_info_data_t bi; unsigned char guard[64]; } b;
    memset(&b, 0xCD, sizeof b);
    mach_msg_type_number_t cnt = THREAD_INFO_MAX;           // larger than the flavor: only its size is written
    thread_t self = mach_thread_self();
    kern_return_t kr = thread_info(self, THREAD_BASIC_INFO, (thread_info_t)&b.bi, &cnt);
    int intact = 1;
    for (int i = 0; i < 64; i++) intact &= b.guard[i] == 0xCD;
    printf("basic kr=%d count=%u guard %d user>0 %d run_state %d policy %d suspend %d\n", kr, cnt, intact,
           b.bi.user_time.seconds > 0 || b.bi.user_time.microseconds > 0, b.bi.run_state, b.bi.policy, b.bi.suspend_count);
    thread_identifier_info_data_t id;
    cnt = THREAD_IDENTIFIER_INFO_COUNT;
    kr = thread_info(self, THREAD_IDENTIFIER_INFO, (thread_info_t)&id, &cnt);
    uint64_t tid;
    pthread_threadid_np(NULL, &tid);
    printf("identifier kr=%d count=%u id matches pthread_threadid_np %d\n", kr, cnt, id.thread_id == tid);
    cnt = 2;
    kr = thread_info(self, THREAD_BASIC_INFO, (thread_info_t)&b.bi, &cnt);
    printf("short count kr=%d\n", kr);
    (void)x;
    return 0;
}
