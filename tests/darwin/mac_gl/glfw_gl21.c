/* GLFW 3.4 (static, Cocoa) GL 2.1 test: 300 frames of a rotating triangle, PPM of frame 299 (argv[1]).
 * Same binary runs on macOS and on XEF-OSX (AppKit-lite). HIDDEN=1 hides the window. */
#define GL_SILENCE_DEPRECATION
#include <GLFW/glfw3.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
static void on_error(int code, const char *desc) { fprintf(stderr, "GLFW error 0x%x: %s\n", code, desc); }
static void dump_ppm(const char *path, int w, int h) {
  unsigned char *px = malloc((size_t)w * h * 3);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, w, h, GL_RGB, GL_UNSIGNED_BYTE, px);
  FILE *f = fopen(path, "wb");
  if (f) { fprintf(f, "P6\n%d %d\n255\n", w, h); for (int y = h - 1; y >= 0; y--) fwrite(px + (size_t)y * w * 3, 3, w, f); fclose(f); }
  free(px);
}
int main(int argc, char **argv) {
  const char *out = argc > 1 ? argv[1] : NULL;
  glfwSetErrorCallback(on_error);
  if (!glfwInit()) { puts("glfwInit failed"); return 1; }
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2); glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
  glfwWindowHint(GLFW_COCOA_RETINA_FRAMEBUFFER, GLFW_FALSE);
  if (getenv("HIDDEN")) glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
  GLFWwindow *w = glfwCreateWindow(320, 240, "cand1 GL2.1", NULL, NULL);
  if (!w) { puts("window failed"); glfwTerminate(); return 2; }
  glfwMakeContextCurrent(w); glfwSwapInterval(0);
  printf("GL_VERSION=%s\nGL_RENDERER=%s\n", glGetString(GL_VERSION), glGetString(GL_RENDERER));
  int n = 0;
  for (; n < 300; n++) {
    int fw, fh; glfwGetFramebufferSize(w, &fw, &fh); glViewport(0, 0, fw, fh);
    glClearColor(0.1f, 0.1f, 0.2f, 1); glClear(GL_COLOR_BUFFER_BIT);
    glMatrixMode(GL_MODELVIEW); glLoadIdentity(); glRotatef(n * 2.0f, 0, 0, 1);
    glBegin(GL_TRIANGLES); glColor3f(1, 0, 0); glVertex2f(-0.5f, -0.5f); glColor3f(0, 1, 0); glVertex2f(0.5f, -0.5f);
    glColor3f(0, 0, 1); glVertex2f(0, 0.5f); glEnd();
    if (n == 299 && out) dump_ppm(out, fw, fh);
    glfwSwapBuffers(w); glfwPollEvents();
  }
  { /* backend facts: read after the loop (the Mac reports the 2x backing size only until its first backing-properties event); must be identical on macOS and XEF-OSX (no gamepads, one monitor, US layout) */
    int mc = 0, ww, wh, fw, fh; float sx, sy; glfwGetMonitors(&mc); glfwGetWindowSize(w, &ww, &wh); glfwGetFramebufferSize(w, &fw, &fh);
    glfwGetWindowContentScale(w, &sx, &sy);
    printf("glfw=%s\nmonitors=%d primary=%d joystick0=%d window=%dx%d fb=%dx%d scale=%.1f\n", glfwGetVersionString(), mc, glfwGetPrimaryMonitor() != NULL,
           glfwJoystickPresent(GLFW_JOYSTICK_1), ww, wh, fw, fh, sx);
    const char *ka = glfwGetKeyName(GLFW_KEY_A, 0), *k1 = glfwGetKeyName(GLFW_KEY_1, 0), *ks = glfwGetKeyName(GLFW_KEY_SLASH, 0);
    printf("keynames A=%s 1=%s slash=%s\n", ka ? ka : "(null)", k1 ? k1 : "(null)", ks ? ks : "(null)"); }
  printf("frames=%d\n", n); fflush(stdout);
  if (getenv("GLTRI_HOLD_MS")) usleep(atoi(getenv("GLTRI_HOLD_MS")) * 1000);
  glfwDestroyWindow(w); glfwTerminate(); return 0;
}
