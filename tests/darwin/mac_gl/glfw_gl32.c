/* GLFW 3.4 (static, Cocoa) GL 3.2 core test: 300 frames of a rotating triangle, PPM of frame 299 (argv[1]).
 * Same binary runs on macOS and on XEF-OSX (AppKit-lite). HIDDEN=1 hides the window. */
#define GL_SILENCE_DEPRECATION
#define GLFW_INCLUDE_GLCOREARB
#include <GLFW/glfw3.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>
static const char *vs = "#version 150\nin vec2 p;in vec3 c;out vec3 vc;uniform float a;void main(){float s=sin(a),k=cos(a);gl_Position=vec4(k*p.x-s*p.y,s*p.x+k*p.y,0,1);vc=c;}";
static const char *fs = "#version 150\nin vec3 vc;out vec4 o;void main(){o=vec4(vc,1);}";
static GLuint sh(GLenum t, const char *s) { GLuint h = glCreateShader(t); glShaderSource(h, 1, &s, NULL); glCompileShader(h); GLint ok; glGetShaderiv(h, GL_COMPILE_STATUS, &ok); if (!ok) { char l[512]; glGetShaderInfoLog(h, 512, NULL, l); puts(l); exit(3); } return h; }
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
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3); glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 2);
  glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE); glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
  glfwWindowHint(GLFW_COCOA_RETINA_FRAMEBUFFER, GLFW_FALSE);
  if (getenv("HIDDEN")) glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
  GLFWwindow *w = glfwCreateWindow(320, 240, "cand2 GL3.2", NULL, NULL);
  if (!w) { puts("window failed"); glfwTerminate(); return 2; }
  glfwMakeContextCurrent(w); glfwSwapInterval(0);
  printf("GL_VERSION=%s\nGL_RENDERER=%s\n", glGetString(GL_VERSION), glGetString(GL_RENDERER));
  GLuint pr = glCreateProgram(); glAttachShader(pr, sh(GL_VERTEX_SHADER, vs)); glAttachShader(pr, sh(GL_FRAGMENT_SHADER, fs));
  glBindAttribLocation(pr, 0, "p"); glBindAttribLocation(pr, 1, "c"); glLinkProgram(pr); glUseProgram(pr);
  GLint ua = glGetUniformLocation(pr, "a");
  float v[] = {-.5f, -.5f, 1, 0, 0, .5f, -.5f, 0, 1, 0, 0, .5f, 0, 0, 1};
  GLuint vao, vbo; glGenVertexArrays(1, &vao); glBindVertexArray(vao); glGenBuffers(1, &vbo); glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof v, v, GL_STATIC_DRAW);
  glEnableVertexAttribArray(0); glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 20, (void *)0);
  glEnableVertexAttribArray(1); glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 20, (void *)8);
  int n = 0;
  for (; n < 300; n++) {
    int fw, fh; glfwGetFramebufferSize(w, &fw, &fh); glViewport(0, 0, fw, fh);
    glClearColor(0.1f, 0.1f, 0.2f, 1); glClear(GL_COLOR_BUFFER_BIT);
    glUniform1f(ua, n * 0.035f); glDrawArrays(GL_TRIANGLES, 0, 3);
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
  printf("glerr=0x%x\nframes=%d\n", glGetError(), n); fflush(stdout);
  if (getenv("GLTRI_HOLD_MS")) usleep(atoi(getenv("GLTRI_HOLD_MS")) * 1000);
  glfwDestroyWindow(w); glfwTerminate(); return 0;
}
