/* gltri_core: GL 3.2 core / GLSL 150 scene: VAO+VBO+EBO, uniforms, depth-tested rotating textured cube
 * (glDrawElements), a triangle (glDrawArrays), and a 2x2x2 3D texture built with glTexImage3D (10 args) and
 * patched with glTexSubImage3D (11 args): both spill arguments to the stack on arm64 Darwin.
 * 300 frames, PPM dump at frame 299, glGetError checked each frame. */
#define GL_SILENCE_DEPRECATION 1
#include <OpenGL/gl3.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef NOSHIM
static int xef_win_create_core(int w, int h, const char *t, int a, int b) { (void)w; (void)h; (void)t; (void)a; (void)b; return 0; }
static void xef_win_swap(void) {}
static int xef_win_poll(void) { return 0; }
static int xef_win_dump(const char *p) { (void)p; return 0; }
#else
extern int xef_win_create_core(int w, int h, const char *title, int major, int minor);
extern void xef_win_swap(void);
extern int xef_win_poll(void);
extern int xef_win_dump(const char *path);
#endif

static const char *VS =
    "#version 150\n"
    "in vec3 aPos; in vec3 aNrm;\n"
    "uniform mat4 uMvp; uniform mat4 uRot; uniform float uMode;\n"
    "out vec3 vTc; out vec3 vNrm;\n"
    "void main(){ vTc = aPos*0.5+0.5; vNrm = mat3(uRot)*aNrm;\n"
    "  gl_Position = uMvp*vec4(aPos,1.0); }\n";
static const char *FS =
    "#version 150\n"
    "in vec3 vTc; in vec3 vNrm; out vec4 oCol;\n"
    "uniform sampler3D uTex; uniform float uMode;\n"
    "void main(){\n"
    "  if (uMode > 0.5) { oCol = vec4(1.0,0.8,0.1,1.0); return; }\n"
    "  float l = 0.55 + 0.45*max(dot(normalize(vNrm), normalize(vec3(0.3,0.5,0.8))), 0.0);\n"
    "  oCol = vec4(texture(uTex, vTc).rgb*l, 1.0); }\n";

static GLuint compile(GLenum type, const char *src) {
    GLuint s = glCreateShader(type);
    GLint ok = 0;
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) { char log[1024]; glGetShaderInfoLog(s, sizeof log, NULL, log); fprintf(stderr, "shader: %s\n", log); exit(3); }
    return s;
}

/* separate calls: clang would fuse sinf+cosf into ___sincosf_stret (HFA return, not bridged by the HLE yet) */
static __attribute__((noinline)) float msin(float x) { return sinf(x); }
static __attribute__((noinline)) float mcos(float x) { return cosf(x); }

static void mat_mul(float *r, const float *a, const float *b) {   /* column-major r = a*b */
    int i, j, k;
    for (i = 0; i < 4; i++) for (j = 0; j < 4; j++) {
        float s = 0; for (k = 0; k < 4; k++) s += a[k*4+i] * b[j*4+k];
        r[j*4+i] = s;
    }
}
static void mat_rot(float *m, float ang, float x, float y, float z) {
    float l = sqrtf(x*x+y*y+z*z), c = mcos(ang), s = msin(ang), t = 1-c;
    x /= l; y /= l; z /= l;
    memset(m, 0, 64);
    m[0]=t*x*x+c;   m[4]=t*x*y-s*z; m[8]=t*x*z+s*y;
    m[1]=t*x*y+s*z; m[5]=t*y*y+c;   m[9]=t*y*z-s*x;
    m[2]=t*x*z-s*y; m[6]=t*y*z+s*x; m[10]=t*z*z+c;
    m[15]=1;
}

