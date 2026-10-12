# XEF — notatka przekazania (stan na 2026-10-12)

Ten plik jest dla następnej sesji. Pełny opis architektury: `docs/ARCHITECTURE.md`.
Specyfikacja projektu (od użytkownika): szybki translator AArch64 → x86-64, user-mode Linux;
wydajność jest priorytetem zaraz po poprawności. Użytkownik akceptuje każdy plan, a celem
jest „rozwijaj XEF dopóki nie skończą się tokeny”.

**Zasady repo:** commity BEZ stopki „Co-Authored-By: Claude” (wyraźne życzenie użytkownika).
Remote: `git@github.com:su-Snufkin/XEF.git`, gałąź `main`.

## Szybki start (nowa maszyna / cloud)
```sh
tools/setup.sh                       # cmake/ninja (venv), sysroot arm64, qemu-user, źródła benchmarków
export PATH=$PWD/.tools/venv/bin:$PATH
cmake -S . -B build -G Ninja -DCMAKE_CXX_COMPILER=clang++ && ninja -C build
cmake -S . -B build-dbg -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_COMPILER=clang++ && ninja -C build-dbg
tests/guest/run.sh                   # programy C/C++ vs qemu (27/27 przechodzi)
(cd tests/diff && python3 fuzz.py -n 3000 --class all --seed 1)   # fuzzer instrukcji vs qemu
bench/build.sh && bench/run.py       # benchmarki -> docs/benchmarks.md
```
Uruchamianie: `build/xef [-L sysroot] prog args` (dla binarek dynamicznych `-L .tools/sysroot-aarch64`).
Diagnostyka: `--stats`, `--profile`, `--dump-ir`, `--dump-code`, `-v`, `--no-tier2`,
`--tier2-threshold N`. Do porównań wydajności `tools/ab.py binA binB -- args` (maszyna jest
zaszumiona, więc licz się z dużą wariancją i używaj minimum z wielu przebiegów).

## Co działa
- Loader ELF (static, static-pie, dynamic przez ld-linux z rootfs), syscalle (generic → x86-64 z konwersjami).
- Frontend: pełne int/load-store/branch/system, LSE, NEON/FP (szeroko; rzadkie operacje przez `vec_ref`).
  Brak: LDXP/STXP/CASP w codegenie (`fatal`), SHA1/SHA256, FP16 arytmetyka.
- Tier 1 JIT: stałe mapowanie rejestrów, NZCV w EFLAGS (CF=!C), lookahead żywotności flag,
  rematerializacja flag, block linking, IBTC inline, natywny RSB dla BL/RET.
- Tier 2: regiony gorących pętli z regionalnym mapowaniem rejestrów, dataflow flag, wątek
  kompilacji w tle, sampling SIGPROF, degradacja regionów, które wychodzą zbyt często.
- Wątki (clone → pthread_create), fork/vfork, execve (z obsługą shebang i natywnych binarek x86).
- Testy: 27 programów gościa zgodnych z qemu; fuzzer bez niezgodności poza znakiem/payloadem NaN
  (świadome odstępstwo, opisane w ARCHITECTURE.md).

## Wydajność (ostatnie pomiary, i7-13620H VM)
CoreMark 200k: natywnie ~4,7 s, XEF ~7,9–8,4 s, qemu ~28,7 s (≈55% natywnej, ≈3,5× qemu).
zstd -6 (48 MB): natywnie ~0,55 s, XEF ~1,3–1,5 s, qemu ~4,8 s. Szczegóły w `docs/benchmarks.md`.

## PRACA W TOKU: sygnały (nie skończone, niezacommitowane testy w `tests/guest/wip/`)
Zaimplementowane w `src/os/signals.cpp`:
- sigaction gościa, handler hosta `async_handler` dla sygnałów z handlerem gościa
  (sygnały wewnętrzne SEGV/BUS/ILL/FPE/PROF/TRAP zostają przy XEF),
- `pending` per wątek (`ThreadCtx`), sprawdzanie w stubie `enter` i po syscallach,
- single-step (flaga TF) do najbliższego wejścia bloku w `trap_handler`, potem
  przekierowanie do `exit_to_runtime` (tier 1) albo `RegionInfo::sig_exit` (tier 2),
