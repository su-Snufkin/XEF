# XEF — notatka przekazania (stan na 2026-10-13)

Ten plik jest dla następnej sesji. Pełny opis architektury: `docs/ARCHITECTURE.md`.
Specyfikacja projektu (od użytkownika): szybki translator AArch64 → x86-64, user-mode Linux;
wydajność jest priorytetem zaraz po poprawności. Użytkownik akceptuje każdy plan, a celem
jest „rozwijaj XEF dopóki nie skończą się tokeny”.

**Zasady repo:** commity BEZ stopki „Co-Authored-By: Claude”; autor zawsze `su-Snufkin <341201482+su-Snufkin@users.noreply.github.com>` (ustawione w `git config` repo; nie podawaj `-c user.email`).
Remote: `git@github.com:su-Snufkin/XEF.git`; od 2026-10-13 praca bezpośrednio na `main` (`git push origin main`), bez PR-ów bez prośby.

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
- `XEF_CHECK_NZCV=1` — szybka klasyfikacja NZCV w lookahead (`quick_flags`, translate.cpp) porównywana z
  translatorem przy każdym bloku; uruchom z nią fuzzer i duże programy po zmianach w dekoderze.
- `XEF_STRICT_FLAGS=1` — nie zakładaj, że NZCV jest martwe przy BL/BLR/RET (AAPCS64) i BR (cele: wejścia funkcji, tablice skoków, computed goto; runtime ostrzega, gdy cel BR czyta NZCV jako pierwsze); fuzzer go ustawia.

## Pomiar wydajności (2026-10-13)
- Czas ścienny jest zaszumiony (turbo, rdzenie P/E): do A/B używaj `build/pstat -r N cmd` (tools/pstat.c:
  cycles:u / instructions:u / branch-miss przez perf_event_open, bez perf; `cc -O2 -o build/pstat tools/pstat.c`).
- Regiony tier 2 tworzą się w zależności od próbkowania, więc wyniki z tier 2 bywają bimodalne
  (`calls`); jakość samego kodu porównuj z `--no-tier2`.
- `--profile` pokazuje tier bloku i zapisuje `/tmp/xef-hotN.counts`; `tools/annotate_hot.py` daje
  zdezasemblowany kod gorących bloków z rozkładem próbek na instrukcje hosta.
- `XEF_REGSTATS=1 --profile`: dostępy do rejestrów gościa ważone próbkami (wybór mapowania).
- Python: `build/xef -L .tools/rootfs-arm64 /usr/bin/python3 /tmp/bench.py` (skrypt w rootfs/tmp).
- **Czas translacji** liczy się w realnych programach: start Pythona z importem ~70 modułów to ~45%
  czasu w translatorze, benchmark shaderów GLES (`bench/micro/gles_shader.c`, llvmpipe) ~55%.
  `--stats` podaje `translation time`; fazy najlepiej mierzyć tymczasowymi licznikami rdtsc
  (dekodowanie / lookahead NZCV / analyze / emisja / zależności) i `build/pstat` (instructions:u).
- `tools/codecmp.py XEF_A XEF_B -- prog args`: czy dwie wersje XEF generują ten sam kod hosta
  (bez ASLR, `--dump-code`, adresy helperów i rel32 ignorowane). Każda zmiana translatora, która
  ma nie zmieniać kodu, powinna przejść ten test (Python z `PYTHONHASHSEED=0`; JIT-y gościa i
  wątki są niedeterministyczne).

## Wnioski z sesji 2026-10-13 (co pomogło, co nie)
- Pomogło: prefetch z PRFM (zstd -12%), NZCV martwe przy BR + krótsze RET/IBTC (Python -12%, calls -30%),
  mapowanie rejestrów wg kompilatora (clang: x8-x12), dokładny lookahead NZCV przez pętle, natywne
  AES/PMULL/SHA (TLS), RADDHN (simd 7x), fuzja tst/test, flagi liczone przy konsumencie.
- Nie pomogło (wycofane): inline cache dla BR/BLR — miejsca `br` w interpreterach (CPython) są
  megamorficzne, IC dokładał ~5% cykli; `calls` (4 cele) też wolniejsze.
- FMAXNM/FMINNM(P/V) natywnie, z dokładną obsługą sygnalizującego NaN (propagowany, wyciszony; najpierw operand 1).

## Wnioski z sesji 2026-10-13 (2): szybkość translacji, regresja FMAXNM
- Lookahead NZCV: `mincore` przy każdej zmianie strony kosztował więcej niż dekodowanie (cache
  stron per wątek, unieważniany przez `g_cache.epoch`); `quick_flags` obejmuje teraz hinty PAC/BTI,
  load/store we wszystkich trybach adresowania, BR/BLR, logiczne/bitfield/EXTR/extended/mnożenia/
  MRS (sprawdzane przeciw `slow_flags` na milionach losowych kodowań). Zakresy peek są logowane
  per prosty odcinek i tylko dla odpowiedzi „martwe” (odpowiedź „żywe” nie zależy od kodu).
