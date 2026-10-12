# GUI applications and 3D games under XEF

XEF runs unmodified AArch64 X11/OpenGL programs on an x86-64 host. Rendering uses the guest's
own Mesa (llvmpipe: LLVM JIT-compiles shaders to AArch64 code at run time, which XEF then
translates; this relies on code invalidation via `IC IVAU`), and the window goes to the host
X server over the normal X11 socket.

## Native host OpenGL (`--host-gl`)

With `--host-gl` (or `XEF_HOST_GL=1`) the guest's `libGL.so.1` / `libGLX.so.0` / `libOpenGL.so.0`
are replaced by a small AArch64 shim (`tools/build_thunks.sh` → `build/thunks/libGL.so.1`). Every
GL/GLX entry point (≈3100, generated from the host's GL headers by `tools/gen_glthunks.py`) is a
stub `mov x17,#id; hlt #0x5846; ret`; XEF turns it into a call of the host's native libGL with
the arguments moved from AAPCS64 to SysV. Pointers pass unchanged (shared address space, same
LP64 layouts). GLX runs on a host Xlib connection to the same X server: window XIDs are
server-side, so the host renders into the guest's windows. Rendering is then native — llvmpipe
with AVX2 here, or the GPU driver on a real machine.

| Workload | guest Mesa (emulated) | `--host-gl` | native x86 on the same host |
|---|---|---|---|
| glmark2 (build, phong, texture, refract) | 174 | 387 | 350 |
| SuperTuxKart, Lighthouse race | 2.2 FPS | 9.4 FPS | 7.4 FPS |

Verified with `--host-gl`:

| Program | Notes | Screenshot |
|---|---|---|
| Neverball, Extreme Tux Racer, OpenArena, Minetest, Warzone 2100, glxgears | | `hostgl-games.png` |
| Blender 4.0 | libepoxy, GL 4.5 core | `blender-hostgl.png` |
| Stellarium 24.4 | Qt 6, 17 FPS | `stellarium-hostgl.png` |
| Godot 3.5 | editor; GLES3 3D scene with shadows at 28 FPS (time goes to the host's llvmpipe) | `godot3-hostgl.png` |
| Red Eclipse 1.6 | GL 4.5 core, bot match: `redeclipse "-xstart abuse 2 0"` | `redeclipse-hostgl.png` |
| Trigger Rally | race (driven with xdotool) | `trigger-rally-hostgl.png` |
| TORCS | quick race against four AI cars, 25 FPS | `hostgl-games2.jpg` |
| MegaGlest, Armagetron Advanced, X-Moto | menus / animated 3D menu | `hostgl-games2.jpg` |
| Scorched3D | wxWidgets launcher starting the SDL client; tutorial match against bots | `scorched3d-hostgl.jpg` |
| BZFlag, Widelands, Endless Sky | menus | |
| LibreOffice 24.2 Writer | GTK3; ready in ~15 s; typing, spell checking (no --host-gl needed) | `libreoffice-writer.jpg` |
| vkmark (Vulkan) | 300 points vs 360 natively (llvmpipe/lavapipe) | |

(screenshots in `docs/screenshots/`)

EGL (X11 platform) and GLES go through the same shim (`libEGL.so.1`, `libGLESv2.so.2`,
`libGLESv1_CM.so.1` are redirected too): eglinfo, eglgears_x11, and WebGL in WebKitGTK (22 → 41
FPS) run on the host (`docs/screenshots/hostgl-egl.png`).

Vulkan: `libvulkan.so.1` is redirected to a second shim (`build/thunks/libvulkan.so.1`, ~630
entry points from `vulkan_core.h`, Xlib and XCB WSI). Allocation callbacks are dropped (NULL),
debug messengers are faked in the guest and stripped from `vkCreateInstance`'s pNext chain,
`VkXlibSurfaceCreateInfoKHR::dpy` / `VkXcbSurfaceCreateInfoKHR::connection` are swapped for host
connections, and `vkGet*ProcAddr` hand out the shim's stubs for functions the host provides.
vulkaninfo and vkcube run on the host's lavapipe (`docs/screenshots/vkcube-hostvk.png`).

Callbacks from the host into guest code (`glDebugMessageCallback`) run the guest function on the
calling guest thread (nested JIT run, return via `hlt #0x5847`). Limits: the
GBM/Wayland EGL platforms are not supported; X errors on the host connection are ignored instead
of reaching the guest's handler.

## Setup

```sh
tools/setup.sh && tools/mkrootfs.sh                    # base rootfs: shells, X11 apps, Mesa, GL demos
tools/mkrootfs.sh glmark2-x11 neverball extremetuxracer openarena minetest # more packages (dependencies are resolved)
Xvfb :1 -screen 0 800x600x24 &                         # or any host X server
export DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1
export SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null       # no audio device in containers
R=.tools/rootfs-arm64
build/xef -L $R $R/usr/bin/glxgears
build/xef -L $R $R/usr/games/neverball
build/xef -L $R $R/usr/games/etr
build/xef -L $R $R/usr/games/openarena +map aggressor   # shell-script launchers work too
build/xef -L $R $R/usr/games/minetest
```

`tools/guishot.sh SECONDS OUT.png -- /usr/games/supertuxkart --race-now --track=lighthouse` runs a
program from the rootfs with these settings and takes a screenshot of the X server.

`mkrootfs.sh` also generates what package maintainer scripts normally would (gdk-pixbuf loader
cache, compiled GSettings schemas, icon caches, fontconfig cache) by running the guest's own tools
under XEF.

## Sound

Guest programs talk to the host's PulseAudio / PipeWire-Pulse server over its Unix socket (the
protocol is architecture-independent): with `XDG_RUNTIME_DIR` (or `PULSE_SERVER`) pointing at the
host session, aarch64 `paplay`, SDL2 games (`SDL_AUDIODRIVER=pulseaudio`) and OpenAL games
(`ALSOFT_DRIVERS=pulse`) play sound. Verified by recording a null sink's monitor: a 440 Hz tone
from `paplay` and Neverball's menu music arrive intact. Without a sound server use the
`dummy` / `null` drivers shown above.

## Verified (2026-10-12, i7 cloud VM, Xvfb)

| Program | Result |
|---|---|
| xlogo, xeyes, xclock | work |
| galculator (GTK 3), xterm running the guest bash | work, interactive (`docs/screenshots/gtk-xterm.png`) |
| glxinfo | OpenGL 4.5 compat / ES 3.2, llvmpipe (LLVM 20.1.2) |
| glxgears | ~380 FPS |
| glmark2 (build, phong, texture, refract) | score 174 (native x86 llvmpipe on the host: 350) |
| Neverball | menus, level select, gameplay (`docs/screenshots/neverball-game.png`) |
| Extreme Tux Racer | menus and racing (`docs/screenshots/etr-race.png`) |
| OpenArena (ioquake3, launched through its shell script) | menus, deathmatch with bots (`docs/screenshots/openarena-game.png`) |
| Minetest (Irrlicht + LuaJIT) | world creation and gameplay (`docs/screenshots/minetest-game.png`) |
| SuperTuxKart 1.4 | race on Lighthouse (`--race-now`, `docs/screenshots/supertuxkart-race.png`) |
| GIMP 2.10 | UI (`docs/screenshots/gimp.png`); Script-Fu batch: fill, selection, Gaussian blur plug-in, PNG export (`docs/screenshots/gimp-batch-output.png`) |
| Warzone 2100 (GL 4.5 core; run `warzone2100.real`, the wrapper uses bubblewrap) | skirmish game (`docs/screenshots/warzone2100-skirmish.png`) |
| Armagetron Advanced, SuperTux 2 | menus (`docs/screenshots/armagetronad.png`, `supertux.png`) |
| mpv (lavfi test source, X11 output) | real-time 25 FPS playback (`docs/screenshots/mpv.png`) |
| FeatherPad (Qt) | works (`docs/screenshots/qt-featherpad.png`) |
| WebKitGTK MiniBrowser (multi-process, JavaScriptCore JIT) | page with CSS gradients, canvas, JS (`docs/screenshots/webkit-minibrowser.png`), WebGL cube at ~22 FPS (`docs/screenshots/webkit-webgl.png`); needs `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` (bubblewrap/seccomp sandbox is not emulated) |

Without `ALSOFT_DRIVERS=null` OpenAL games spin on failing audio calls when no sound device
exists (not an XEF issue).
