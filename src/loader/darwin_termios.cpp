// XEF-OSX — Darwin termios on Linux. struct termios differs in every part: 8-byte tcflag_t/speed_t fields, other bit
// values in all four flag words, other c_cc indices (and _POSIX_VDISABLE 0xff instead of 0), speeds stored as plain
// baud numbers. Also the tc*/cf* functions with their own queue/action numbers, the TIOC* ioctls libc and
// programs issue directly, posix_openpt (O_NOCTTY differs) and openpty/forkpty. Constants: macOS SDK <sys/termios.h>,
// <sys/ttycom.h> (see tests/darwin/mac/termios_conv.c).
#include "loader/darwin_hle.h"
#include "common/common.h"

#include <errno.h>
#include <fcntl.h>
#include <pty.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#include <utmp.h>

namespace xef {

struct DarwinTermios {
    uint64_t iflag, oflag, cflag, lflag;
    uint8_t cc[20];
    uint8_t pad[4];
    uint64_t ispeed, ospeed;
};
static_assert(sizeof(DarwinTermios) == 72 && offsetof(DarwinTermios, ispeed) == 56, "Darwin struct termios");

struct BitMap { uint64_t d; tcflag_t l; };
static const BitMap kIflag[] = {{0x1, IGNBRK}, {0x2, BRKINT}, {0x4, IGNPAR}, {0x8, PARMRK}, {0x10, INPCK}, {0x20, ISTRIP},
                                {0x40, INLCR}, {0x80, IGNCR}, {0x100, ICRNL}, {0x200, IXON}, {0x400, IXOFF}, {0x800, IXANY},
                                {0x2000, IMAXBEL}, {0x4000, IUTF8}};
static const BitMap kOflag[] = {{0x1, OPOST}, {0x2, ONLCR}, {0x10, OCRNL}, {0x20, ONOCR}, {0x40, ONLRET}, {0x80, OFILL},
                                {0x20000, OFDEL}, {0x100, NL1}, {0x1000, CR1}, {0x2000, CR2}, {0x8000, BS1}, {0x10000, VT1},
                                {0x4000, FF1}};
static const BitMap kCflag[] = {{0x400, CSTOPB}, {0x800, CREAD}, {0x1000, PARENB}, {0x2000, PARODD}, {0x4000, HUPCL},
                                {0x8000, CLOCAL}, {0x30000, CRTSCTS}};
static const BitMap kLflag[] = {{0x1, ECHOKE}, {0x2, ECHOE}, {0x4, ECHOK}, {0x8, ECHO}, {0x10, ECHONL}, {0x20, ECHOPRT},
                                {0x40, ECHOCTL}, {0x80, ISIG}, {0x100, ICANON}, {0x400, IEXTEN}, {0x800, EXTPROC},
                                {0x400000, TOSTOP}, {0x800000, FLUSHO}, {0x20000000, PENDIN}, {0x80000000, NOFLSH}};
// Darwin c_cc index -> Linux index (-1: no Linux counterpart)
static const int kCc[20] = {VEOF, VEOL, VEOL2, VERASE, VWERASE, VKILL, VREPRINT, -1, VINTR, VQUIT, VSUSP, -1,
                            VSTART, VSTOP, VLNEXT, VDISCARD, VMIN, VTIME, -1, -1};
static const struct { speed_t code; uint64_t baud; } kSpeeds[] = {
    {B0, 0}, {B50, 50}, {B75, 75}, {B110, 110}, {B134, 134}, {B150, 150}, {B200, 200}, {B300, 300}, {B600, 600},
    {B1200, 1200}, {B1800, 1800}, {B2400, 2400}, {B4800, 4800}, {B9600, 9600}, {B19200, 19200}, {B38400, 38400},
    {B57600, 57600}, {B115200, 115200}, {B230400, 230400}, {B460800, 460800}, {B921600, 921600}};

static uint64_t to_baud(speed_t c) {
    for (auto& s : kSpeeds) if (s.code == c) return s.baud;
    return 38400;
}
static bool to_code(uint64_t baud, speed_t* c) {
    for (auto& s : kSpeeds) if (s.baud == baud) { *c = s.code; return true; }
    return false;
}

static void from_linux(const struct termios& l, DarwinTermios* d) {
    memset(d, 0, sizeof *d);
    for (auto& b : kIflag) if (l.c_iflag & b.l) d->iflag |= b.d;
    for (auto& b : kOflag) if ((l.c_oflag & b.l) == b.l) d->oflag |= b.d;
    if ((l.c_oflag & TABDLY) == TAB3) d->oflag |= 0x4;             // OXTABS
    for (auto& b : kCflag) if ((l.c_cflag & b.l) == b.l) d->cflag |= b.d;
    d->cflag |= (uint64_t)((l.c_cflag & CSIZE) >> 4) << 8;          // CS5..CS8
    for (auto& b : kLflag) if (l.c_lflag & b.l) d->lflag |= b.d;
    for (int i = 0; i < 20; i++) {
        if (kCc[i] < 0) continue;
        uint8_t v = l.c_cc[kCc[i]];
        d->cc[i] = (i != 16 && i != 17 && v == 0) ? 0xff : v;      // _POSIX_VDISABLE (VMIN/VTIME are numbers)
    }
    d->cc[11] = 0x19;   // VDSUSP ^Y, VSTATUS ^T: macOS defaults (Linux has neither)
    d->cc[18] = 0x14;
    d->ispeed = to_baud(cfgetispeed(&l));
    d->ospeed = to_baud(cfgetospeed(&l));
}
static bool to_linux(const DarwinTermios* d, struct termios* l) {
    for (auto& b : kIflag) { if (d->iflag & b.d) l->c_iflag |= b.l; else l->c_iflag &= ~b.l; }
    l->c_oflag &= ~(OPOST | ONLCR | OCRNL | ONOCR | ONLRET | OFILL | OFDEL | NLDLY | CRDLY | TABDLY | BSDLY | VTDLY | FFDLY);
    for (auto& b : kOflag) if ((d->oflag & b.d) == b.d) l->c_oflag |= b.l;
    if (d->oflag & 0x4) l->c_oflag |= TAB3;
    l->c_cflag &= ~(CSTOPB | CREAD | PARENB | PARODD | HUPCL | CLOCAL | CRTSCTS | CSIZE);
    for (auto& b : kCflag) if ((d->cflag & b.d) == b.d) l->c_cflag |= b.l;
    l->c_cflag |= (tcflag_t)(((d->cflag >> 8) & 3) << 4);
    for (auto& b : kLflag) { if (d->lflag & b.d) l->c_lflag |= b.l; else l->c_lflag &= ~b.l; }
    for (int i = 0; i < 20; i++) {
        if (kCc[i] < 0) continue;
        uint8_t v = d->cc[i];
        l->c_cc[kCc[i]] = (i != 16 && i != 17 && v == 0xff) ? 0 : v;
    }
    speed_t is, os;
    if (!to_code(d->ispeed ? d->ispeed : d->ospeed, &is) || !to_code(d->ospeed, &os)) return false;
    cfsetispeed(l, is);
    cfsetospeed(l, os);
    return true;
}

static int t_tcgetattr(int fd, DarwinTermios* d) {
    struct termios l;
    if (tcgetattr(fd, &l) < 0) return -1;
    from_linux(l, d);
    return 0;
}
static int t_tcsetattr(int fd, int act, const DarwinTermios* d) {
    bool soft = act & 0x10;   // TCSASOFT: leave the hardware (c_cflag, speeds) alone
    act &= ~0x10;
    if (act < 0 || act > 2) { errno = EINVAL; return -1; }   // TCSANOW/TCSADRAIN/TCSAFLUSH: 0/1/2 on both
    struct termios l;
    if (tcgetattr(fd, &l) < 0) return -1;
    struct termios keep = l;
    if (!to_linux(d, &l)) { errno = EINVAL; return -1; }
    if (soft) {
        l.c_cflag = keep.c_cflag;
        cfsetispeed(&l, cfgetispeed(&keep));
        cfsetospeed(&l, cfgetospeed(&keep));
    }
    return tcsetattr(fd, act, &l);
}
static uint64_t t_cfgetispeed(const DarwinTermios* d) { return d->ispeed; }
static uint64_t t_cfgetospeed(const DarwinTermios* d) { return d->ospeed; }
static int t_cfsetispeed(DarwinTermios* d, uint64_t s) { d->ispeed = s; return 0; }
static int t_cfsetospeed(DarwinTermios* d, uint64_t s) { d->ospeed = s; return 0; }
static int t_cfsetspeed(DarwinTermios* d, uint64_t s) { d->ispeed = d->ospeed = s; return 0; }
static void t_cfmakeraw(DarwinTermios* d) {   // as Libc's cfmakeraw
    d->iflag &= ~(uint64_t)(0x2000 | 0x400 | 0x10 | 0x2 | 0x8 | 0x20 | 0x40 | 0x80 | 0x100 | 0x200 | 0x4);
    d->iflag |= 0x1;
    d->oflag &= ~(uint64_t)0x1;
    d->lflag &= ~(uint64_t)(0x8 | 0x2 | 0x4 | 0x10 | 0x100 | 0x80 | 0x400 | 0x80000000 | 0x400000 | 0x20000000);
    d->cflag &= ~(uint64_t)(0x300 | 0x1000);
    d->cflag |= 0x300 | 0x800;
    d->cc[16] = 1;
    d->cc[17] = 0;
}
static int t_tcflush(int fd, int q) {          // TCIFLUSH/TCOFLUSH/TCIOFLUSH: 1/2/3 (Linux 0/1/2)
    if (q < 1 || q > 3) { errno = EINVAL; return -1; }
    return tcflush(fd, q - 1);
}
static int t_tcflow(int fd, int a) {           // TCOOFF/TCOON/TCIOFF/TCION: 1..4 (Linux 0..3)
    if (a < 1 || a > 4) { errno = EINVAL; return -1; }
    return tcflow(fd, a - 1);
}
static int t_posix_openpt(int dflags) {
    int f = 0;
    if ((dflags & 3) == 2) f |= O_RDWR; else if ((dflags & 3) == 1) f |= O_WRONLY;
    if (dflags & 0x20000) f |= O_NOCTTY;
    if (dflags & 0x1000000) f |= O_CLOEXEC;
    return posix_openpt(f);
}
struct DarwinWinsize { unsigned short row, col, xpixel, ypixel; };   // same layout as Linux
static int t_openpty(int* amaster, int* aslave, char* name, const DarwinTermios* tp, const struct winsize* wp) {
    struct termios l, *lp = nullptr;
    if (tp) {
        memset(&l, 0, sizeof l);
        if (!to_linux(tp, &l)) { errno = EINVAL; return -1; }
        lp = &l;
    }
    return openpty(amaster, aslave, name, lp, wp);
}
static pid_t t_forkpty(int* amaster, char* name, const DarwinTermios* tp, const struct winsize* wp) {
    int m, s;
    if (t_openpty(&m, &s, name, tp, wp) < 0) return -1;
    pid_t p = darwin_fork();
    if (p < 0) { close(m); close(s); return -1; }
    if (p == 0) {
        close(m);
        if (login_tty(s) < 0) _exit(1);
        return 0;
    }
    close(s);
    *amaster = m;
    return p;
}

bool darwin_termios_ioctl(int fd, unsigned long req, void* arg, int* ret) {
    switch (req) {
        case 0x40487413: *ret = t_tcgetattr(fd, (DarwinTermios*)arg); return true;              // TIOCGETA
        case 0x80487414: case 0x80487415: case 0x80487416:                                   // TIOCSETA/W/F
            *ret = t_tcsetattr(fd, (int)(req - 0x80487414), (const DarwinTermios*)arg); return true;
        case 0x80087467: *ret = ioctl(fd, TIOCSWINSZ, arg); return true;                     // TIOCSWINSZ
        case 0x20007461: *ret = ioctl(fd, TIOCSCTTY, 0); return true;                        // TIOCSCTTY
        case 0x20007471: *ret = ioctl(fd, TIOCNOTTY); return true;                           // TIOCNOTTY
        case 0x40047477: *ret = ioctl(fd, TIOCGPGRP, arg); return true;                      // TIOCGPGRP
        case 0x80047476: *ret = ioctl(fd, TIOCSPGRP, arg); return true;                      // TIOCSPGRP
        case 0x40047473: *ret = ioctl(fd, TIOCOUTQ, arg); return true;                       // TIOCOUTQ
        case 0x80017472: *ret = ioctl(fd, TIOCSTI, arg); return true;                        // TIOCSTI
        case 0x2000740d: *ret = ioctl(fd, TIOCEXCL); return true;                            // TIOCEXCL
        case 0x2000740e: *ret = ioctl(fd, TIOCNXCL); return true;                            // TIOCNXCL
        case 0x80047410: {                                                                   // TIOCFLUSH: FREAD 1 | FWRITE 2, 0 = both
            int w = arg ? *(int*)arg : 0;
            int q = (w == 0 || w == 3) ? TCIOFLUSH : (w == 1 ? TCIFLUSH : TCOFLUSH);
            *ret = tcflush(fd, q); return true;
        }
        case 0x2000745e: *ret = tcdrain(fd); return true;                                    // TIOCDRAIN
        case 0x2000747b: *ret = ioctl(fd, TIOCSBRK); return true;
        case 0x2000747a: *ret = ioctl(fd, TIOCCBRK); return true;
        case 0x4004746a: *ret = ioctl(fd, TIOCMGET, arg); return true;                       // TIOCM_* bits match
        case 0x8004746d: *ret = ioctl(fd, TIOCMSET, arg); return true;
        case 0x2000746f: *ret = tcflow(fd, TCOOFF); return true;                             // TIOCSTOP
        case 0x2000746e: *ret = tcflow(fd, TCOON); return true;                              // TIOCSTART
        case 0x80047470: *ret = ioctl(fd, TIOCPKT, arg); return true;
        case 0x4004741a: *ret = ioctl(fd, TIOCGETD, arg); return true;
        case 0x8004741b: *ret = ioctl(fd, TIOCSETD, arg); return true;
        case 0x8004667d: *ret = ioctl(fd, FIOASYNC, arg); return true;
        case 0x20007454: *ret = grantpt(fd); return true;                                     // TIOCPTYGRANT
        case 0x20007452: *ret = unlockpt(fd); return true;                                    // TIOCPTYUNLK
        case 0x40807453: {                                                                    // TIOCPTYGNAME (128 bytes)
            *ret = ptsname_r(fd, (char*)arg, 128) == 0 ? 0 : -1; return true;
        }
    }
    return false;
}

void* darwin_termios_lookup(const char* name) {
    struct E { const char* n; void* f; };
    static const E k[] = {
        {"_tcgetattr", (void*)&t_tcgetattr}, {"_tcsetattr", (void*)&t_tcsetattr},
        {"_cfgetispeed", (void*)&t_cfgetispeed}, {"_cfgetospeed", (void*)&t_cfgetospeed},
        {"_cfsetispeed", (void*)&t_cfsetispeed}, {"_cfsetospeed", (void*)&t_cfsetospeed},
        {"_cfsetspeed", (void*)&t_cfsetspeed}, {"_cfmakeraw", (void*)&t_cfmakeraw},
        {"_tcflush", (void*)&t_tcflush}, {"_tcflow", (void*)&t_tcflow},
        {"_posix_openpt", (void*)&t_posix_openpt}, {"_openpty", (void*)&t_openpty}, {"_forkpty", (void*)&t_forkpty},
    };
    for (const E& e : k) if (!strcmp(e.n, name)) return e.f;
    return nullptr;
}

}  // namespace xef
