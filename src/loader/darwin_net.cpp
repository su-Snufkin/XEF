// XEF-OSX — BSD sockets / netdb in Darwin ABI on top of the Linux host (sockaddr layouts, option numbers,
// message flags, addrinfo, EAI_* codes).
#include "loader/darwin_hle.h"
#include "common/common.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <sys/utsname.h>
#include <unistd.h>
#include <vector>

namespace xef {

int darwin_errno_from_linux(int e);

static int err(int e) { errno = e; return -1; }

// ---- address families / sockaddr ----------------------------------------------------------------------
static int af_to_linux(int d) { switch (d) { case 30: return AF_INET6; case 18: return AF_APPLETALK; case 32: return AF_UNSPEC; default: return d; } }
static int af_to_darwin(int l) { switch (l) { case AF_INET6: return 30; default: return l; } }

// returns the Linux length, or -1
static socklen_t sa_to_linux(const void* d, socklen_t dlen, sockaddr_storage* out) {
    memset(out, 0, sizeof *out);
    if (!d || dlen < 2) return 0;
    const uint8_t* b = (const uint8_t*)d;
    int fam = b[1];
    switch (fam) {
        case 2: {   // sockaddr_in {len, family, port, addr}
            sockaddr_in* s = (sockaddr_in*)out;
            s->sin_family = AF_INET;
            memcpy(&s->sin_port, b + 2, 2);
            memcpy(&s->sin_addr, b + 4, 4);
            return sizeof(sockaddr_in);
        }
        case 30: {  // sockaddr_in6 {len, family, port, flowinfo, addr[16], scope}
            sockaddr_in6* s = (sockaddr_in6*)out;
            s->sin6_family = AF_INET6;
            memcpy(&s->sin6_port, b + 2, 2);
            memcpy(&s->sin6_flowinfo, b + 4, 4);
            memcpy(&s->sin6_addr, b + 8, 16);
            memcpy(&s->sin6_scope_id, b + 24, 4);
            return sizeof(sockaddr_in6);
        }
        case 1: {   // sockaddr_un {len, family, path[104]}
            sockaddr_un* s = (sockaddr_un*)out;
            s->sun_family = AF_UNIX;
            size_t n = dlen > 2 ? dlen - 2 : 0;
            if (n > 104) n = 104;
            memcpy(s->sun_path, b + 2, n);
            return (socklen_t)(2 + n);
        }
        default: {
            memcpy(out, d, dlen < sizeof *out ? dlen : sizeof *out);
            ((sockaddr*)out)->sa_family = (sa_family_t)af_to_linux(fam);
            return dlen;
        }
    }
}
// writes a Darwin sockaddr of at most cap bytes; returns the full Darwin length
static socklen_t sa_to_darwin(const sockaddr* l, socklen_t llen, void* out, socklen_t cap) {
    uint8_t tmp[128];
    memset(tmp, 0, sizeof tmp);
    socklen_t n = 0;
    switch (l->sa_family) {
        case AF_INET: {
            const sockaddr_in* s = (const sockaddr_in*)l;
            tmp[0] = 16; tmp[1] = 2;
            memcpy(tmp + 2, &s->sin_port, 2); memcpy(tmp + 4, &s->sin_addr, 4);
            n = 16; break;
        }
        case AF_INET6: {
            const sockaddr_in6* s = (const sockaddr_in6*)l;
            tmp[0] = 28; tmp[1] = 30;
            memcpy(tmp + 2, &s->sin6_port, 2); memcpy(tmp + 4, &s->sin6_flowinfo, 4);
            memcpy(tmp + 8, &s->sin6_addr, 16); memcpy(tmp + 24, &s->sin6_scope_id, 4);
            n = 28; break;
        }
        case AF_UNIX: {
            const sockaddr_un* s = (const sockaddr_un*)l;
            size_t pl = llen > 2 ? llen - 2 : 0;
            if (pl > 104) pl = 104;
            tmp[1] = 1;
            memcpy(tmp + 2, s->sun_path, pl);
            n = (socklen_t)(2 + pl);
            tmp[0] = (uint8_t)n;
            break;
        }
        default:
            memcpy(tmp, l, llen < sizeof tmp ? llen : sizeof tmp);
            tmp[1] = (uint8_t)af_to_darwin(l->sa_family);
            n = llen;
    }
    if (out && cap) memcpy(out, tmp, n < cap ? n : cap);
    return n;
}

// ---- options ----------------------------------------------------------------------------------------------
static bool sockopt_to_linux(int dlevel, int dopt, int* llevel, int* lopt) {
    if (dlevel == 0xffff) {
        *llevel = SOL_SOCKET;
        switch (dopt) {
            case 0x0001: *lopt = SO_DEBUG; return true;       case 0x0002: *lopt = SO_ACCEPTCONN; return true;
            case 0x0004: *lopt = SO_REUSEADDR; return true;   case 0x0008: *lopt = SO_KEEPALIVE; return true;
            case 0x0010: *lopt = SO_DONTROUTE; return true;   case 0x0020: *lopt = SO_BROADCAST; return true;
            case 0x0080: *lopt = SO_LINGER; return true;      case 0x0100: *lopt = SO_OOBINLINE; return true;
            case 0x0200: *lopt = SO_REUSEPORT; return true;   case 0x0400: *lopt = SO_TIMESTAMP; return true;
            case 0x1001: *lopt = SO_SNDBUF; return true;      case 0x1002: *lopt = SO_RCVBUF; return true;
            case 0x1003: *lopt = SO_SNDLOWAT; return true;    case 0x1004: *lopt = SO_RCVLOWAT; return true;
            case 0x1005: *lopt = SO_SNDTIMEO; return true;    case 0x1006: *lopt = SO_RCVTIMEO; return true;
            case 0x1007: *lopt = SO_ERROR; return true;       case 0x1008: *lopt = SO_TYPE; return true;
            default: return false;
        }
    }
    if (dlevel == 6) { *llevel = IPPROTO_TCP; *lopt = dopt == 0x10 ? TCP_KEEPIDLE : dopt; return true; }
    if (dlevel == 0) { *llevel = IPPROTO_IP; *lopt = dopt == 4 ? IP_TTL : dopt == 10 ? IP_TOS : dopt; return true; }
    if (dlevel == 41) { *llevel = IPPROTO_IPV6; *lopt = dopt == 27 ? IPV6_V6ONLY : dopt; return true; }
    *llevel = dlevel; *lopt = dopt;
    return true;
}
static int msgflags_to_linux(int d) {
    int l = d & 0x0f;                       // OOB, PEEK, DONTROUTE, EOR
    if (d & 0x40) l |= MSG_WAITALL;
    if (d & 0x80) l |= MSG_DONTWAIT;
    if (d & 0x80000) l |= MSG_NOSIGNAL;
    if (d & 0x20) l |= MSG_TRUNC;
    if (d & 0x10) l |= MSG_CTRUNC;
    return l;
}

static int d_socket(int dom, int type, int proto) {
    int l = af_to_linux(dom);
    return socket(l, type, proto);
}
static int d_socketpair(int dom, int type, int proto, int* sv) { return socketpair(af_to_linux(dom), type, proto, sv); }
static int d_bind(int fd, const void* a, socklen_t len) {
    sockaddr_storage ss; socklen_t ll = sa_to_linux(a, len, &ss);
    return bind(fd, (sockaddr*)&ss, ll);
}
// connectx(2): only the destination endpoint matters here (no source binding, no TFO data)
static int d_connectx(int fd, const void* endpoints, uint32_t, uint32_t, const void*, uint32_t, size_t* len, uint32_t* connid) {
    struct Ep { uint32_t srcif; uint32_t pad; const void* src; uint32_t srclen; uint32_t pad2; const void* dst; uint32_t dstlen; };
    const Ep* ep = (const Ep*)endpoints;
    if (!ep || !ep->dst) { errno = EINVAL; return -1; }
    if (len) *len = 0;
    if (connid) *connid = 1;
    sockaddr_storage ss; socklen_t ll = sa_to_linux(ep->dst, ep->dstlen, &ss);
    return connect(fd, (sockaddr*)&ss, ll);
}
static int d_sendmsg_x() { errno = ENOSYS; return -1; }

static int d_connect(int fd, const void* a, socklen_t len) {
    sockaddr_storage ss; socklen_t ll = sa_to_linux(a, len, &ss);
    return connect(fd, (sockaddr*)&ss, ll);
}
static int d_accept(int fd, void* a, socklen_t* len) {
    sockaddr_storage ss; socklen_t ll = sizeof ss;
    int r = accept(fd, a ? (sockaddr*)&ss : nullptr, a ? &ll : nullptr);
    if (r >= 0 && a && len) *len = sa_to_darwin((sockaddr*)&ss, ll, a, *len);
    return r;
}
static int d_getsockname(int fd, void* a, socklen_t* len) {
    sockaddr_storage ss; socklen_t ll = sizeof ss;
    int r = getsockname(fd, (sockaddr*)&ss, &ll);
    if (r == 0) *len = sa_to_darwin((sockaddr*)&ss, ll, a, *len);
    return r;
}
static int d_getpeername(int fd, void* a, socklen_t* len) {
    sockaddr_storage ss; socklen_t ll = sizeof ss;
    int r = getpeername(fd, (sockaddr*)&ss, &ll);
    if (r == 0) *len = sa_to_darwin((sockaddr*)&ss, ll, a, *len);
    return r;
}
static int d_setsockopt(int fd, int level, int opt, const void* val, socklen_t len) {
    int ll, lo;
    if (!sockopt_to_linux(level, opt, &ll, &lo)) return 0;     // unsupported option: pretend success
    if (level == 0xffff && (opt == 0x1005 || opt == 0x1006) && len >= 12) {   // Darwin timeval {i64, i32}
        struct timeval tv; tv.tv_sec = *(const int64_t*)val; tv.tv_usec = *(const int32_t*)((const char*)val + 8);
        return setsockopt(fd, ll, lo, &tv, sizeof tv);
    }
    if (level == 0xffff && opt == 0x1022) return 0;          // SO_NOSIGPIPE
    return setsockopt(fd, ll, lo, val, len);
}
static int d_getsockopt(int fd, int level, int opt, void* val, socklen_t* len) {
    int ll, lo;
    if (!sockopt_to_linux(level, opt, &ll, &lo)) { if (val && len && *len >= 4) *(int*)val = 0; return 0; }
    if (level == 0xffff && opt == 0x1007) {      // SO_ERROR: translate the errno value
        int r = getsockopt(fd, ll, lo, val, len);
        if (r == 0 && val) *(int*)val = darwin_errno_from_linux(*(int*)val);
        return r;
    }
    return getsockopt(fd, ll, lo, val, len);
}
static ssize_t d_send(int fd, const void* b, size_t n, int fl) { return send(fd, b, n, msgflags_to_linux(fl) | MSG_NOSIGNAL); }
static ssize_t d_recv(int fd, void* b, size_t n, int fl) { return recv(fd, b, n, msgflags_to_linux(fl)); }
static ssize_t d_sendto(int fd, const void* b, size_t n, int fl, const void* a, socklen_t al) {
    if (!a) return send(fd, b, n, msgflags_to_linux(fl) | MSG_NOSIGNAL);
    sockaddr_storage ss; socklen_t ll = sa_to_linux(a, al, &ss);
    return sendto(fd, b, n, msgflags_to_linux(fl) | MSG_NOSIGNAL, (sockaddr*)&ss, ll);
}
static ssize_t d_recvfrom(int fd, void* b, size_t n, int fl, void* a, socklen_t* al) {
    if (!a) return recvfrom(fd, b, n, msgflags_to_linux(fl), nullptr, nullptr);
    sockaddr_storage ss; socklen_t ll = sizeof ss;
    ssize_t r = recvfrom(fd, b, n, msgflags_to_linux(fl), (sockaddr*)&ss, &ll);
    if (r >= 0) *al = sa_to_darwin((sockaddr*)&ss, ll, a, *al);
    return r;
}
// Darwin msghdr: {void* name; u32 namelen; iovec* iov; int iovlen; void* control; u32 controllen; int flags}
struct DMsghdr { void* name; uint32_t namelen; uint32_t pad0; struct iovec* iov; int32_t iovlen; int32_t pad1; void* control; uint32_t controllen; int32_t flags; };
static ssize_t d_sendmsg(int fd, const DMsghdr* m, int fl) {
    struct msghdr lm; memset(&lm, 0, sizeof lm);
    sockaddr_storage ss;
    if (m->name) { lm.msg_namelen = sa_to_linux(m->name, m->namelen, &ss); lm.msg_name = &ss; }
    lm.msg_iov = m->iov; lm.msg_iovlen = m->iovlen;
    return sendmsg(fd, &lm, msgflags_to_linux(fl) | MSG_NOSIGNAL);    // control messages are not translated
}
static ssize_t d_recvmsg(int fd, DMsghdr* m, int fl) {
    struct msghdr lm; memset(&lm, 0, sizeof lm);
    sockaddr_storage ss; lm.msg_name = m->name ? &ss : nullptr; lm.msg_namelen = m->name ? sizeof ss : 0;
    lm.msg_iov = m->iov; lm.msg_iovlen = m->iovlen;
    ssize_t r = recvmsg(fd, &lm, msgflags_to_linux(fl));
    if (r >= 0) { if (m->name) m->namelen = sa_to_darwin((sockaddr*)&ss, lm.msg_namelen, m->name, m->namelen); m->controllen = 0; m->flags = lm.msg_flags; }
    return r;
}
static int d_shutdown(int fd, int how) { return shutdown(fd, how); }

// ---- select / pselect with Darwin timeval ------------------------------------------------------------------------
static int d_select(int n, fd_set* r, fd_set* w, fd_set* e, const int64_t* tv /* {sec, usec32} */) {
    struct timeval t, *tp = nullptr;
    if (tv) { t.tv_sec = tv[0]; t.tv_usec = (int32_t)tv[1]; tp = &t; }
    return select(n, r, w, e, tp);
}
static int d_pselect(int n, fd_set* r, fd_set* w, fd_set* e, const int64_t* ts, const void*) {
    struct timeval t, *tp = nullptr;
    if (ts) { t.tv_sec = ts[0]; t.tv_usec = ts[1] / 1000; tp = &t; }
    return select(n, r, w, e, tp);
}

// ---- netdb -------------------------------------------------------------------------------------------------------
struct DAddrinfo { int32_t ai_flags, ai_family, ai_socktype, ai_protocol; uint32_t ai_addrlen, pad; char* ai_canonname; void* ai_addr; DAddrinfo* ai_next; };
static int eai_to_darwin(int l) {
    switch (l) {
        case 0: return 0;
        case EAI_BADFLAGS: return 3; case EAI_NONAME: return 8; case EAI_AGAIN: return 2; case EAI_FAIL: return 4;
        case EAI_FAMILY: return 5; case EAI_SOCKTYPE: return 10; case EAI_SERVICE: return 9; case EAI_MEMORY: return 6;
        case EAI_SYSTEM: return 11; case EAI_OVERFLOW: return 14;
#ifdef EAI_NODATA
        case EAI_NODATA: return 7;
#endif
        default: return 4;
    }
}
static int aiflags_to_linux(int d) {
    int l = d & (AI_PASSIVE | AI_CANONNAME | AI_NUMERICHOST);
    if (d & 0x1000) l |= AI_NUMERICSERV;
    if (d & 0x400) l |= AI_ADDRCONFIG;
    if (d & 0x800) l |= AI_V4MAPPED;
    if (d & 0x100) l |= AI_ALL;
    return l;
}
static int d_getaddrinfo(const char* node, const char* serv, const DAddrinfo* hints, DAddrinfo** res) {
    struct addrinfo lh, *lhp = nullptr, *lres = nullptr;
    if (hints) {
        memset(&lh, 0, sizeof lh);
        lh.ai_flags = aiflags_to_linux(hints->ai_flags);
        lh.ai_family = af_to_linux(hints->ai_family);
        lh.ai_socktype = hints->ai_socktype;
        lh.ai_protocol = hints->ai_protocol;
        lhp = &lh;
    }
    int r = getaddrinfo(node, serv, lhp, &lres);
    if (r) return eai_to_darwin(r);
    DAddrinfo *head = nullptr, **tail = &head;
    for (struct addrinfo* p = lres; p; p = p->ai_next) {
        DAddrinfo* d = (DAddrinfo*)calloc(1, sizeof(DAddrinfo) + 128);
        d->ai_flags = 0; d->ai_family = af_to_darwin(p->ai_family); d->ai_socktype = p->ai_socktype; d->ai_protocol = p->ai_protocol;
        d->ai_addr = (char*)d + sizeof(DAddrinfo);
        d->ai_addrlen = sa_to_darwin(p->ai_addr, p->ai_addrlen, d->ai_addr, 128);
        if (p->ai_canonname) d->ai_canonname = strdup(p->ai_canonname);
        *tail = d; tail = &d->ai_next;
    }
    freeaddrinfo(lres);
    *res = head;
    return 0;
}
static void d_freeaddrinfo(DAddrinfo* a) {
    while (a) { DAddrinfo* n = a->ai_next; free(a->ai_canonname); free(a); a = n; }
}
static int d_getnameinfo(const void* sa, socklen_t salen, char* host, socklen_t hostlen, char* serv, socklen_t servlen, int flags) {
    sockaddr_storage ss; socklen_t ll = sa_to_linux(sa, salen, &ss);
    int lf = 0;
    if (flags & 2) lf |= NI_NUMERICHOST; if (flags & 8) lf |= NI_NUMERICSERV; if (flags & 4) lf |= NI_NAMEREQD; if (flags & 16) lf |= NI_DGRAM;
    return eai_to_darwin(getnameinfo((sockaddr*)&ss, ll, host, hostlen, serv, servlen, lf));
}
static const char* d_gai_strerror(int e) {
    switch (e) {
        case 0: return "no error"; case 1: return "address family for hostname not supported"; case 2: return "temporary failure in name resolution";
        case 3: return "invalid value for ai_flags"; case 4: return "non-recoverable failure in name resolution";
        case 5: return "ai_family not supported"; case 6: return "memory allocation failure";
        case 7: return "no address associated with hostname"; case 8: return "nodename nor servname provided, or not known";
        case 9: return "servname not supported for ai_socktype"; case 10: return "ai_socktype not supported";
        case 11: return "system error returned in errno"; case 12: return "invalid value for hints"; case 13: return "resolved protocol is unknown";
        case 14: return "argument buffer overflow"; default: return "unknown error";
    }
}

// ---- uname ---------------------------------------------------------------------------------------------------------
static int d_uname(char* u) {   // five 256-byte fields
    struct utsname l; if (uname(&l)) return -1;
    memset(u, 0, 5 * 256);
    strcpy(u, "Darwin");
    strncpy(u + 256, l.nodename, 255);
    strcpy(u + 512, "25.0.0");
    strcpy(u + 768, "Darwin Kernel Version 25.0.0: XEF-OSX emulated; root:xnu-12377.1.9~1/RELEASE_ARM64_T8103");
    strcpy(u + 1024, "arm64");
    return 0;
}

static const char* d_inet_ntop(int af, const void* src, char* dst, socklen_t size) {
    int laf = af_to_linux(af);
    const char* r = inet_ntop(laf, src, dst, size);
    if (!r) errno = darwin_errno_from_linux(errno);
    return r;
}

static int d_inet_pton(int af, const char* src, void* dst) {
    int laf = af_to_linux(af);
    int r = inet_pton(laf, src, dst);
    if (r < 0) errno = darwin_errno_from_linux(errno);
    return r;
}

struct NetShim { const char* name; void* fn; };
static const NetShim kNet[] = {
    {"_socket", (void*)&d_socket}, {"_socketpair", (void*)&d_socketpair}, {"_bind", (void*)&d_bind}, {"_connect", (void*)&d_connect},
    {"_connectx", (void*)&d_connectx}, {"_sendmsg_x", (void*)&d_sendmsg_x}, {"_recvmsg_x", (void*)&d_sendmsg_x},
    {"_accept", (void*)&d_accept}, {"_listen", (void*)&listen}, {"_getsockname", (void*)&d_getsockname}, {"_getpeername", (void*)&d_getpeername},
    {"_setsockopt", (void*)&d_setsockopt}, {"_getsockopt", (void*)&d_getsockopt}, {"_send", (void*)&d_send}, {"_recv", (void*)&d_recv},
    {"_sendto", (void*)&d_sendto}, {"_recvfrom", (void*)&d_recvfrom}, {"_sendmsg", (void*)&d_sendmsg}, {"_recvmsg", (void*)&d_recvmsg},
    {"_shutdown", (void*)&d_shutdown}, {"_select", (void*)&d_select}, {"_select$DARWIN_EXTSN", (void*)&d_select},
    {"_select$1050", (void*)&d_select}, {"_pselect", (void*)&d_pselect}, {"_pselect$DARWIN_EXTSN", (void*)&d_pselect},
    {"_getaddrinfo", (void*)&d_getaddrinfo}, {"_freeaddrinfo", (void*)&d_freeaddrinfo}, {"_getnameinfo", (void*)&d_getnameinfo},
    {"_gai_strerror", (void*)&d_gai_strerror}, {"_uname", (void*)&d_uname},
    {"_inet_ntop", (void*)&d_inet_ntop}, {"_inet_pton", (void*)&d_inet_pton},
    {"inet_ntop", (void*)&d_inet_ntop}, {"inet_pton", (void*)&d_inet_pton},
};
void* darwin_net_lookup(const char* name) {
    for (const NetShim& s : kNet) if (!strcmp(s.name, name)) return s.fn;
    return nullptr;
}

} // namespace xef
