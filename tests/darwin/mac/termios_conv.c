// termios on a pty: every flag/c_cc/speed set explicitly reads back unchanged (struct layout + constant conversion),
// cfmakeraw, TCSASOFT, TIOCGETA == tcgetattr, winsize, tcflush/tcflow numbers, forkpty child I/O.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>
static void show(const char *what, struct termios *t) {
  printf("%s: i=%#lx o=%#lx c=%#lx l=%#lx cc[INTR]=%d cc[EOF]=%d cc[VMIN]=%d cc[VTIME]=%d cc[ERASE]=%d cc[WERASE]=%d cc[LNEXT]=%d ispeed=%lu ospeed=%lu\n",
         what, (unsigned long)t->c_iflag, (unsigned long)t->c_oflag, (unsigned long)t->c_cflag, (unsigned long)t->c_lflag,
         t->c_cc[VINTR], t->c_cc[VEOF], t->c_cc[VMIN], t->c_cc[VTIME], t->c_cc[VERASE], t->c_cc[VWERASE], t->c_cc[VLNEXT],
         (unsigned long)cfgetispeed(t), (unsigned long)cfgetospeed(t));
}
int main(void) {
  int m, s;
  struct winsize ws = {30, 100, 0, 0};
  if (openpty(&m, &s, NULL, NULL, &ws) < 0) { perror("openpty"); return 1; }
  struct termios t;
  memset(&t, 0, sizeof t);
  t.c_iflag = BRKINT | ICRNL | IXON | IXANY | IMAXBEL | IUTF8;
  t.c_oflag = OPOST | ONLCR;
  t.c_cflag = CREAD | CS8 | HUPCL;
  t.c_lflag = ECHOKE | ECHOE | ECHOK | ECHO | ECHOCTL | ISIG | ICANON | IEXTEN | PENDIN;
  t.c_cc[VEOF] = 4; t.c_cc[VEOL] = _POSIX_VDISABLE; t.c_cc[VEOL2] = _POSIX_VDISABLE; t.c_cc[VERASE] = 0x7f; t.c_cc[VWERASE] = 23;
  t.c_cc[VKILL] = 21; t.c_cc[VREPRINT] = 18; t.c_cc[VINTR] = 3; t.c_cc[VQUIT] = 28; t.c_cc[VSUSP] = 26; t.c_cc[VSTART] = 17;
  t.c_cc[VSTOP] = 19; t.c_cc[VLNEXT] = 22; t.c_cc[VDISCARD] = 15; t.c_cc[VMIN] = 1; t.c_cc[VTIME] = 0;
  cfsetspeed(&t, B38400);
  printf("set=%d\n", tcsetattr(s, TCSANOW, &t));
  struct termios g; tcgetattr(s, &g); show("cooked", &g);
  printf("VEOL disabled=%d\n", g.c_cc[VEOL] == _POSIX_VDISABLE);
  struct termios io; ioctl(s, TIOCGETA, &io);
  printf("TIOCGETA same flags=%d\n", io.c_iflag == g.c_iflag && io.c_lflag == g.c_lflag && io.c_cflag == g.c_cflag && io.c_oflag == g.c_oflag);
  cfmakeraw(&g); show("raw(local)", &g);
  tcsetattr(s, TCSAFLUSH, &g); tcgetattr(s, &g); show("raw", &g);
  g.c_cflag = (g.c_cflag & ~CSIZE) | CS7 | PARENB; g.c_lflag |= ECHO;
  tcsetattr(s, TCSANOW | TCSASOFT, &g); tcgetattr(s, &g);
  printf("TCSASOFT keeps cflag: cs8=%d parenb=%d echo=%d\n", (g.c_cflag & CSIZE) == CS8, !!(g.c_cflag & PARENB), !!(g.c_lflag & ECHO));
  cfsetspeed(&g, B115200); tcsetattr(s, TCSANOW, &g); tcgetattr(s, &g); printf("speed=%lu\n", (unsigned long)cfgetospeed(&g));
  struct winsize w2; ioctl(s, TIOCGWINSZ, &w2); printf("winsize %dx%d\n", w2.ws_col, w2.ws_row);
  w2.ws_col = 132; ioctl(m, TIOCSWINSZ, &w2); ioctl(s, TIOCGWINSZ, &w2); printf("after TIOCSWINSZ cols=%d\n", w2.ws_col);
  printf("tcflush=%d %d %d bad=%d tcflow=%d\n", tcflush(s, TCIFLUSH), tcflush(s, TCOFLUSH), tcflush(s, TCIOFLUSH), tcflush(s, 77), tcflow(s, TCOON));
  close(s); close(m);
  fflush(stdout);
  int fm; pid_t p = forkpty(&fm, NULL, NULL, &ws);
  if (p == 0) { struct winsize cw; ioctl(0, TIOCGWINSZ, &cw); printf("child tty=%d cols=%d\n", isatty(0), cw.ws_col); fflush(stdout); _exit(4); }
  char buf[128]; int n = 0, r;
  while ((r = read(fm, buf + n, sizeof buf - 1 - n)) > 0) n += r;
  buf[n] = 0;
  int st; waitpid(p, &st, 0);
  for (char *q = buf; *q; q++) if (*q == '\r') *q = ' ';
  printf("forkpty got [%s] exit=%d\n", buf, WEXITSTATUS(st));
  return 0;
}
