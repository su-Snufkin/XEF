#!/usr/bin/env python3
"""Generates the OpenGL/GLX host-thunk tables from the host's GL headers.

Outputs:
  src/thunks/gl_table.inc      host side: X(name, signature, flags) per function, id = position
  thunks/gl_stubs.S            guest side: one exported AArch64 stub per function
  thunks/gl_names.inc          guest side: {name, stub} table for glXGetProcAddress

Signature: "<ret>:<args>", one letter per value (AAPCS64 -> SysV marshalling in src/thunks):
  v void, i 32-bit int, l 64-bit int/pointer, b u8, c s8, s s16, S u16, f float, d double,
  D Display* (replaced by the host connection).
Flags: 1 = takes a callback (not forwarded), 2 = implemented by the guest shim (raw thunk only),
  8 = eglGetPlatformDisplay: arg 1 is a Display* when arg 0 is EGL_PLATFORM_X11.

usage: gen_glthunks.py [include-dir]   (default /usr/include)
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INC = sys.argv[1] if len(sys.argv) > 1 else '/usr/include'

INT32 = {'GLenum', 'GLbitfield', 'GLuint', 'GLint', 'GLsizei', 'GLfixed', 'GLhandleARB', 'GLclampx', 'int',
         'unsigned int', 'unsigned', 'Bool', 'Status', 'GLuint', 'GLXVideoDeviceNV', 'uint32_t', 'int32_t'}
U8 = {'GLboolean', 'GLubyte', 'unsigned char'}
S8 = {'GLbyte', 'GLchar', 'char', 'GLcharARB'}
S16 = {'GLshort', 'short'}
U16 = {'GLushort', 'GLhalf', 'GLhalfNV', 'GLhalfARB', 'unsigned short'}
F32 = {'GLfloat', 'GLclampf', 'float'}
F64 = {'GLdouble', 'GLclampd', 'double'}
I64 = {'GLintptr', 'GLsizeiptr', 'GLintptrARB', 'GLsizeiptrARB', 'GLint64', 'GLuint64', 'GLint64EXT',
       'GLuint64EXT', 'GLsync', 'GLvdpauSurfaceNV', 'GLeglImageOES', 'GLeglClientBufferEXT', 'long',
       'unsigned long', 'int64_t', 'uint64_t', 'XID', 'GLXDrawable', 'GLXPixmap', 'GLXWindow',
       'GLXPbuffer', 'GLXContextID', 'GLXFBConfigID', 'GLXVideoSourceSGIX', 'GLXFBConfigIDSGIX',
       'GLXPbufferSGIX', 'Window', 'Pixmap', 'Font', 'Colormap', 'GLXContext', 'GLXFBConfig',
       'GLXFBConfigSGIX', 'GLXVideoCaptureDeviceNV', 'GLXHyperpipeNetworkSGIX', '__GLXextFuncPtr',
       'GLXVideoDeviceNV*', 'size_t', 'ssize_t', 'GLXFBConfig*'}
CALLBACK = {'GLDEBUGPROC', 'GLDEBUGPROCARB', 'GLDEBUGPROCKHR', 'GLDEBUGPROCAMD', 'GLVULKANPROCNV',
            'EGLDEBUGPROCKHR', 'EGLSetBlobFuncANDROID', 'EGLGetBlobFuncANDROID'}
INT32 |= {'EGLint', 'EGLBoolean', 'EGLenum', 'EGLNativeFileDescriptorKHR'}
I64 |= {'EGLDisplay', 'EGLConfig', 'EGLContext', 'EGLSurface', 'EGLClientBuffer', 'EGLImage', 'EGLImageKHR',
        'EGLSync', 'EGLSyncKHR', 'EGLSyncNV', 'EGLAttrib', 'EGLAttribKHR', 'EGLTime', 'EGLTimeKHR', 'EGLTimeNV',
        'EGLuint64KHR', 'EGLuint64NV', 'EGLDeviceEXT', 'EGLOutputLayerEXT', 'EGLOutputPortEXT', 'EGLStreamKHR',
        'EGLObjectKHR', 'EGLLabelKHR', 'EGLsizeiANDROID', 'EGLNativePixmapType', 'EGLNativeWindowType',
        'EGLnsecsANDROID', '__eglMustCastToProperFunctionPointerType'}
# the guest's pending X requests must reach the server before these (drawables created by the guest)
SYNC = {'glXMakeCurrent', 'glXMakeContextCurrent', 'glXMakeCurrentReadSGI', 'glXCreateWindow', 'glXCreatePixmap',
        'glXCreateGLXPixmap', 'glXCreateGLXPixmapWithConfigSGIX', 'glXSwapBuffers'}
# implemented in the guest shim (memory the guest frees with XFree, guest function pointers)
SHIM = {'glXChooseVisual', 'glXGetVisualFromFBConfig', 'glXChooseFBConfig', 'glXGetFBConfigs',
        'glXGetProcAddress', 'glXGetProcAddressARB', 'glXChooseFBConfigSGIX', 'glXGetVisualFromFBConfigSGIX',
        'eglGetProcAddress', 'eglGetDisplay', 'eglGetPlatformDisplay', 'eglGetPlatformDisplayEXT'}
# EGL calls that use the guest's X windows: XSync the display the guest last passed to eglGetDisplay
SYNC_EGL = {'eglCreateWindowSurface', 'eglCreatePlatformWindowSurface', 'eglCreatePlatformWindowSurfaceEXT',
            'eglMakeCurrent', 'eglSwapBuffers', 'eglCreatePixmapSurface', 'eglCreatePlatformPixmapSurface'}

def classify(t):
    t = t.replace('const', ' ').replace('struct', ' ').strip()
    t = re.sub(r'\s+', ' ', t)
    if '*' in t:
        base = t.replace('*', '').strip()
        if base == 'Display' and t.count('*') == 1:
            return 'D'
        return 'l'
    if t == 'EGLNativeDisplayType':
        return 'D'
    if t in CALLBACK:
        return 'CB'
    if t in INT32: return 'i'
    if t in U8: return 'b'
    if t in S8: return 'c'
    if t in S16: return 's'
    if t in U16: return 'S'
    if t in F32: return 'f'
    if t in F64: return 'd'
    if t in I64: return 'l'
    if t == 'void': return 'v'
    return None

def split_param(p):
    p = p.strip()
    if p in ('', 'void'): return None
    p = re.sub(r'\[\s*\d*\s*\]', '*', p)              # arrays decay to pointers
    m = re.match(r'(.*?)([A-Za-z_]\w*)$', p)
    if m and m.group(1).strip() and not m.group(1).strip().endswith(('unsigned', 'const')):
        return m.group(1)
    return p                                           # unnamed parameter

def parse(text, pattern):
    out = []
    for m in re.finditer(pattern, text, re.S):
        ret, name, params = m.group(1), m.group(2), m.group(3)
        out.append((name, ret, params))
    return out

funcs = {}
order = []
def add(name, ret, params):
    if name in funcs: return
    rc = classify(ret)
    if rc is None or rc == 'D': rc = 'l'
    args, flags = [], 0
    for p in params.split(','):
        t = split_param(p)
        if t is None: continue
        c = classify(t)
        if c is None:
            if '(' in p: c = 'l'                      # function pointer parameter
            else: return                              # unknown type: skip function
        if c == 'CB': c, flags = 'l', flags | 1
        args.append(c)
    if name in SHIM: flags |= 2
    if name in ('eglGetPlatformDisplay', 'eglGetPlatformDisplayEXT'): flags |= 8   # X11 native display
    funcs[name] = (rc, ''.join(args), flags)
    order.append(name)

def read(f):
    with open(os.path.join(INC, f)) as fh: return fh.read()

for f in ('GL/gl.h', 'GL/glext.h'):
    for name, ret, params in parse(read(f), r'GLAPI\s+([^;()]+?)\s*(?:GL)?APIENTRY\s+(gl\w+)\s*\((.*?)\)\s*;'):
        add(name, ret, params)
glx = read('GL/glx.h')
for name, ret, params in parse(glx, r'extern\s+([\w\s\*]+?)\s*\b(glX\w+)\s*\((.*?)\)\s*;'):
    add(name, ret, params)
add('glXGetProcAddress', 'void*', 'const GLubyte *procname')
for f in ('EGL/egl.h', 'EGL/eglext.h'):
    for name, ret, params in parse(read(f), r'EGLAPI\s+([^;()]+?)\s*EGLAPIENTRY\s+(egl\w+)\s*\((.*?)\)\s*;'):
        add(name, ret, params)
glxext = read('GL/glxext.h')
for blk in re.findall(r'#ifdef GLX_GLXEXT_PROTOTYPES\n(.*?)#endif', glxext, re.S):
    for name, ret, params in parse(blk, r'([\w\s\*]+?)\s*\b(glX\w+)\s*\((.*?)\)\s*;'):
        add(name, ret.strip(), params)

# ---- Vulkan (separate guest shim: libvulkan.so.1)
vk_order = []
VK_SHIM = {'vkGetInstanceProcAddr', 'vkGetDeviceProcAddr', 'vkCreateDebugUtilsMessengerEXT',
           'vkDestroyDebugUtilsMessengerEXT', 'vkCreateDebugReportCallbackEXT', 'vkDestroyDebugReportCallbackEXT',
           'vk_icdGetInstanceProcAddr'}
VK_FLAGS = {'vkCreateXlibSurfaceKHR': 16, 'vkCreateXcbSurfaceKHR': 32, 'vkCreateInstance': 64,
            'vkCreateDevice': 128}
vkdir = os.path.join(INC, 'vulkan')
if os.path.exists(os.path.join(vkdir, 'vulkan_core.h')):
    core = read('vulkan/vulkan_core.h')
    vk_types = {}
    for m in re.finditer(r'typedef enum (\w+)', core): vk_types[m.group(1)] = 'i'
    for m in re.finditer(r'VK_DEFINE_HANDLE\((\w+)\)', core): vk_types[m.group(1)] = 'l'
    for m in re.finditer(r'VK_DEFINE_NON_DISPATCHABLE_HANDLE\((\w+)\)', core): vk_types[m.group(1)] = 'l'
    for m in re.finditer(r'typedef (VkFlags|uint32_t|int32_t) (\w+);', core): vk_types[m.group(2)] = 'i'
    for m in re.finditer(r'typedef (VkFlags64|uint64_t) (\w+);', core): vk_types[m.group(2)] = 'l'
    for m in re.finditer(r'typedef struct (\w+) \{', core): vk_types.setdefault(m.group(1), 'STRUCT')
    vk_types.update({'uint32_t': 'i', 'int32_t': 'i', 'uint64_t': 'l', 'int64_t': 'l', 'size_t': 'l', 'float': 'f',
                     'int': 'i', 'VisualID': 'l', 'Window': 'l', 'xcb_window_t': 'i', 'xcb_visualid_t': 'i',
                     'uint16_t': 'S', 'uint8_t': 'b', 'void': 'v', 'PFN_vkVoidFunction': 'l', 'char': 'c'})
    def vk_class(t):
        t = re.sub(r'\s+', ' ', t.replace('const', ' ')).strip()
        if '*' in t:
            base = t.replace('*', '').strip()
            if base == 'Display': return 'D'
            if base == 'xcb_connection_t': return 'X'
            if base == 'VkAllocationCallbacks': return 'A'
            return 'l'
        return vk_types.get(t)
    def vk_add(name, ret, params):
        if name in funcs: return
        rc = vk_class(ret)
        if rc in (None, 'STRUCT'): return
        args = []
        for p in params.split(','):
            p = p.strip()
            if not p or p == 'void': continue
            p = re.sub(r'\[\s*\w*\s*\]', '*', p)
            m = re.match(r'(.*?)([A-Za-z_]\w*)$', p)
            c = vk_class(m.group(1) if m else p)
            if c in (None, 'STRUCT'): return       # unknown / struct by value: not thunked
            args.append(c)
        fl = (2 if name in VK_SHIM else 0) | VK_FLAGS.get(name, 0)
        funcs[name] = (rc, ''.join(args), fl)
        order.append(name)
        vk_order.append(name)
    for f in ('vulkan/vulkan_core.h', 'vulkan/vulkan_xlib.h', 'vulkan/vulkan_xcb.h'):
        if not os.path.exists(os.path.join(INC, f)): continue
        for m in re.finditer(r'VKAPI_ATTR\s+([\w\s\*]+?)\s+VKAPI_CALL\s+(vk\w+)\s*\((.*?)\)\s*;', read(f), re.S):
            vk_add(m.group(2), m.group(1), m.group(3))

# host helpers used by the guest shim (resolved in the host libX11)
funcs['xef_host_XFree'] = ('i', 'l', 2); order.append('xef_host_XFree')

os.makedirs(os.path.join(ROOT, 'src/thunks'), exist_ok=True)
os.makedirs(os.path.join(ROOT, 'thunks'), exist_ok=True)
with open(os.path.join(ROOT, 'src/thunks/gl_table.inc'), 'w') as f:
    f.write('// Generated by tools/gen_glthunks.py from the host GL headers. Do not edit.\n')
    for n in order:
        rc, a, fl = funcs[n]
        f.write('X(%s, "%s:%s", %d)\n' % (n, rc, a, fl))
def write_stubs(path, names):
  with open(path, 'w') as f:
    f.write('// Generated by tools/gen_glthunks.py. Guest stubs: x17 = thunk id, HLT #0x5846 calls the host.\n')
    f.write('    .text\n')
    for n in names:
        i = order.index(n)
        rc, a, fl = funcs[n]
        sym = n if n.startswith('xef_') else ('xef_raw_' + n) if fl & 2 else n
        f.write('    .globl %s\n    .type %s, %%function\n    .p2align 2\n%s:\n' % (sym, sym, sym))
        f.write('    mov x17, #%d\n    hlt #0x5846\n    ret\n' % i)
        f.write('    .size %s, .-%s\n' % (sym, sym))
    f.write('    .section .note.GNU-stack,"",%progbits\n')
write_stubs(os.path.join(ROOT, 'thunks/vk_stubs.S'), vk_order)
with open(os.path.join(ROOT, 'thunks/vk_names.inc'), 'w') as f:
    f.write('// Generated by tools/gen_glthunks.py.\n')
    for n in sorted(vk_order):
        if not funcs[n][2] & 2: f.write('{"%s", (void*)%s},\n' % (n, n))
with open(os.path.join(ROOT, 'thunks/vk_decls.inc'), 'w') as f:
    for n in vk_order:
        if not funcs[n][2] & 2: f.write('DECL(%s)\n' % n)
vkset = set(vk_order)
order_gl = [n for n in order if n not in vkset]
with open(os.path.join(ROOT, 'thunks/gl_stubs.S'), 'w') as f:
    f.write('// Generated by tools/gen_glthunks.py. Guest stubs: x17 = thunk id, HLT #0x5846 calls the host.\n')
    f.write('    .text\n')
    for n in order_gl:
        i = order.index(n)
        rc, a, fl = funcs[n]
        sym = n if n.startswith('xef_') else ('xef_raw_' + n) if fl & 2 else n
        f.write('    .globl %s\n    .type %s, %%function\n    .p2align 2\n%s:\n' % (sym, sym, sym))
        if n in SYNC or n in SYNC_EGL:   # guest XSync first: its own X requests (window creation) must be done
            f.write('    stp x29, x30, [sp, #-80]!\n    mov x29, sp\n    stp x0, x1, [sp, #16]\n'
                    '    stp x2, x3, [sp, #32]\n    stp x4, x5, [sp, #48]\n    stp x6, x7, [sp, #64]\n'
                    '    bl %s\n' % ('xef_guest_xsync_egl' if n in SYNC_EGL else 'xef_guest_xsync') +
                    '    ldp x0, x1, [sp, #16]\n    ldp x2, x3, [sp, #32]\n    ldp x4, x5, [sp, #48]\n'
                    '    ldp x6, x7, [sp, #64]\n    ldp x29, x30, [sp], #80\n')
        f.write('    mov x17, #%d\n    hlt #0x5846\n    ret\n' % i)
        f.write('    .size %s, .-%s\n' % (sym, sym))
    f.write('    .section .note.GNU-stack,"",%progbits\n')
with open(os.path.join(ROOT, 'thunks/gl_decls.inc'), 'w') as f:
    f.write('// Generated by tools/gen_glthunks.py.\n')
    for n in order_gl:
        if not funcs[n][2] & 2: f.write('DECL(%s)\n' % n)
with open(os.path.join(ROOT, 'thunks/gl_names.inc'), 'w') as f:
    f.write('// Generated by tools/gen_glthunks.py.\n')
    for n in sorted(order_gl):
        rc, a, fl = funcs[n]
        if not fl & 2:
            f.write('{"%s", (void*)%s},\n' % (n, n))
print('%d functions (%d GL/GLX/EGL, %d Vulkan)' % (len(order), len(order) - len(vk_order), len(vk_order)))
