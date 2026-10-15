# XEF-OSX (XEF-0SX)

**XEF-OSX** to emulator i warstwa translacji binarki pozwalająca na uruchamianie programów **macOS ARM64 (Apple Silicon / Darwin AArch64)** na systemach **x86-64 Linux**.

Projekt łączy:
1. **Silnik translacji dwupoziomowego JIT (AArch64 → x86-64)** z projektu **XEF** (dekoder instrukcji ARM64, optymalizacje IR, Tier-1 per-block JIT oraz Tier-2 region compiler).
2. **Warstwę zgodności z macOS (Darwin)** inspirowaną i zaadaptowaną z projektu **Darling**:
   - Loader formatu **Mach-O 64-bit ARM64** (`MH_MAGIC_64`) oraz binarek uniwersalnych **FAT / Universal Mach-O** (`FAT_MAGIC` / `FAT_CIGAM`), automatycznie wybierający wycinek ARM64.
   - Prawidłowe odwzorowanie segmentów `__PAGEZERO` (ochrona pamięci 4GB), `__TEXT`, `__DATA`, `__LINKEDIT`, BSS.
   - Odczyt i inicjalizacja punktów wejścia `LC_MAIN` (`entryoff`) oraz `LC_UNIXTHREAD`.
   - Inicjalizacja obszaru **macOS Commpage** (`0x00007fffffe00000` oraz `0x0000000fffffc000`) z informacjami o CPU, wersjach i parametrach systemu.
   - Układ stosu zgodny z **Darwin / Apple Silicon ABI** (struktura `argc`, `argv`, `envp`, `apple` ze zmienną `executable_path=...`, wyrównanie 16-bajtowe).
   - Obsługa wywołań systemowych Darwin:
     - BSD System Calls (`x16`, `svc #0x80` oraz `svc #0`, mapowanie flag i struktur m.in. `stat64`, `open`, `mmap`, `ulock_wait`/`ulock_wake` na Linuksowy futex, `sysctl`, `getentropy`, `pipe`, `ioctl`).
     - Obsługa konwencji flag błędów Darwin (ustawianie flagi Carry `C=1` przy błędzie i `C=0` przy sukcesie).
     - Trapy jądra Mach (m.in. `mach_reply_port`, `thread_self_trap`, `task_self_trap`, `host_self_trap`, `mach_timebase_info_trap`, `mach_msg_trap`).

---

## Budowanie

```bash
# Ustawienie narzędzi cmake i ninja:
export PATH=$PWD/.tools/venv/bin:$PATH

# Konfiguracja i kompilacja za pomocą Clanga:
cmake -S . -B build -G Ninja -DCMAKE_CXX_COMPILER=clang++
ninja -C build
```

Po zbudowaniu powstaną binarki:
- `build/xef-osx` (oraz `build/xef`).

---

## Uruchamianie programów macOS ARM64

```bash
# Uruchomienie binarki Mach-O ARM64:
build/xef-osx ścieżka/do/programu_macho_arm64 [argumenty...]

# Uruchomienie uniwersalnej binarki FAT (x86_64 + arm64):
build/xef-osx ścieżka/do/programu_universal [argumenty...]

# Opcjonalnie z rootfs macOS / Darling prefixem:
build/xef-osx -L /sciezka/do/macos_rootfs /sciezka/do/programu
```

---

## Uruchomienie testów Darwin ARM64

W katalogu `tests/darwin` znajduje się zautomatyzowany zestaw testów sprawdzający:
1. `hello_darwin` — kompilowany przez Clang dla macOS ARM64 z wywołaniami Darwin `SYS_write` i `SYS_exit`.
2. `complex_darwin` — test trapów Mach (`mach_timebase_info`), `getpid`, `mmap` i `munmap`, oraz arytmetyki wektorowej NEON / FP.
3. `hello_universal` — prawdziwa uniwersalna binarka Mach-O FAT (x86_64 + arm64) utworzona przez `llvm-lipo`.
4. `test_c` — program w C dla środowiska Darwin ARM64 testujący przekazywanie argumentów linii poleceń (`argc`, `argv`).

Aby uruchomić testy:
```bash
tests/darwin/run_tests.sh
```

---

## Rootfs z bibliotekami macOS (dyliby budowane z open source na prawdziwym Macu)

`xef-osx` ładuje zależności (`LC_LOAD_DYLIB`) z rootfs (`-L darwin-rootfs`). libSystem jest emulowane
(HLE, `src/loader/darwin_hle.cpp`, `darwin_sys_shims.cpp`, `darwin_stubs.cpp`, `darwin_mach.cpp`), a reszta to
prawdziwy kod arm64 zbudowany z otwartych źródeł na zdalnym Macu (`ssh mac`, patrz `CLAUDE.local.md`):

| Biblioteka | Źródło | Skrypt |
|---|---|---|
| libc++, libc++abi, libunwind | LLVM 19 | `tools/build_darwin_rootfs.sh` |
| libobjc (Objective-C runtime) | Apple objc4-951 | `tools/build_libobjc.sh` |
| libsystem_blocks (bloki + klasy ObjC) | Apple libclosure | `tools/build_system_libs.sh` |
| libdispatch (własna, "lite") | `rootfs-src/libdispatch-lite` | `tools/build_libdispatch_lite.sh` |
| libicucore | ICU 74 | `tools/build_icu.sh` |
| CoreFoundation | Darling (`darling-corefoundation`) | `tools/build_corefoundation.sh` |
| Foundation | Darling (`darling-foundation`) | `tools/build_foundation.sh` |

Dane (strefy czasowe): `tools/setup_darwin_rootfs_data.sh`. Eksperymentalnie (nieużywane przez HLE): prawdziwy
`libsystem_kernel` (`tools/build_libsystem_kernel.sh`) i libplatform (`tools/build_libplatform.sh`).

Testy referencyjne — program jest kompilowany prawdziwym Apple clang na Macu, uruchamiany tam i pod XEF, a wyniki
porównywane:

```bash
tests/darwin/macref.sh            # wszystkie tests/darwin/mac/*.{c,cpp,m}
tests/darwin/try.sh plik.m        # jeden plik: wynik z Maca vs xef-osx
```
