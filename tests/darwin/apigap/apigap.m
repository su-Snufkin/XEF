// Which methods of a public API list (tools/appkit_api.py) the frameworks in the rootfs do not implement.
// Built on Linux without SDK headers (tools/appkit_gap.sh); prints "X Class" for a class that is missing or only
// a generated stub, "M Class +/-selector [D]" for a method the class does not respond to.
typedef struct objc_class *Class;
typedef struct objc_object *id;
typedef struct objc_selector *SEL;
typedef struct __sFILE FILE;
extern int printf(const char *, ...);
extern FILE *fopen(const char *, const char *);
extern char *fgets(char *, int, FILE *);
extern char *strchr(const char *, int);
extern char *strstr(const char *, const char *);
extern int strcmp(const char *, const char *);
extern unsigned long strlen(const char *);
extern id objc_getClass(const char *);
extern Class object_getClass(id);
extern SEL sel_registerName(const char *);
extern signed char class_respondsToSelector(Class, SEL);
extern const char *class_getImageName(Class);
extern signed char XEFClassImplements(Class, SEL) __attribute__((weak_import));   // AppKit-lite: not a catch-all stub

int main(int argc, char **argv) {
    FILE *f = argc > 1 ? fopen(argv[1], "r") : 0;
    if (!f) { printf("usage: apigap api.txt\n"); return 2; }
    static char line[4096], last[256];
    int lastMissing = 0;
    while (fgets(line, sizeof line, f)) {
        char *cls = line, *kind = strchr(cls, '\t');
        if (!kind) continue;
        *kind++ = 0;
        char *sel = strchr(kind, '\t');
        if (!sel) continue;
        *sel++ = 0;
        char *dep = strchr(sel, '\t');
        if (!dep) continue;
        *dep++ = 0;
        if (strcmp(cls, last) != 0) {
            unsigned long n = strlen(cls);
            for (unsigned long i = 0; i <= n && i < sizeof last - 1; i++) last[i] = cls[i];
            Class c = (Class)objc_getClass(cls);
            const char *img = c ? class_getImageName(c) : 0;
            lastMissing = !c || (img && strstr(img, ".xefstubs"));
            if (lastMissing) printf("X\t%s\n", cls);
        }
        if (lastMissing) continue;
        Class c = (Class)objc_getClass(cls);
        if (kind[0] == '+') c = object_getClass((id)c);
        SEL s = sel_registerName(sel);
        if (!(XEFClassImplements ? XEFClassImplements(c, s) : class_respondsToSelector(c, s)))
            printf("M\t%s\t%c%s%s\n", cls, kind[0], sel, dep[0] == 'D' ? "\tD" : "");
    }
    return 0;
}
