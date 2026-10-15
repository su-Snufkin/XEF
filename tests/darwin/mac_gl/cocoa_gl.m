#define GL_SILENCE_DEPRECATION
#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
static const char *g_out;   // argv[1]: PPM of the last frame (read back before the flush)
static void dump_ppm(const char *path, int w, int h) {
  unsigned char *px = malloc((size_t)w * h * 3);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, w, h, GL_RGB, GL_UNSIGNED_BYTE, px);
  FILE *f = fopen(path, "wb");
  if (f) { fprintf(f, "P6\n%d %d\n255\n", w, h); for (int y = h - 1; y >= 0; y--) fwrite(px + (size_t)y * w * 3, 3, w, f); fclose(f); }
  free(px);
}
@interface V:NSOpenGLView{@public int n;} @end
@implementation V
-(void)drawRect:(NSRect)r{
  [[self openGLContext] makeCurrentContext];
  glViewport(0,0,(int)r.size.width,(int)r.size.height);
  glClearColor(0.1f,0.1f,0.2f,1);glClear(GL_COLOR_BUFFER_BIT);
  glMatrixMode(GL_MODELVIEW);glLoadIdentity();glRotatef(n*2.0f,0,0,1);
  glBegin(GL_TRIANGLES);glColor3f(1,0,0);glVertex2f(-.5f,-.5f);glColor3f(0,1,0);glVertex2f(.5f,-.5f);glColor3f(0,0,1);glVertex2f(0,.5f);glEnd();
  if(n==299&&g_out)dump_ppm(g_out,(int)r.size.width,(int)r.size.height);
  glFlush();[[self openGLContext] flushBuffer];
}
@end
int main(int argc,char**argv){@autoreleasepool{
  if(argc>1)g_out=argv[1];
  [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
  NSOpenGLPixelFormatAttribute at[]={NSOpenGLPFADoubleBuffer,NSOpenGLPFAAccelerated,0};
  NSOpenGLPixelFormat*pf=[[NSOpenGLPixelFormat alloc]initWithAttributes:at];
  if(!pf){puts("no pixel format");return 2;}
  NSWindow*w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,320,240) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  V*v=[[V alloc]initWithFrame:NSMakeRect(0,0,320,240) pixelFormat:pf];
  [v setWantsBestResolutionOpenGLSurface:NO];
  [w setContentView:v];
  if(!getenv("HIDDEN"))[w makeKeyAndOrderFront:nil];
  [[v openGLContext] makeCurrentContext];
  printf("GL_VERSION=%s\n",glGetString(GL_VERSION));
  int n=0;
  for(;n<300;n++){v->n=n;[v drawRect:[v bounds]];
    NSEvent*e;while((e=[NSApp nextEventMatchingMask:NSEventMaskAny untilDate:nil inMode:NSDefaultRunLoopMode dequeue:YES]))[NSApp sendEvent:e];}
  printf("frames=%d\n",n);fflush(stdout);
  if(getenv("GLTRI_HOLD_MS"))usleep(atoi(getenv("GLTRI_HOLD_MS"))*1000);   // keep the window up for screenshots
  return 0;}}
