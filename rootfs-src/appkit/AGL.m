/*
 * AGL implementation for XEF
 * Based on Darling specifications
 */

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef void* AGLContext;
typedef void* AGLPixelFormat;
typedef void* AGLDrawable;
typedef void* AGLPbuffer;
typedef void* AGLRendererInfo;
typedef void* AGLDevice;
typedef uint32_t GLenum;
typedef uint8_t GLboolean;
typedef int32_t GLint;
typedef int32_t GLsizei;
typedef void GLvoid;
typedef uint32_t GLuint;
typedef uint16_t GLushort;
typedef uint8_t GLubyte;
typedef double GLdouble;

static int g_fakeToken = 1;

AGLContext aglCreateContext(AGLPixelFormat pix, AGLContext share) { return (AGLContext)&g_fakeToken; }
GLboolean aglDestroyContext(AGLContext ctx) { return 1; }
GLboolean aglSetCurrentContext(AGLContext ctx) { return 1; }
AGLContext aglGetCurrentContext(void) { return (AGLContext)&g_fakeToken; }
GLboolean aglUpdateContext(AGLContext ctx) { return 1; }
void aglSwapBuffers(AGLContext ctx) {}

@interface XEF_AGL_Placeholder : NSObject @end
@implementation XEF_AGL_Placeholder @end