- ramka `rt_sigframe` AArch64 (siginfo, ucontext, sigcontext, fpsimd_context, frame record),
  `rt_sigreturn`, `sigsuspend`, `sigaltstack`, maska sygnałów,
- trampolina sigreturn w pamięci gościa (glibc aarch64 nie ustawia SA_RESTORER).

Stan testu `tests/guest/wip/t_signals.c`:
- działa: `raise`/`kill` do siebie, SA_SIGINFO;
- **zawiesza się**: SIGALRM przerywający ciasną pętlę bez syscalli (dostarczanie przez TF).

Hipotezy do sprawdzenia:
1. Krokowanie przez TF nigdy nie trafia na `b->code == rip`, bo pętla jest w regionie tier 2,
   a wejścia bloków wewnętrznych są wykrywane przez `find_by_host`. Sprawdzić też, czy `sig_exit`
   istnieje i czy TF nie jest zdejmowany przez coś po drodze.
2. Sekwencja przywracania flag (`rol/shr/add/sahf`) nie rusza TF, ale `pushfq` w JIT zapisuje TF
   w `flags_spill`; `need_flags` przez `sahf` go nie przywraca (OK). Natomiast `popfq` w stubie
   `enter` odtwarza `st->eflags` — upewnić się, że TF nie trafia tam z `exit_to_runtime` podczas
   krokowania (`signals_deliver_pending` czyści bit 0x100, ale inne wyjścia nie).
3. Możliwe, że SIGTRAP od TF przychodzi z `si_code` > 0, ale `t->stepping` jest fałszywe w innym wątku.

Debug: `build-dbg/xef` + gdb (`handle SIGTRAP nostop noprint pass`) albo licznik kroków w
`trap_handler` wypisywany przez `write(2, ...)`. Po naprawie przenieść test z `wip/` do
`tests/guest/` (oczekiwane wyjście = to, co daje qemu).

## Następne kroki (priorytet)
1. Dokończyć sygnały (wyżej), potem synchroniczne SIGSEGV/SIGBUS do handlerów gościa
   (wymaga mapy host-PC → guest-PC: `CodegenOut::pcmap` jest liczona, ale nigdzie nie zapisywana).
2. Inwalidacja kodu przy SMC/munmap (`code_invalidate_range` to dziś no-op): indeks bloków po
   stronach, unpublish + odlinkowanie (`ExitInfo::next_in`), ochrona zapisu stron z kodem, epoki
   przy zwalnianiu kodu. Lookahead flag też czyta kod następników, więc trzeba to uwzględnić.
3. LDXP/STXP/CASP (cmpxchg16b); potem włączyć HWCAP_ATOMICS/CRC32 w loaderze (`guest_hwcap`).
4. Tier 2: przypinanie rejestrów V do XMM, eliminacja zbędnych zapisów do CpuState, regiony
   obejmujące wywołania (BL), lepszy dobór regionów; tier 1: tańsze kopie (VI init per blok to ~50 KB memset).
5. Trwały cache AOT, thunki bibliotek (memcpy/strlen/libm), przeliczenie benchmarków.
6. Mapa rejestrów regionu w handlerze crashy (dziś zakłada mapowanie kanoniczne).

## Pułapki, na które już wpadliśmy
- **Nie zapisywać danych na stronach z kodem.** Licznik obok kodu dawał 25-krotne spowolnienia
  (SMC machine clears). Dane zmienne alokować przez `g_cache.alloc_data`.
- Interwał ITIMER_PROF przeżywa execve: przed exec trzeba go wyłączyć (`ItimerPause`).
- Maska sygnałów gościa nie może blokować sygnałów wewnętrznych (`kInternalSigs`).
- `fid(kEntryFlags)` kiedyś czytał poza tablicą IR; stała 0xFFFF to pseudo-wartość.
- qemu nie wykona exec binarki aarch64 (brak binfmt), więc dla takich testów używaj plików `.expected`.
