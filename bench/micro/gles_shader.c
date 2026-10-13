// Headless GLES2 fragment-shader benchmark: EGL surfaceless context (Mesa), an FBO, a
// math-heavy fragment shader (llvmpipe compiles it with LLVM at run time: NEON code that XEF
// translates), N frames, pixel checksum. Libraries are dlopen'ed, so no GL headers are needed.
//   EGL_PLATFORM=surfaceless LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 ./gles_shader [frames] [size]
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef void* EGLDisplay;
typedef void* EGLContext;
typedef void* EGLConfig;
typedef int EGLint;
typedef unsigned GLenum, GLuint;
typedef int GLint, GLsizei;
typedef float GLfloat;
typedef unsigned char GLubyte;
typedef unsigned EGLenum;

#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_OPENGL_ES2_BIT 0x0004
#define EGL_NONE 0x3038
#define EGL_CONTEXT_CLIENT_VERSION 0x3098
#define EGL_OPENGL_ES_API 0x30A0
#define EGL_SURFACE_TYPE 0x3033
#define GL_FRAGMENT_SHADER 0x8B30
#define GL_VERTEX_SHADER 0x8B31
#define GL_COMPILE_STATUS 0x8B81
#define GL_LINK_STATUS 0x8B82
#define GL_FRAMEBUFFER 0x8D40
#define GL_RENDERBUFFER 0x8D41
#define GL_RGBA8 0x8058
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#define GL_TRIANGLE_STRIP 0x0005
#define GL_FLOAT 0x1406
#define GL_RGBA 0x1908
#define GL_UNSIGNED_BYTE 0x1401
#define GL_COLOR_BUFFER_BIT 0x4000

#define FN(ret, name, args) static ret(*name) args
FN(EGLDisplay, eglGetPlatformDisplayEXT, (EGLenum, void*, const EGLint*));
FN(int, eglInitialize, (EGLDisplay, EGLint*, EGLint*));
FN(int, eglChooseConfig, (EGLDisplay, const EGLint*, EGLConfig*, EGLint, EGLint*));
FN(int, eglBindAPI, (EGLenum));
FN(EGLContext, eglCreateContext, (EGLDisplay, EGLConfig, EGLContext, const EGLint*));
FN(int, eglMakeCurrent, (EGLDisplay, void*, void*, EGLContext));
FN(void*, eglGetProcAddress, (const char*));
FN(GLuint, glCreateShader, (GLenum));
FN(void, glShaderSource, (GLuint, GLsizei, const char* const*, const GLint*));
FN(void, glCompileShader, (GLuint));
FN(void, glGetShaderiv, (GLuint, GLenum, GLint*));
FN(void, glGetShaderInfoLog, (GLuint, GLsizei, GLsizei*, char*));
FN(GLuint, glCreateProgram, (void));
FN(void, glAttachShader, (GLuint, GLuint));
FN(void, glBindAttribLocation, (GLuint, GLuint, const char*));
FN(void, glLinkProgram, (GLuint));
FN(void, glGetProgramiv, (GLuint, GLenum, GLint*));
FN(void, glUseProgram, (GLuint));
FN(GLint, glGetUniformLocation, (GLuint, const char*));
FN(void, glUniform1f, (GLint, GLfloat));
FN(void, glGenFramebuffers, (GLsizei, GLuint*));
FN(void, glBindFramebuffer, (GLenum, GLuint));
FN(void, glGenRenderbuffers, (GLsizei, GLuint*));
FN(void, glBindRenderbuffer, (GLenum, GLuint));
FN(void, glRenderbufferStorage, (GLenum, GLenum, GLsizei, GLsizei));
FN(void, glFramebufferRenderbuffer, (GLenum, GLenum, GLenum, GLuint));
FN(GLenum, glCheckFramebufferStatus, (GLenum));
FN(void, glViewport, (GLint, GLint, GLsizei, GLsizei));
FN(void, glVertexAttribPointer, (GLuint, GLint, GLenum, unsigned char, GLsizei, const void*));
FN(void, glEnableVertexAttribArray, (GLuint));
FN(void, glDrawArrays, (GLenum, GLint, GLsizei));
FN(void, glReadPixels, (GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void*));
FN(void, glFinish, (void));
FN(void, glClear, (GLenum));

static const char* vs =
    "attribute vec2 p; varying vec2 uv;\n"
    "void main() { uv = p * 0.5 + 0.5; gl_Position = vec4(p, 0.0, 1.0); }\n";
static const char* fs =
    "precision highp float; varying vec2 uv; uniform float t;\n"
    "void main() {\n"
    "  vec3 c = vec3(0.0); vec2 z = uv * 3.0 - 1.5;\n"
    "  for (int i = 0; i < 24; i++) {\n"
    "    z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + vec2(0.285 + 0.01 * sin(t), 0.01);\n"
    "    float d = inversesqrt(dot(z, z) + 1.0);\n"
    "    c += vec3(d, sqrt(abs(z.x)) * d, clamp(z.y * d, 0.0, 1.0)) / float(i + 1);\n"
    "    z = normalize(z + 0.001) * min(length(z), 4.0);\n"
    "  }\n"
    "  vec3 n = normalize(vec3(uv - 0.5, 0.7));\n"
    "  float l = pow(max(dot(n, normalize(vec3(0.3, 0.5, 1.0))), 0.0), 8.0);\n"
    "  gl_FragColor = vec4(clamp(c * 0.5 + l, 0.0, 1.0), 1.0 / (1.0 + c.x));\n"
    "}\n";

