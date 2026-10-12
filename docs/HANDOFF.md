# XEF — notatka przekazania (stan na 2026-10-12)

Ten plik jest dla następnej sesji. Pełny opis architektury: `docs/ARCHITECTURE.md`.
Specyfikacja projektu (od użytkownika): szybki translator AArch64 → x86-64, user-mode Linux;
wydajność jest priorytetem zaraz po poprawności. Użytkownik akceptuje każdy plan, a celem
jest „rozwijaj XEF dopóki nie skończą się tokeny”.

**Zasady repo:** commity BEZ stopki „Co-Authored-By: Claude”; autor zawsze `su-Snufkin <341201482+su-Snufkin@users.noreply.github.com>` (ustawione w `git config` repo; nie podawaj `-c user.email`).
Remote: `git@github.com:su-Snufkin/XEF.git`; bieżąca praca na gałęzi `claude/upbeat-wright-ausggy` (`git push -u origin claude/upbeat-wright-ausggy`), bez PR-ów bez prośby.

## Szybki start (nowa maszyna / cloud)
```sh
tools/setup.sh                       # cmake/ninja (venv), sysroot arm64, qemu-user, źródła benchmarków
export PATH=$PWD/.tools/venv/bin:$PATH
cmake -S . -B build -G Ninja -DCMAKE_CXX_COMPILER=clang++ && ninja -C build
cmake -S . -B build-dbg -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_COMPILER=clang++ && ninja -C build-dbg
tests/guest/run.sh                   # programy C/C++ vs qemu (72/72)
tests/rootfs/run.sh                  # ścieżki -L (symlinki wewnątrz rootfs)
tests/gui/run.sh                     # shimy --host-gl (bez serwera X)
tools/build_thunks.sh                # shimy gościa dla --host-gl (libGL/libEGL/libvulkan)
(cd tests/diff && python3 fuzz.py -n 3000 --class all --seed 1)   # fuzzer instrukcji vs qemu
bench/build.sh && bench/run.py       # benchmarki -> docs/benchmarks.md
```
Uruchamianie: `build/xef [-L sysroot] prog args` (dla binarek dynamicznych `-L .tools/sysroot-aarch64`).
Diagnostyka: `--stats`, `--profile`, `--dump-ir`, `--dump-code`, `-v`, `--no-tier2`,
`--tier2-threshold N`. Do porównań wydajności `tools/ab.py binA binB -- args` (maszyna jest
zaszumiona, więc licz się z dużą wariancją i używaj minimum z wielu przebiegów).

## Co działa
- Loader ELF (static, static-pie, dynamic przez ld-linux z rootfs), skrypty `#!` także jako program startowy.
- Syscalle: generic → x86-64 z konwersjami; ścieżki absolutne przekierowywane do rootfs (także w
  passthrough: statx, mkdirat, renameat, xattr, chdir…; `getcwd` zdejmuje prefiks rootfs).
- Frontend: int/LSE (także A/R), LDXP/STXP/CASP, NEON/FP, AES/SHA1/SHA256/PMULL/CRC32 (HWCAP ogłasza
  je + ATOMICS). Brak: FP16 arytmetyka (FPHP/ASIMDHP), SVE.
- Tier 1/Tier 2 jak wcześniej; wiele operacji NEON natywnie (patrz `--stats` → "vector ops via C helper").
- Sygnały: asynchroniczne (TF single-step) i **synchroniczne SIGSEGV/SIGBUS** do handlerów gościa
  (mapa host-PC→guest-PC per blok w `CodeCache::set_pcmap`, rejestry z mapowania bloku/regionu).
- **Inwalidacja kodu**: IC IVAU, munmap/mmap FIXED/mprotect/mremap; zależności bloków (ciało + lookahead
  flag) w indeksie stron; regiony tier 2 zabijane przez przekierowanie wewnętrznych skoków (atomowo).
- Wątki, fork/vfork, execve; przepełnienie stosu JIT (głęboka rekurencja) obsługiwane.
- **GUI / gry 3D** (docs/GUI.md): X11, GTK3, Qt, Mesa llvmpipe (GL 4.5), glmark2, Neverball, ETR,
  OpenArena, Minetest, SuperTuxKart, Warzone 2100, TORCS, Trigger Rally, Red Eclipse, Scorched3D,
  MegaGlest, Blender 4.0, Godot 3.5, Stellarium, WebKitGTK (WebGL), vkcube/vkmark.
