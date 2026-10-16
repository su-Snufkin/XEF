// sysctl KERN_PROC (kinfo_proc) for PID / ALL / UID / PGRP and KERN_PROCARGS2 (argc, exec path, argv, env).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <sys/proc.h>
#include <unistd.h>
#include <errno.h>
int main(int argc, char **argv) {
  (void)argc;
  struct kinfo_proc k; size_t l = sizeof k;
  int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
  int r = sysctl(mib, 4, &k, &l, NULL, 0);
  printf("pid r=%d len=%zu stat=%d lp64=%d comm=%s ppid_ok=%d pgid_ok=%d uid_ok=%d ruid_ok=%d start_ok=%d\n", r, l, k.kp_proc.p_stat,
         !!(k.kp_proc.p_flag & P_LP64), k.kp_proc.p_comm, k.kp_eproc.e_ppid == getppid(), k.kp_eproc.e_pgid == getpgrp(),
         k.kp_eproc.e_ucred.cr_uid == geteuid(), k.kp_eproc.e_pcred.p_ruid == getuid(), k.kp_proc.p_starttime.tv_sec > 1600000000);
  mib[3] = 999999; l = sizeof k; r = sysctl(mib, 4, &k, &l, NULL, 0); printf("missing r=%d len=%zu\n", r, l);
  int all[3] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL}; l = 0;
  r = sysctl(all, 3, NULL, &l, NULL, 0); printf("all size r=%d multiple=%d nonzero=%d\n", r, (int)(l % sizeof k), l > 0);
  struct kinfo_proc *v = malloc(l + 64 * sizeof k); l += 64 * sizeof k;
  r = sysctl(all, 3, v, &l, NULL, 0); int found = 0;
  for (size_t i = 0; i < l / sizeof k; i++) if (v[i].kp_proc.p_pid == getpid()) found = 1;
  printf("all r=%d self listed=%d\n", r, found);
  size_t small = sizeof k; errno = 0; r = sysctl(all, 3, v, &small, NULL, 0); printf("small buf r=%d enomem=%d\n", r, errno == ENOMEM);
  int byuid[4] = {CTL_KERN, KERN_PROC, KERN_PROC_UID, (int)geteuid()}; l = 0; sysctl(byuid, 4, NULL, &l, NULL, 0); printf("uid nonzero=%d\n", l > 0);
  int pg[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PGRP, getpgrp()}; l = sizeof(struct kinfo_proc) * 64; r = sysctl(pg, 4, v, &l, NULL, 0);
  printf("pgrp r=%d has_self=%d\n", r, l >= sizeof k);
  setenv("XEF_ARGS_TEST", "yes", 1);
  int pa[3] = {CTL_KERN, KERN_PROCARGS2, getpid()}; char buf[65536]; l = sizeof buf;
  r = sysctl(pa, 3, buf, &l, NULL, 0);
  int n = *(int *)buf; char *p = buf + 4; char *exe = p; p += strlen(p); while (!*p && p < buf + l) p++;
  printf("procargs2 r=%d argc=%d exe_basename=%s", r, n, strrchr(exe, '/') ? strrchr(exe, '/') + 1 : exe);
  for (int i = 0; i < n; i++) { printf(" [%s]", i == 0 ? (strrchr(p, '/') ? strrchr(p, '/') + 1 : p) : p); p += strlen(p) + 1; }
  int sawenv = 0; while (p < buf + l && *p) { if (!strncmp(p, "PATH=", 5)) sawenv = 1; p += strlen(p) + 1; }
  printf(" env_has_PATH=%d argv1=%s\n", sawenv, argv[1]);
  return 0;
}
