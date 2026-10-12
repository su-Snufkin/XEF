# XEF — architektura

XEF to translator binarny przestrzeni użytkownika: uruchamia programy Linux/AArch64 na
x86-64. Priorytet: poprawność, zaraz potem wydajność. Ten dokument opisuje stan bieżący
kodu; jest aktualizowany przy każdej zmianie struktury.

## Struktura katalogów

```
src/
  main.cpp                 opcje, start
  common/                  typy, log/fatal, wykrywanie cech CPU (cpuid)
  loader/                  ładowanie ELF (ET_EXEC/ET_DYN, PT_INTERP), stos startowy, auxv
  frontend/a64/            dekoder + translacja A64 -> IR
     translate.cpp         int, load/store, skoki, system; lookahead żywotności NZCV
     translate_simd.cpp    NEON / FP
  ir/                      IR w formie SSA (ir.h), builder ze składaniem stałych
  backend/
     vec_ref.cpp           referencyjna implementacja operacji wektorowych/FP (dokładna semantyka ARM)
     x64/assembler.h       emiter x86-64 (GPR, SSE, VEX/AVX, BMI2)
     x64/codegen_t1*.cpp   generator kodu (wspólny dla tier 1 i tier 2), t1_internal.h
     x64/stubs.cpp         stuby wejścia/wyjścia z JIT
  runtime/
     cpu_state.h           CpuState gościa + stałe mapowanie rejestrów
     code_cache.*          pamięć kodu, mapa PC->blok, IBTC, linkowanie wyjść, obszar danych
     dispatch.cpp          translacja + pętla wykonania wątku
     tier2.cpp             kompilator regionów (tier 2), sampler SIGPROF, wątek kompilacji
     helpers.cpp           ścieżki wolne wywoływane z JIT (operacje wektorowe, konwersje), pula stałych
  os/                      syscalle (tablica generic -> x86-64), sygnały, wątki
  profile/                 statystyki (--stats) i profiler (--profile)
tests/
  diff/                    fuzzer instrukcji XEF vs qemu-aarch64 (runner.c, tramp.S, fuzz.py)
  guest/                   programy C/C++ porównywane z qemu (run.sh)
  asm/                     ręczne testy asemblerowe
bench/                     benchmarki (build.sh, run.py, micro/*.c) -> docs/benchmarks.md
tools/                     fetch_debs.py (sysroot bez roota), timeit.py, ab.py (porównania A/B)
```

## Gorąca ścieżka wykonania

### Pamięć
Adres gościa == adres hosta (mapowanie tożsamościowe). Dostęp do pamięci gościa to jedna
instrukcja x86 z pełnym trybem adresowania (`ldr x9,[x0,x1,lsl #3]` -> `mov rax,[rdi+rsi*8]`).
Binarki PIE ładowane są pod 0x5500000000, interpreter pod adres wybrany przez jądro.
Strona gościa = 4 KiB (AT_PAGESZ); binarki wyrównane do 16/64 KiB działają bez zmian.

### Rejestry (mapowanie kanoniczne, tier 1)

| x86 | gość |
|---|---|
| rdi rsi rdx r10 r8 r9 | X0–X5 (= rejestry argumentów `syscall` x86; `memcpy(x0,x1,x2)` = SysV rdi/rsi/rdx) |
| rbx rbp r12 | X19 X20 X21 (najczęstsze po X0–X3 w skompilowanym kodzie; X6/X7/FP są 2–13× rzadsze) |
| r13 r14 | LR (X30), SP |
| r15 | `CpuState* + 128` (najgorętsze pola w zasięgu disp8) |
| rsp | stos JIT = natywny stos powrotów (patrz niżej) |
| rax rcx r11 | temporaria bloku |

Pozostałe rejestry gościa żyją w `CpuState`. Rejestry wektorowe V0–V31 żyją w `CpuState`;
w obrębie bloku wartości są w XMM0–15 (wszystkie traktowane jako temporaria).

