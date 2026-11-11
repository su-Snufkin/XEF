// Runs on a real Mac: records facts about the exported API of system libraries that their .tbd files do not
// carry - whether a symbol is a function or data, the size and value of constants, the superclass of each
// Objective-C class. tools/gen_framework_stubs.py turns that into stub frameworks. No code is copied.
//
//   clang -O1 -framework Foundation mac_fwdump.m -o mac_fwdump && ./mac_fwdump < request.txt > facts.txt
//
// request:  L <install name> / S <symbol> / C <class>, repeated
// facts:    L <install name> <1|0 loaded>
//           F <symbol>                          function
//           S <symbol> <hex of UTF-8>           pointer to a constant CFString / NSString
//           D <symbol> <size> <hex bytes or -> <segment,section>
//           C <class> <superclass or -> <install name of the superclass's image or ->
//           E                                   end of library (missing: the child crashed or timed out)
// Each library is loaded in a child process (an initializer may crash or hang).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <sys/wait.h>
#import <signal.h>

typedef struct { uint64_t lo, hi; char seg[17], sect[17]; uint32_t flags; } Sect;

// section of the image at `base` that contains addr
static int find_section(const struct mach_header_64 *mh, uint64_t addr, Sect *out) {
    const struct load_command *lc = (const void *)(mh + 1);
    intptr_t slide = 0;
    int have_slide = 0;
    for (uint32_t i = 0; i < mh->ncmds; i++, lc = (const void *)((const char *)lc + lc->cmdsize)) {
        if (lc->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *sc = (const void *)lc;
        if (!have_slide && strcmp(sc->segname, "__TEXT") == 0) { slide = (intptr_t)mh - (intptr_t)sc->vmaddr; have_slide = 1; }
    }
    lc = (const void *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++, lc = (const void *)((const char *)lc + lc->cmdsize)) {
        if (lc->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *sc = (const void *)lc;
        const struct section_64 *s = (const void *)(sc + 1);
        for (uint32_t j = 0; j < sc->nsects; j++, s++) {
            uint64_t lo = s->addr + slide;
            if (addr >= lo && addr < lo + s->size) {
                out->lo = lo; out->hi = lo + s->size; out->flags = s->flags;
                memcpy(out->seg, s->segname, 16); out->seg[16] = 0;
                memcpy(out->sect, s->sectname, 16); out->sect[16] = 0;
                return 1;
            }
        }
    }
    return 0;
}

static int section_of(uint64_t addr, Sect *out) {
    Dl_info di;
    if (!dladdr((void *)addr, &di) || !di.dli_fbase) return 0;
    return find_section(di.dli_fbase, addr, out);
}

static void hex(const unsigned char *p, size_t n) {
    for (size_t i = 0; i < n; i++) printf("%02x", p[i]);
}

typedef struct { const char *name; uint64_t addr; Sect s; int ok; } Sym;
static int by_addr(const void *a, const void *b) {
    uint64_t x = (*(Sym *const *)a)->addr, y = (*(Sym *const *)b)->addr;
    return x < y ? -1 : x > y;
}

static void dump(const char *lib, char **syms, int nsyms, char **classes, int nclasses) {
    void *h = dlopen(lib, RTLD_LAZY | RTLD_LOCAL);
    printf("L\t%s\t%d\n", lib, h != NULL);
    if (!h) { printf("E\n"); return; }
    Sym *v = calloc(nsyms + 1, sizeof(Sym));
    Sym **order = calloc(nsyms + 1, sizeof(Sym *));
    int n = 0;
    for (int i = 0; i < nsyms; i++) {
        const char *nm = syms[i];
        void *a = dlsym(h, nm[0] == '_' ? nm + 1 : nm);
        if (!a) continue;
        v[n].name = nm; v[n].addr = (uint64_t)a;
        v[n].ok = section_of(v[n].addr, &v[n].s);
        order[n] = &v[n]; n++;
    }
    qsort(order, n, sizeof(Sym *), by_addr);
    for (int i = 0; i < n; i++) {
        Sym *s = order[i];
        if (!s->ok) continue;
        if ((s->s.flags & S_ATTR_PURE_INSTRUCTIONS) || (s->s.flags & S_ATTR_SOME_INSTRUCTIONS) ||
            strcmp(s->s.sect, "__text") == 0 || strncmp(s->s.sect, "__auth_stubs", 12) == 0 || strncmp(s->s.sect, "__stubs", 7) == 0) {
            printf("F\t%s\n", s->name);
            continue;
        }
        uint64_t end = s->s.hi;
        for (int j = i + 1; j < n; j++)
            if (order[j]->addr > s->addr) { if (order[j]->addr < end) end = order[j]->addr; break; }
        uint64_t size = end - s->addr;
        int zerofill = (s->s.flags & SECTION_TYPE) == S_ZEROFILL;
        // a pointer to a constant string object?
        if (size >= 8 && !zerofill && (s->addr & 7) == 0) {
            uint64_t p = *(uint64_t *)s->addr;
            Sect ps;
            if (p > 0x100000000ull && (p & 7) == 0 && section_of(p, &ps) && strcmp(ps.sect, "__cfstring") == 0) {
                @autoreleasepool {
                    const char *u = [(__bridge NSString *)(void *)p UTF8String];
                    if (u) { printf("S\t%s\t", s->name); hex((const unsigned char *)u, strlen(u)); printf("\n"); continue; }
                }
            }
        }
        printf("D\t%s\t%llu\t", s->name, size);
        int constant = strcmp(s->s.seg, "__TEXT") == 0 || strstr(s->s.sect, "const") != NULL;
        int emit = constant && !zerofill && size <= 256;
        if (emit) {   // no pointers: a pointer cannot be reproduced by value
            for (uint64_t o = 0; o + 8 <= size && emit; o += 8) {
                if ((s->addr + o) & 7) break;
                uint64_t w = *(uint64_t *)(s->addr + o);
                Dl_info di;
                if (w > 0x100000000ull && w < 0x800000000000ull && dladdr((void *)w, &di)) emit = 0;
            }
        }
        if (emit) hex((const unsigned char *)s->addr, size); else printf("-");
        printf("\t%s,%s\n", s->s.seg, s->s.sect);
    }
    for (int i = 0; i < nclasses; i++) {
        Class c = objc_getClass(classes[i]);
        if (!c) continue;
        Class sup = class_getSuperclass(c);
        const char *img = sup ? class_getImageName(sup) : NULL;
        printf("C\t%s\t%s\t%s\n", classes[i], sup ? class_getName(sup) : "-", img ? img : "-");
    }
    printf("E\n");
}

int main(void) {
    static char line[1 << 16];
    char *lib = NULL;
    char **syms = NULL, **classes = NULL;
    int nsyms = 0, nclasses = 0, csyms = 0, cclasses = 0;
    int more = 1;
    while (more) {
        more = fgets(line, sizeof line, stdin) != NULL;
        size_t len = more ? strlen(line) : 0;
        if (len && line[len - 1] == '\n') line[--len] = 0;
        if (!more || line[0] == 'L') {
            if (lib) {
                fflush(stdout);
                pid_t pid = fork();
                if (pid == 0) {
                    int devnull = open("/dev/null", O_WRONLY);
                    dup2(devnull, 2);
                    alarm(60);
                    dump(lib, syms, nsyms, classes, nclasses);
                    fflush(stdout);
                    _exit(0);
                }
                int st = 0;
                waitpid(pid, &st, 0);
                if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) fprintf(stderr, "failed: %s (status %#x)\n", lib, st);
                for (int i = 0; i < nsyms; i++) free(syms[i]);
                for (int i = 0; i < nclasses; i++) free(classes[i]);
                free(lib);
                nsyms = nclasses = 0;
            }
            lib = more ? strdup(line + 2) : NULL;
        } else if (line[0] == 'S') {
            if (nsyms == csyms) syms = realloc(syms, (csyms = csyms ? csyms * 2 : 1024) * sizeof(char *));
            syms[nsyms++] = strdup(line + 2);
        } else if (line[0] == 'C') {
            if (nclasses == cclasses) classes = realloc(classes, (cclasses = cclasses ? cclasses * 2 : 1024) * sizeof(char *));
            classes[nclasses++] = strdup(line + 2);
        }
    }
    return 0;
}
