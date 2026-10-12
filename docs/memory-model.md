# Model pamięci: AArch64 na x86-TSO

x86-64 gwarantuje TSO: kolejność load->load, load->store i store->store jest zachowana
sprzętowo, a zamienić miejscami można tylko store->load (późniejszy load może wyprzedzić
wcześniejszy store do innego adresu). AArch64 jest słabszy. Translacja może więc pomijać
wszystko, co TSO zapewnia za darmo, a musi wstawić barierę tylko tam, gdzie ARM wymaga
porządku store->load.

| instrukcja AArch64 | x86-64 | uzasadnienie |
|---|---|---|
| zwykłe LDR/STR | `mov` | TSO jest silniejsze niż słaby porządek ARM |
| `DMB ISHLD` / `DMB *LD` | nic | load->load i load->store są zachowane w TSO |
| `DMB ISHST` / `DMB *ST` | nic | store->store jest zachowany w TSO |
| `DMB ISH`/`SY` (pełna) | `lock or dword [rsp],0` (gdy flagi martwe) lub `mfence` (gdy NZCV żywe) | jedyny przypadek wymagający porządku store->load; `lock or` jest tańszy niż `mfence`, ale niszczy EFLAGS |
| `DSB *` | jak pełna DMB | brak efektów urządzeń w user-space; wystarczy porządek pamięci |
| `ISB` | nic | x86 jest spójny dla kodu; modyfikacje kodu wykrywane są przez SMC/inwalidację |
| `LDAR`, `LDAPR`, `LDAPUR` | `mov` | load ma w TSO semantykę acquire |
| `STLR`, `STLUR` | `xchg [m], r` | release jest darmowe, ale ARM wymaga, by STLR->LDAR były uporządkowane (RCsc); `xchg` (niejawny `lock`) daje pełną barierę |
| `LDXR`/`LDAXR` | `mov` + zapamiętanie (adres, wartość) w CpuState | monitor wyłączności emulowany przez porównanie wartości |
| `STXR`/`STLXR` | `lock cmpxchg` z zapamiętaną wartością | atomowe, bez globalnego locka; semantyka ABA jak w FEX/qemu: zapis przechodzi, jeśli wartość się nie zmieniła |
| `CLREX` | unieważnienie zapamiętanego adresu | |
| `CAS*` | `lock cmpxchg` | |
| `SWP*` | `xchg` | |
| `LDADD*` | `lock xadd` | |
| `LDCLR/LDEOR/LDSET/LD{S,U}{MAX,MIN}` | pętla `lock cmpxchg` | brak natywnego odpowiednika zwracającego starą wartość |
| `DC ZVA` | 8× `mov qword` (64 B) | DCZID_EL0 zgłasza bloki 64 B |
| `DC/IC` (utrzymanie cache) | nic | |

Warianty acquire/release instrukcji LSE i CAS nie potrzebują nic ponad `lock`: instrukcje
z prefiksem `lock` są w x86 pełnymi barierami.

Wszystkie pominięcia wynikają z gwarancji TSO opisanych w Intel SDM vol. 3A §9.2
(„Memory Ordering in P6 and More Recent Processor Families”).
