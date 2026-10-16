// host_info (BASIC/SCHED), Mach clock services, host_statistics64/host_processor_info shape, Darwin dev_t encoding
// (major()/minor() of /dev/null and /dev/tty) and devname_r.
#include <mach/mach.h>
#include <mach/clock.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
int main(void) {
  host_basic_info_data_t b; mach_msg_type_number_t c = HOST_BASIC_INFO_COUNT;
  kern_return_t r = host_info(mach_host_self(), HOST_BASIC_INFO, (host_info_t)&b, &c);
  printf("basic r=%d c=%u type=%#x sub=%d cpus_ok=%d maxmem_ok=%d\n", r, c, b.cpu_type, b.cpu_subtype, b.max_cpus > 0 && b.avail_cpus <= b.max_cpus, b.max_mem > (1ull << 28));
  host_sched_info_data_t s; c = HOST_SCHED_INFO_COUNT; r = host_info(mach_host_self(), HOST_SCHED_INFO, (host_info_t)&s, &c);
  printf("sched r=%d %d %d\n", r, s.min_timeout, s.min_quantum);
  c = 1; printf("short count r=%d\n", host_info(mach_host_self(), HOST_BASIC_INFO, (host_info_t)&b, &c));
  clock_serv_t cs; mach_timespec_t t1, t2;
  r = host_get_clock_service(mach_host_self(), CALENDAR_CLOCK, &cs); clock_get_time(cs, &t1);
  printf("calendar r=%d close_to_time=%d\n", r, labs((long)t1.tv_sec - (long)time(NULL)) <= 1);
  host_get_clock_service(mach_host_self(), SYSTEM_CLOCK, &cs); clock_get_time(cs, &t1); clock_get_time(cs, &t2);
  printf("system monotonic=%d nsec_ok=%d bad=%d\n", t2.tv_sec > t1.tv_sec || (t2.tv_sec == t1.tv_sec && t2.tv_nsec >= t1.tv_nsec),
         t1.tv_nsec >= 0 && t1.tv_nsec < 1000000000, host_get_clock_service(mach_host_self(), 9, &cs));
  vm_statistics64_data_t v; c = HOST_VM_INFO64_COUNT;
  r = host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&v, &c); printf("vm64 r=%d c=%u free>0=%d\n", r, c, v.free_count > 0);
  host_cpu_load_info_data_t l; c = HOST_CPU_LOAD_INFO_COUNT; r = host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, (host_info_t)&l, &c);
  printf("cpuload r=%d c=%u ticks>0=%d\n", r, c, l.cpu_ticks[CPU_STATE_USER] + l.cpu_ticks[CPU_STATE_IDLE] > 0);
  natural_t n; processor_info_array_t pi; mach_msg_type_number_t pic;
  r = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &pi, &pic);
  printf("procinfo r=%d count=ncpu*4: %d\n", r, pic == n * CPU_STATE_MAX);
  vm_deallocate(mach_task_self(), (vm_address_t)pi, pic * sizeof(int));
  struct stat st; stat("/dev/null", &st); char buf[64];
  printf("/dev/null devname=%s roundtrip=%d\n", devname_r(st.st_rdev, S_IFCHR, buf, sizeof buf), makedev(major(st.st_rdev), minor(st.st_rdev)) == st.st_rdev);
  printf("missing=%s blk-vs-chr=%s\n", devname_r(makedev(250, 9999), S_IFCHR, buf, sizeof buf) ? "found" : "(null)",
         devname_r(st.st_rdev, S_IFBLK, buf, sizeof buf) ? "found" : "(null)");
  return 0;
}
