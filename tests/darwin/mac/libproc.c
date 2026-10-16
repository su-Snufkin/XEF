// libproc: proc_pidinfo flavors (LISTFDS, TBSDINFO, TASKINFO, TASKALLINFO, SHORTBSDINFO, VNODEPATHINFO), proc_pidpath,
// proc_name, proc_listpids / proc_listchildpids; only fields with the same meaning on any machine are printed.
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <libproc.h>
#include <stdio.h>
#include <string.h>
#include <signal.h>
#include <sys/proc_info.h>
#include <sys/wait.h>
#include <unistd.h>
int main(int argc, char **argv) {
  (void)argc;
  int p[2]; pipe(p);
  int f = open("/dev/null", O_RDONLY);
  pid_t me = getpid();
  int est = proc_pidinfo(me, PROC_PIDLISTFDS, 0, NULL, 0);
  struct proc_fdinfo fi[256];
  int n = proc_pidinfo(me, PROC_PIDLISTFDS, 0, fi, sizeof fi) / (int)sizeof fi[0];
  int pipes = 0, vnodes = 0, sawf = 0;
  for (int i = 0; i < n; i++) { if (fi[i].proc_fdtype == PROX_FDTYPE_PIPE && (fi[i].proc_fd == p[0] || fi[i].proc_fd == p[1])) pipes++;
                                if (fi[i].proc_fd == f && fi[i].proc_fdtype == PROX_FDTYPE_VNODE) sawf = 1; vnodes += fi[i].proc_fdtype == PROX_FDTYPE_VNODE; }
  printf("listfds estimate>=n: %d, our pipe fds=%d, /dev/null vnode=%d sorted=%d\n", est >= n * 8, pipes, sawf, n < 2 || fi[0].proc_fd < fi[1].proc_fd);
  struct proc_bsdinfo b;
  int r = proc_pidinfo(me, PROC_PIDTBSDINFO, 0, &b, sizeof b);
  printf("tbsd r=%d pid=%d ppid_ok=%d status=%u comm=%s name=%s uid_ok=%d nfiles>=%d start_ok=%d\n", r, b.pbi_pid == (unsigned)me,
         b.pbi_ppid == (unsigned)getppid(), b.pbi_status, b.pbi_comm, b.pbi_name, b.pbi_uid == geteuid(), b.pbi_nfiles >= 5, b.pbi_start_tvsec > 1600000000);
  printf("short buffer r=%d\n", proc_pidinfo(me, PROC_PIDTBSDINFO, 0, &b, sizeof b - 1));
  errno = 0; printf("no such pid r=%d esrch=%d\n", proc_pidinfo(999999, PROC_PIDTBSDINFO, 0, &b, sizeof b), errno == ESRCH);
  struct proc_taskinfo t;
  r = proc_pidinfo(me, PROC_PIDTASKINFO, 0, &t, sizeof t);
  printf("task r=%d rss>0=%d vsize>=rss=%d threads=%d\n", r, t.pti_resident_size > 0, t.pti_virtual_size >= t.pti_resident_size, t.pti_threadnum);
  struct proc_taskallinfo a;
  r = proc_pidinfo(me, PROC_PIDTASKALLINFO, 0, &a, sizeof a);
  printf("taskall r=%d comm=%s threads=%d\n", r, a.pbsd.pbi_comm, a.ptinfo.pti_threadnum);
  struct proc_bsdshortinfo s;
  r = proc_pidinfo(me, PROC_PIDT_SHORTBSDINFO, 0, &s, sizeof s);
  printf("short r=%d comm=%s pid_ok=%d\n", r, s.pbsi_comm, s.pbsi_pid == (unsigned)me);
  struct proc_vnodepathinfo v;
  chdir("/tmp");
  r = proc_pidinfo(me, PROC_PIDVNODEPATHINFO, 0, &v, sizeof v);
  char cwd[1024]; getcwd(cwd, sizeof cwd);
  printf("vnodepath r=%d cwd_match=%d root=%s\n", r, strcmp(v.pvi_cdir.vip_path, cwd) == 0, v.pvi_rdir.vip_path[0] ? v.pvi_rdir.vip_path : "(empty)");
  char path[PROC_PIDPATHINFO_MAXSIZE];
  r = proc_pidpath(me, path, sizeof path);
  printf("pidpath basename=%s len_ok=%d\n", basename(path), r == (int)strlen(path));
  char nm[64]; r = proc_name(me, nm, sizeof nm); printf("proc_name=%s r=%d\n", nm, r);
  pid_t c = fork();
  if (c == 0) { pause(); _exit(0); }
  usleep(200000);
  pid_t kids[16]; int k = proc_listchildpids(me, kids, sizeof kids);
  printf("children=%d first_is_child=%d\n", k, k >= 1 && kids[0] == c);
  int bytes = proc_listpids(PROC_PPID_ONLY, me, kids, sizeof kids);
  printf("listpids ppid bytes=%d\n", bytes);
  int all = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
  printf("all estimate>0=%d\n", all > 0);
  r = proc_pidinfo(c, PROC_PIDTBSDINFO, 0, &b, sizeof b);
  printf("child comm=%s status=%u\n", b.pbi_comm, b.pbi_status);
  kill(c, 9); waitpid(c, NULL, 0);
  (void)argv;
  return 0;
}
