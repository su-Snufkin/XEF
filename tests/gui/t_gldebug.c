// --host-gl: glDebugMessageCallback reaches the guest callback (host -> guest call). EGL surfaceless,
// no window needed. Build: see tests/gui/run.sh
#include <stdio.h>
typedef void* EGLDisplay; typedef void* EGLConfig; typedef void* EGLContext; typedef int EGLint;
EGLDisplay eglGetPlatformDisplay(unsigned platform, void* native, const long* attribs);
int eglInitialize(EGLDisplay, EGLint*, EGLint*);
int eglBindAPI(unsigned api);
int eglChooseConfig(EGLDisplay, const EGLint*, EGLConfig*, EGLint, EGLint*);
EGLContext eglCreateContext(EGLDisplay, EGLConfig, EGLContext, const EGLint*);
int eglMakeCurrent(EGLDisplay, void*, void*, EGLContext);
void* eglGetProcAddress(const char*);
void glEnable(unsigned);
typedef void (*DebugProc)(unsigned, unsigned, unsigned, unsigned, int, const char*, const void*);

static int calls;
static unsigned last_type;
static const void* last_user;
static void on_debug(unsigned source, unsigned type, unsigned id, unsigned severity, int length, const char* msg,
                     const void* user) {
    calls++;
    last_type = type;
    last_user = user;
}

int main(void) {
    EGLDisplay d = eglGetPlatformDisplay(0x31DD /*SURFACELESS_MESA*/, 0, 0);
    EGLint maj, min, n;
    if (!eglInitialize(d, &maj, &min)) { printf("no EGL\n"); return 1; }
    eglBindAPI(0x30A2 /*OPENGL_API*/);
    EGLint cfg_attr[] = {0x3040 /*RENDERABLE_TYPE*/, 0x0008 /*OPENGL_BIT*/, 0x3038};
    EGLConfig cfg;
    eglChooseConfig(d, cfg_attr, &cfg, 1, &n);
    EGLint ctx_attr[] = {0x30FC /*CONTEXT_FLAGS_KHR*/, 1 /*DEBUG_BIT*/, 0x3038};
    EGLContext ctx = eglCreateContext(d, cfg, 0, ctx_attr);
    if (!ctx || !eglMakeCurrent(d, 0, 0, ctx)) { printf("no context\n"); return 1; }
    void (*cb)(DebugProc, const void*) = (void (*)(DebugProc, const void*))eglGetProcAddress("glDebugMessageCallback");
    glEnable(0x92E0 /*DEBUG_OUTPUT*/);
    glEnable(0x8242 /*DEBUG_OUTPUT_SYNCHRONOUS*/);
    static int marker;
    cb(on_debug, &marker);
    glEnable(0xFFFF);   // GL_INVALID_ENUM -> debug message
    printf("debug callback: calls>0=%d type=%#x user ok=%d\n", calls > 0, last_type, last_user == &marker);
    return 0;
}
