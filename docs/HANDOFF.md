# XEF — notatka przekazania (stan na 2026-10-13)

Ten plik jest dla następnej sesji. Pełny opis architektury: `docs/ARCHITECTURE.md`.
Specyfikacja projektu (od użytkownika): szybki translator AArch64 → x86-64, user-mode Linux;
wydajność jest priorytetem zaraz po poprawności. Użytkownik akceptuje każdy plan, a celem
jest „rozwijaj XEF dopóki nie skończą się tokeny”.

**Zasady repo:** commity BEZ stopki „Co-Authored-By”; autor i committer zawsze: `JupiczeQ <74213715+JupiczeQ@users.noreply.github.com>` (bezwzględnie NIGDY `iw134987`!).
Remote: `https://github.com/su-Snufkin/XEF.git`; gałąź robocza: `XEF-OSX` (`git push origin XEF-OSX`). Praca na `XEF-OSX`.

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
- `XEF_NO_AVX=1` przechodzi wszystkie testy (patrz niżej: `xop` bez AVX z `d == s2`).

## Wnioski z sesji 2026-10-14: weryfikacja audytów zewnętrznych (Gemini)
- Ścieżka SSE bez AVX: `Assembler::xop` robi `movaps d, s1`, więc `d == s2 != s1` niszczył drugi
  operand (TBL 1 rej., FCVTZU, UHSUB/SHSUB, SQADD/SQSUB .4S, PCMPGTQ w SMAX/UABD/UABA .2D). Teraz
  asercja w `xop`; uruchamiaj `XEF_NO_AVX=1 tests/guest/run.sh` po zmianach w codegen_t1_vec.
- Kontekst wątku (CpuState+IBTC, stos JIT, IR, sigaltstack) wraca do puli przy `thread_exit`, a wątek
  wraca z `thread_trampoline` przez `longjmp` (glibc zwalnia stos pthread): 30k wątków to było 13 GB RSS.
- Blok kończy się, gdy IR ma < 512 wolnych miejsc (LD3/ST3 element po elemencie: asercja w builderze);
  mapa PC bez duplikatów; `--max-block` ≤ 256.
- UDF/HLT → SIGILL, BRK → SIGTRAP do handlera gościa (bez handlera: fatal jak wcześniej);
  `execve` zachowuje argv[0] (`--argv0`); readlinkat zdejmuje prefiks rootfs; mremap unieważnia nowy
  adres; epoll_pwait przycina maxevents > 4096; STSET/STCLR/STEOR (Rt = XZR) to jeden `lock or/and/xor`.
- Odrzucone tezy (sprawdzone): częściowy zapis V przy fault w LD1 wielorej. (ARM: rejestry UNKNOWN),
  „rozdarty” LDXP bez STXP (ARM nie gwarantuje atomowości bez STXP; kompilatory robią pętlę),
  dest hint w `new_x` nadpisujący umierający operand (operandy są w `xpinned_`), nadpisanie stosu
  JIT w `guest_call` (wpisy RET są walidowane adresem gościa: tylko koszt predykcji).

## Wnioski z sesji 2026-10-14 (2): wydajność z listy „Następne kroki”
- Maszyna w chmurze (Xeon 2.8 GHz, bez perf_event: `build/pstat` nie działa) jest zaszumiona
  ±3–5%; A/B przez `tools/ab.py` z N ≥ 5, wnioski tylko z dużych różnic. Instrukcje translatora
  liczy `valgrind --tool=callgrind --smc-check=all` (build z `-g`: `-DCMAKE_CXX_FLAGS=-g`).
- `tools/setup.sh` / `mkrootfs.sh` potrzebują `bsdtar` (`apt-get install libarchive-tools`);
  base-files z noble-updates ma `/bin -> usr/bin` (fetch_debs.py zachowuje istniejący katalog).
  Rootfs z Pythonem: `tools/mkrootfs.sh python3.12 libpython3.12-stdlib libpython3.12-testsuite`
  (jest tylko `/usr/bin/python3.12`). Benchmark GLES: skompiluj `bench/micro/gles_shader.c` do
  rootfs/tmp i uruchom z `EGL_PLATFORM=surfaceless LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1`.
- Głowa regionu będąca członkiem łańcucha tier 1 była wchodzona przez fall-through w kodzie t1
  (bez linku): pierwsza iteracja pętli shadera llvmpipe w każdym wywołaniu szła w t1 (~25% próbek).
  Teraz go-live zabija człony łańcucha przed głową i czyści IBTC głowy (gles −5%, zstd -6 −4%).
- Regiony z BL (callee poza regionem, transfer wokół wywołania), liczniki wywołań, eksmisja przy
  zbyt częstych (`XEF_T2_CALL_MOVES`); wywołania tylko na cyklu przez głowę (inaczej regiony
  puchły do 48 bloków kodu za wywołaniami i zstd tracił 8%). Pętla z wywołaniem co 8 iteracji −30%,
  co 2 −14%, w każdej iteracji: eksmisja po 16 ms. Przy okazji: `kill_region` indeksował stuby
  w kolejności układu, a skoki w kolejności R — zabity region wznawiał pod złym pc.
- `--profile` podaje próbki wg pliku gościa i zapisuje `/tmp/xef-prof-guest.txt`;
  `tools/prof_syms.py` sumuje je per funkcja (llvm-symbolizer). libc to ~1–2% w Pythonie i GLES
  (thunki memcpy/strlen niewiele by dały).
- Lookahead NZCV: przebiegi od głowy zapamiętane per wątek i epokę (90M → 45M instrukcji przy
  imporcie ~45 modułów, translacja −6%; kod bajtowo ten sam — codecmp wymaga, by obie wersje
  alokowały tak samo, bo host-malloc przesuwa adresy mmap gościa).
- FRECPE/FRSQRTE .2S/.4S/skalar f32 natywnie (dokładnie: FZ/DN/RMode, denormale; 10× w pętli
  vrecpe+vrecps); vec_ref miał błąd: |x| ≥ 2^126 dawało 0 zamiast denormala bez FZ.
- Zdegradowany region blokuje nie próbowane człony (coremark: ~65 regionów → ~25).
- **Trwały cache translacji** (`XEF_AOT=1`, docs/ARCHITECTURE.md): import ~45 modułów Pythona
  0.35 → 0.25 s CPU na ciepło (+~10% na zimno: capture + zapis ~14 MB), benchmark GLES (20 klatek,
  głównie start) 0.86 → 0.55 s. Testy gościa przechodzą na zimno i ciepło, testy stdlib też.
  Pod valgrindem klucz się zmienia (/proc/self/exe to narzędzie valgrinda). Do zrobienia:
  włączyć domyślnie po sprawdzeniu aplikacji GUI; kompaktowanie pliku (duplikaty z równoległych
  procesów; limit 256 MB → od nowa); add_deps to największy koszt ładowania.
- Inlining BL w regionach + RET w regionie (porównanie X30 z adresami powrotu inlinowanych
  wywołań); pętla wołająca 5-instrukcyjny liść w każdej iteracji 1.15 → 0.74 s, calls −5%.
  BLR w regionie (transfer jak BL); koszt wywołania w modelu eksmisji = ruchy + 16.
- FMAXNM/FMINNM: bez NaN 4 instrukcje (max(a,b) & max(b,a)), dokładna sekwencja NaN w zimnym
  kodzie za blokiem (`ColdMinMax`, run_cold): simd −7%, shader GLES −8%. Ten wzorzec (rzadki
  przypadek poza linią) nadaje się też do innych operacji z dużymi poprawkami.
- DSE zapisów rejestrów gościa przez dostępy do pamięci (bariera „now++” dla Load/Store w
  analyze) — eksperyment bez bariery: zstd/coremark/Python bez zysku (zstd nawet gorzej). Nie warto.
- Spekulatywna translacja w tle (cele wyjść nowych bloków) była gorsza 2×: codegen trzyma
  `g_cache.lock`, więc wątek w tle blokuje główny, a ~40% tłumaczonych bloków nigdy nie rusza.
  Warunek wstępny: codegen bez globalnej blokady (bufory kodu per wątek).
- Python stdlib: test_posix (sched_rr_get_interval, fexecve) i test_zipfile
  (test_write_filtered_python_package) padają też na 27f8647 — do naprawy (poprawność).
- Sprawdzone i odrzucone (bez mierzalnego zysku): mapa GCC z X29 zamiast X5 (Ubuntu noble ma
  frame pointery, X29 to 3–8% dostępów), wagi użyć rejestrów wg próbek w regionie, wyłączenie
  łańcuchów (8% mniej bloków, ten sam czas), leniwe zerowanie górnej połowy wyników skalarnych FP
  (w pętli daxpy `vmovq` i tak leży na łańcuchu przez granicę iteracji).
- Translacja nadal ~45–57% startu programów (Python: ~2.7 µs/blok, 60k bloków; callgrind:
  analyze 20%, emit 23%, dekodowanie 20%, lookahead 9%) — bez jednego gorącego punktu.

## Następne kroki (priorytet)
0. Przepuścić więcej programów przez `XEF_VERIFY=1` (testy stdlib Pythona, aplikacje GUI) i naprawić
   znalezione bloki; testy Pythona (w tym asyncio, ssl) przechodzą po naprawie slotów spill
   i dostarczania sygnałów (test_socket: tylko VSOCK — środowisko).
1. Wydajność gier: V są już przypinane (XMM6–15), regiony obejmują BL (callee poza regionem).
   W gorącej pętli shadera t2 ≈ t1: koszt to 25+ rejestrów V na 16 XMM (sloty CpuState/vspill)
   i sama arytmetyka (div/sqrt). Inlining BL i szybkie FMAXNM zrobione.
   Odroczone zapisy rejestrów V (dziś VSet przed każdym dostępem do pamięci jest zachowywany dla
   precyzji SIGSEGV): wymaga zapisu w mapie PC, w którym XMM/slocie jest bieżąca wartość V.
   Pomiar zysku utrudnia szum maszyny (glmark2 ±15%); mierzyć CPU-time przy LP_NUM_THREADS=1.
2. FP16 arytmetyka (HWCAP FPHP/ASIMDHP); w helperze zostały FRECPE/FRSQRTE f64 i operacje
   bez AVX (sprawdzaj `--stats` → „vector ops via C helper”).
2a. Regiony tier 2 rzadko powstają w CPython: głowy kończą się BR (computed goto) / BLR / RET —
   potrzebny BR w regionie (lokalne IBTC celów-członków). DSE zapisów rejestrów gościa między
   blokami (wymaga rozluźnienia precyzji stanu przy SIGSEGV dla martwych rejestrów).
3. Zwalnianie kodu (cache rośnie bez końca: inwalidacja tylko odpina bloki), epoki dla wątków.
4. Cache AOT: jest (opt-in, patrz wyżej); thunki bibliotek (libc ~1–2% w Pythonie/GLES: mało warte).

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

---

## XEF-OSX — stan na 2026-10-15 (Apple Silicon Mach-O / Darwin HLE)

### 1. Ważne zasady środowiska i repozytorium
- **Autor i Committer:** Zawsze wyłącznie `JupiczeQ <74213715+JupiczeQ@users.noreply.github.com>`.
- **Nigdy** nie commitować ani nie pushować z konta `iw134987` ani adresu uczelnianego.
- **Bez stopki** `Co-Authored-By` w commitach.
- **Gałąź:** `XEF-OSX` (`git push origin XEF-OSX`).
- **Zdalny Apple Silicon Mac M1 (macOS 27, 16K pages):**
  - Dostęp przez `ssh mac` (user `kacperwrona`, klucz `~/.ssh/xef_mac`). Adres się zmienia: LAN `192.168.0.208`, ngrok TCP (nie działa
    z chmury: proxy przepuszcza tylko HTTP(S)), tunel Cloudflare: `ProxyCommand cloudflared access ssh --hostname <x>.trycloudflare.com`
    (`pip install pycloudflared` daje binarkę `cloudflared`). Hasło do sudo: `2137`.
  - Narzędzie do synchronizacji pakietów z Maca do rootfs: `tools/pull_homebrew.sh <nazwa>`.

### 2. Architektura i kluczowe wdrożenia (2026-10-15)
- **Automatyczne wykrywanie Mach-O i darwin-rootfs:**
  - `src/main.cpp`: binarki Mach-O ARM64 (`is_macho_binary`) automatycznie włączają tryb Darwina (`g_is_darwin = true`).
  - Jeśli flaga `-L` nie została podana, a ścieżka do pliku wykonywalnego leży wewnątrz `darwin-rootfs`, rootfs jest wykrywany automatycznie.
  - `tools/pull_homebrew.sh` tworzy wewnątrz rootfs symlinki relatywne (`ln -srfn`), zapobiegając błędnemu rozwiązywaniu ścieżek bezwzględnych `/opt/homebrew/...` na maszynie hosta Linuksa.
- **Pełne dopasowanie struktur ABI & Locale (`_RuneLocale`):**
  - Rozmiar `DarwinRuneLocale`: dokładnie 3208 bajtów (potwierdzone `static_assert`).
  - Pola: magic `"RuneMagA"`, `runetype` pod offsetem 60 (0x3c), `maplower` pod 1084 (0x43c), `mapupper` pod 2108 (0x83c), rozszerzenia zakresów `runetype_ext`, `maplower_ext`, `mapupper_ext`.
  - Eksport symboli: `_DefaultRuneLocale`, `__DefaultRuneLocale`, `_CurrentRuneLocale`, `___CurrentRuneLocale`.
  - Przeliczanie kategorii w `darwin_setlocale`: Darwin `LC_CTYPE` (2) -> Linux `LC_CTYPE` (0), `LC_ALL` (0) -> Linux (6) itd.
  - Zgodność ABI dla regexów BSD: 32-bajtowy `DarwinRegex` i 16-bajtowy `DarwinRegmatch` (64-bitowe `rm_so`/`rm_eo`).
- **Obsługa specyfiki Apple Silicon — Strony Pamięci 16 KB:**
  - Na Apple Silicon Darwin ARM64 natywny rozmiar strony jądra to **16384 (16 KB)**.
  - `src/loader/commpage.cpp`: `COMM_PAGE_USER_PAGE_SHIFT_64` i `COMM_PAGE_KERNEL_PAGE_SHIFT` ustawione na 14 (`1 << 14 == 16384`).
  - `darwin_sysconf(_SC_PAGESIZE)` oraz `darwin_getpagesize()` zwracają 16384.
  - Zmienne systemowe Darwina: `_vm_page_size` = 16384, `_vm_page_shift` = 14.
  - `darwin_mmap`: alokacje anonimowe (`MAP_ANONYMOUS`) bez `MAP_FIXED` są alokowane z buforem i docięciem tak, aby zwracany adres był zawsze wyrównany do 16 KB. Zapobiega to underflowom alokatora pamięci V8 przy odejmowaniu prefiksu/sufiksu (co wcześniej skutkowało błędem `0 == munmap(addr, size)` z ujemną długością `0xffffffffffffd000`).
- **Czas Mach (Mach Time APIs):**
  - `_mach_absolute_time` / `_mach_approximate_time`: monotoniczne nanosekundy (`CLOCK_MONOTONIC`).
  - `_mach_continuous_time` / `_mach_continuous_approximate_time`: czas od startu systemu uwzględniający uśpienie (`CLOCK_BOOTTIME`).
  - `_mach_boottime_usec`: czas rozruchu w mikrosekundach od epoki (`CLOCK_REALTIME - CLOCK_BOOTTIME`).
  - `_mach_timebase_info`: `numer = 1`, `denom = 1`.
  - `_mach_wait_until`: `clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, nullptr)`.
- **Wątki i Pthread ABI:**
  - Shimy `darwin_pthread_attr_*` w `src/loader/darwin_pthread.cpp`.
  - Mapowanie `setdetachstate` i `getdetachstate`:
    - Darwin: `PTHREAD_CREATE_JOINABLE = 1`, `PTHREAD_CREATE_DETACHED = 2`.
    - Linux: `PTHREAD_CREATE_JOINABLE = 0`, `PTHREAD_CREATE_DETACHED = 1`.
  - Stuby ochrony JIT na Apple Silicon: `_pthread_jit_write_protect_np`, `_pthread_jit_write_protect_supported_np`, `_pthread_jit_write_with_callback_np`, `_pthread_jit_write_freeze_callbacks_np`.
- **Propagacja `errno` w HLE Variadic Shims:**
  - W `darwin_hle_dispatch`: variadic shimy (`_fcntl`, `_open`, `_ioctl`) przed wywołaniem zerują `errno` hosta, a po wywołaniu propagują błąd: `if (errno) g_darwin_errno = darwin_errno_from_linux(errno)`.
  - Wyeliminowało to nieskończoną pętlę sprawdzania deskryptorów w libuv (`uv__cloexec`).

### 3. Stan przetestowanych programów (Homebrew & Apple system)
- **Przechodzące testy referencyjne:** `./tests/darwin/macref.sh` przechodzi 14/14 (Objective-C, CoreFoundation, threads, libc, stdio, zlib).
- **Homebrew CLI (100% działające):**
  - `tree`
  - `xz`
  - `zstd`
  - `sqlite3`
  - `ninja`
  - `pcre2grep` (wraz z JIT PCRE2/SLJIT!)
  - `python3` (3.14.4)
  - `lua` (5.5.0)
  - `wget`
  - `openssl` (3.6.4)
  - macOS arm64e `/bin/ls` i `/bin/date`
- **Node.js (v24.1.0):**
  - `node --version` wykonuje się i zwraca `v24.1.0`.
  - Silnik V8 pomyślnie startuje, alokuje stertę i wykonuje kod JS bootstrapu (`pre_execution.js`).
  - Aktualny punkt badania: weryfikacja callbacków V8 C++ API w `setupInspectorHooks` (`RegisterAsyncHookWrapper`).