### Flagi NZCV
NZCV żyje w EFLAGS hosta w postaci kanonicznej: SF=N, ZF=Z, **CF=!C**, OF=V. Odwrócony carry
sprawia, że `CMP`/`SUBS` + `B.cond` mapują się bezpośrednio na `cmp` + `jcc` bez korekty
(HS->jae, LO->jb, HI->ja, LS->jbe, GE/LT/GT/LE bezpośrednio). `ADDS` dostaje `cmc`,
`ANDS`/`TST` dostaje `stc`.

Kontrakt: na granicy bloku EFLAGS zawierają NZCV gościa — chyba że analiza żywotności
wykaże, że żaden następnik nie czyta NZCV przed jego nadpisaniem:
* **tier 1**: lookahead — dekodowanie (przez ten sam translator) do 24 instrukcji następników,
* **tier 2**: dataflow po CFG regionu.

Gdy instrukcja musi zniszczyć EFLAGS, a flagi są jeszcze potrzebne:
1. kod używa form nie ruszających flag (`lea`, `mov`, `not`, `shlx/sarx/shrx/rorx`, `movzx`, `cmov`),
2. flagi tanie do odtworzenia (z `SUBS`/`ADDS`/`ANDS`) są **rematerializowane** przed konsumentem
   (`cmp a,b` lub — dla warunków EQ/NE/MI/PL — `test wynik,wynik`),
3. w ostateczności: `pushf` przy zapisie i odtworzenie przez `rol ax,8 / shr al,3 / add al,0x7f / sahf`
   (bez mikrokodowanego `popf`).

Skoki warunkowe nie niszczące flag: CBZ/CBNZ przez `mov rcx,x; jrcxz`, TBZ przez `shlx/sarx` + `jrcxz`.

### Bloki, linkowanie, skoki pośrednie
* Blok kończy się na skoku/wyjątku lub po 128 instrukcjach.
* Każde wyjście bezpośrednie to `jmp/jcc rel32` z polem wyrównanym do 4 bajtów; początkowo
  prowadzi do stubu linkującego, a po przetłumaczeniu celu jest atomowo przepisywane na skok
  bezpośredni. Dispatcher w C++ jest tylko ścieżką awaryjną.
* Skoki pośrednie (BR/BLR/RET-mismatch) sprawdzają **IBTC** inline: 16K wpisów po 16 B,
  sekwencja nie rusza flag (`movzx/lea/not/lea/jrcxz`), a każde miejsce skoku ma własny
  `jmp [r11+8]`, więc BTB przewiduje cele niezależnie.
* **BL/RET**: BL robi `push adres_powrotu_gościa; call cel`, RET porównuje adres na stosie
  JIT z X30 (bez flag) i wykonuje natywny `ret`, więc predyktor powrotów CPU (RSB) działa
  dla kodu gościa. Gdy adresy się nie zgadzają (longjmp, korutyny), stos JIT jest resetowany
  i używane jest IBTC.

### Tier 2 (regiony)
* **Wykrywanie gorących bloków**: SIGPROF co 1 ms czasu CPU, zliczanie próbek per blok,
  bez liczników na gorącej ścieżce. Próg: 3 próbki.
* **Kompilacja**: wątek w tle buduje region: blok gorący plus przetłumaczone już następniki
  przez skoki bezpośrednie, w promieniu 16 KiB, do 48 bloków. Region musi zawierać cykl.
* **Mapowanie regionalne**: rejestry hosta przypisane do gości nieużywanych w regionie
  dostają najczęściej używane X8–X28. Reszta trafia do puli temporariów. Transfer rejestrów
  odbywa się wyłącznie na wejściu do regionu i na wyjściach; na wyjściu zapisywane są tylko
  rejestry modyfikowane w regionie.