static GLuint shader(GLenum type, const char* src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, 0);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) { char log[2048]; glGetShaderInfoLog(s, sizeof log, 0, log); fprintf(stderr, "shader: %s\n", log); exit(1); }
    return s;
}

int main(int argc, char** argv) {
    int frames = argc > 1 ? atoi(argv[1]) : 20, size = argc > 2 ? atoi(argv[2]) : 256;
    void* egl = dlopen("libEGL.so.1", RTLD_NOW);
    void* gl = dlopen("libGLESv2.so.2", RTLD_NOW);
    if (!egl || !gl) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
#define L(lib, name) *(void**)&name = dlsym(lib, #name); if (!name) { fprintf(stderr, "missing %s\n", #name); return 1; }
    L(egl, eglInitialize) L(egl, eglChooseConfig) L(egl, eglBindAPI) L(egl, eglCreateContext) L(egl, eglMakeCurrent)
    L(egl, eglGetProcAddress)
    *(void**)&eglGetPlatformDisplayEXT = eglGetProcAddress("eglGetPlatformDisplayEXT");
    L(gl, glCreateShader) L(gl, glShaderSource) L(gl, glCompileShader) L(gl, glGetShaderiv) L(gl, glGetShaderInfoLog)
    L(gl, glCreateProgram) L(gl, glAttachShader) L(gl, glBindAttribLocation) L(gl, glLinkProgram) L(gl, glGetProgramiv)
    L(gl, glUseProgram) L(gl, glGetUniformLocation) L(gl, glUniform1f) L(gl, glGenFramebuffers) L(gl, glBindFramebuffer)
    L(gl, glGenRenderbuffers) L(gl, glBindRenderbuffer) L(gl, glRenderbufferStorage) L(gl, glFramebufferRenderbuffer)
    L(gl, glCheckFramebufferStatus) L(gl, glViewport) L(gl, glVertexAttribPointer) L(gl, glEnableVertexAttribArray)
    L(gl, glDrawArrays) L(gl, glReadPixels) L(gl, glFinish) L(gl, glClear)
    EGLDisplay d = eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, 0, 0);
    if (!d || !eglInitialize(d, 0, 0)) { fprintf(stderr, "eglInitialize failed\n"); return 1; }
    EGLint ca[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_SURFACE_TYPE, 0, EGL_NONE};
    EGLConfig cfg;
    EGLint n = 0;
    if (!eglChooseConfig(d, ca, &cfg, 1, &n) || !n) { fprintf(stderr, "no config\n"); return 1; }
    eglBindAPI(EGL_OPENGL_ES_API);
    EGLint xa[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    EGLContext c = eglCreateContext(d, cfg, 0, xa);
    if (!c || !eglMakeCurrent(d, 0, 0, c)) { fprintf(stderr, "context failed\n"); return 1; }
    GLuint fb, rb;
    glGenFramebuffers(1, &fb);
    glBindFramebuffer(GL_FRAMEBUFFER, fb);
    glGenRenderbuffers(1, &rb);
    glBindRenderbuffer(GL_RENDERBUFFER, rb);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, size, size);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) { fprintf(stderr, "fbo incomplete\n"); return 1; }
    GLuint prog = glCreateProgram();
    glAttachShader(prog, shader(GL_VERTEX_SHADER, vs));
    glAttachShader(prog, shader(GL_FRAGMENT_SHADER, fs));
    glBindAttribLocation(prog, 0, "p");
    glLinkProgram(prog);
    glUseProgram(prog);
    GLint ut = glGetUniformLocation(prog, "t");
    static const GLfloat quad[] = {-1, -1, 1, -1, -1, 1, 1, 1};
    glVertexAttribPointer(0, 2, GL_FLOAT, 0, 0, quad);
    glEnableVertexAttribArray(0);
    glViewport(0, 0, size, size);
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int f = 0; f < frames; f++) {
        glClear(GL_COLOR_BUFFER_BIT);
        glUniform1f(ut, f * 0.1f);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }
    glFinish();
    clock_gettime(CLOCK_MONOTONIC, &t1);
    unsigned char* px = malloc((size_t)size * size * 4);
    glReadPixels(0, 0, size, size, GL_RGBA, GL_UNSIGNED_BYTE, px);
    uint64_t sum = 0;
    for (int i = 0; i < size * size * 4; i++) sum = sum * 31 + px[i];
    printf("checksum %016llx\n", (unsigned long long)sum);
    fprintf(stderr, "%d frames %dx%d: %.3f s\n", frames, size, size,
            (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9);
    return 0;
}