### 4. OpenGL dla Mach-O (2026-10-15)
- `src/loader/darwin_gl.cpp`: importy `_gl[A-Z]*` z aplikacji arm64 Mach-O są rozwiązywane przez libGL hosta
  (lazy `dlopen`, `glXGetProcAddressARB`) i rejestrowane przez `darwin_hle_register_function`. Hook jest na początku
  `darwin_hle_resolve_symbol` (przed `g_hle_lock` i przed fallbackiem `dlsym` do libc). Aliasy `*VertexArraysAPPLE`,
  maskowanie zwracanych wartości (`glIs*` 8 bitów, `glGetError` itp. 32 bity) w `darwin_gl_fix_ret`.
- Shim okna (symbole tylko XEF): `_xef_win_create/_swap/_poll/_dump` (Xlib + GLX, `glXChooseVisual`, kontekst legacy;
  `_xef_win_dump` zapisuje PPM P6 od góry do dołu, wołać przed swap).
- Test: `tests/darwin/gl_test.sh` (Xvfb na wolnym display, `gltri` x2, SSIM między uruchomieniami, zrzut okna; wpięty w
  `run_tests.sh` jako Test 5). `tests/darwin/gltri` budowany na Macu (`tests/darwin/mac_gl/build.sh`, brak `ld64.lld`
  lokalnie). Referencja z prawdziwego Maca: `tests/darwin/mac_gl/ref.ppm` (SSIM 0,996 względem XEF; różnica to oświetlenie
  Mesa/Apple). `GLTRI_HOLD_MS` trzyma ostatnią klatkę, żeby test zdążył zrobić zrzut okna.
- Ograniczenia: wywołania GL z >8 argumentami całkowitymi (glTexImage3D, glBlitFramebuffer) nie są przepakowywane
  (Apple pakuje stos w naturalnym rozmiarze); GL/Xlib tylko z wątku, który utworzył okno; brak AppKit/CoreGraphics/IOKit
  (GLFW/Cocoa to etapy B i C w `docs/MACOS_3D_PLAN.md`).
- Lokalnie `tests/darwin/run_tests.sh` i `tests/guest/run.sh` nie budują się bez `ld64.lld`/`ld.lld`; prebuilt
  `hello_darwin`, `complex_darwin`, `hello_universal` działają (rc 0).

### 5. Cocoa przez AppKit-lite (2026-10-15)
- `rootfs-src/appkit/` (AppKit.m ~480 LOC, MRC; Cocoa.c, OpenGL.c) + `tools/build_appkit.sh`: własne dyliby arm64 budowane na Macu
  (NSApplication/NSWindow/NSView/NSOpenGLView/NSOpenGLContext/NSOpenGLPixelFormat/NSEvent/NSScreen + stuby), instalowane w
  `darwin-rootfs/System/Library/Frameworks/{AppKit(Versions/C; A->C),Cocoa,OpenGL}.framework`. Wołają płaskie funkcje
  `xef_host_*` (kontrakt: `rootfs-src/appkit/xef_host.h`). Listy selektorów: `cand3_selectors.txt`, `cand1_selectors.txt` (GLFW).
- `src/loader/darwin_appkit_host.cpp`: strona hosta (okno X11 + własny kontekst GLX na okno, zdarzenia X → NSEvent, tabela
  keycode; okno tworzone niemapowane, `show` czeka na MapNotify; okno nigdy nie mapowane (HIDDEN=1) też ma działający GL).
- `tests/darwin/cocoa_gl` (z cand3_cocoa + zrzut PPM klatki 299): ta sama binarka działa na Macu i na XEF; referencja
  `tests/darwin/mac_gl/ref_cocoa.ppm` (SSIM ≥0,95 wymagane w gl_test.sh; wyszło ~1,0). Zdarzenia (klawisze/mysz/resize/close) są
  zaimplementowane, ale nietestowane w czasie działania (aplikacja ich nie dostaje).
- GLFW 3.4 (etap C, 2026-10-15): `tests/darwin/glfw_gl21` i `glfw_gl32` (źródła `tests/darwin/mac_gl/glfw_gl{21,32}.c`, GLFW statycznie na Macu,
  `tests/darwin/mac_gl/build.sh`) działają na Macu i XEF; referencje `ref_glfw21/32.ppm` (SSIM 1,0000, ±1 na 38 bajtach), `HIDDEN=1` działa,
  wydruk faktów (monitors/joystick/nazwy klawiszy) identyczny z Makiem. Nowe dyliby (`tools/build_appkit.sh`): CoreGraphics (jeden ekran ID 1 z hosta,
  jeden tryb 60 Hz, gamma tylko do odczytu, fade/Associate = `// HLE:` no-op), IOKit (pusty IORegistry, IOHIDManager bez urządzeń),
  CoreServices (`UCKeyTranslate`, układ US ANSI), Carbon/HIToolbox (bundle `com.apple.HIToolbox`, TIS), Info.plist `com.apple.opengl` w OpenGL.framework.
  `dlsym` na obrazie OpenGL.framework (CFBundleGetFunctionPointerForName w GLFW) idzie przez most host-GL. Kontrakt hosta rozszerzony o
  `xef_host_gl_set_profile` (profil core 3.2/4.1 -> glXCreateContextAttribsARB), `screen_info`, `window_set_frame/hide`, `pointer/pointer_warp`; zdarzenia
  enter/exit/focus, modyfikatory jako FlagsChanged. `___sincosf_stret`/`___sincos_stret` zwracają HFA w v0/v1 (`darwin_hle_dispatch`, tryby shim -3/-4;
  test `tests/darwin/mac/sincos_stret.c`). Zdarzenia GLFW (klawisze/mysz/scroll/resize/focus) sprawdzone na Xvfb przez XTest.
- Ograniczenia lite: schowek tylko w procesie, brak drag&drop, kursory (kształt/obraz) nie trafiają do X11, `miniaturize` tylko unmap, brak odświeżania z hosta (60 Hz zakładane).
- Logowanie: poziom 1 = flaga `-v` (nie zmienna środowiskowa).

### 6. Node.js 24.1 pod xef-osx (2026-10-16)
- `console.log("hi", 1+1)` → `hi 2`, rc 0, ~0,4 s; `tests/darwin/node_test.sh` (wyjście identyczne z Makiem, `node_expected.txt`).
- Przyczyny (trzy nałożone): (1) **NZCV przez RET**: Apple LLVM outline'uje funkcje zwracające wynik we flagach (V8 `_OUTLINED_FUNCTION_0`:
  `...; cmp; ret`, wołający robi `b.ne`); założenie „flagi martwe przy RET” gubiło `cmp` w callee. Naprawa: `scan_flag_returning_calls()` /
  `ret_keeps_flags()` (translate.cpp), skan `__TEXT,__text` w `link_image`, takie BL/RET nie są inlinowane w tier 2. Objaw: null oddball
  traktowany jako ConsString → SIGSEGV w `Runtime_StringCharCodeAt`. `XEF_STRICT_FLAGS=1` to maskuje. (2) **FJCVTZS** (V8 przy każdej konwersji
  double→int32) jako helper z NZCV=0b0Z00. (3) **kqueue** było stubem: teraz warstwa na epoll (ident, data/FIONREAD, EV_EOF, EVFILT_USER przez eventfd).
- Testy: `tests/darwin/mac/fjcvtzs.c`, `flagret.c` (macref 18/18). Pomoc diagnostyczna: `XEF_DBG_SEGV*`, `XEF_DBG_SEGV_FRAMES` (łańcuch ramek V8),
  `XEF_DBG_PC=lo-hi` + `--trace --max-block 1`.
- Do zrobienia: `child_process.execSync` abortuje w libuv (spawn); kqueue bez VNODE/PROC/SIGNAL/TIMER (fs.watch, uv_signal); skan flag widzi tylko
  bezpośrednie BL (nie `b`/`blr`); zmiana translatora nie przeszła `fuzz.py` ani `tests/guest` (brak qemu/ld.lld lokalnie) — uruchomić na maszynie z narzędziami.

### 7. OpenMW 0.51 (SDL2 + OSG + MyGUI) przez AppKit-lite (2026-10-16)
- `/Applications/OpenMW.app` z Maca (rsync do `darwin-rootfs/Applications/`) startuje, otwiera okno GL, ładuje Morrowind.esm/BSA,
  odtwarza intro i menu działa. Dane: `openmw.cfg` w `~/Library/Preferences/openmw/` hosta (import przez `openmw-iniimporter` z paczki,
  też pod xef-osx). Uruchamianie: `OPENMW_DISABLE_CRASH_CATCHER=1 build/xef-osx -L darwin-rootfs .../OpenMW.app/Contents/MacOS/openmw`
  (crash catcher OpenMW robi fork+exec debuggera). OpenMW łapie SIGTERM: zabijać `kill -9` (`timeout -s KILL`).
- Loader: dylib osiągnięty przez symlink (`libosgDB.162` -> `libosgDB.3.6.5`) to ten sam obraz (klucz: realpath hosta, jak inode w dyld)
  — wcześniej dwie kopie libosg/libosgDB miały osobne `osgDB::Registry` i pluginy (dds/png) „nie istniały”. `dlsym` na uchwycie z
  `dlopen(NULL)` szuka globalnie (OSG `glGetStringi`). `___fpclassify{d,f,l}` mapują FP_* glibc -> Darwin, `___exp10f`, `_proc_pidpath`,
  `_*_l` ctype. Nierozwiązany symbol DANYCH jest wiązany do adresu thunka (odczyt daje bajty `hlt`/`movz`, np. `0xd44b08c0d2806951`).
- AppKit-lite dla SDL2 (`SDL_cocoa*.m`): stałe notyfikacji, NSAlert (komunikat na stderr, pierwszy przycisk), NSButton,
  NSGraphicsContext/NSBezierPath/NSColorSpace (no-op), metody NSWindow/NSView/NSApplication/NSEvent/NSPasteboard/NSCursor z SDL2,
  `+resolveInstanceMethod:` na NSView/NSWindow/NSApplication: nieznany selektor = no-op zwracający 0, logowany `STUB -[klasa sel]`.
  Nowe dyliby: CoreVideo (CVDisplayLink z wątkiem 60 Hz — SDL czeka na niego przy swap interval), AudioToolbox (+ nazwy CoreAudio/
  AudioUnit; brak urządzeń, OpenAL wyłącza dźwięk), dodatki CoreGraphics/IOKit/HIToolbox/CoreServices,
  `OpenGL.framework/Libraries/libGL.dylib` (SDL dlopen).
- Diagnostyka: fatal `brk` drukuje backtrace gościa; `XEF_GUEST_BT=N[,count]` — od N s każde wywołanie HLE (do `count` na wątek) drukuje
  backtrace gościa (gdzie kręci się zawieszony program); symbolizacja na Macu: `atos -o <obraz> -arch arm64 -l <base> <adresy>`.
- „New Game” (2026-10-16): wisiało na `Loading cell Imperial Prison Ship` — `MWGui::LocalMapBase::setActiveCell` tworzył widgety mapy
  bez końca (RSS +4 MB/s). Po scaleniu poprawki NZCV-przez-RET (sekcja 6) przechodzi: ~70 s ładowania statku, potem gra (AiTravel), RSS stały
  ~760 MB — najpewniej pętla zależała od funkcji zwracającej wynik we flagach. `ret_keeps_flags` skanuje wstecz tylko w zeskanowanym
  `__text` (strona przed `__TEXT` bywa PROT_NONE, a `guest_readable`/mincore tego nie widzi — OpenMW padał w XEF).
- AppKit-lite: widok opuszczający okno (lub zwalniany) przestaje być jego first responderem — SDL2 usuwa i zwalnia `fieldEdit` będąc
  first responderem, a następny `keyDown:` (Enter w intro) / `resignFirstResponder` szedł do zwolnionej pamięci (vtable obiektu OSG jako „klasa”).
- `tests/darwin/macref.sh`: 18/18 po scaleniu z 6b51080; `foundation_file` sporadycznie SIGSEGV (~1/20 przebiegów, także na samym 6b51080) — do zbadania.

### 8. Sesja nocna 2026-10-16 (kolejka aplikacji)
Świeży kontener: `darwin-rootfs` = `rsync mac:xef-remote/out/rootfs/` + `tools/setup_darwin_rootfs_data.sh` + `tools/pull_homebrew.sh <app>`.
Bez Maca: `tools/fetch_bottle.py [--libcxx] <formuła...>` — butelki arm64 z ghcr.io (zależności z formulae.brew.sh, placeholdery
`@@HOMEBREW_*@@` w load commands/tekstach, linki opt/ i bin/ jak `brew pour`); `--libcxx` kładzie libc++/abi/unwind z butelki llvm do `/usr/lib`.
Na Macu brakuje wielu aplikacji z kolejki (git, curl, jq, rg, fd, go, rust, ...): te bierzemy przez fetch_bottle.py.

Zrobione:
- `foundation_file` flaky (~10%): libdispatch-lite nie wołał `_Block_use_RR2`, więc `Block_copy` nie zatrzymywał przechwyconych obiektów
  ObjC (bloki KVO NSOperation działały na zwolnionej pamięci). Test `block_capture.m`. 0/80 po poprawce.
- Zrzut fatalnego sygnału podaje obraz+offset `lr`.
- `posix_spawn`: był stubem (ignorował file actions, maskę sygnałów, SETSID, CLOEXEC_DEFAULT). Teraz pełna semantyka, błąd exec przez potok,
  `addinherit_np/addchdir_np/addfchdir_np`, gettery. kqueue: `EVFILT_PROC` (NOTE_EXIT/EXITSTATUS, pidfd) i `EVFILT_TIMER` (timerfd).
  Node `child_process` działa (execSync/spawnSync/exec/sygnał). Test `spawn_kqueue.c`.
- argv/envp/apple: łańcuchy rosnąco i ciągiem jak XNU (libuv `uv_set_process_title`; npm padał w `bzero`). Test `argv_layout.c`.
  `npm --version` (11.3.0), `npm init`, `npm install left-pad`, `npm install esbuild` działają (sieć, TLS).
- pthread TSD w tablicy gościa za TPIDRRO_EL0 (768 slotów, klucze od 258 jak na macOS), destruktory przy wyjściu wątku, wartość z `pthread_exit`;
  `pthread_t` gościa = osobny blok w `tsd[0]` (mapowany na wątek hosta: join/detach/kill/threadid/stack), `mach_thread_self` per wątek.
  Go (`esbuild` 0.28, binarka Go) działa: transform i bundle przez node. Test `pthread_tsd.c`.
- FILE gościa = powłoka `struct __sFILE` Darwina (`darwin_stdio.cpp`; makra `getc_unlocked` itd. czytają pola), `%p` jak BSD (`0x0`).
- exec*/execvP przez `process_execve`; `fork/vfork` z handlerami `pthread_atfork` i blokadami XEF (glibc fork); `memset_s`; jedno `environ`.
- LDAP/GSS: uczciwe kody „niedostępne”; `/usr/lib/libcurl.4.dylib` itd. z butelek (`fetch_bottle.py --syslibs`).
- setjmp/longjmp/sigsetjmp jako kod gościa (`emit_setjmp_family`); libproc (`darwin_proc.cpp`); `host_statistics(64)`,
  `host_processor_info`, `host_info`, zegary Mach; termios (`darwin_termios.cpp`: struktura, flagi, c_cc, prędkości, TIOC*, openpty/forkpty);
  tsearch/lfind/qsort_b z callbackami gościa; sysctl KERN_PROC/PROCARGS2/BOOTTIME; `dev_t` Darwina; cmsghdr (SCM_RIGHTS) w sendmsg/recvmsg.
- `tools/ptyrun.py` — programy interaktywne na pty (wpisywanie klawiszy, wynik bez sekwencji escape).
- macref 63/63 (stan po Bun). Dodatkowo: `darwin_fs.cpp` (rodzina `*at` przez nakładkę rootfs względem dirfd, xattr→`user.*`, statfs/statvfs,
  pathconf, mkstemp*, getattrlist, SysV IPC), CommonDigest (`darwin_commoncrypto.cpp`), popen/system przez `/bin/sh` rootfs
  (`fetch_bottle.py --shell`), EVFILT_SIGNAL, timeval z 32-bitowym usec, sem_open, kinfo_proc/PROCARGS2, cmsg/SCM_RIGHTS.
- Rootfs w chmurze: `/bin/sh` = bash z butelki; `/usr/lib/libcurl.4.dylib` itd. (`--syslibs`). Komendy spoza rootfs (np. `ls`, `uname`)
  wykonują się natywnie na hoście (x86-64) i widzą system plików hosta, nie rootfs.

