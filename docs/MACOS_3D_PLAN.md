# Plan: aplikacja 3D macOS arm64 na XEF-OSX (pamięć trwała)

Stan na 2026-10-15. Cel i kryteria: `docs/PROMPT_MACOS_3D.md`. Aktualizuj statusy po każdym kroku.

## Wybór strategii: hybryda P1 → P2 (P3 odrzucone)
1. **P1 najpierw.** Wspólny rdzeń: `_gl*` z aplikacji Mach-O trafiają przez HLE do libGL hosta
   (GLX w procesie xef-osx). Najkrótsza droga do pierwszej klatki, najniższe ryzyko, używa
   istniejącego mechanizmu stubów (`hlt #0x5846`). Pierwsza aplikacja: własny program w C
   (legacy GL 2.1) z małym API okna (`_xef_win_*`).
2. **P2 potem (AppKit-lite, nie Darling/Cocotron).** Ta sama warstwa host-GL, a na wierzchu mała
   własna biblioteka AppKit/OpenGL.framework (arm64 Mach-O budowana na Macu) dla `cand3_cocoa`
   (29 symboli), potem GLFW (`cand1`). Real AppKit odpada: brak WindowServera (bootstrap 1102,
   xpc stuby), Darling/Cocotron AppKit to tygodnie pracy.
3. **P3 odrzucone.** Metal→Vulkan: tylko Indium/Iridium (Darling), nie zgodne z ABI Metal, XL.
   ANGLE: L–XL, nie obsługuje legacy GL; tańsza jest bezpośrednia ścieżka host-GL.
   Opcjonalna tania próba później: `mtl2spv` na shaderach `cand4_metal`.

## Fakty (Faza 0)
- Loader: mini-dyld, brakujący dylib = cichy HLE dep; nierozwiązany symbol fatalny dopiero przy wywołaniu
  (`darwin_hle.cpp:2944`). `darwin_hle_register_function` `:2880`, `darwin_hle_dispatch` `:2899`,
  fallback `dlsym` `:2810-2835`. xef-osx nie linkuje libGL (CMakeLists.txt:24).
- Most AAPCS64→SysV kopiuje 8-bajtowe słowa stosu; Apple pakuje naturalnie → psuje GL >8 arg całkowitych.
- Brak: AppKit, OpenGL, CoreGraphics, QuartzCore, IOKit, Metal. Są: CF, Foundation, libobjc, libdispatch-lite, libc++.
- Lokalnie brak `ld64.lld`: binarki testowe buduję na Macu (`ssh mac`) i commituję jak `hello_darwin`.
- Brak `xwd`: zrzuty przez `import -window root` (ImageMagick) na prywatnym Xvfb `:99`
  (`:1` ma martwy socket). Skrypt oceny obrazu: `imgcheck.py` (scratchpad → do repo jako `tools/imgcheck.py`).
- Kandydaci (Mac: `~/xef-remote/out/cand/`): cand1_gl21, cand2_gl32 (GLFW 3.4), cand3_cocoa, cand4_metal.

## Zadania i statusy
Statusy: [ ] następne, [~] w toku, [x] zrobione, [!] zablokowane.

### Etap A — P1: pierwsza klatka (aplikacja C + host GL)
- [x] A1 `src/loader/darwin_gl.{cpp,h}`: lazy dlopen libGL/libX11, rozwiązywanie `_gl*` przez glXGetProcAddressARB → `darwin_hle_register_function`
- [x] A2 hook w `darwin_hle.cpp` (przed fallbackiem dlsym, explicit-only), sprawdzić `resolve_import` dla brakującego OpenGL dylib
- [x] A3 shim okna: `_xef_win_create/_swap/_poll/_dump` (Xlib + GLX, zrzut PPM w procesie)
- [x] A4 aplikacja testowa `tests/darwin/mac_gl/gltri.c` (budowa na Macu) — CHECKPOINT „widzę okno", „pierwszy trójkąt"
- [x] A5 test regresji `tests/darwin/gl_test.sh` (Xvfb :99, rc==0, `frames=300`, imgcheck) + wpięcie w run_tests.sh
- [x] A6 (opcjonalne dla kostki; potrzebne dla cand2) scena (shadery, VBO, depth) + przepakowanie argumentów stosu dla >8 arg (wg sygnatur z gl_table.inc) — CHECKPOINT „scena"
- [x] A7 docs (HANDOFF, GUI), commit

### Etap B — P2: Cocoa przez AppKit-lite (cand3)
- [ ] B1 lista selektorów cand3 (otool -ov), `rootfs-src/appkit/`
- [ ] B2 `tools/build_appkit.sh` + AppKit/Cocoa/OpenGL.framework (arm64 Mach-O, budowa na Macu)
- [ ] B3 `src/loader/darwin_appkit_host.cpp` (okno/zdarzenia/swap przez X11+GLX)
- [ ] B4 cand3_cocoa: okno + 300 klatek + exit 0, porównanie z Makiem

### Etap C — GLFW (cand1)
- [ ] C1 zebrać `unresolved symbol` na poziomie logowania 1; zasilić stubami CG/IOKit/Carbon/CoreVideo
- [ ] C2 cand1_gl21 → cand2_gl32

## Kryteria sukcesu (z promptu) — status
1. start bez crasha: [x] (gltri)  2. zrzut 3D: [x] (SSIM 0,996 vs Mac)  3. ≥300 klatek, rc 0: [x]  4. powtarzalność + test: [x] (gl_test.sh)  5. commit + docs: [x]

## Ryzyka do sprawdzenia wcześnie
- wyrównanie stosu 16 B przy wywołaniu Mesa/AVX z mostu HLE; blokada `g_hle_lock` nie może być trzymana przez wywołanie
- Xlib nie jest wątkowo bezpieczny: pętla zdarzeń na wątku wywołującym
- dane eksportowane (`NSApp`) w lite dylibie
- czy sesja ssh na Macu ma GUI (oracle dla okna); wcześniej cand1–4 działały
- dlsym fallback na glibc może związać symbol z semantyką Linuksa
