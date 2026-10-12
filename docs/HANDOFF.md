# XEF — notatka przekazania (stan na 2026-10-12)

Ten plik jest dla następnej sesji. Pełny opis architektury: `docs/ARCHITECTURE.md`.
Specyfikacja projektu (od użytkownika): szybki translator AArch64 → x86-64, user-mode Linux;
wydajność jest priorytetem zaraz po poprawności. Użytkownik akceptuje każdy plan, a celem
jest „rozwijaj XEF dopóki nie skończą się tokeny”.

**Zasady repo:** commity BEZ stopki „Co-Authored-By: Claude”; autor zawsze `su-Snufkin <341201482+su-Snufkin@users.noreply.github.com>` (ustawione w `git config` repo; nie podawaj `-c user.email`).
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
- **GUI / gry 3D** (docs/GUI.md): X11, GTK3, Qt, Mesa llvmpipe (GL 4.5), glxgears, glmark2 (174 vs 350
  natywnie), Neverball, Extreme Tux Racer, OpenArena, Minetest, SuperTuxKart — wszystkie grywalne.

## Narzędzia
- `tools/mkrootfs.sh [pkg…]` — rootfs arm64 z Ubuntu noble (z zależnościami), `tools/guishot.sh` —
  uruchom program GUI i zrób zrzut (Xvfb `:1`). Domyślne env dla GUI: `LIBGL_ALWAYS_SOFTWARE=1
  SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null`.
- `--trace` (bez linkowania, ślad ostatnich bloków przy skoku w niezamapowany adres), `--profile`
  (bloki + czas poza JIT wg funkcji/bibliotek), `--stats` (lista operacji wektorowych przez helper C).
- Sieć w chmurze: deb.debian.org zablokowany → `tools/setup.sh` używa Ubuntu ports/archive.

## Następne kroki (priorytet)
1. Wydajność gier: przypinanie rejestrów V do XMM w regionach tier 2 (shadery llvmpipe to gorące
   pętle NEON), mniej przeładowań stałych wektorowych, regiony obejmujące BL.
2. FP16 arytmetyka (HWCAP FPHP/ASIMDHP), rzadsze operacje NEON wciąż w helperze (`--stats`).
3. Zwalnianie kodu (cache rośnie bez końca: inwalidacja tylko odpina bloki), epoki dla wątków.
4. Trwały cache AOT, thunki bibliotek.

## Pułapki, na które już wpadliśmy
- Remat flag w terminatorach nie może używać RAX (cel skoku) — RAX jest przypinany w Exit*Indirect/Ret.
- `CLONE_PARENT_SETTID` musi być zapisany zanim dziecko ruszy (glibc: ptid == ctid).
- `alloc_code()` tylko rezerwuje; drugi alloc przed `commit_code` zwraca ten sam adres.