Tabela aplikacji (2026-10-16, Linux x86-64 w chmurze):
| aplikacja | status | uwagi |
|---|---|---|
| node 24.1 | działa | console/fs/http/crypto/worker_threads/child_process; npm 11.3 (`init`, `install` z sieci, esbuild) |
| esbuild (Go) | działa | binarka Go uruchamiana przez node |
| git 2.56 | działa | init/add/commit/diff/log/gc, `clone` https (libcurl z butelki) |
| curl 8.23 | działa | https z weryfikacją OpenSSL; LDAP/GSS niedostępne (błąd 7 / fallback) |
| jq, ripgrep, fd, fzf | działa | realne użycie: wyszukiwanie/liczniki rg, fd po typie i rozszerzeniu, `fzf -f`, filtry jq (zgodne z narzędziami hosta) |
| vim 9.2 | działa | ex-mode i interaktywnie (pty) |
| neovim 0.12 | działa | LuaJIT (`--headless`, lua), edycja interaktywna na pty (`tools/ptyrun.py`) |
| tmux 3.6 | działa | sesja, powłoka, wyjście |
| htop 3.4 | działa | lista procesów, uptime; CPU% w 1. klatce zawyżone (próbka startowa htop) |
| ssh 10.6 | działa | połączenie z Makiem (klucz, ProxyCommand cloudflared), `scp` w obie strony bajt w bajt |
| rsync 3.5 | działa | lokalna kopia i `-ai --delete` (nakładka rootfs przy `*at` względem dirfd) |
| redis 8.10 | działa | server + cli (set/get/incr/lists, shutdown) |
| nginx 1.31 | działa | statyczne pliki, return, 404, 2 workery, zamknięcie SIGTERM |
| numpy 2.5 (+OpenBLAS) | działa | algebra liniowa (inv/slogdet/eigvalsh/svd), FFT, sort/unique, einsum; wyniki zgodne z Makiem co do wersji bibliotek (Mac ma numpy 2.4.4) |
| python 3.14 | działa | ssl, sqlite3, asyncio (TCP), hashlib, decimal, lzma, multiprocessing, subprocess, ctypes, https |
| PostgreSQL 14 | działa | initdb, postgres, psql (socket uniksowy i TCP), pg_ctl stop |
| ruby 4.0 | działa | json, digest, Thread, fork, Open3, TCP, Fiddle, Net::HTTP https |
| php 8.5 | działa | PDO sqlite, intl, preg, mb, https, stream sockets, shell_exec |
| cmake 4.3 + ninja | działa | konfiguracja i budowa projektu C z clang + ld64.lld (`SDKROOT=/opt/xef-sdk`, `tests/darwin/cmake_test.sh`); brak `vm_stat` (narzędzie Apple) tylko w logu |
| ffmpeg 8.1 | działa | x264+AAC bitexact identyczne z Makiem (`tests/darwin/ffmpeg_test.sh`), VP9/Opus |
| ImageMagick 7 | działa | `magick` generacja, resize, identify, PNG/JPEG/WebP |
| go 1.27 | działa | `go version`, `go build` (zimny cache, compile/asm/link jako procesy potomne), binarka = wynik z Maca (`tests/darwin/go_test.sh`) |
| rustc 1.99 / cargo | działa | `cargo new`, `cargo build --release`, linkowanie `ld64.lld` (butelka lld) ze stub-SDK `tools/make_darwin_sdk.py`; binarka działa też natywnie na Macu (`tests/darwin/rust_test.sh`) |
| ld64.lld 23 | działa | linker Mach-O pod xef-osx |
| clang 23 (butelka llvm) | działa (bez nagłówków SDK) | `clang -isysroot /opt/xef-sdk --ld-path=/opt/homebrew/bin/ld64.lld`: program C bez `#include` kompiluje się i linkuje, binarka działa też na Macu (`tests/darwin/clang_test.sh`); `#include <stdio.h>` wymaga nagłówków SDK Apple |
| Deno 2.9 | działa | TypeScript (swc), WebCrypto, pliki, Deno.serve + fetch, Deno.Command (`tests/darwin/deno_test.sh`) |
| Bun 1.4 | działa | TypeScript, Bun.write/file, Bun.serve + fetch, spawnSync, node:fs (`tests/darwin/bun_test.sh`) |
| OpenJDK 27 | działa | `java -version`, `javac`, programy z wątkami/strumieniami, JIT C1/C2 (`tests/darwin/java_test.sh`) |

Go i Rust (2026-10-16, cd.):
- Go: lstat/O_NOFOLLOW/O_EXCL/mkdir/rmdir na samym linku (GOROOT), ścieżka hosta w rootfs → ścieżka gościa (argv[0]),
  ścisłe NZCV dla binarek Go (`__go_buildinfo`: kompilator Go zostawia flagi żywe przez BR tablic skoków),
  SHA256H/H2 w miejscu abef (brak xmm w tier 2), `kevent`/`fcntl` zwracają 64-bitowe -1 (Go porównuje 64 bity — netpoll padał),
  uchwyt `pthread_t` zna wątek hosta zanim gość go rozda (pthread_kill(0) przy wywłaszczaniu Go zabijał `go build`).
- Rust: rejestr stref malloc (jemalloc), `pthread_attr_setstacksize` respektowany, clonefile/fclonefileat, setattrlist/fsetattrlist,
  mmap/vm_allocate w całych stronach 16K (wcześniej munmap gościa zdejmował pamięć hosta obok — crash w ld.so),
  vm_allocate bez ANYWHERE nie nadpisuje mapowania (KERN_NO_SPACE), kopia argumentów stosowych HLE nie czyta za końcem stosu.
- Linkowanie bez SDK Apple: `tools/make_darwin_sdk.py` generuje `.tbd` (libSystem = nazwy HLE + funkcje libc hosta + obrazy
  implicit) w `darwin-rootfs/opt/xef-sdk`; `SDKROOT=/opt/xef-sdk`, `-C linker=/opt/homebrew/bin/ld64.lld -C linker-flavor=ld64.lld`.
  cargo: `PATH=/opt/homebrew/bin:...` (inaczej znajdzie rustc hosta), `CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER`, `RUSTFLAGS` jak w teście.
- Java: `<fenv.h>` arm64 (`darwin_fenv.cpp`; fenv_t 16 B — glibc nadpisywał zapisane x23/x24 HotSpota), `thread_info`
  (BASIC/IDENTIFIER, zapis tylko rozmiaru flavora — wcześniej memset count*4 zerował rekord ramki), porty wyjątków Mach,
  `__clear_cache` → unieważnienie translacji (JIT), dlsym nie znajduje funkcji tylko-glibc (np. pthread_condattr_setclock),
  pipe2/dup3 z flagami Darwina, `guest_readable` czyta stronę (mincore akceptował PROT_NONE __PAGEZERO).
- Deno: kopie deskryptora kqueue (F_DUPFD_CLOEXEC w mio) = ta sama kolejka (kcmp / eventfd w fdinfo),
  pthread_get/setschedparam z politykami Darwina, oraz translator: NZCV żywe przez BL do helperów outlinera
  (przepuszczających flagi albo czytających je na wejściu: `cmp ; bl OUTLINED(csel …)`) — hashbrown liczył zły
  growth_left i swc psuł stertę. Diagnostyka: `XEF_DBG_FLAGS=1 --trace --max-block 1` wypisuje BL/RET, po których
  flagi uznano za martwe, a cel je czyta.
- Bun: `__getdirentries64`, `mach_vm_map` z maską wyrównania (sterta struktur JSC, 4 GB), `vm_inherit`, `thread_switch`,
  `mach_port_construct/destruct` + kqueue `EVFILT_MACHPORT` (eventfd portu czytelny, gdy czeka wiadomość), `kevent64`
  (IMMEDIATE, ERROR_EVENTS), wszystkie `name$NOCANCEL` → implementacja `name` (wcześniej host z flagami Darwina),
  SIGTRAP z adresem w siginfo.
- libdispatch-lite: stan `dispatch_apply` na stercie z refcountem (spóźniony worker pisał w ramkę stosu wołającego;
  `foundation_threads` padał ~1/5, flaky także przed sesją). Przebudowa: `tools/build_libdispatch_lite.sh`.
- Odłożone: clang/gcc z `#include <stdio.h>` wymaga nagłówków SDK Apple — nie kopiujemy ich; do decyzji użytkownika.
  gcc-15 (Homebrew) potrzebuje dodatkowo systemowego `as`/`ld` z Command Line Tools.
- Testy gościa Linux (`tests/guest`): 78 ok / 42 fail — identycznie na buildzie sprzed sesji (ld.so/glibc z Debiana trixie w kontenerze),
  nie regresja tej gałęzi.

macOS GUI / 3D & Metal (2026-10-16):
- AppKit-lite (`rootfs-src/appkit/AppKit.m`, `src/loader/darwin_appkit_host.cpp`):
  - Poprawiona synchronizacja współrzędnych kursora myszy przy zmianie rozmiaru okna (`XEF_EV_RESIZE` zapytuje X11 o geometrię przez `XTranslateCoordinates` i aktualizuje `origin.y`, wysyłając `windowDidMove:` oraz `windowDidResize:`).
  - Wsparcie dla EWMH `_NET_WM_STATE_FULLSCREEN` i pełna obsługa `toggleFullScreen:` z `NSWindowStyleMaskFullScreen` i notyfikacjami przejścia.
  - Opróżnianie `NSRunLoop` wewnątrz `-[NSApplication nextEventMatchingMask:...]` dla natychmiastowego wykonywania bloków wątku głównego.
  - Dodane metody `setOneShot:`, `registerForDraggedTypes:`, `unregisterDraggedTypes`, `setMouseConfinementRect:`, `addChildWindow:ordered:`, `removeChildWindow:`.
  - Dodana kategoria `NSAppleEventManager (AppKitLite)` dla obsługi event handlerów Apple Event.
- QuartzCore.framework (`rootfs-src/appkit/QuartzCore.m`):
  - Pełna implementacja `CALayer`, `CAMetalLayer` i `CAMetalDrawable`.
  - Funkcja `CACurrentMediaTime(void)` oraz funkcje macierzy 3D `CATransform3D` (`CATransform3DIdentity`, `CATransform3DMakeTranslation`, `CATransform3DMakeScale`, `CATransform3DMakeRotation`, `CATransform3DConcat`, itp.).
  - Klasy animacji (`CAAnimation`, `CAPropertyAnimation`, `CABasicAnimation`, `CAKeyframeAnimation`, `CATransition`, `CAMediaTimingFunction`, `CADisplayLink`) i warstwy pochodne (`CAGradientLayer`, `CAShapeLayer`, `CATextLayer`, `CAOpenGLLayer`).
  - Podpięcie `[CAMetalDrawable present]` pod wymianę buforów okna X11 (`xef_host_swap`).
- Metal.framework (`rootfs-src/appkit/Metal.m`):
  - Kompletna implementacja frameworka Metal w architekturze arm64 Mach-O: `MTLCreateSystemDefaultDevice`, `MTLCopyAllDevices`, `MTLCopyAllDevicesWithObserver`, `MTLRemoveDeviceObserver`.
  - Wszystkie klasy deskryptorów: `MTLRenderPipelineDescriptor`, `MTLRenderPipelineColorAttachmentDescriptor`, `MTLRenderPassDescriptor`, `MTLTextureDescriptor`, `MTLVertexDescriptor`, `MTLDepthStencilDescriptor`, `MTLSamplerDescriptor`, `MTLCompileOptions`.
  - Zasoby i bufory: `XEFMetalBuffer` (`contents`, `storageMode`, `cpuCacheMode`), `XEFMetalTexture` (z buforami pikseli, `XEFMetalTextureStorage` współdzielonym przez `newTextureViewWithPixelFormat:`, oraz pełną obsługą 4- i 6-argumentowego `replaceRegion:` i `getBytes:`), `XEFMetalLibrary`, `XEFMetalFunction`, `XEFMetalRenderPipelineState`, `XEFMetalComputePipelineState`.
  - Kodery i potoki renderujące: `XEFMetalCommandQueue`, `XEFMetalCommandBuffer`, `XEFMetalRenderCommandEncoder` (dekodowanie `MTLVertexDescriptor`, obsługa shaderów MSL z dynamicznym parsowaniem lub wbudowanymi literalami, uniform MVP, fast-path dla 2D blit `FullscreenVert`/`BlitFrom2D`, rasteryzator trójkątów/linii/punktów z interpolacją perspektywiczną, scissor test i alpha blending), `XEFMetalComputeCommandEncoder`, `XEFMetalBlitCommandEncoder`.
  - Prezentacja pikseli na hoście: `xef_host_present_pixels` w `src/loader/darwin_appkit_host.cpp` rysujący teksturę klatki na buforze okna X11 z odwróceniem osi Y i podmianą buforów (`CAMetalDrawable present`).
  - Optymalizacja wydajności rasteryzatora Metal i prezentacji na hoście:
    - Wyeliminowano dynamiczny dispatch `objc_msgSend` w pętli pikseli (spadek z ~1 mln wywołań na klatkę do 0; czas w `libobjc.A.dylib` spadł z 18% do 2.3%).
    - Wdrożono `xef_rasterize_triangle_fast` z inkrementalnymi równaniami krawędzi (zaledwie 2 dodawania na piksel), bezpośrednim próbkowaniem tekstur i szybkim stałoprzecinkowym blendingiem alfa (`xef_blend_over_bgra`, `xef_blend_premul_bgra`). Udział regionów Tier-2 JIT wzrósł z 41% do 85.5%.
    - `xef_host_present_pixels` używa `glTexSubImage2D` przy stałym rozmiarze, unikając reallokacji tekstury sterownika GPU co klatkę.
    - `xef_host_window_get_geometry` natychmiast zwraca zapamiętaną geometrię okna `hw`, eliminując po 2 blokujące zapytania X11 (`XTranslateCoordinates` i `XGetGeometry`) na każde wywołanie `[window frame]`.
    - Rezultat: eliminacja przycięć launchera i interfejsu ImGui w `orbit64` — czas renderowania klatki GUI spadł z ~800 ms do ~1.4 ms.
  - Klasa bazowa `XEFMetalObject` z dynamicznym stubowaniem `resolveInstanceMethod:` dla bezpiecznego fallbacku niezaimplementowanych metod.
- Weryfikacja:
  - `cand4_metal` (`tests/darwin/cand4_metal`): program testowy Metal 3D z potokiem wierzchołków MSL i renderpass offscreen przechodzi 300 klatek w teście automatycznym `tests/darwin/metal_test.sh` (`PASS metal_test`).
  - Emulator Nintendo 64 `orbit64` (SDL3 + Metal GPU): pomyślna inicjalizacja urządzenia Metal (`XEFMetalDevice`), eliminacja czarnego ekranu poprzez implementację warstw `NSView` (`+layerClass`, `-makeBackingLayer`, `setWantsLayer:YES`), podpięcie `CAMetalDrawable` i transfer pikseli swapchaina SDL3. Pełny interfejs GUI, okładki, przyciski i emulacja gry (`Mario Kart 64`) działają płynnie i stabilnie w 60 FPS (11.3 ms/klatkę).
  - Wszystkie testy regresji (`tests/darwin/gl_test.sh`: gltri, gltri_core, cocoa_gl, glfw_gl21, glfw_gl32 oraz `tests/darwin/metal_test.sh`) przechodzą w 100% (PASS gl_test, PASS metal_test).

Implementacja MetalVK (Natywny backend Vulkan dla Metal) pod XEF-OSX (2026-10-17):
- **Architektura MetalVK dla XEF-OSX** (opis historyczny — ten backend został zastąpiony, patrz sekcja 9):
  - Nowoczesna warstwa akceleracji sprzętowej tłumacząca potok Apple Metal bezpośrednio na Vulkan 1.3 / 1.4 dla Linuksa.
- **Implementacja backendu Vulkan dla Metal (`src/loader/darwin_metal_vk.h`, `src/loader/darwin_metal_vk.cpp`, `src/loader/darwin_metal_vk_spv.h`)**:
  - Dynamiczny loader Vulkan (`dlopen("libvulkan.so.1")`, dynamiczne rozwiązywanie funkcji instancji i urządzenia przez `vkGetInstanceProcAddr`).
  - Wybór i inicjalizacja urządzenia GPU (preferencja dedykowanego GPU `VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU`, np. NVIDIA GeForce RTX 4050, z fallbackiem do zintegrowanego Intel RPL-P).
  - Format mappings: pełne mapowanie formatów pikseli Metal na Vulkan (`MTLPixelFormatBGRA8Unorm` -> `VK_FORMAT_B8G8R8A8_UNORM`, `RGBA8Unorm`, `R8Unorm`, `RG8Unorm`, `RGBA16Float`, `Depth32Float`, itp.).
  - Zarządzanie teksturami: `tex_create`, `tex_update`, `tex_copy`, `tex_readback`, `tex_destroy` z buforami staging i barierami pamięci (`VkImageMemoryBarrier`).
  - Render pass i bufor ramki: render passy z czyszczeniem (`VK_ATTACHMENT_LOAD_OP_CLEAR`) i ładowaniem (`VK_ATTACHMENT_LOAD_OP_LOAD`), obsługa buforów ramki `VkFramebuffer`.
  - Potoki graficzne i shadery: wbudowane shadery SPIR-V vertex i fragment dla operacji 2D/3D i blitów Metal, dynamiczny viewport i scissor, pełne mapowanie operacji i współczynników blendingu alfa (`VkPipelineColorBlendAttachmentState`).
  - Rysowanie i prezentacja: nagrywanie komend rysowania (`vkCmdDraw`, `vkCmdDrawIndexed`), synchronizacja kolejki `VkQueue` i transfer do prezentacji okna.
  - Elastyczny wybór backendu: automatyczna detekcja Vulkan z bezpiecznym fallbackiem do OpenGL (`XEF_METAL_BACKEND=vulkan|gl`).