- **`--host-gl`** (thunki): GL/GLX/EGL/GLES/Vulkan gościa → natywne biblioteki hosta (src/thunks,
  thunks/, tools/gen_glthunks.py). Wywołania zwrotne host→gość przez `guest_call` (hlt #0x5847).
- Aplikacje: LibreOffice Writer, Krita, Inkscape, OpenSCAD, mpv, Blender, Godot, Stellarium (docs/GUI.md).
  `XEF_PROFILE_AT=N` + `--profile` daje raport po N s (opcje XEF są przekazywane przez execve).
- Python 3.12 z rootfs przechodzi testy stdlib (pakiet `libpython3.12-testsuite`; uruchamiaj
  `build/xef -L R /usr/bin/python3 -m test ...` — ścieżką gościa, inaczej sys.prefix wskazuje hosta).

## Narzędzia
- `tools/mkrootfs.sh [pkg…]` — rootfs arm64 z Ubuntu noble (z zależnościami), `tools/guishot.sh` —
  uruchom program GUI i zrób zrzut (Xvfb `:1`). Domyślne env dla GUI: `LIBGL_ALWAYS_SOFTWARE=1
  SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null`.
- `--trace` (bez linkowania, ślad ostatnich bloków przy skoku w niezamapowany adres), `--profile`
  (bloki + czas poza JIT wg funkcji/bibliotek), `--stats` (lista operacji wektorowych przez helper C).
- Sieć w chmurze: deb.debian.org zablokowany → `tools/setup.sh` używa Ubuntu ports/archive.
- **Szukanie błędów translacji**: uruchom duży program/test (np. testy stdlib Pythona), a gdy wynik
  różni się od qemu: `--max-block 1 --no-tier2` (czy to interakcja w bloku?), potem bisekcja zakresu
  adresów z `XEF_SPLIT=lo-hi` (bloki z tego zakresu po jednej instrukcji) i `setarch x86_64 -R`
  (stałe adresy bibliotek) — skrypt w stylu `/tmp/bisectg.sh` z historii; znaleziony blok odtwórz
  w asm jako test w tests/guest/. Tak znalezione: dzielenie przez stałą 64-bit (pożyczony rejestr),
  cset po remat flag, zwolnienie operandów flag w terminatorze.
- **`XEF_VERIFY=lo-hi`** (src/runtime/verify.cpp): bloki z zakresu najpierw w interpreterze IR
  (skalarne i NEON/FP przez `vec_ref`; atomiki/helpery/rejestry systemowe pomijane; tier 2 wyłączony), potem JIT bez linkowania; raportuje różnice
  rejestrów/NZCV/pc/zapisów. Najszybsza droga do błędnego bloku — tak znaleziony błąd slotów spill
  (X25519/TLS). `XEF_SPLIT` przyjmuje listę zakresów (`0-a,b-7fffffffffff` = dziel wszystko poza [a,b)).
- `XEF_STRICT_FLAGS=1` — nie zakładaj, że NZCV jest martwe przy BL/BLR/RET (AAPCS64); fuzzer go ustawia.

## Następne kroki (priorytet)
0. Przepuścić więcej programów przez `XEF_VERIFY=1` (testy stdlib Pythona, aplikacje GUI) i naprawić
   znalezione bloki; testy Pythona (w tym asyncio, ssl) przechodzą po naprawie slotów spill
   i dostarczania sygnałów (test_socket: tylko VSOCK — środowisko).
1. Wydajność gier: przypinanie rejestrów V do XMM w regionach tier 2 (shadery llvmpipe to gorące
   pętle NEON), mniej przeładowań stałych wektorowych, regiony obejmujące BL.
   Odroczone zapisy rejestrów V (dziś VSet przed każdym dostępem do pamięci jest zachowywany dla
   precyzji SIGSEGV): wymaga zapisu w mapie PC, w którym XMM/slocie jest bieżąca wartość V.
   Pomiar zysku utrudnia szum maszyny (glmark2 ±15%); mierzyć CPU-time przy LP_NUM_THREADS=1.
2. FP16 arytmetyka (HWCAP FPHP/ASIMDHP), rzadsze operacje NEON wciąż w helperze (`--stats`).
3. Zwalnianie kodu (cache rośnie bez końca: inwalidacja tylko odpina bloki), epoki dla wątków.
4. Trwały cache AOT, thunki bibliotek.

## Pułapki, na które już wpadliśmy
- Remat flag czyta operandy producenta flag: zapis rejestru docelowego (select/adc) i zwalnianie
  rejestrów w terminatorze muszą nastąpić PO `need_flags`/z zachowaniem tych wartości.
- `nzcv_live_at` używa wspólnego `scratch` — wskaźniki do jego instrukcji są nieważne po rekurencji.
- Pożyczenie zmapowanego rejestru gościa (`alloc_temp` bez wolnych tymczasowych) musi przepiąć wartości
  czytające ten rejestr (także nietknięte GetReg) na zapisaną kopię w CpuState.
- Wewnętrzne fd XEF (pipe tier 2) są ≥1000 i chronione przed close/close_range/dup3 gościa — dziecko po
  fork zamykające „wszystko” inaczej podmieniało je na pliki gościa.
- Odzyskiwanie slotów spill musi odbudować mapę z żywych wartości: martwa wartość może mieć „swój” slot
  zajęty już przez żywą (zepsute TLS/ECDHE).
- Sygnał złapany, gdy wątek jest w runtime (poza kodem JIT), jest tylko oznaczany: dyspozytor musi go
  dostarczyć przed ponownym wejściem do JIT (inaczej połączona gorąca pętla kręci się w nieskończoność).
- FPCR (RMode, FZ) jest odwzorowane na MXCSR hosta przy MSR FPCR i sigreturn (fesetround, CGAL).
- `pkill -f build/xef` zabija też powłokę, której linia poleceń to zawiera — używaj `pkill -x xef`.
- Gdy GUI nagle „nie ma X11” (SDL: x11 not available), sprawdź czy Xvfb :1 żyje (`xdpyinfo`).
- Próbkowanie używa sygnału RT 64 (`kSampleSig`), SIGPROF należy do gościa.
- Remat flag w terminatorach nie może używać RAX (cel skoku) — RAX jest przypinany w Exit*Indirect/Ret.
- `CLONE_PARENT_SETTID` musi być zapisany zanim dziecko ruszy (glibc: ptid == ctid).
- `alloc_code()` tylko rezerwuje; drugi alloc przed `commit_code` zwraca ten sam adres.