int main(int argc, char **argv) {
    const char *out = argc > 1 ? argv[1] : "/tmp/gltri_core.ppm";
    int frame, frames = 0, i, f;
    static const float N[6][3] = {{0,0,-1},{0,0,1},{0,-1,0},{0,1,0},{-1,0,0},{1,0,0}};
    static const float P[6][4][3] = {   /* faces: -z, +z, -y, +y, -x, +x */
        {{-1,-1,-1},{-1,1,-1},{1,1,-1},{1,-1,-1}}, {{-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}},
        {{-1,-1,-1},{1,-1,-1},{1,-1,1},{-1,-1,1}}, {{-1,1,-1},{-1,1,1},{1,1,1},{1,1,-1}},
        {{-1,-1,-1},{-1,-1,1},{-1,1,1},{-1,1,-1}}, {{1,-1,-1},{1,1,-1},{1,1,1},{1,-1,1}}};
    float vb[24*6]; unsigned short ib[36];
    static const float tri[3][6] = {{-0.95f,-0.95f,0,0,0,1},{-0.65f,-0.95f,0,0,0,1},{-0.8f,-0.65f,0,0,0,1}};
    GLuint vao[2], vbo[2], ebo, prog, tex, vs, fs;
    GLint uMvp, uRot, uMode, uTex;
    unsigned char texels[8][4];
    unsigned char patch[4] = {255, 255, 255, 255};
    GLenum err;

    for (f = 0; f < 6; f++) for (i = 0; i < 4; i++) {
        memcpy(&vb[(f*4+i)*6], P[f][i], 12); memcpy(&vb[(f*4+i)*6+3], N[f], 12);
    }
    for (f = 0; f < 6; f++) {
        static const int q[6] = {0,1,2,0,2,3};
        for (i = 0; i < 6; i++) ib[f*6+i] = (unsigned short)(f*4 + q[i]);
    }
    for (i = 0; i < 8; i++) {   /* texel (x,y,z) = bit i: distinct colour per octant */
        texels[i][0] = (i & 1) ? 230 : 40; texels[i][1] = (i & 2) ? 230 : 40; texels[i][2] = (i & 4) ? 230 : 40;
        texels[i][3] = 255;
    }

    if (xef_win_create_core(640, 480, "gltri_core", 3, 2) < 0) { fprintf(stderr, "core window create failed\n"); return 1; }
    fprintf(stderr, "GL_VERSION=%s\nGLSL=%s\n", (const char *)glGetString(GL_VERSION),
            (const char *)glGetString(GL_SHADING_LANGUAGE_VERSION));
    vs = compile(GL_VERTEX_SHADER, VS); fs = compile(GL_FRAGMENT_SHADER, FS);
    prog = glCreateProgram();
    glAttachShader(prog, vs); glAttachShader(prog, fs);
    glBindAttribLocation(prog, 0, "aPos"); glBindAttribLocation(prog, 1, "aNrm");
    glBindFragDataLocation(prog, 0, "oCol");
    glLinkProgram(prog);
    { GLint ok = 0; glGetProgramiv(prog, GL_LINK_STATUS, &ok); if (!ok) { fprintf(stderr, "link failed\n"); return 3; } }
    uMvp = glGetUniformLocation(prog, "uMvp"); uRot = glGetUniformLocation(prog, "uRot");
    uMode = glGetUniformLocation(prog, "uMode"); uTex = glGetUniformLocation(prog, "uTex");

    glGenVertexArrays(2, vao); glGenBuffers(2, vbo); glGenBuffers(1, &ebo);
    glBindVertexArray(vao[0]);
    glBindBuffer(GL_ARRAY_BUFFER, vbo[0]); glBufferData(GL_ARRAY_BUFFER, sizeof vb, vb, GL_STATIC_DRAW);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo); glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof ib, ib, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0); glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 24, (void *)0);
    glEnableVertexAttribArray(1); glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 24, (void *)12);
    glBindVertexArray(vao[1]);
    glBindBuffer(GL_ARRAY_BUFFER, vbo[1]); glBufferData(GL_ARRAY_BUFFER, sizeof tri, tri, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0); glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 24, (void *)0);
    glEnableVertexAttribArray(1); glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 24, (void *)12);

    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_3D, tex);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
    glTexImage3D(GL_TEXTURE_3D, 0, GL_RGBA8, 2, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, texels);          /* 10 args */
    glTexSubImage3D(GL_TEXTURE_3D, 0, 1, 1, 1, 1, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, patch);              /* 11 args */
    if ((err = glGetError()) != 0) { fprintf(stderr, "glGetError after setup = 0x%x\n", err); return 2; }

    glViewport(0, 0, 640, 480);
    glEnable(GL_DEPTH_TEST);
    glUseProgram(prog);
    glUniform1i(uTex, 0);
    for (frame = 0; frame < 300; frame++) {
        float rx[16], ry[16], rot[16], model[16], proj[16], mvp[16], id[16];
        const float n = 1.5f, fa = 20.0f, l = -0.8f, r = 0.8f, b = -0.6f, t = 0.6f;
        glClearColor(0.1f, 0.2f, 0.3f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        mat_rot(rx, 25.0f * 3.14159265f / 180.0f, 1, 0, 0);
        mat_rot(ry, frame * 1.5f * 3.14159265f / 180.0f, 0.3f, 1.0f, 0.1f);
        mat_mul(rot, rx, ry);
        memcpy(model, rot, 64); model[14] = -6.0f;                       /* translate(0,0,-6) * rot */
        memset(proj, 0, 64);
        proj[0] = 2*n/(r-l); proj[5] = 2*n/(t-b); proj[8] = (r+l)/(r-l); proj[9] = (t+b)/(t-b);
        proj[10] = -(fa+n)/(fa-n); proj[11] = -1; proj[14] = -2*fa*n/(fa-n);
        mat_mul(mvp, proj, model);
        memset(id, 0, 64); id[0] = id[5] = id[10] = id[15] = 1;
        glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_3D, tex);
        glUniformMatrix4fv(uMvp, 1, GL_FALSE, mvp);
        glUniformMatrix4fv(uRot, 1, GL_FALSE, rot);
        glUniform1f(uMode, 0.0f);
        glBindVertexArray(vao[0]);
        glDrawElements(GL_TRIANGLES, 36, GL_UNSIGNED_SHORT, (void *)0);
        glUniformMatrix4fv(uMvp, 1, GL_FALSE, id);
        glUniformMatrix4fv(uRot, 1, GL_FALSE, id);
        glUniform1f(uMode, 1.0f);
        glBindVertexArray(vao[1]);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        if ((err = glGetError()) != 0) { fprintf(stderr, "glGetError frame %d = 0x%x\n", frame, err); return 2; }
        if (frame == 299) xef_win_dump(out);
        xef_win_swap();
        frames++;
        if (xef_win_poll() == 1) break;
    }
    if (getenv("GLTRI_HOLD_MS")) usleep(atoi(getenv("GLTRI_HOLD_MS")) * 1000);
    printf("frames=%d\n", frames);
    return 0;
}