- **MetalLibraryArchive (`MTLB`) & Prekompilowane Shadery Metal**:
  - Zaimplementowano w `Metal.framework` (`rootfs-src/appkit/Metal.m`) natywny parser binarnego formatu archiwów `MTLB` (`MetalLibraryArchive`):
    - Odczyt nagłówka `MTLB` (platformID, wersja formatu, offsety listy funkcji i bitcode'u).
    - Dekodowanie wpisów funkcji (`NAME`, `TYPE` dla vertex/fragment/kernel, `MDSZ`, `OFFT` z offsetami segmentów metadanych i bitcode'u).
    - Automatyczne wyciąganie bloków LLVM Bitcode (AIR) dla każdej funkcji w bibliotece.
    - Automatyczna lokalizacja zasobów `default.metallib` w `[NSBundle mainBundle]` przy wywołaniu `newDefaultLibrary` / `newDefaultLibraryWithBundle:`.
  - Dodano test integracyjny `tests/darwin/metallib_test.m` ładujący binarny plik `AAPLShaders.metallib`:
    - Weryfikuje prawidłowe odczytanie wszystkich funkcji (`vertexShader`, `fragmentShader`), ich typów oraz utworzenie stanu potoku `MTLRenderPipelineState`.
    - Rozszerzono `tests/darwin/metal_test.sh` o weryfikację archiwów metallib (`PASS metal_test`).
- **Natywne wsparcie Depth & Stencil w MetalVK**:
  - Rozszerzono `xef_host_metal_pipeline_t`, `PipelineKey` oraz `get_or_create_pipeline` w `darwin_metal_vk.cpp` o pełne stany bufora głębokości i szablonu (`VkPipelineDepthStencilStateCreateInfo`).
  - Mapowanie operacji porównania (`VK_COMPARE_OP_LESS`, `EQUAL`, `GREATER`, `ALWAYS`, etc.) oraz operacji szablonu (`VK_STENCIL_OP_KEEP`, `ZERO`, `REPLACE`, `INCR_CLAMP`, etc.).
  - Integracja `XEFMetalDepthStencilState`, front/back stencil descriptors oraz referencji szablonu (`setStencilReferenceValue:`).
- **MetalKit.framework (`MTKView`)**:
  - Zaimplementowano kompletny framework `MetalKit.framework` (`rootfs-src/appkit/MetalKit.m`) dostarczający `MTKView` i protokół `MTKViewDelegate`.
  - Powiązanie z warstwą `CAMetalLayer`, obsługa `colorPixelFormat`, `depthStencilPixelFormat`, `clearColor`, `currentDrawable`, `currentRenderPassDescriptor`, delegata renderowania `drawInMTKView:` i automatycznego skalowania `drawableSize`.
  - Przebudowano frameworki na Macu i zintegrowano z testem `tests/darwin/metalkit_test.m` (włączonym do `metal_test.sh`).



### 9. MetalVK — prawdziwy Metal na Vulkanie (2026-10-17/18)

Poprzedni backend (`darwin_metal_vk.cpp`, rasteryzer trójkątów) usunięto. Obecna architektura:
- **`mtlc/xef-mtlc`** — osobny proces (protokół w `src/metal/mtl_shader_proto.h`): AIR → SPIR-V własnym emiterem
  (strukturyzacja w stylu clspv, pamięć device/constant przez BDA, thread/threadgroup przez tablice słów),
  oraz MSL → AIR (`mtlc/msl/frontend.cpp`: clang C++20 + generowany `metal_stdlib` z `gen_metal_stdlib.py`).
  Walidacja SPIR-V domyślnie włączona (`XEF_MTL_NO_VALIDATE` wyłącza) — niepoprawny SPIR-V wywracał sterownik.
- **`src/metal`** — silnik: zasoby bindless (set 0), tabele argumentów w buforach pierścieniowych, dynamic rendering,
  layout GENERAL, semafory timeline, swapchain na oknie X11 AppKit.
- **Gość** — `rootfs-src/appkit/Metal*.m`, `QuartzCore.m`, `MetalKit.m` (+`MetalKitAssets.m`, LZFSE w `lzfse/`),
  `ModelIO.m`, `AppKitNib.m` (nib/storyboard, `NSApplicationMain`), `compat/blocks_objc.m` (copy bloków).
- **Wyrocznia na Macu**: `xcrun metal` kompiluje korpus MSL SPIRV-Cross; `xef-mtlc --refl` porównuje refleksję
  (wejścia/wyjścia/wiązania) bibliotek Apple z naszym frontendem — 414/507 identycznych. Testy `.m` buduje się i
  uruchamia na Macu, żeby sprawdzić, że same testy są poprawne (`heap_event_test` przepisany pod prawdziwy Metal).
- **Znalezione i naprawione błędy** (wybrane): sampler `compareFunction` stosowany do zwykłego `sample` (biały ekran
  w SDL_gpu), koercja ABI AArch64 `float3` w wywołaniach intrinsiców, nieparsowane atrybuty członków `stage_in`,
  `early_fragment_tests` w formacie Apple, tablice tekstur w argumentach, liczby całkowite nietypowej szerokości.
- **Działa**: orbit64 (UI + Mario Kart 64, 60 fps), wszystkie 34 SDL_gpu_examples, szablon Xcode „Metal Game”,
  vkcube przez MoltenVK. Aplikacje testowe leżą w `darwin-rootfs` (ignorowane przez git); jak je zbudować — commity
  i `tests/darwin/metal_test.sh`.
- **Braki**: shadery teselacji/mesh, atomiki na teksturach, `get_sample_position`, funkcje widoczne/wskaźniki funkcji,
  ray tracing, liczniki GPU, mapy rasteryzacji, część przeciążeń `sample_compare`; ICB tylko kodowane na CPU.

---

## XEF-OSX — stuby wszystkich frameworków (2026-11-11)

- **Cel:** aplikacja linkująca dowolny framework systemowy ma się załadować i dostać `nil`/`0` z tego, czego nie ma,
  zamiast paść na nierozwiązanym symbolu / brakującej klasie. Prawdziwych binarek Apple nie kopiujemy (zasada z
  `docs/PROMPT_MACOS_3D.md` zostaje): wymagałyby prawdziwego libSystem, jądra XNU i demonów (WindowServer, XPC),
  a do tego nie wolno ich rozpowszechniać. Zamiast tego z Maca bierzemy **fakty o API**.
- **Potok** (`tools/build_framework_stubs.sh`): `.tbd` z SDK na Macu → `mac-out/sdk`; `tools/mac_fwdump.m` na Macu
  (`dlopen` każdej biblioteki w osobnym procesie: funkcja czy dane, wartości stałych CFString, bajty stałych liczbowych,
  rozmiary, nadklasy) → `mac-out/facts.txt`; `tools/gen_framework_stubs.py build` generuje `.m` + `.s` i buduje dyliby
  **lokalnie** (clang `-target arm64-apple-macos12.0` + `ld64.lld`, bez nagłówków SDK). Kroki 1–2 potrzebują Maca
  tylko raz (wynik zostaje w `mac-out/`, poza gitem); krok 3 trwa ~3 min.
- **Wynik (SDK 26, macOS 27):** 2546 bibliotek (2413 pełnych stubów, 133 pliki `<dylib>.xefstubs` obok ręcznie pisanych),
  210 tys. funkcji, 163 tys. stałych napisowych, 26 tys. innych danych, 87 tys. klas; rootfs 74 MB → 274 MB.
  47 bibliotek nie dało się załadować na Macu (rodzaj symbolu zgadywany z nazwy — `guess()`).
- **Loader** (`macho_loader.cpp`): obraz z eksportem `_xef_generated_stub` ma `MachImage::stub`; jest pomijany w
  `dyld_flat_lookup` i przy wiązaniu przez ordinal, a pytany (`dyld_stub_lookup`) dopiero po dylibach rootfs i jawnych
  implementacjach HLE, przed fallbackiem do hosta. `X.xefstubs` jest ładowany razem z `X` (tylko `/System/Library/`).
  Generator dodatkowo pomija nazwy zdefiniowane w dylibach rootfs, w HLE (`"_nazwa"` w `src/loader/darwin_*.cpp`) i w glibc.
- **Klasy:** nieznana wiadomość → `forwardingTargetForSelector:` → obiekt klasy `XEFStubSink`, której
  `+resolveInstanceMethod:` dodaje metodę zwracającą 0. `forwardInvocation:` NIE działa w tym rootfs
  (`rootfs-src/corefoundation/arm64_forwarding.m` robi `abort()`), więc starsze stuby „Generated from Darling specs”
  (`rootfs-src/appkit/*.m` z `forwardInvocation:`) padają na nieznanym selektorze — do przepisania na ten sam mechanizm.
- **Diagnostyka:** `XEF_STUB_TRACE=1` wypisuje każde wywołanie stuba (`xef-stub: _Funkcja`, `xef-stub: -[Klasa sel]`).
- **Testy:** `tests/darwin/fwstubs_test` (budowany na Linuksie: `tests/darwin/fwstubs/build.sh`), Test 7 w `run_tests.sh`.
  Po wygenerowaniu stubów: `macref.sh` 68/69 (`foundation_more` pada tak samo bez stubów), `gl_test` PASS,
  `frameworks_test` PASS; start +10–80 ms (więcej obrazów do zmapowania i klas do rejestracji).
- **Budowanie w chmurze:** `apt-get install llvm-18-dev libclang-18-dev spirv-tools libx11-dev libgl-dev libvulkan-dev xvfb`,
  cmake z `-DCMAKE_CXX_FLAGS="-isystem /usr/lib/llvm-18/include"`; `ld64.lld` = `/usr/bin/ld64.lld-18`. Rootfs z Maca:
  `ssh mac 'cd ~/xef-remote/out/rootfs && tar -cf - . | gzip' | tar -xzf - -C darwin-rootfs`. `metal_test` wymaga Vulkana.
- **Następne kroki:** (1) stuby dla `/usr/lib/*.dylib` (`--prefix /usr/lib/`), (2) struktury zwracane przez x8 nie są
  zerowane, (3) duplikaty klas między ręcznymi frameworkami (NSColor w AppKit i SceneKit, MDL* w SceneKit i ModelIO,
  CUICatalog w IconServices i CoreUI), (4) rootfs na Macu jest starszy niż gałąź (brak `SLSTransaction`,
  `SystemVersion.plist`: `private_frameworks_test`, `tools_and_priv_test` padają) — przebudować `tools/build_*.sh`.

---

## XEF-OSX — rozbudowa AppKit-lite (2026-11-12)

Zadanie od użytkownika: „rozwiń AppKit jak tylko możesz”. Poniżej stan, metoda pracy, pułapki i kolejka zadań.

### 1. Metoda: wyrocznia z prawdziwego Maca (trzymaj się jej)
- **Każde zachowanie najpierw zmierz na Macu.** Test w `tests/darwin/mac/*.m` drukuje fakty (wartości domyślne,
  obcinanie zakresów, kolejność callbacków, ramki po layoucie). `tests/darwin/macref.sh nazwa` buduje go na Macu
  z prawdziwym Cocoa (`clang -fobjc-arc -framework Cocoa`, wykrywane po `Cocoa.h`), uruchamia tam i pod XEF, porównuje
  wyjście linia po linii. Najpierw napisz test, uruchom **tylko na Macu** (`ssh mac 'cd ~/xef-remote/src/macref && clang
  ... && ./test'`), przeczytaj wynik, dopiero potem implementuj. Prawdziwy AppKit ma sporo nieoczywistych reguł
  (patrz §4) — zgadywanie się nie opłaca.
- Testy bez okna na ekranie działają przez ssh (`NSWindow ... defer:YES` też). Unikaj w testach: metryk fontów,
  wyników niejednoznacznych layoutów (remisy priorytetów, widok bez ograniczenia szerokości), `visibleRect` widoku
  bez okna (prawdziwy AppKit zwraca wtedy ogromny prostokąt), ułamków zależnych od skali ekranu (Mac ma 2x, XEF 1x —
  np. NSSplitView zaokrągla do 0,5 pt na Macu; dobieraj rozmiary tak, żeby wychodziły liczby całkowite).
- **Mapa braków:** `tools/appkit_gap.sh` (podsumowanie) i `tools/appkit_gap.sh NSView` (brakujące metody klasy).
  Źródło prawdy to nagłówki SDK (`mac-out/headers`, pobierane z Maca przy pierwszym użyciu; `tools/appkit_api.py`
  wyciąga metody, właściwości i wymagane metody adoptowanych protokołów). Program `tests/darwin/apigap/apigap.m`
  (budowany lokalnie, bez Maca) pyta pod XEF o każdą metodę przez `XEFClassImplements` z AppKit.m, który **nie liczy
  stubów „łapiących wszystko”** (`lite_stub`). Protokół NSAccessibility (~285 metod na klasę) jest pomijany, chyba że
  `WITH_ACCESSIBILITY=1`.
- **Stan liczbowy:** 3690 z 8332 publicznych metod AppKit zaimplementowane naprawdę (44%); 1509 brakuje w
  istniejących klasach, 3133 w 207 nieistniejących klasach. Pierwszy uczciwy pomiar (po rundach 1–2) dawał 3216.
  Wcześniejsze „3182/8152” było zawyżone przez stuby łapiące wszystko (NSView „brakowało” 5 metod, naprawdę 214).

### 2. Co doszło (pliki w `rootfs-src/appkit/`, wszystkie w `tools/build_appkit.sh` i `build_appkit_only.sh`)
- **`AppKitControls2.m/.h`** — NSSlider(+Cell: liniowy, pionowy, kołowy, znaczniki), NSStepper, NSProgressIndicator
  (pasek, nieokreślony, spinner; animacja NSTimer), NSSegmentedControl (3 tryby śledzenia), NSImageView/NSImageCell,
  NSLevelIndicator (4 style), NSColorWell, NSSwitch, NSComboBox (lista jako menu), NSDatePicker (tekstowy + stepper),
  NSTabView/NSTabViewItem, NSSplitView (przeciąganie dzielnika, delegat), NSStackView (układ ręczny, bez solvera),
  NSVisualEffectView, NSPanel, NSGradient (liniowy/radialny), NSAnimationContext (bez interpolacji: zmiany od razu,
  completion na następnym obrocie pętli). Test: `appkit_controls.m` (139 linii, zgodne z Makiem).
- **`AppKitTable.m/.h`** — NSTableView (cell-based i view-based z kolejką reużycia), NSTableColumn, NSTableHeaderView
  (sortowanie kliknięciem, zmiana szerokości kolumny), NSTableHeaderCell, NSTableRowView, NSTableCellView,
  NSOutlineView (drzewo węzłów `XEFOutlineNode`, trójkąty, klawisze ←/→). NSScrollView umieszcza `headerView`
  dokumentu w osobnym NSClipView nad treścią (`kXEFHeaderClip`, obiekt stowarzyszony). Test: `appkit_table.m`.
- **`AppKitView.m`** — reszta API NSView i NSWindow (kategorie `XEFMore`): edycja hierarchii, przebiegi layoutu,
  `cacheDisplayInRect:toBitmapImageRep:` (renderuje drzewo widoków do bitmapy), tooltipy, gesture recognizers (lista),
  arkusze (sheet = okno wyśrodkowane nad rodzicem), okna potomne, zapisywanie ramek (`NSWindow Frame <nazwa>` w
  NSUserDefaults), slot toolbara, właściwości paska tytułu/zakładek. Rzadki stan: `NSView->_extra` (słownik) i
  `props(okno)` (obiekt stowarzyszony).
- **Rdzeń NSView w `AppKit.m` / `AppKitGraphics.m` przepisany** pod prawdziwe zachowanie (test `appkit_view.m`,
  120 linii): `_xefInsertSubview:atIndex:` (kolejność callbacków), `resizeSubviewsWithOldSize:` /
  `resizeWithOldSuperviewSize:` z arytmetyką Apple (`autoresize_axis`), skala i origin bounds, powiadomienia
  frame/bounds, `viewDidHide`/`viewDidUnhide`, hit-testing przez `NSMouseInRect`, `layoutSubtreeIfNeeded` wołane przed
  każdym `_xefRedraw`. **Zmiany semantyki:** `-[NSView tag]` = −1, `acceptsFirstResponder` = NO, `needsDisplay` = NO
  bez okna, `NSPointInRect`/`NSMouseInRect` mają teraz krawędzie jak w AppKit (wcześniej obie włączne).
- **`AppKitLayout.m/.h` — Auto Layout od zera:** solver Cassowary (tablica simpleksowa jak w Kiwi) z
  **leksykograficznymi priorytetami** (wektor współczynników celu na poziom priorytetu, do 12 poziomów na jedno
  rozwiązanie — wyższy priorytet zawsze wygrywa, bez wag), NSLayoutConstraint (+ klucze nib), NSLayoutAnchor /
  XAxis / YAxis / Dimension, NSLayoutGuide, `constraintsWithVisualFormat:` (VFL: `|`, `-`, `-(pred,pred)-`,
  `[v(==w@p)]`, metryki, opcje wyrównania), `_NSDictionaryOfVariableBindings`, `fittingSize`. Test: `appkit_layout.m`.
  - Hierarchia rozwiązywana w całości we współrzędnych najwyższego widoku, y w dół; zmienne na element: x, top,
    width, height. Widok z `translatesAutoresizingMaskIntoConstraints == YES` wnosi swoją ramkę jako wymagane
    ograniczenia; reszta dostaje ramkę z rozwiązania. Rozmiar korzenia: wymagany dla contentView okna, inaczej
    priorytet 490 (zmierzone: ograniczenie @500 go przebija, @400 nie). `fittingSize`: szer./wys. → 0 @50.
  - Kiedy liczy: `XEFLayoutSolveIfNeeded` z `layoutSubtreeIfNeeded`, tylko gdy zmienił się licznik `g_generation`
    (podbijany przez `XEFLayoutInvalidate()` w setFrame, zmianach hierarchii, ograniczeń, intrinsic size) albo rozmiar
    korzenia. Aktywne ograniczenia: globalna tablica `g_active` (bez retain); trzyma je najbliższy wspólny przodek
    (`view.constraints`). `XEFLayoutViewGone` z `-[NSView dealloc]` usuwa ograniczenia martwego widoku.
  - Darlingowe atrapy NSLayoutConstraint/NSLayoutAnchor **wyłączone z builda Foundation** (`skip` w
    `tools/build_foundation.sh`) — klasy są teraz w AppKit.
- **Foundation: `rootfs-src/foundation/NSIndexSet_xef.m`** zastępuje `NSIndexSet.m` z darling-foundation, który trzymał
  zakresy nieposortowane (złe `count`, `lastIndex`, `containsIndex:`, kolejność enumeracji po dodaniu mniejszego
  indeksu). Format archiwum jak u Apple (varinty w `NSRangeData`). Test: `indexset.m`.
- **Galeria:** `tests/darwin/appkit_gallery/` (build.sh buduje na Macu, binarka `gallery` w repo), zrzut:
  `DISPLAY=:7 XEF_APPKIT_SHOT=out.ppm XEF_APPKIT_SHOT_EXIT=1 build/xef-osx -L darwin-rootfs
  tests/darwin/appkit_gallery/gallery` (`GALLERY_SKIP=abcdef` pomija sekcje — przydatne do bisekcji awarii).
  Wynik: `docs/screenshots/appkit-gallery.png`.

### 3. Pętla pracy (kopiuj-wklej)
```sh
tools/build_appkit_only.sh                                   # AppKit na Macu -> darwin-rootfs (~40 s)
tools/gen_framework_stubs.py build --sdk mac-out/sdk --facts mac-out/facts.txt --only '/AppKit$'
                                                             # KONIECZNE po każdym buildzie AppKit (patrz §4)
tests/darwin/macref.sh appkit_view appkit_table appkit_controls appkit_layout indexset
tests/darwin/gl_test.sh; build/xef-osx -L darwin-rootfs tests/darwin/frameworks_test
tools/appkit_gap.sh                                          # pokrycie
tools/build_foundation.sh && rsync -a mac:xef-remote/out/rootfs/System/Library/Frameworks/Foundation.framework \
    darwin-rootfs/System/Library/Frameworks/                 # Foundation (skrypt nie kopiuje do lokalnego rootfs)
```
- Kontrola kompilacji z ostrzeżeniami o nieznanych selektorach (AppKit budowany jest z `-w`): na Macu
  `clang -fsyntax-only -Wno-everything -Wobjc-method-access -fno-objc-arc -isysroot $(xcrun --show-sdk-path) -I. plik.m`.
  **Nieznany selektor zwracający CGFloat/NSRect/NSSize jest wołany jak funkcja zwracająca `id` → śmieci.** Deklaruj
  metody w nagłówkach (`AppKit*.h`) albo w kategorii `NSObject (…Informal)` na górze pliku.
- Stan regresji po tej sesji: `macref.sh` 73/74 (pada tylko stary `foundation_more`), `gl_test` PASS,
  `frameworks_test` PASS, `fwstubs_test` PASS, galeria identyczna piksel w piksel przed i po Auto Layout.

### 4. Pułapki znalezione w tej sesji
- **Stary `AppKit.xefstubs` dubluje nowe klasy.** Po dodaniu klasy do AppKit-lite trzeba przegenerować plik
  uzupełniający (`--only '/AppKit$'`), inaczej objc widzi dwie definicje i `appkit_gap.sh` liczy klasę jako brakującą.
- **AppKit musi linkować CoreGraphics i CoreText** (dodane): aplikacja używająca tylko AppKit zostawiała
  `CGAffineTransformMakeTranslation` nierozwiązane (dynamic_lookup nie ładuje dyliba).
- **`-[NSScrollView tile]` zwalniał scroller** (remove + add w tablicy podwidoków, która miała jedyną referencję).
  Naprawione; wzorzec „usuń i dodaj z powrotem” na `_subviews` zawsze otaczaj retain/release.
- **`forwardInvocation:` nie działa w tym rootfs** (CF robi `abort`) — używaj `forwardingTargetForSelector:`.
- **Klasy z Foundation Darlinga bywają atrapami** (NSLayoutConstraint, NSIndexSet). Gdy coś z Foundation zachowuje
  się dziwnie, napisz test w `tests/darwin/mac/` — różnica wyjdzie od razu.
- Prawdziwy AppKit — reguły, które zaskakują (wszystkie odwzorowane i pokryte testami):
  NSSegmentedControl w trybie select-one ignoruje `setSelected:NO`; w trybie momentary `selectedSegment` zawsze −1 poza
  akcją; NSTabView `selectNext/Previous` pyta delegata `shouldSelect` dwa razy; `selectRowIndexes:byExtendingSelection:YES`
  działa także przy wyłączonej wielokrotnej selekcji i nie pyta delegata; `selectAll:` pyta `shouldSelectRow:` o każdy
  wiersz; NSOutlineView po zwinięciu rodzica pamięta rozwinięte dzieci i otwiera je przy ponownym rozwinięciu (z pełnym
  protokołem should/will/did), a `reloadData` pyta `shouldExpandItem:` o każdy otwarty element bez powiadomień;
  NSProgressIndicator nie obcina wartości przy zmianie zakresu; NSTableColumn ma domyślny tytuł „Field”;
  ponowne `addSubview:` tego samego widoku przenosi go na wierzch bez callbacków; `hitTest:` na krawędziach zależy od
  odwrócenia nadwidoku; `resizeSubviewsWithOldSize:` nie jest wołane dla widoku bez podwidoków.

### 5. Co dalej (w kolejności wartości dla prawdziwych aplikacji)
1. **Klasy nieistniejące, często używane:** NSToolbar/NSToolbarItem (slot `-[NSWindow toolbar]` już jest; rysować
   pasek nad contentView), NSGestureRecognizer + Click/Pan/Magnification/Press (lista w `-[NSView gestureRecognizers]`
   jest; trzeba dostarczać zdarzenia w `-[NSWindow sendEvent:]`), NSPopover, NSImageRep (+ NSPDFImageRep/NSCIImageRep
   jako atrapy), NSSound, NSSplitViewItem/NSSplitViewController/NSTabViewController, NSGridView, NSCollectionView,
   NSObjectController/NSArrayController/NSTreeController (bindings przez KVC/KVO), NSPathControl, NSAnimation.
2. **Braki w istniejących klasach** (`tools/appkit_gap.sh Klasa`): NSDocument 72, NSText 71, NSTextView 60, NSImage 60,
   NSWorkspace 54, NSApplication 53, NSEvent 50, NSResponder 44, NSViewController 35, NSMenu 35. Część getterów w
   `AppKitView.m` czyta `props()`/`_extra`, a istniejące settery w `AppKit.m` piszą do ivarów albo nigdzie
   (`frameAutosaveName`, `acceptsMouseMovedEvents`, `isDocumentEdited`, `titleVisibility`) — ujednolicić.
3. **Auto Layout — dokończenie:** NSStackView przepisać na ograniczenia (teraz układ ręczny w `_xefLayout`);
   aktywować ograniczenia z nibów (`initWithCoder:` jest, ale `NSViewConstraints` widoku nie są instalowane — patrz
   `AppKitNib.m`); linie bazowe (`firstBaseline`/`lastBaseline` = góra/dół); `anchorWithOffsetToAnchor:`; kierunek RTL;
   okno dopasowujące się do `fittingSize` contentView; solver jest przebudowywany przy każdej zmianie (bez edycji
   przyrostowej) — przy tysiącach ograniczeń trzeba będzie dodać `suggestValue`/usuwanie z Cassowary.
4. **Stare atrapy „Generated from Darling specs”** (`rootfs-src/appkit/*.m` z `forwardInvocation:`) przepisać na
   `forwardingTargetForSelector:` albo usunąć na rzecz generowanych stubów (`tools/gen_framework_stubs.py`).
5. **Rysowanie:** NSBox nie rysuje tytułu ustawionego przez `setTitle:`; NSTabView rysuje tylko zakładki u góry;
   brak rysowania toolbara i arkuszy „wysuwanych”; NSDatePicker bez kalendarza graficznego.
6. Duplikaty klas między ręcznymi frameworkami (NSColor w AppKit i SceneKit, MDL* w SceneKit i ModelIO, CUICatalog
   w IconServices i CoreUI) — wciąż otwarte.

### 6. Dodatek (2026-11-12, po Auto Layout): kontrolery, zdarzenia, gesty
- **`AppKitControllers.m/.h`:** reszta NSViewController (dzieci w kolejności, `presentViewControllerAsSheet:` /
  `AsModalWindow:` / `AsPopover…` jako okna, `dismissViewController:`, commitEditing), **NSSplitViewController +
  NSSplitViewItem** (sidebar: canCollapse, holding 260; widok kontrolera to kontener, a `splitView` jest jego dzieckiem —
  tak jak na Macu), **NSTabViewController** (tabView tworzony przy ładowaniu widoku; tytuł propaguje się z wybranej
  zakładki; widok wybranego dziecka ładuje się dopiero z widokiem kontrolera), **rozpoznawacze gestów** (Click, Pan,
  Press, Magnification, Rotation), reszta NSResponder (gesty, dotyk, odtwarzanie stanu, `presentError:`).
  Deklaracja NSViewController przeniesiona z AppKitNib.m do `AppKitControllers.h`.
- **Łańcuch odpowiedzi:** widok z kontrolerem ma `nextResponder` = kontroler, a ten dalej = to, co następowałoby po
  widoku (`-[NSView setNextResponder:]`, klucz `viewController` w `_extra`).
- **NSEvent:** `mouseEventWithType:…`, `keyEventWithType:…`, `enterExitEventWithType:…`, `otherEventWithType:` (data1/2,
  subtype), `eventNumber`, `trackingNumber`, `userData`, `isARepeat`; okno wyszukiwane po `windowNumber`.
- **Gesty: dyspozytor `XEFGestureDispatch`** w `-[NSWindow sendEvent:]` przekazuje mysz rozpoznawaczom widoku pod
  kursorem i jego przodków, ale **nie wstrzymuje zdarzeń dla widoków** (prawdziwy AppKit opóźnia je do niepowodzenia
  gestu — potrzebny model czasowy). Zmierzone na Macu: okno bez ekranu (`defer:YES`) nie dostarcza gestów w ogóle,
  więc test pokrywa tylko wartości domyślne, podpinanie i odpinanie; samo rozpoznawanie jest nieweryfikowane.
- Stan: `macref.sh` 74/75 (tylko stary `foundation_more`), `gl_test`, `frameworks_test` PASS, galeria bez zmian;
  3912 z 8332 metod (47%). Zrobione z listy §5: NSSplitViewItem/Controller, NSTabViewController, gesty, NSViewController,
  NSEvent, NSResponder. Zostają: NSToolbar, NSPopover (kontroler pokazuje okno), NSImageRep, NSSound, NSGridView,
  NSCollectionView, kontrolery bindings.

### 7. Dodatek (2026-11-12, cel „dokończ implementację AppKit”): atrapy z poprawnym ABI i klasy modelu
- **Generator atrap:** `tools/appkit_headers.py` (typowany czytnik nagłówków SDK) i `tools/gen_appkit_stubs.py` tworzą
  `rootfs-src/appkit/AppKitGenerated.m`: dla każdej publicznej metody i klasy, której AppKit-lite nie ma, wpis z poprawną
  konwencją wywołania. Pary property (getter/setter, także struktury NSRect/NSSize/…) **naprawdę przechowują wartość**
  (obiekt stowarzyszony), `-init…` zwraca `[self init]`, `+shared…` daje jedną instancję, wyniki NSArray/NSDictionary to
  puste kolekcje, reszta zwraca 0/nil/NO. **Celowo pomijane:** callbacki w stylu delegata (`tabView:shouldSelect…`,
  `…DidResize:`) i `validate…` — atrapa zwracająca NO unieważniłaby wołanie frameworka (tak padł `appkit_controllers`).
  Klasy bez ręcznej implementacji kompilowane są statycznie (tbd-stuby ich nie dublują), metody dopinane w konstruktorze
  AppKit tylko tam, gdzie nic ich nie implementuje (`XEFClassImplements`). `XEF_APPKIT_NO_GENERATED=1` wyłącza atrapy.
- **Uczciwy pomiar:** `tools/appkit_gap.sh` liczy z wyłączonymi atrapami → „implemented” to tylko prawdziwy kod
  (**4203 z 8257**), a „generated placeholders” to osobna liczba (4313). Atrapy nie są implementacją: aplikacja się nie
  wywróci, ale funkcjonalność nie działa.
- **Pisanie klasy ręcznie:** dodaj jej `@interface` do nagłówka `AppKit*.h` (generator uważa wtedy klasę za ręczną i
  przestaje ją emitować — `rootfs-src/appkit/generated_classes.txt` odświeża się sam), napisz `.m`, wpisz plik do
  `tools/build_appkit*.sh`, `tools/gen_appkit_stubs.py`, `tools/appkit_gap.sh`, `tools/build_appkit_only.sh`. Brakujące metody
  napisanej klasy dostaną atrapy automatycznie.
- **`AppKitModel.m/.h` (zgodne z Makiem, `appkit_misc.m`):** NSToolbar/NSToolbarItem/NSToolbarItemGroup (model z protokołem
  delegata: domyślne identyfikatory ładowane przy `window.toolbar=`, `willAddItem`/`didRemoveItem`, wybór tylko spośród
  `selectableItemIdentifiers`; **pasek nie jest rysowany**), NSAnimation (krzywe, znaczniki postępu, tryb blokujący i
  timer), NSPopover (okno bez ramki + powiadomienia; bez wzorca z Maca), NSController/NSObjectController/NSArrayController
  (zawartość, sortowanie, filtr, selekcja podążająca za obiektami, reguły pustej selekcji; bez bindings).
  Zmierzone nietypowości: `addObject:` na kontrolerze tablicowym nie sortuje do czasu `rearrangeObjects`; `setSizeMode:` na
  toolbarze jest ignorowane; `tag` pozycji toolbara = −1 i nie jest kopiowany; filtr usuwający zaznaczony obiekt zostawia
  pustą selekcję mimo `avoidsEmptySelection`.
- **NSPredicate bez NSInvocation:** w tym rootfs `NSInvocation` na arm64 abortuje, więc `filteredArrayUsingPredicate:`
  nie działa. NSArrayController używa własnego ewaluatora (`xef_eval`: porównania, AND/OR/NOT, BEGINSWITH/ENDSWITH/
  CONTAINS/IN). Reszta Foundation, która polega na NSInvocation (KVO z selektorami, undo, timery z invocation), nadal wymaga
  implementacji forwardingu na arm64 w `rootfs-src/corefoundation/arm64_forwarding.m`.
- **Co jeszcze jest tylko atrapą (największe):** NSCollectionView, NSMatrix, NSBrowser, NSGridView, NSImageRep i podklasy,
  NSSound, NSTreeController, NSPathControl, NSSpellChecker, NSTypesetter, NSTextLayoutManager (TextKit 2), NSDrawer,
  NSRuleEditor, NSScrubber / Touch Bar, NSPrintOperation (pełne), NSWorkspace (większość), NSDocument (72 metody).
- **NSGridView (zgodny z Makiem, `appkit_grid.m`):** NSGridView/NSGridRow/NSGridColumn/NSGridCell w `AppKitModel.m`. Ramki
  liczone bezpośrednio, bez solvera: szerokość kolumny = max szerokości widoków z widocznych wierszy, wysokość wiersza
  analogicznie, odstępy 6 pt tylko między widocznymi, **komórki scalone nie wliczają się do szerokości ani wysokości**,
  rozmiar „automatyczny” to `FLT_MIN`, rozmieszczenie komórka → kolumna/wiersz → siatka (Leading/Top domyślnie). Widok
  zgłasza `fittingSize` jako `intrinsicContentSize`, więc solver Auto Layout ustawia go na rozmiar treści. Stan: 4275 z 8257
  metod prawdziwych (52%), atrap 4051 (185 klas).
- **Kolejne największe luki do ręcznego napisania** (każda ma w `appkit_gap.sh` listę metod): NSMatrix, NSBrowser,
  NSCollectionView (+Layout), NSImageRep (+PDF/Cached/Custom), NSTreeController, NSSound, NSPathControl, NSTextLayoutManager,
  NSSpellChecker. **Warunek wstępny dla wielu rzeczy:** `NSInvocation` na arm64 (patrz wyżej) — bez niego KVO z selektorami,
  undo i `NSPredicate` w Foundation Darlinga nie działają.

### 8. NSInvocation i forwarding na arm64 (2026-11-12)
- **Zrobione:** `rootfs-src/corefoundation/arm64_forwarding.m` zawiera teraz **własny `NSInvocation`** (Darlingowy `NSInvocation.m`
  i `NSBlockInvocation.m` są wyłączone z builda CF w `tools/build_corefoundation.sh`; ich `__invoke__` był tylko w asm x86) oraz
  prawdziwy **`-forwardInvocation:`**. ABI Apple AAPCS64: x0–x7, d0–d7, HFA do 4 elementów w d-rejestrach, struktury ≤16 B w
  x-rejestrach, większe przez wskaźnik, stos z naturalnym wyrównaniem (struktury w slotach 8 B), wynik w x0/x1, d0–d3 albo przez
  x8. Stan trzymany w ivarach z nagłówka Darlinga (`_frame` wskazuje na `State`). `xef_invoke_asm` (wywołanie z buforem
  rejestrów i kopią stosu) i `_CF_forwarding_prep_0` (handler forwardingu: najpierw `forwardingTargetForSelector:`, potem
  `NSInvocation` z zapisanych rejestrów i stosu wołającego, wynik wraca w rejestrach) mają dyrektywy CFI, więc wyjątki ObjC
  przechodzą przez te ramki. `+load` rejestruje handler (`objc_setForwardHandler`).
- **Test `tests/darwin/mac/invocation.m`** zgodny z Makiem: int/long long/float/double/BOOL/char, NSRect/NSSize/NSRange, struktury
  małe, HFA (Pair, float[3]), duże (32 B), mieszane, 10 intów i 10 doublów (stos), SEL, id; API (`retainArguments`, indeksy
  poza zakresem, `invokeWithTarget:`), proxy NSProxy i wrapper z `forwardInvocation:` (wyniki struktur i argumenty na stosie
  przez forwarding), `performSelector:`, `NSPredicate`, `NSUndoManager`.
- **Skutki:** `NSPredicate` i `filteredArrayUsingPredicate:` działają (NSArrayController używa już natywnych); starsze stuby
  „Generated from Darling specs” z `forwardInvocation:` przestały abortować; undo działa. KVO działa (`tests/darwin/mac/kvo.m`: settery int/obiekt/double/BOOL, KVC, powiadomienia ręczne z prior, initial).
  **Zostaje jedna ścieżka:** `setValue:forKey:` na obserwowanym obiekcie dla klucza bez settera (zapis wprost do ivara) wywraca się w
  `_NSKeyValueWillChangeBySetting` w Foundation Darlinga (argument `self` dostaje śmieci: `x1 = 0xe00001683`; typedefy wskaźników
  funkcji zgadzają się z definicjami, więc to nie zła sygnatura — zacznij od `NSKeyValueIvarSetter makeNSKVONotifying`). `NSUndoManager.prepareWithInvocationTarget:` Darlinga zwraca samego siebie, więc
  metody NSObject (np. `setValue:forKey:`) nie są rejestrowane — prawdziwy AppKit zwraca proxy.

### 9. NSMatrix i NSCollectionView (2026-11-12)
- **NSMatrix** (`AppKitModel.m`, zgodny z Makiem, `appkit_matrix.m`): tryby radio/highlight/list/track, budowa z prototypu lub klasy
  komórki, reguły zaznaczania zmierzone na Macu (radio zaznacza pierwszą komórkę i nie dopuszcza pustego zaznaczenia, `deselectAllCells`
  jest wtedy ignorowane, tryb list zastępuje zaznaczenie, `renewRows:columns:` nie zmniejsza tablicy komórek), geometria, edycje
  wierszy/kolumn, target/action/doubleAction macierzy. Metryki tekstu różnią się między platformami, więc test ustawia `cellSize`.
- **NSCollectionView + NSCollectionViewFlowLayout + NSCollectionViewItem + NSCollectionViewLayoutAttributes** (`appkit_collection.m`):
  elementy tworzone leniwie przy layoucie (kolejność wywołań źródła danych: `sections count0 count1 item0.0 …`), przepływ pionowy i
  poziomy ze **wspólnym rozkładem wolnego miejsca między elementy** (np. 3 elementy 80 pt w 296 pt: x = 12/120/228), wstawki sekcji
  powtarzane dla każdej sekcji, ponowne pobranie wszystkich elementów po `reloadData`, selekcja z flagą `selected` elementów, delegat
  wołany tylko przy akcjach użytkownika (`deselectAll:` woła `didDeselect…`). W NSScrollView widok ma rozmiar co najmniej klipa wzdłuż
  osi poprzecznej i treści wzdłuż osi przewijania. Bez okna prawdziwy AppKit w ogóle nie robi layoutu — test używa okna.
- **Testy z oknem wymagają `DISPLAY`** (np. `DISPLAY=:7 tests/darwin/macref.sh appkit_collection`; `Xvfb :7 -screen 0 1280x800x24`).
  Mac przez ssh pozwala na okna (`defer:NO`, `orderFront:`), ale nie ma `timeout` — kończ test `_exit(0)`.
- Stan: **4422 z 8257** metod prawdziwych (54%), atrap 3997 (179 klas); `macref.sh` 80/81.

### 10. Dekodowanie obrazów (2026-11-12)
- **Host:** `xef_host_image_decode/copy/free` (`src/loader/darwin_cg_host.cpp`, deklaracje w `rootfs-src/appkit/xef_host.h`) ładują
  `libgdk_pixbuf-2.0` przez dlopen (jak cairo/pango) i dekodują każdy format, który host zna (PNG, JPEG, GIF, TIFF, WebP, BMP, SVG…) do
  RGBA8 bez premultiplikacji. Bez gdk-pixbuf dekodowanie jest po prostu wyłączone (`NSImage` zwraca nil).
- **AppKit-lite** (`AppKitGraphics.m`, kategorie `XEFDecode`): `-[NSBitmapImageRep initWithData:]` (premultiplikuje do formatu domyślnego, więc
  `_xefCreateContext` dalej działa), `+imageRepWithData:`, `+imageRepWithContentsOfFile:`, `-[NSImage initWithData:/initWithContentsOfFile:/
  initWithContentsOfURL:/initByReferencingFile:/initByReferencingURL:]` — nil dla śmieci i brakujących plików (wcześniej atrapa
  zwracała pusty obraz 0×0). Rozmiar obrazu = rozmiar w pikselach (bez obsługi DPI/@2x).
- **Test:** `tests/darwin/appkit_image/build.sh` → `tests/darwin/image_test` (uruchamiany w `run_tests.sh`, test 9; `XEF_TEST_PNG`).
- Stan: **4427 z 8257** metod prawdziwych; zostają atrapy `NSImageRep` (poza bitmapą), `NSBrowser` (117 metod), `NSSound`, `NSTreeController`,
  `NSPathControl`, `NSTextLayoutManager`, `NSSpellChecker`. `metal_test` w `run_tests.sh` wymaga Vulkana i przerywa skrypt (znane).

### 11. NSTreeController / NSTreeNode (2026-11-12)
- `AppKitModel.m`, zgodne z Makiem (`tests/darwin/mac/appkit_tree.m`): drzewo budowane z `content` i `childrenKeyPath`, `arrangedObjects`
  (korzeń z `childNodes`, `descendantNodeAtIndexPath:`, `indexPath`, `isLeaf`), zaznaczenie przez `NSIndexPath` (`avoidsEmptySelection` domyślnie
  YES; ścieżki są przyjmowane bez walidacji jak w AppKit), `selectedNodes/Objects`, edycje (`insertObject:atArrangedObjectIndexPath:`,
  `removeObject(s)…`, `move…`, `add:/addChild:/insert:/insertChild:/remove:`) wprost na listach w modelu (listy niezmienne zamieniane na zmienne),
  sortowanie deskryptorami kluczy obiektów reprezentowanych. Różnica: u Maca rodzicem węzłów najwyższego poziomu jest ukryty węzeł, nie
  `arrangedObjects`; test tego nie porównuje.
- **Poprawka Foundation:** `-[NSArray componentsJoinedByString:]` Darlinga porównywał elementy z ostatnim przez tożsamość, więc wspólne obiekty
  (np. `@0, @0`) traciły separator (`"00"`). Łatka w `tools/build_corefoundation.sh` (na Macu w źródle `darling/corefoundation/NSArray.m`).
- Stan: **4477 z 8257** metod prawdziwych; `macref.sh` 13/13 dla testów AppKit.

### 12. NSBrowser (2026-11-12)
- `AppKitModel.m`, zgodny z Makiem w API opartym na elementach (`appkit_browser.m`: `rootItemForBrowser:`, `browser:numberOfChildrenOfItem:`,
  `child:ofItem:`, `isLeafItem:`, `objectValueForItem:`): kolumny dzieci, `loadColumnZero` (root pobierany raz), `selectRow(Indexes):inColumn:`
  (zaznaczenie gałęzi otwiera kolejną kolumnę, liść ją ucina), `lastColumn`, `selectedColumn`, `path`/`setPath:` (zła ścieżka czyści zaznaczenie
  i zwraca NO), `pathToColumn:`, `indexPathForColumn:`, `selectionIndexPath(s)`, `itemAtRow:inColumn:`, `parentForItemsInColumn:`, `reloadColumn:`,
  tytuły, szerokości (przycinane do `minColumnWidth`), domyślne ustawienia zmierzone na Macu. Programowe zaznaczenie nie woła delegata.
- Rysowanie to proste listy (biały panel, zaznaczenie `selectedControlColor`, separator); `mouseDown:` zaznacza wiersz i woła akcję/delegata.
- **Nie ma:** klasycznego API z macierzami (`browser:numberOfRowsInColumn:`, `willDisplayCell:`), przewijania kolumn, przeciągania, klawiszy strzałek.
  `rowHeight` na Macu rzuca wyjątek dla delegatów macierzowych — tu zwraca 17.
- Stan: **4573 z 8257** metod prawdziwych.

### 13. NSPathControl i NSSound (2026-11-12)
- **NSPathControl / NSPathControlItem / NSPathComponentCell / NSPathCell** (`AppKitModel.m`, `appkit_pathcontrol.m`): elementy z adresu URL (plik: korzeń
  „Macintosh HD” + składowe, inne schematy: bez korzenia), `pathComponentCells` zsynchronizowane z elementami, jawne `setPathItems:`, style,
  `editable` domyślnie YES, placeholder, `clickedPathItem`; rysowanie rzędu tytułów i klik. Tytuł korzenia na Macu zależy od nazwy woluminu
  — test go nie porównuje. Brak: rozwijanego menu stylu popup, przeciągania, edycji ścieżki.
- **NSSound** (`appkit_sound.m`, zgodny z Makiem): parsowanie WAV (czas trwania), `volume`, `loops`, `play/pause/resume/stop`, `currentTime`,
  `isPlaying`, delegat `sound:didFinishPlaying:` (NO przy `stop`, YES po końcu), `setName:`/`+soundNamed:`. **Dźwięk nie jest odtwarzany** (host
  nie ma wyjścia audio w AppKit-lite) — odtwarzanie jest tylko mierzone w czasie. Inne formaty niż WAV → nil.
- `tests/darwin/run_tests.sh` pomija `metal_test`, gdy nie ma użytecznego Vulkana, więc skrypt dochodzi do końca (testy 7–9 działają).
- Przy okazji: `NSCharacterSet +URLPathAllowedCharacterSet` nie istnieje w Foundation Darlinga.
- Stan: **4637 z 8257** metod prawdziwych; `macref.sh` 15/15 dla testów AppKit.

### 14. Obrazy: kodowanie, lockFocus, drawingHandler (2026-11-12)
- **Host:** `xef_host_image_encode/blob_copy/blob_free` (`darwin_cg_host.cpp`) zapisują RGBA przez `gdk_pixbuf_save_to_bufferv` (png, jpeg z `quality`,
  tiff, bmp; GIF i JPEG 2000 nie mają zapisu → nil).
- **NSBitmapImageRep** (`AppKitGraphics.m`, kategoria `XEFEncode`): `representationUsingType:properties:` (`NSImageCompressionFactor` dla JPEG),
  `TIFFRepresentation`, `+representationOfImageRepsInArray:…`, `+imageRepsWithData:`, `colorAtX:y:`, `setColor:atX:y:`, `getPixel:/setPixel:`,
  `bitmapFormat`, `isPlanar`. Piksele są zwracane/ustawiane z uwzględnieniem premultiplikacji.
- **NSImage:** działające `lockFocus`/`lockFocusFlipped:`/`unlockFocus` (rysowanie do nowej bitmapy, która zastępuje reprezentacje),
  `+imageWithSize:flipped:drawingHandler:` (blok wykonywany leniwie przy pierwszym użyciu, jednorazowo — AppKit woła go przy każdym rysowaniu),
  `addRepresentations:`, `removeRepresentation:`, `bestRepresentation…`, `TIFFRepresentation`, prawdziwe `copy`, `imageTypes` i pokrewne.
- **Pułapka:** kontekst bitmapowy CG jest buforowany i trafia do pikseli reprezentacji dopiero po `CGContextFlush`/zwolnieniu. `+[NSGraphicsContext
  restoreGraphicsState]` spłukuje teraz kontekst utworzony z `graphicsContextWithBitmapImageRep:`.
- Test: `tests/darwin/image_test` (kodowanie PNG/JPEG/TIFF i odczyt z powrotem, `lockFocus`, handler). Stan: **4666 z 8257** metod prawdziwych.

### 15. NSWorkspace i NSApplication (2026-11-12)
- **NSWorkspace** (`AppKitDocument.m`, kategoria `XEFTypes`, `appkit_workspace.m` zgodny z Makiem): tabela typów UTI (~40 wpisów: tekst, obrazy, audio, PDF,
  foldery, pakiety…) z hierarchią — `type:conformsToType:`, `preferredFilenameExtensionForType:`, `localizedDescriptionForType:`, `filenameExtension:isValidForType:`,
  `typeOfFile:error:` (symlink przez `lstat`, katalog → `public.folder`, nieistniejący → nil z błędem), `isFilePackageAtPath:`, `fileLabels/Colors`, woluminy z
  `/proc/mounts` (`mountedLocalVolumePaths`, `getFileSystemInfoForPath:…`), aplikacje z `/Applications` i `~/Applications` (`URLsForApplicationsWithBundleIdentifier:`,
  `fullPathForApplication:`), `duplicateURLs:`, obraz pulpitu, `launchApplication:`, `openURLs:withApplicationAtURL:…`. Ikony plików to rysowane (lockFocus)
  uogólnione obrazki 32×32 — nie prawdziwe ikony typów. Brak: domyślnych aplikacji dla typów, wysuwania nośników.
- **NSApplication** (`AppKit.m`, kategoria `XEFModal`, `appkit_modal.m` zgodny z Makiem): **prawdziwe sesje modalne** — `runModalForWindow:` wcześniej wracało od razu z 1000;
  teraz `beginModalSessionForWindow:`/`runModalSession:`/`endModalSession:`, `stopModal`, `stopModalWithCode:`, `abortModal`, `modalWindow` (zdarzenia innych okien są wtedy
  pomijane), `enumerateWindowsWithOptions:usingBlock:`, `activationPolicy` (domyślnie Prohibited jak w programie bez bundla), `replyToApplicationShouldTerminate:` oraz
  `NSTerminateLater` w `terminate:`, `dockTile`, `miniaturizeAll:`, `orderedDocuments`, drobiazgi. `validateMenuItem:` zwraca YES (Mac też).
- Stan: **4736 z 8257** metod prawdziwych; `macref.sh` 17/17.

### 16. NSDocument i NSTextView — uzupełnienia (2026-11-12)
- **NSDocument** (`AppKitDocument.m`, kategoria `XEFExtras`, `appkit_document2.m`): przestarzałe API oparte na nazwach plików (`fileName`, `readFromFile:ofType:`,
  `writeToFile:…`, `dataRepresentationOfType:`, `lastComponentOfFileName`…) mapowane na API URL, `duplicateAndReturnError:` (wymaga pliku na dysku), `moveToURL:`, lock/unlock
  (stan zmienia się w następnym obiegu run loopa jak w AppKit), `writableTypesForSaveOperation:`, powiadomienia prezentera pliku (puste). **Różnica nieodtworzona:**
  na Macu `duplicateAndReturnError:` i `moveToURL:completionHandler:` dla dokumentu spoza `NSDocumentController` zwracają błąd — test tego nie porównuje.
- **NSTextView** (`AppKitText.m`, kategoria `XEFExtras`, `appkit_textview2.m`): `+scrollableTextView`, `+scrollableDocumentContentTextView`, `+scrollablePlainDocumentContentTextView`,
  `+fieldEditor` (parametry zmierzone na Macu: autoresizing 18, vertical resizable, widthTracksTextView), **prawdziwy tekst oznaczony** (`setMarkedText:…`, `markedRange`,
  `hasMarkedText`, `unmarkText` — wcześniej `hasMarkedText` zawsze NO), `smartInsertForString:…`, `smartDeleteRangeForProposedRange:`, `rangeForUserCompletion`,
  `attributedSubstringFromRange:`, `acceptableDragTypes`, `textHighlightAttributes`, `performValidatedReplacementInRange:` i drobiazgi. `smartInsertDeleteEnabled` jest teraz prawdziwą
  właściwością. Uzupełnianie słów (`completionsForPartialWordRange:`) zwraca pustą listę (Mac: podpowiedzi słownika).
- Stan: **4838 z 8257** metod prawdziwych; `macref.sh` 19/19.

### 17. NSImageRep (2026-11-12)
- `AppKitGraphics.m` / `AppKitLite.h`, `appkit_imagerep.m` (zgodny z Makiem): **`NSImageRep` jest prawdziwą klasą bazową** (`NSBitmapImageRep` dziedziczy po niej): `size`/`setSize:` (rozmiar
  w punktach niezależny od pikseli), `hasAlpha`, `bitsPerSample`, `colorSpaceName`, `isOpaque` (domyślnie YES też z alfą), `draw/drawAtPoint:/drawInRect:`, **rejestr klas**
  (`registerImageRepClass:`, `registeredImageRepClasses`, `imageRepClassForData:` po sygnaturze PNG/JPEG/GIF/TIFF/BMP/WebP), `+imageRepsWithContentsOfFile:` i pokrewne.
  **`NSCustomImageRep`** (selektor rysujący z delegatem albo blok `drawingHandler`), a `NSImage` potrafi narysować taką reprezentację.
- Różnice: Mac zapisuje DPI w PNG, więc rozmiar odczytanej z pliku reprezentacji bywa inny niż piksele (tu rozmiar = piksele); `+imageUnfilteredTypes` bazowej klasy jest
  pusta (jak u Maca). Brak: `NSPDFImageRep`, `NSEPSImageRep`, `NSCachedImageRep` (nadal atrapy).
- Test `appkit_*` w `macref.sh` zdarzył się raz niestabilny (jedno FAIL przy 20 testach, brak powtórzenia przy dwóch kolejnych biegach) — podejrzewany ssh/Xvfb.
- Stan: **4886 z 8257** metod prawdziwych.

### 18. NSMatrix i NSEvent — uzupełnienia (2026-11-12)
- **NSMatrix** (`AppKitModel.m`, kategoria `XEFMore`, `appkit_matrix2.m` zgodny z Makiem): `addRowWithCells:`/`insertRow:withCells:`/`addColumnWithCells:`/`insertColumn:withCells:`
  (kolejność komórek jak u Maca), `makeCellAtRow:column:`, `getNumberOfRows:columns:`, `setState:atRow:column:`, `sendAction:to:forAllCells:` (NO = tylko zaznaczone), sortowanie
  (`NSCell -compare:` porównuje `stringValue`), `setSelectionFrom:to:anchor:highlight:`, tło i tło komórek (rysowane), `keyCell`, tooltipy komórek, delegat, `tabKeyTraversesCells` (domyślnie YES), hooki edycji tekstu.
- **NSEvent** (`AppKit.m`, kategoria `XEFClass`, `appkit_event2.m`): `doubleClickInterval` 0.5, `keyRepeatDelay/Interval`, `mouseCoalescingEnabled`, **zdarzenia okresowe**
  (`startPeriodicEventsAfterDelay:withPeriod:` wrzuca `NSEventTypePeriodic` do kolejki), `charactersByApplyingModifiers:`, `addGlobalMonitor…` (zwraca token, nigdy nie wywołuje bloku),
  akcesory gestów/tabletu (zera). Na Macu te akcesory rzucają wyjątek dla zwykłych zdarzeń myszy — tu zwracają 0.
- Stan: **4973 z 8257** metod prawdziwych; `macref.sh` 22/22.

### 19. NSSpellChecker (2026-11-12)
- `AppKitText.m` / `AppKitText.h`, `appkit_spell.m` zgodny z Makiem: sprawdzanie pisowni na liście słów **`/usr/share/dict/words` z Maca** (`tools/build_appkit_only.sh` kopiuje ją do
  `darwin-rootfs/usr/share/dict/` przy pierwszym uruchomieniu; bez niej wszystko jest uznawane za poprawne). `checkSpellingOfString:startingAt:` (z zawijaniem; słowo już
  rozpoczęte przed offsetem jest pomijane), wariant z `wrap:`/tagiem/`wordCount:` (liczba słów łącznie ze znalezionym błędnym), `countWordsInString:`, ignorowanie
  słów per tag dokumentu, `learnWord:`/`unlearnWord:`/`hasLearnedWord:`, `guessesForWordRange:` (odległość edycyjna 1 względem słownika), `completionsForPartialWordRange:`
  (prefiksy, max 20), `availableLanguages` (tylko `en`), `uniqueSpellDocumentTag`. Odmiany (-s, -ed, -ing, -ly, -er, -est, -'s) są rozpoznawane prostymi regułami — to nie
  prawdziwy słownik Apple, więc rzadkie słowa mogą być oceniane inaczej niż na Macu. Brak: gramatyki, panelu pisowni, `checkString:range:types:` zwraca pustą listę.
- Stan: **5011 z 8257** metod prawdziwych; `macref.sh` 23/23.

### 20. NSLayoutManager — atrybuty tymczasowe i pomocniki glifów (2026-11-12)
- **Atrybuty tymczasowe działają** (`AppKitText.m`, `appkit_layout2.m` zgodny z Makiem): wcześniej `addTemporaryAttribute…` było pustą metodą. Teraz cień (`NSMutableAttributedString`
  długości storage'u) trzyma je, `temporaryAttributesAtCharacterIndex:effectiveRange:` (także `longestEffectiveRange:inRange:`) i `temporaryAttribute:…` zwracają zakresy jak AppKit,
  a układ/rysowanie używa storage'u z nałożonymi atrybutami (`_xefDisplayString`; podkreślenia, kolory tła i tekstu z podświetleń wyszukiwania). Storage pozostaje nietknięty.
  Cień jest przycinany/uzupełniany przy zmianie długości tekstu — nie śledzi pozycji edycji (prawdziwy AppKit przesuwa zakresy).
- Pomocniki glifów (glif = znak): `CGGlyphAtIndex:isValidIndex:`, `getGlyphsInRange:…bidiLevels:`, `notShownAttribute…`, `attachmentSizeForGlyphAtIndex:`, `usesDefaultHyphenation`,
  `attributedString`, `fillBackgroundRectArray:…`, `underline/strikethroughGlyphRange:…`, `showAttachmentCell:…`; settery układu (`setLineFragmentRect:…`, `setLocation:…`) przyjmowane bez efektu.
- Stan: **5049 z 8257** metod prawdziwych; `macref.sh` 24/24; pełny `run_tests.sh` przechodzi (metal_test pominięty bez Vulkana).

### 21. NSMenu i NSSavePanel — uzupełnienia (2026-11-12)
- `AppKit.m` (kategorie `XEFMore`/`XEFLegacy`), `appkit_menu_panel.m` zgodny z Makiem: **NSSavePanel** — `identifier`, `accessoryView`, `nameFieldLabel` ("Save As:"), `extensionHidden` (domyślnie YES),
  `canSelectHiddenExtension`, `treatsFilePackagesAsDirectories`, `showsHiddenFiles`, `showsTagField` (YES), `tagNames` (puste, gdy pole tagów ukryte — jak u Maca), przestarzałe
  `filename/directory/requiredFileType/runModalForDirectory:file:/beginSheetForDirectory:…` (mapowane na API URL; `beginSheet…` jest synchroniczne), `NSOpenPanel filenames`. Same właściwości
  panelu nie zmieniają okna hosta (`xef_host_file_dialog`). **NSMenu** — `identifier`, `presentationStyle`, `selectionMode`, `selectedItems` (stan włączony elementów), `menuChangedMessagesEnabled`
  (domyślnie NO), `+paletteMenuWithColors:titles:…` (pozycje z próbkami koloru, brak rysowania palety), `menuBarHeight`, `appearance`.
- Stan: **5123 z 8257** metod prawdziwych; `macref.sh` 25/25.

### 22. NSCollectionView — uzupełnienia (2026-11-12)
- `AppKitModel.m` (kategoria `XEFMore`), `appkit_collection2.m` zgodny z Makiem: `backgroundView` (dodawany pod elementami, bez rozciągania przy zmianie rozmiaru), `backgroundViewScrollsWithContent`,
  `prefetchDataSource`, `content` (stara właściwość; tylko przechowywana), `setSelectionIndexes:` (sekcja 0), `isFirstResponder`, metody widoków dodatkowych (nagłówki/stopki — zwracają puste wyniki,
  bo `NSCollectionViewFlowLayout` tu ich nie tworzy), `moveItemAtIndexPath:`/`moveSection:` (tylko unieważniają układ), przeciąganie (puste). Na Macu `selectionIndexes=` i `toggleSectionCollapse:` rzucają wyjątek
  dla widoku z dataSource — test ich nie porównuje.
- Stan: **5146 z 8257** metod prawdziwych; `macref.sh` 26/26.

### 23. NSBrowser — klasyczne API z macierzami, NSBrowserCell (2026-11-12)
- `AppKitModel.m`, `appkit_browser2.m` zgodny z Makiem: gdy delegat ma `browser:numberOfRowsInColumn:` (a nie `numberOfChildrenOfItem:`), kolumna to `NSMatrix` jednokolumnowa
  z komórkami `NSBrowserCell` (klasa komórki i macierzy ustawialne; domyślnie `+cellClass` = NSBrowserCell, `matrixClass` = NSMatrix). **Komórki ładują się leniwie** —
  `browser:willDisplayCell:atRow:column:` wołany jest przy pierwszym dostępie (`loadedCellAtRow:column:`, `selectedCell`, ścieżka), nie przy `loadColumnZero` (kolejność wywołań
  jak na Macu: `rows0`, `cell0.1`, `rows1`). `setLeaf:` komórki decyduje o otwarciu następnej kolumny, ścieżka bierze `stringValue` komórek, `setPath:` je dopasowuje,
  `matrixInColumn:`, `columnOfMatrix:`, `selectedCell(s)`. `NSBrowserCell` jest prawdziwą klasą (`isLeaf`, `isLoaded`, `reset`). W trybie klasycznym `titleOfColumn:` zwraca `@""`.
- Nadal brak: przewijania kolumn, przeciągania, klawiszy strzałek, `browser:createRowsForColumn:inMatrix:`, `browser:selectRow:inColumn:` i innych rzadkich callbacków.
- Stan: **5161 z 8257** metod prawdziwych; `macref.sh` 27/27.

### 24. NSTypesetter / NSATSTypesetter (2026-11-12)
- `AppKitText.m` / `AppKitText.h`, `appkit_typesetter.m` zgodny z Makiem: prawdziwe klasy z ustawieniami (`usesFontLeading`, `hyphenationFactor`, `lineFragmentPadding`, `bidiProcessingEnabled`,
  `typesetterBehavior` — `NSTypesetterLatestBehavior` czyta się jako 15, domyślnie 4), `+sharedSystemTypesetter` (instancja `NSATSTypesetter`), `attributedString`, zakresy akapitu
  (`paragraphGlyphRange` bez separatora), `actionForControlCharacterAtIndex:` (nowa linia 24, tab 4, inne 1), decyzje łamania linii, znak dzielenia U+2010, odstępy 0. Układ linii nadal robi
  `NSLayoutManager` — metody układu (`layoutParagraphAtPoint:`, `layoutGlyphsInLayoutManager:…`) są puste, więc własne podklasy typesettera nie wpływają na wygląd tekstu.
- Stan: **5249+ z 8257** metod prawdziwych; `macref.sh` 28/28; pełny `run_tests.sh` przechodzi (uruchomiony w tej rundzie).

### 25. NSRuleEditor (2026-11-12)
- `AppKitModel.m`, `appkit_ruleeditor.m` zgodny z Makiem: model wierszy (prosty/złożony, zagnieżdżone) sterowany delegatem (`numberOfChildrenForCriterion:`, `child:forCriterion:`, `displayValueForCriterion:`,
  `predicatePartsForCriterion:`): `addRow:` w trybie złożonym na pustym edytorze tworzy wiersz złożony i prosty podwiersz, kryteria nowego wiersza to pierwsze dziecko na każdym poziomie,
  `insertRowAtIndex:withType:asSubrowOfRow:animate:` (wiersze najwyższego poziomu trafiają za poddrzewo poprzednika), `removeRowAtIndex:`/`removeRowsAtIndexes:includeSubrows:`,
  `setCriteria:andDisplayValues:forRowAtIndex:`, `parentRowForRow:`, `subrowIndexesForRow:`, selekcja, domyślne wartości (nesting 2, wysokość 32, klucze `rowType/subrows/criteria/displayValues`),
  `predicate`/`predicateForRow:` budowane z części dostarczanych przez delegata (literały kluczy `NSRuleEditorPredicate…`). Rysowanie to lista tekstów z wcięciem; brak prawdziwych kontrolek wiersza
  (popupy, przyciski +/−) i animacji.
- Stan: **5294 z 8257** metod prawdziwych; `macref.sh` 29/29.

### 26. NSColor i NSWindow — uzupełnienia (2026-11-12)
- **NSColor** (`AppKitGraphics.m`, kategoria `XEFMore`, `appkit_color2.m` zgodny z Makiem): komponenty CMYK (`colorWithDeviceCyan:…` zachowuje dokładne wartości CMYK, kolory RGB liczą
  je wzorem naiwnym — bez profilu kolorów, więc wynik różni się od Apple'owej konwersji), `colorWithColorSpace:hue:saturation:brightness:alpha:`, **kolory wzorcowe** (`colorWithPatternImage:`,
  `patternImage` — kopia obrazu, `type` = 1; rysowanie wzorem nie jest zaimplementowane), brakujące kolory systemowe, `currentControlTint`. Brak nazw katalogowych (`catalogNameComponent`).
- **NSWindow** (`AppKit.m`, kategoria `XEFMore`, `appkit_window2.m`): `identifier`, `validateMenuItem:` (`performClose:`/`performMiniaturize:`/`performZoom:` zależne od `styleMask`), `animator`
  (zmiany stosują się od razu — AppKit animuje, więc odczyt tuż po ustawieniu daje tam starą wartość), `convertBaseToScreen:`, `showsResizeIndicator` (NO) itd.
- Stan: **5349 z 8257** metod prawdziwych; `macref.sh` 31/31.

### 27. NSAttributedString — czytniki dokumentów; stałe tekstowe AppKit (2026-11-12)
- **Znalezisko:** 86 publicznych stałych `NSString *const` AppKit (m.in. `NSDocumentTypeDocumentAttribute`, `NSRTFTextDocumentType`, `NSHTMLTextDocumentType`, `NSTextListMarker…`) nie miało wartości —
  aplikacja dostawała śmieci zamiast stringu. Teraz są zdefiniowane w `AppKitText.m` z wartościami odczytanymi z macOS, a test `appkit_consts.m` (wygenerowany z nagłówków SDK, 820 stałych) porównuje
  wszystkie z Makiem. Dodając nową stałą, uruchom `tests/darwin/macref.sh appkit_consts`. (`NSAppearanceNameAccessibilityHighContrastAqua` ma u Maca wartość `NSAppearanceNameAccessibilityAqua`.)
- **NSAttributedString** (`AppKitText.m`, kategoria `XEFDocuments`, `appkit_attrstr.m` zgodny z Makiem): `initWithData:options:documentAttributes:error:` (RTF, HTML, tekst zwykły), `initWithRTF:`,
  `initWithHTML:` itd. Parser HTML obsługuje `b/strong`, `i/em`, `u`, `br`, bloki (zamknięcie `p/div/h*/li` daje `\n`), encje, pomija `script/style/head`; parser RTF: grupy, `\b`, `\i`, `\par`, `\tab`, `\uN`, `\'hh`,
  pomija tabele fontów i kolorów — **to nie WebKit ani pełny RTF** (brak tabel, obrazów, kolorów, rozmiarów czcionek). Błędny RTF → nil z błędem. `attributedStringWithAttachment:`, `lineBreakBeforeIndex:withinRange:`,
  `textTypes`, zakresy bloków/list (puste).
- Stan: **5376 z 8257** metod prawdziwych; `macref.sh` 33/33; pełny `run_tests.sh` przechodzi.

### 28. NSCell, NSCollectionViewLayout, NSStatusItem, NSRulerView (2026-11-12)
- **NSCell** (`AppKitControls.m`, kategoria `XEFMore`, `appkit_cell2.m` zgodny z Makiem): `takeFloatValueFrom:`/`takeIntegerValueFrom:`, `cellAttribute:`/`setCellAttribute:to:`
  (wyłączona/stan/edytowalna/podświetlona/ramka/stan mieszany), `getPeriodicDelay:interval:` (0.2 / 0.025), `identifier`, `sendsActionOnEndEditing`, `defaultFocusRingType` (2), przestarzałe API wpisu/mnemoników.
- **NSCollectionViewLayout** (`AppKitModel.m`): domyślne haki klasy bazowej (atrybuty dodatkowe, przejścia, aktualizacje) — nic nie zmieniają, bez własnych układów podklasy dostają sensowne wartości domyślne.
- **NSStatusItem / NSStatusBar** (`AppKit.m`, `appkit_statusitem.m`): element ma teraz prawdziwy `button` (`NSStatusBarButton`), `length` (-1 = zmienna), `isVisible`, `behavior`, `autosaveName` ("Item-N"),
  `statusBar`, przestarzałe `title/image/action/target` przekazywane do przycisku, `thickness` 22. **Nic nie pojawia się na pasku zadań hosta** — to model.
- **NSRulerView / NSRulerMarker** (`AppKitModel.m`, `appkit_ruler.m`): grubości (reguła 17, markery 15 → `requiredThickness` 32), jednostki (domyślnie "Centimeters" jak na testowanym Macu; lokalizacja zależna),
  `registerUnitWithName:…`, znaczniki (`addMarker:`, położenie, ruchomość), rysowanie kresek co jednostkę. Nie podpięte do `NSScrollView` (`hasHorizontalRuler`) ani do przewijania.
- Stan: **5526 z 8257** metod prawdziwych; `macref.sh` 36/36; pełny `run_tests.sh` przechodzi.

### 29. Bindings (NSObject) i NSImage — ustawienia (2026-11-12)
- **Cocoa bindings** (`AppKit.m`, kategoria `XEFBindings`, `appkit_bindings.m` zgodny z Makiem): `bind:toObject:withKeyPath:options:`, `unbind:`, `infoForBinding:` (opcje zawsze słownik, też puste),
  `exposeBinding:`/`exposedBindings` (łańcuch klas; NSView: hidden/toolTip, NSControl: enabled/value/…), opcje `NSValueTransformerName` (w tym `NSNegateBoolean`) i `NSNullPlaceholder`. **Tylko w jedną stronę**
  (model → właściwość; obserwacja KVO, więc właściwość modelu musi mieć setter): zmiana pola tekstowego przez użytkownika nie wraca do modelu — kontrolki trzeba by wołać `-[NSObject _xefPropagate…]`, którego nie ma.
  `NSController` ma własne bindowanie przez kontrolery z §6. Nie zaimplementowano protokołów delegata z `NSObject` (`controlTextDid…`, `changeFont:` itd. — świadomie, bo zmieniłyby `respondsToSelector:`).
- **NSImage** (`AppKitGraphics.m`, kategoria `XEFSettings`, `appkit_image2.m` zgodny z Makiem): ustawienia (`backgroundColor`, `matchesOnMultipleResolution`, `prefersColorMatch`, `cacheMode`…), `hitTestRect:…`
  (próbkowanie alfy), przestarzałe `compositeToPoint:…`, `dissolveToPoint:fromRect:fraction:`, symbole SF (`imageWithSystemSymbolName:variableValue:…` → nil).
- Stan: **5576 z 8257** metod prawdziwych; `macref.sh` 38/38.

### 30. NSTextField, NSButton, NSView, NSScrollView, NSTableView, NSWorkspace — uzupełnienia (2026-11-12)
- `AppKitControls.m`, `AppKitTable.m`, `AppKitDocument.m`; testy `appkit_controls2.m` i `appkit_scroll2.m` zgodne z Makiem.
  **NSTextField**: wywołania delegata edycji (`textDidBeginEditing:` → powiadomienie + `controlTextDidBeginEditing:`, analogicznie koniec i zmiana; `textShouldBegin/EndEditing:` pyta delegata), `placeholderStrings`,
  `lineBreakStrategy`, `+labelWithAttributedString:`. **NSButton**: `+buttonWithTitle:image:target:action:` (bezel 0 jak u Maca), `maxAcceleratorLevel` (1), `springLoaded`, `tintProminence`, `imageHugsTitle`, `borderShape`,
  opóźnienie okresowe 0.4/0.075. **NSView**: `appearance`/`effectiveAppearance` (dziedziczone po przodkach, potem okno/aplikacja), `animator` (zmiany od razu), `convertSizeToBase:`, stare API gState.
  **NSScrollView**: **limity powiększenia** (min 0.25, max 4; `setMagnification:` przycina i zapamiętuje, **ale treść nie jest skalowana**), `magnifyToFitRect:`, `documentCursor`, strony przewijania (10), `rulerViewClass`,
  linijki (tylko przechowywane), pasek wyszukiwania (tylko pozycja). **NSTableView**: `focusedColumn`, `drawsGrid`, enumeratory zaznaczenia, `textShouldBegin/EndEditing:`.
  **NSWorkspace**: przestarzałe API uruchamiania (`launchApplication:`, `openTempFile:`, `getInfoForFile:…` — zgodnie z Makiem zwracają NO dla nieistniejących).
- Stan: **5715 z 8257** metod prawdziwych; `macref.sh` 40/40; pełny `run_tests.sh` przechodzi.

### 31. NSText jako front klastra; model Touch Bara (2026-11-12)
- **`[[NSText alloc] initWithFrame:]` zwraca `NSTextView`** (jak AppKit; `appkit_nstext.m` zgodny z Makiem). Przy okazji ujednolicono domyślne ustawienia `NSTextView initWithFrame:` z Makiem: `usesFontPanel` YES,
  `maxSize` = (szerokość ramki, 1e7), `baseWritingDirection` domyślnie -1 (natural; teraz zapamiętywane). Metody abstrakcyjnej `NSText` nadal nie są zdefiniowane na samej klasie `NSText`
  (instancje zawsze są `NSTextView`), więc `appkit_gap.sh` liczy je jako brakujące — to świadoma różnica w liczeniu.
- **Touch Bar** (`AppKitModel.m`, `appkit_touchbar.m` zgodny z Makiem): `NSTouchBar` (identyfikatory domyślne/dozwolone/wymagane/główny/Esc, `templateItems`, delegat `touchBar:makeItemForIdentifier:`,
  pamięć podręczna elementów, wbudowane elementy `NSTouchBarItemIdentifier…`), `NSTouchBarItem`, `NSCustomTouchBarItem`, `NSGroupTouchBarItem` (`groupTouchBar`, szerokości). **Nic nie jest wyświetlane** (`isVisible` zawsze NO);
  pozostałe elementy (`NSPickerTouchBarItem`, `NSSliderTouchBarItem`, `NSScrubber`…) nadal atrapy.
- Stan: **5775 z 8257** metod prawdziwych; `macref.sh` 42/42.

### 32. NSDrawer, NSPrinter, NSPDFImageRep (2026-11-12)
- **NSDrawer** (`AppKitModel.m`, `appkit_drawer.m` zgodny z Makiem): maszyna stanów — `open` → Opening (1) + `drawerWillOpen:`, po 0.25 s Open (2) + `drawerDidOpen:`; `close` → Closing (3), `close:`
  pyta `drawerShouldClose:` (a `close` nie), `toggle:`; z Closing `open` wraca do Opening, a `openOnEdge:` działa tylko ze stanu Closed. Domyślne offsety (0/15), min/max rozmiaru (FLT_MAX), domyślny widok zawartości.
  **Szuflada nie jest rysowana** — to model.
- **NSPrinter**: brak drukarek (`printerNames` puste, `printerWithName:` nil), stałe odpowiedzi dla reszty.
- **NSPDFImageRep** (`AppKitGraphics.m`, host `xef_host_pdf_info/render` w `darwin_cg_host.cpp`, `appkit_pdfrep.m` zgodny z Makiem): liczba stron i rozmiar z **`pdfinfo`**, strona renderowana przez **`pdftocairo -png -transp`**
  (poppler-utils na hoście; bez nich `NSPDFImageRep` zwraca nil), `pageCount`, `currentPage` (przycinane), `bounds`, `PDFRepresentation`, `drawInRect:` (dpi dobrane do rozmiaru docelowego, przezroczyste tło);
  `NSImage initWithData:` wybiera klasę reprezentacji z rejestru (PDF i bitmapy), `+imageRepClassForData:` rozpoznaje `%PDF`. Brak: ładowania z pliku `.pdf` przez `NSImage initWithContentsOfFile:`? — działa przez `initWithData:`;
  brak zaznaczania/tekstu PDF.
- Stan: **5836 z 8257** metod prawdziwych; `macref.sh` 44/44; pełny `run_tests.sh` przechodzi.

### 33. Domyślne wartości atrap z Maca (2026-11-12)
- **`tools/capture_defaults.py`** (wymaga Maca): dla każdej klasy, która nadal jest generowaną atrapą, tworzy obiekt na Macu (`init` / `initWithFrame:`), woła proste gettery (BOOL, liczby, NSString/NSNumber, NSRect/NSSize/NSPoint)
  w procesie potomnym (awaria lub wyjątek gubi tylko tę klasę) i zapisuje `rootfs-src/appkit/generated_defaults.txt` (115 wartości z 49 klas; tylko 21 różni się od zera). `tools/gen_appkit_stubs.py` wstawia je do tabeli
  `kDefaultsTable` w `AppKitGenerated.m`, a getter atrapy odpowiada wartością z Maca, dopóki nic nie ustawiono (np. `NSWorkspaceOpenConfiguration.promptsUserIfNeeded` = YES,
  `NSScrubberProportionalLayout.numberOfVisibleItems` = 5, `NSTextLayoutManager.usesFontLeading` = YES). Test: `appkit_defaults.m`. To **nie** zamienia atrapy w implementację — `appkit_gap.sh` nadal liczy je jako brakujące.
  Klasy, których nie da się utworzyć przez `init` (wymagają specjalnych inicjalizatorów), nie mają przechwyconych wartości.
- Stan: **5836 z 8257** metod prawdziwych (bez zmian; atrapy wiernie odpowiadają); `macref.sh` 45/45.

### 34. NSDiffableDataSourceSnapshot, NSWorkspaceOpenConfiguration, NSSpeechSynthesizer (2026-11-12)
- **NSDiffableDataSourceSnapshot** (`AppKitModel.m`, `appkit_snapshot.m` zgodny z Makiem): uporządkowane sekcje z unikalnymi identyfikatorami elementów — dołączanie/wstawianie/przenoszenie/usuwanie elementów i sekcji
  (elementy przenoszone między sekcjami zmieniają sekcję, `appendItems…` bez sekcji trafia do ostatniej, usuwanie sekcji kasuje jej elementy, `deleteAllItems` kasuje też sekcje, nieistniejące identyfikatory są pomijane;
  na Macu `reloadItems…` z nieznanym identyfikatorem rzuca wyjątek — tu jest pusta). Nie jest podpięty do `NSTableView`/`NSCollectionView` (brak `NSCollectionViewDiffableDataSource`).
- **NSWorkspaceOpenConfiguration**: prawdziwy pojemnik ustawień z domyślnymi wartościami Maca (prompts/recents/activates/substitution = YES, architektura 0xFFFFFFFF). **Nie wpływa** na `NSWorkspace` (`openURL:configuration:…` ignoruje go).
- **NSSpeechSynthesizer** (`appkit_speech.m` zgodny z Makiem): mówienie jest tylko mierzone w czasie (słowa / tempo), **bez dźwięku** (brak syntezatora mowy na hoście); `startSpeakingString:` zwraca NO dla pustego tekstu,
  `stopSpeaking` ustawia `isSpeaking` na NO od razu, a `didFinishSpeaking:NO` przychodzi w następnym obiegu run loopa; `defaultVoice` to na stałe `com.apple.speech.synthesis.voice.Alex`.
- Stan: **5914 z 8257** metod prawdziwych; `macref.sh` 47/47; pełny `run_tests.sh` przechodzi.

### 35. NSTextAttachment; przechwytywanie domyślnych wartości — proces na klasę (2026-11-12)
- **NSTextAttachment** (`AppKitText.m`, `appkit_attachment.m` zgodny z Makiem): `contents`, `fileType`, `image`, `bounds` (domyślnie zero), `fileWrapper` (tworzony automatycznie przez `initWithData:ofType:`, ale **nie**
  rozpakowywany przy `initWithFileWrapper:` — `contents` zostaje nil), `lineLayoutPadding` (0), `attachmentBoundsForAttributes:…` (jawne `bounds`, a gdy zero — rozmiar obrazu), `imageForBounds:…`.
  **Układ tekstu nadal nie rysuje załączników** (`NSLayoutManager` ich nie obsługuje) — to tylko model.
- `tools/capture_defaults.py` uruchamia teraz **osobny proces dla każdej klasy** (wcześniejsze `fork()` po starcie wątków AppKit wywalało się w `+initialize`, co gubiło wiele klas) i dla podklas `NSTouchBarItem`
  używa `initWithIdentifier:`. Przechwycono 208 wartości (50 różnych od zera). Skrypt nie nadpisuje tabeli, gdy nic nie przechwycił.
- Stan: **5938 z 8257** metod prawdziwych; `macref.sh` 48/48.

### 36. NSScrubber (2026-11-12)
- `AppKitModel.m`, `appkit_scrubber.m` zgodny z Makiem: źródło danych (`numberOfItemsForScrubber:`, odczytywane przy `reloadData` i `setSelectedIndex:`), `selectedIndex` (-1; poza zakresem po przeładowaniu wraca do -1; **delegat nie jest wołany**
  przy ustawianiu programowym), `mode`/`itemAlignment`/`continuous` i pozostałe flagi, domyślny `scrubberLayout` (`NSScrubberFlowLayout`), rejestr klas elementów (`registerClass:forItemIdentifier:`, `makeItemWithIdentifier:owner:`
  zwraca instancję zarejestrowanej klasy, nil dla nieznanego identyfikatora). `itemViewForItemAtIndex:` zawsze nil (na Macu też, dopóki element nie jest widoczny) — **nic nie jest układane ani wyświetlane**.
- Stan: **~5960 z 8257** metod prawdziwych (patrz `tools/appkit_gap.sh`).

### 37. NSScreen, NSCursor, NSAlert, NSBox, NSSearchField, NSBezierPath, NSScroller — uzupełnienia (2026-11-12)
- `AppKit.m`, `AppKitControls.m`, `AppKitGraphics.m`; test `appkit_misc2.m` zgodny z Makiem. **NSScreen**: `deepestScreen`, `maximumFramesPerSecond` (60), `convertRectFromBacking:`, `backingAlignedRect:…`, `safeAreaInsets` (zero),
  `screensHaveSeparateSpaces` YES. **NSCursor**: brakujące kursory (zoom, dragLink, column/row resize) mapowane na istniejące, `setOnMouseEntered/Exited:`. **NSAlert**: `+alertWithError:` (styl 2, tekst z błędu),
  `icon` (domyślna pusta ikona 64×64), `showsHelp`, `helpAnchor`, `accessoryView`, `delegate`, `suppressionButton` (tworzony, gdy `showsSuppressionButton` — **okno hosta tego nie pokazuje**). **NSBox**: `borderWidth` (1), `cornerRadius`,
  `borderColor`, `titleFont`, `borderType` (3) — przechowywane, rysowanie boxa ich jeszcze nie używa. **NSSearchField**: `recentSearches`, `maximumRecents` (-1), `searchMenuTemplate`, `sendsWholeSearchString` itd.,
  prostokąty przycisków. **NSBezierPath**: domyślne parametry (`defaultMiterLimit` 10, flatness 0.6), `relativeCurveToPoint:…`. **NSScroller**: `+isCompatibleWithOverlayScrollers` YES, stałe odpowiedzi dla reszty.
- Stan: **6087 z 8257** metod prawdziwych; `macref.sh` 50/50; pełny `run_tests.sh` przechodzi.

### 38. NSColorPanel, NSColorList, NSFontPanel (2026-11-12)
- `AppKitText.m` / `AppKitText.h`; testy `appkit_colorpanel.m`, `appkit_fontpanel.m` zgodne z Makiem. **Wcześniej `+sharedColorPanel` i `+sharedFontPanel` zwracały nil** (aplikacja wywołująca je dostawała nil).
  Teraz: współdzielone obiekty (nie `NSPanel`, **nie pokazują okna**) — `color` (wysyła akcję przy `setColor:`), `alpha` z koloru, `continuous`/`showsAlpha` (YES), `mode` (6; `setMode:` jest ignorowane jak u Maca dla niewidocznego panelu),
  `accessoryView`, `setTarget:/setAction:`; `NSFontPanel`: `setPanelFont:isMultiple:`, `panelConvertFont:`, `worksWhenModal` (YES), `setEnabled:` ignorowane. **`NSColorList`**: nazwane listy z kolejnością kluczy
  (`setColor:forKey:` nie zmienia pozycji istniejącego klucza, `insertColor:key:atIndex:`), `+availableColorLists` zawiera tylko listy utworzone w programie (bez wbudowanych list Apple), brak zapisu do pliku.
- Stan: patrz `tools/appkit_gap.sh`; `macref.sh` 52/52.

### 39. Porównanie fabryk klas z Makiem (2026-11-12)
- **`tools/probe_factories.py`** (wymaga Maca): dla każdej klasowej metody bez argumentów zwracającej obiekt (`+shared…`, `+default…`, `+current…` i ok. 160 innych getterów) porównuje, czy wynik jest nil, na Macu i w XEF (proces na klasę).
  Znalazło: `NSHapticFeedbackManager +defaultPerformer`, `NSPrintInfo +defaultPrinter`, `NSTokenField(Cell) +defaultTokenizingCharacterSet` (brakowały), `NSTextInputContext +currentInputContext` (u Maca nil, u nas obiekt;
  generator ma teraz listę `NIL_FACTORIES`), `NSBrowserCell +branchImage` oraz `[[NSSound alloc] init]` (nil jak u Maca). Po poprawkach różnice są tylko dla `NSAdaptiveImageGlyph.contentType` (UTType) i `NSSliderAccessory` (brak klasy).
- Podobna próba **tworzenia każdej klasy przez `init`/`initWithFrame:`** (322 klasy): XEF tworzy wszystko, co Mac; różnice to klasy, które u Maca rzucają wyjątek (XEF jest łagodniejszy) oraz `[[NSURL alloc] init]` (u nas nil — Foundation Darlinga).
- Stan: patrz `tools/appkit_gap.sh`.

### 40. Elementy Touch Bara (przycisk, suwak, wybór), NSCachedImageRep, NSEPSImageRep (2026-11-12)
- `AppKitModel.m`, `appkit_touchitems.m` zgodny z Makiem: **NSButtonTouchBarItem** (trzy fabryki, `customizationLabel` domyślnie = tytuł), **NSSliderTouchBarItem** (prawdziwy `NSSlider` w środku, `doubleValue` przekazywane,
  min. szerokość 64, szerokość akcesorium 36), **NSPickerTouchBarItem** (etykiety/obrazy per indeks, `selectedIndex` -1, `setNumberOfOptions:` zeruje etykiety i daje puste obrazy, `setEnabled:atIndex:`).
  Nic nie jest wyświetlane. Pozostałe elementy (`NSStepperTouchBarItem`, `NSPopoverTouchBarItem`, `NSColorPickerTouchBarItem`, `NSCandidateListTouchBarItem`…) nadal atrapy.
- **NSCachedImageRep** (rect/rozmiar/alfa, `window` tworzony leniwie jak u Maca) i **NSEPSImageRep**: `appkit_epscache.m` — **dzisiejszy macOS nie czyta danych EPS** (`canInitWithData:` = NO, `imageRepWithData:` = nil), więc XEF też nie;
  klasa istnieje tylko dla zgodności API.
- Stan: patrz `tools/appkit_gap.sh`; `macref.sh` 54/54; pełny `run_tests.sh` przechodzi.

### 41. NSSearchFieldCell i NSPrintPanel (2026-11-12)
- `AppKitControls.m`, `AppKitDocument.m`, test `appkit_searchcell.m` zgodny z Makiem: **NSSearchFieldCell** — te same ustawienia co `NSSearchField` (ostatnie wyszukiwania, `maximumRecents` -1, menu szablonu, flagi wysyłania),
  komórki przycisków wyszukiwania/anulowania (tworzone leniwie, `reset…` je zeruje), prostokąty tekstu i przycisków. `NSSearchField` trzyma własne wartości osobno (nie przekazuje ich do komórki).
  **NSPrintPanel** — ustawienia (`options` domyślnie 3, tytuł przycisku, kotwica pomocy, kontrolery akcesoriów); **`runModal` zwraca 0 (anulowano)** — host nie ma okna druku.
- Stan: patrz `tools/appkit_gap.sh`.

