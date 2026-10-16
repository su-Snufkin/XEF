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
- macref 31/31.

Tabela aplikacji (2026-10-16, Linux x86-64 w chmurze):
| aplikacja | status | uwagi |
|---|---|---|
| node 24.1 | działa | console/fs/http/crypto/worker_threads/child_process; npm 11.3 (`init`, `install` z sieci, esbuild) |
| esbuild (Go) | działa | binarka Go uruchamiana przez node |
| git 2.56 | działa | init/add/commit/diff/log/gc, `clone` https (libcurl z butelki) |
| curl 8.23 | działa | https z weryfikacją OpenSSL; LDAP/GSS niedostępne (błąd 7 / fallback) |
| jq, ripgrep, fd, fzf --version, rsync, redis-server, nginx -v | `--version` działa | realne użycie: jq tak; reszta do sprawdzenia |
| vim 9.2 | działa | ex-mode i interaktywnie (pty) |
| tmux 3.6 | działa | sesja, powłoka, wyjście |
| htop 3.4 | działa | lista procesów, uptime; CPU% w 1. klatce zawyżone (próbka startowa htop) |
| ssh 10.6 | `-V` działa | połączenia nie testowane |