- Zależności unieważnień: blok łańcucha rejestrował się raz na każdego późniejszego członka
  (kwadratowo); teraz jeden scalony zbiór zakresów; indeks to tablica open addressing + pula węzłów.
- `analyze()`: kandydaci składania adresów wyznaczani w przebiegach liveness, remat tylko po
  producentach flag, przebiegi bez szans na dopasowanie pomijane. `evacuate_guest`/`evacuate_vreg`
  chodzą po liście żywych wartości. Wszystko bajtowo identyczne (tools/codecmp.py).
- Błąd: mapa host-PC→gość dla członków łańcucha i regionów tier 2 miała przesunięcia od początku
  wspólnego asemblera — SIGSEGV gościa w takim bloku zabijał XEF (t_sigsegv_chain).
- Regresja z 0a08d54: FMAXNM/FMINNM(P) poszły do helpera C (simd 3,5 s zamiast 0,23 s, klatki
  GLES 5×). Teraz natywnie i dokładnie dla sygnalizującego NaN; poprawka sNaN jest omijana skokiem
  (`cmpunord` + `ptest`), gdy żadna linia nie jest NaN, a flagi gościa są martwe/tanie do odtworzenia.
  Sprawdzaj `--stats` („vector ops via C helper”) na benchmarkach po zmianach w codegen_t1_vec.
- Znane (istniało wcześniej): `XEF_NO_AVX=1` — t_crypto, t_simd_conv, t_string, t_threads różnią
  się od qemu (ścieżki SSE bez AVX nie są pokryte testami poza fuzzerem).

## Następne kroki (priorytet)
0. Przepuścić więcej programów przez `XEF_VERIFY=1` (testy stdlib Pythona, aplikacje GUI) i naprawić
   znalezione bloki; testy Pythona (w tym asyncio, ssl) przechodzą po naprawie slotów spill
   i dostarczania sygnałów (test_socket: tylko VSOCK — środowisko).
1. Wydajność gier: przypinanie rejestrów V do XMM w regionach tier 2 (shadery llvmpipe to gorące
   pętle NEON), mniej przeładowań stałych wektorowych, regiony obejmujące BL.
   Odroczone zapisy rejestrów V (dziś VSet przed każdym dostępem do pamięci jest zachowywany dla
   precyzji SIGSEGV): wymaga zapisu w mapie PC, w którym XMM/slocie jest bieżąca wartość V.
   Pomiar zysku utrudnia szum maszyny (glmark2 ±15%); mierzyć CPU-time przy LP_NUM_THREADS=1.
2. FP16 arytmetyka (HWCAP FPHP/ASIMDHP), rzadsze operacje NEON wciąż w helperze (`--stats`):
   FRECPE/FRSQRTE (dokładnie jak ARM: tabela), nasycające zwężenia (SQXTN/UQXTN/SQSHRUN...),
   UADDLP/UADALP, UABA/UABAL, SRHADD/SHADD/UHSUB, URSHR/SRSHR, FMAXV/FMINV, CRC32 (helper C!).
2a. Regiony tier 2 rzadko powstają w kodzie pełnym wywołań (CPython: „region failed”/„demoted”);
   tier 1 dominuje w realnych programach. Pomysły: superbloki przez warunkowe skoki (fallthrough
   bez jmp), układ bloków w regionach (fallthrough zamiast jmp do następnego bloku), DSE zapisów
   rejestrów gościa między blokami (wymaga rozluźnienia precyzji stanu przy SIGSEGV dla martwych rejestrów).
3. Zwalnianie kodu (cache rośnie bez końca: inwalidacja tylko odpina bloki), epoki dla wątków.
4. Trwały cache AOT, thunki bibliotek.

## Pułapki, na które już wpadliśmy
- seccomp gościa (filtry BPF z numerami AArch64) nie może trafić na hosta — zabijałby syscalle XEF:
  `seccomp()` = ENOSYS, `PR_SET/GET_SECCOMP` = EINVAL (jądro bez seccomp, jak qemu-user). Udawanie
  sukcesu bez egzekwowania psuje Firefoksa (chroot + broker przez SIGSYS).
- `/proc/self/task` pokazuje tylko wątki gościa (rejestr TID w thread.cpp): Firefox sygnalizował każdy
  wątek z listy, łącznie z wątkiem kompilatora tier 2, i czekał na odpowiedź.
- Wywołanie helpera C (`emit_call_c`) niszczy rejestry tymczasowe: wartości żywe po wywołaniu, także
  jego argumenty, muszą zostać wyrzucone przed nim (adres IC IVAU używany dalej -> Firefox flushował
  od adresu 0 całą przestrzeń). Weryfikator pomija bloki z helperami, test: t_icflush.
- `IC IVAU`/munmap/mprotect na zakresach bez tłumaczeń nie biorą blokady (bitmapa `mark_code`, 64 KiB):
  tłumacz zaznacza strony PRZED sprawdzeniem epoki, unieważniający podbija epokę PRZED odczytem bitmapy.
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
