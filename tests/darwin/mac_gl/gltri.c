/* gltri: legacy GL 2.1 rotating cube, 300 frames. Pure C, no ObjC.
 * The xef_win_* symbols exist only under XEF (loader shim) or in shim_mac.m (Mac oracle).
 * -DNOSHIM replaces them with no-ops. */
#define GL_SILENCE_DEPRECATION 1
#include <OpenGL/gl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#ifdef NOSHIM
static int xef_win_create(int w, int h, const char *t) { (void)w; (void)h; (void)t; return 0; }
static void xef_win_swap(void) {}
static int xef_win_poll(void) { return 0; }
static int xef_win_dump(const char *p) { (void)p; return 0; }
#else
extern int xef_win_create(int w, int h, const char *title);
extern void xef_win_swap(void);
extern int xef_win_poll(void);
extern int xef_win_dump(const char *path);
#endif

static const float V[8][3] = {
    {-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},{-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}};
static const int F[6][4] = {
    {0,1,2,3},{4,5,6,7},{0,1,5,4},{3,2,6,7},{0,3,7,4},{1,2,6,5}};
static const float C[6][3] = {
    {1,0,0},{0,1,0},{0,0,1},{1,1,0},{1,0,1},{0,1,1}};

static void draw_cube(void) {
    int f, i;
    glBegin(GL_QUADS);
    for (f = 0; f < 6; f++) {
        for (i = 0; i < 4; i++) {
            /* slight per-vertex shading so faces are not flat */
            float s = 0.6f + 0.1f * (float)i;
            glColor3f(C[f][0] * s, C[f][1] * s, C[f][2] * s);
            glVertex3f(V[F[f][i]][0], V[F[f][i]][1], V[F[f][i]][2]);
        }
    }
    glEnd();
}

int main(int argc, char **argv) {
    const char *out = argc > 1 ? argv[1] : "/tmp/gltri.ppm";
    int frame, frames = 0;
    if (xef_win_create(640, 480, "gltri") < 0) { fprintf(stderr, "window create failed\n"); return 1; }
    fprintf(stderr, "GL_VERSION=%s\n", (const char *)glGetString(GL_VERSION));
    glViewport(0, 0, 640, 480);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glFrustum(-0.8, 0.8, -0.6, 0.6, 1.5, 20.0);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glEnable(GL_DEPTH_TEST);
    for (frame = 0; frame < 300; frame++) {
        glClearColor(0.1f, 0.2f, 0.3f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glTranslatef(0.0f, 0.0f, -6.0f);
        glRotatef(25.0f, 1.0f, 0.0f, 0.0f);
        glRotatef(frame * 1.5f, 0.3f, 1.0f, 0.1f);
        draw_cube();
        if (frame == 299) xef_win_dump(out);
        xef_win_swap();
        frames++;
        if (xef_win_poll() == 1) break;
    }
    /* GLTRI_HOLD_MS keeps the last frame on screen so a test can grab the window */
    if (getenv("GLTRI_HOLD_MS")) usleep(atoi(getenv("GLTRI_HOLD_MS")) * 1000);
    printf("frames=%d\n", frames);
    return 0;
}