* **Krawędzie**: wewnętrzne to bezpośrednie `jmp/jcc`; zewnętrzne idą przez stub
  przejścia do mapowania kanonicznego i zwykłe linkowane wyjście.
* **Aktywacja**: linki prowadzące do bloku tier 1 są przepinane na wejście regionu.
* **Sprzężenie zwrotne**: stuby wyjść liczą wyjścia (bez ruszania flag). Region, który
  wychodzi częściej niż 100 000 razy na ms czasu w nim spędzonego, jest degradowany (linki
  wracają do tier 1).
* **Dane zmienne** (liczniki, pula stałych) leżą w osobnym obszarze danych na początku
  rezerwacji code cache: są w zasięgu RIP, ale nie dzielą stron z kodem, bo zapisy obok
  wykonywanego kodu wywołują kosztowne „SMC machine clears”.

### NEON / FP
* Operacje wektorowe to jeden opcode IR (`VOp`) z podoperacją, rozmiarem elementu i flagami
  (skalarna / 64-bitowa).
* Gorące operacje mają bezpośrednie obniżenie do SSE4.1, a przy dostępnym AVX do form VEX
  3-operandowych; FMA przez FMA3, z jawną negacją operandów zgodnie z FPNeg w ARM.
* Reszta wywołuje `vec_ref` (C, dokładna semantyka ARM, łącznie z estymatami FRECPE/FRSQRTE).
* Konwersje FP->int mają poprawki saturacji i NaN zgodne z ARM.
* **Świadome odstępstwo**: znak i payload NaN generowanych przez sprzęt x86 (np. 0/0 daje
  0xFFC00000 zamiast ARM 0x7FC00000). Dokładne odwzorowanie kosztowałoby kilka instrukcji
  na każdą operację FP. Fuzzer raportuje te przypadki osobno („nan-sign/payload-only”).

### Syscalle
Tablica generic->x86-64; większość przechodzi bez zmian, bo X0–X5 leżą już w rejestrach
argumentów syscalli x86. Konwersje: `stat`/`fstat`/`newfstatat`, `epoll_event`, flagi `open`
(O_DIRECTORY/O_NOFOLLOW/O_DIRECT/O_LARGEFILE mają inne wartości), `uname` (machine=aarch64),
`/proc/self/exe`. `brk` jest emulowany na mmap. Ścieżki absolutne są przekierowywane do
rootfs gościa (`-L`/`XEF_ROOTFS`).

### Narzędzia diagnostyczne
* Nieobsługiwana instrukcja: `xef: fatal: unsupported instruction at <adres>: <kodowanie>`.
* Crash w kodzie JIT: blok gościa, offset hosta, rejestry gościa.
* `--stats`: statystyki translacji i wyjść; `--profile`: najgorętsze bloki.
* `--dump-ir`, `--dump-code`: zrzut IR i kodu hosta (`/tmp/xef-<pc>.bin`, `/tmp/xef-t2-<pc>.bin`).

## Testowanie
* `tests/diff/fuzz.py`: losowe kodowania (int / SIMD / FP), walidacja przez llvm-mc,
  porównanie pełnego stanu rejestrów z qemu-aarch64. Wykrywa też instrukcje nieobsługiwane.
* `tests/guest/run.sh`: programy C/C++ (static/dynamic, -O2/-O3) porównywane z qemu.
* qemu i sysroot glibc aarch64 pobierane są bez roota (`tools/fetch_debs.py`) do `.tools/`.
  qemu służy wyłącznie jako wyrocznia w testach, nie w kodzie produkcyjnym.

## Do zrobienia (kolejność)
1. wątki (clone, futex), sygnały do handlerów gościa, inwalidacja przy SMC, LDXP/STXP/CASP,
2. więcej optymalizacji tier 2 (eliminacja zbędnych zapisów, przypinanie V-rejestrów, regiony z wywołaniami),
3. trwały cache AOT,
4. thunki bibliotek (memcpy/strlen/libm, później GL/Vulkan).
