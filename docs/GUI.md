# GUI applications and 3D games under XEF

XEF runs unmodified AArch64 X11/OpenGL programs on an x86-64 host. Rendering uses the guest's
own Mesa (llvmpipe: LLVM JIT-compiles shaders to AArch64 code at run time, which XEF then
translates; this relies on code invalidation via `IC IVAU`), and the window goes to the host
X server over the normal X11 socket.

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

## Verified (2026-10-12, i7 cloud VM, Xvfb)

| Program | Result |
|---|---|
| xlogo, xeyes, xclock | work |
| glxinfo | OpenGL 4.5 compat / ES 3.2, llvmpipe (LLVM 20.1.2) |
| glxgears | ~380 FPS |
| glmark2 (build, phong, texture, refract) | score 137 (native x86 llvmpipe on the host: 350) |
| Neverball | menus, level select, gameplay (`docs/screenshots/neverball-game.png`) |
| Extreme Tux Racer | menus and racing (`docs/screenshots/etr-race.png`) |
| OpenArena (ioquake3, launched through its shell script) | menus, deathmatch with bots (`docs/screenshots/openarena-game.png`) |
| Minetest (Irrlicht + LuaJIT) | world creation and gameplay (`docs/screenshots/minetest-game.png`) |

Without `ALSOFT_DRIVERS=null` OpenAL games spin on failing audio calls when no sound device
exists (not an XEF issue).
