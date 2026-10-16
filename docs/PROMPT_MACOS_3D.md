# CEL
Uruchomić na XEF (gałąź `XEF-OSX`, katalog `/home/igorw/Documents/Projekty/XEF`) co najmniej JEDNĄ
aplikację 3D skompilowaną dla macOS arm64 (Mach-O) na Linuksie x86-64. Aplikacja ma otworzyć okno,
wyrenderować kilka klatek 3D i zachować się tak, jak na prawdziwym Macu (`ssh mac`).
Pracuj autonomicznie, aż ten cel zostanie OSIĄGNIĘTY I ZWERYFIKOWANY. Nie kończ po planie
ani po „częściowym postępie”.

# KRYTERIUM SUKCESU (wszystkie punkty)
1. `build/xef-osx -L darwin-rootfs <app>` startuje bez crasha i bez „unimplemented”, które blokuje renderowanie.
2. Okno pojawia się (Xvfb `:1`, `tools/guishot.sh`), a zrzut ekranu pokazuje scenę 3D (nie czarny/pusty ekran).
   Obejrzyj zrzut sam (Read na PNG). Dla pewności porównaj go ze zrzutem tej samej aplikacji z Maca.
3. Program działa stabilnie ≥ 300 klatek (np. licznik klatek w stdout lub `--stats`) i kończy się kodem 0.
4. Wynik jest powtarzalny (2 uruchomienia z rzędu) i jest dodany test regresji w `tests/darwin/` (wpięty w `macref.sh` lub `run_tests.sh`).
5. Commit na `XEF-OSX` zgodny z zasadami repo. Zaktualizowane `docs/HANDOFF.md` i `docs/GUI.md`.
Sukces ogłaszasz dopiero po punktach 1–5, z dowodami (komendy, wyjścia, ścieżka do zrzutu).

# ZASADY STAŁE (przeczytaj najpierw `CLAUDE.local.md`, `docs/HANDOFF.md`, `docs/ARCHITECTURE.md`, `docs/GUI.md`)
- Najpierw istniejące open source, potem pisanie od zera: Darling (CoreFoundation, Foundation, AppKit/Cocoa, OpenGL, CoreGraphics, IOKit), Apple OSS (objc4, Libc, xnu, libdispatch, CF), MoltenVK, KosmicKrisp, LLVM, SPIRV-Cross, ANGLE, Mesa, SDL/GLFW.
- Żadnych dylibów Apple skopiowanych z shared cache Maca. Wolno budować OSS-owe biblioteki na Macu (jak libc++/libobjc) i używać Maca jako wyroczni: `ssh mac`, `tests/darwin/macref.sh`.
- Jeśli `ssh mac` nie łączy, sprawdź IP (DHCP; ostatnio .208) w `~/.ssh/config`, a jeśli to nie pomoże, zapytaj użytkownika. `sudo` na Macu tylko gdy naprawdę trzeba, i napisz po co.
- Commity: autor i committer `JupiczeQ <74213715+JupiczeQ@users.noreply.github.com>`, BEZ stopki Co-Authored-By, gałąź `XEF-OSX`. Nie rób `git push`. Małe, atomowe commity po każdym działającym kroku.
- Nie uruchamiaj długich zestawów testów (>~5 min). Do zmian we wspólnych ścieżkach (translator, syscalle) wystarczy `tests/guest/run.sh` oraz `tests/darwin/run_tests.sh`. Dłuższe tylko po zapytaniu.
- Nie pytaj o zgodę na kolejne kroki planu, użytkownik z góry akceptuje każdy plan. Pytaj tylko, gdy jesteś zablokowany czymś, co należy do użytkownika (np. nowy adres Maca).

# JAK UŻYWAĆ SUB-AGENTÓW (kluczowe)
Ty jesteś orkiestratorem: planujesz, delegujesz, weryfikujesz, scalasz i commitujesz. Ciężką pracę
(czytanie dużych źródeł, research, implementacja) zlecaj sub-agentom, żeby kontekst zostawał czysty.
- Niezależne agenty uruchamiaj RÓWNOLEGLE, wszystkie w jednej wiadomości (kilka wywołań Agent naraz). Sekwencyjnie tylko tam, gdzie jest zależność danych.
- Każdy prompt dla agenta musi być samodzielny, bo agent nie widzi tej rozmowy. Podaj w nim: cel, ścieżki, ograniczenia z „ZASAD STAŁYCH”, dokładny format odpowiedzi (≤ 40 linii: wnioski, ścieżki `plik:linia`, komendy, ryzyka) i kryterium ukończenia.
- Typy: `Explore` do przeszukiwania kodu (read-only, ustaw „very thorough”), `Plan` do projektowania, `general-purpose` do implementacji, budowy, testów i researchu sieciowego (WebSearch/WebFetch).
- Agenty implementujące, które mogą edytować te same pliki równolegle, dostają `isolation: "worktree"` i własny, rozłączny zakres plików. Ty scalasz wyniki (cherry-pick/merge) i rozwiązujesz konflikty.
- Nie ufaj raportom agentów. Po każdym zadaniu implementacyjnym sam odpal build i test z kryterium i sprawdź wynik. „Zadziałało” bez dowodu (wyjście komendy) liczy się jako niezrobione.
- Twórz agenty o konkretnych rolach, nie ogólnych „zrób 3D”. Gdy agent utknie, wyślij mu SendMessage z ać od zera.

# FAZA 0 — Rozpoznanie (równolegle, 6 agentów `Explore`/`general-purpose`)
A1. Stan loadera Mach-O: co jest w `src/loader/*` (dyld-style, HLE libSystem, mach, pthread, sygnały), jakie symbole/stuby brakują, jak wygląda ładowanie dylibów i frameworków. Zrób listę „unimplemented”.
A2. Stan grafiki XEF: `--host-gl`, `src/thunks`, `thunks/*`, `tools/gen_glthunks.py`. Czy thunki GL/EGLieżkę Mach-O (inne ABI: stałe, TLS, rejestry x18, wariadyczne wywołania w konwencji Apple)?
A3. Research OSS (WebSearch/WebFetch + klonowanie do `/tmp`-owego scratchpada): jakie gotowe części istnieją dla (a) AppKit/Cocoa/NSWindow/NSOpenGLView na Linuksie (Darling, GNUstep, SDL/GLFW-Cocoa backend), (b) OpenGL.frameworcienka warstwa nad GL/EGL, (c) Metal na Linuksie (czy jest jakiekolwiek OSS tłumaczące Metal→Vulkan, npe projekty; ocena realności), (d) CoreFoundation/Foundation/libdispatch z Darling, ICU.
A4. Na Macu (`ssh mac`): znajdź/zbuduj kandydatów na minimalną aplikację 3D i zbadaj ich zależności (`otool -L`, `dyld_info -imports`, `nm -u`). Kandydaci od najprostszego: (1) własny C/ObjC program z SDL2 lub GLFW (statycznie zlinkowanym) + OpenGL 2.1/legacy, (2) ten sam z OpenGL core 3.2 (3) coś z Cocoa + NSOpenGLView, (4) Metla każdego: lista importowanych symboli per framework.
A5. Analiza luk: które frameworki są potrzebne minimum (libSystem, libc++, libobjc, CoreFoundation, Foundation, AppKit, QuartzCore, OpenGL, CoreGraphics, CoreVideo, IOKit, Metal) i które symbole faktycznie wywołuje wybrany kandydat.
Oceń koszt każdej luki (S/M/L).
A6. Ścieżka testowa: jak automatycznie uruchamiać i weryfikować obraz (Xvfb, `tools/guishot.sh`, porównanie z zrzutem z Maca, metryka np. odsetek niepustych pikseli / SSIM).

# FAZA 1 — Plan (2–3 agenty `Plan` równolegle, konkurencyjne)
Każdy dostaje pełne wyniki fazy 0 i ma zaprojektować OSTATECZNY plan dla innej strategii:
P1. „SDL2/GLFW + legacy GL najpierw”: najkrótsza droga do pierwszej klatki.
P2. „Prawdziwy Cocoa/AppKit z Darling + NSOpenGLView → X11/GLX/EGL”.
P3. „Metal → Vulkan” (tylko jeśli A3 pokazał realną bazę OSS), albo „ANGLE/Metal backend”.
Plan ma zawierać: kolejność kroków z szacunkiem ryzyka, listę plików/funkcji do dodania, sposób testu ka), punkty kontrolne „widzę okno”, „widzę pierwszy trójkąt”, „widzę scenę”.
Potem SAM wybierz plan (lub hybrydę) według kryteriów: najkrótsza droga do kryterium sukcesu, najniższe ryzyko, maksymalne użycie istniejącego OSS. Zapisz wybór z uzasadnieniem (5–10 linii) w `docs/MACOS_3D_PLAN.md` razem z listą zadań i statusami. Ten plik jest Twoją pamięcią trwałą.

# FAZA 2 — Implementacja w pętli (aż do sukcesu)
Powtarzaj, dopóki kryterium sukcesu nie jest spełnione:
1. Weź najbliższy punkt kontrolny z `docs/MACOS_3D_PLAN.md`.
2. Rozbij go na niezależne zadania (np. stuby frameworka X, thunki GL, brakujące syscalle/mach traps, warstwa okna). Uruchom agenty implementujące równolegle (worktree-y), każdy z testem akceptacyjnym w `tests/darwin/`.
3. Scal, zbuduj (`ninja -C build`), uruchom test punktu kontrolnego. Wynik porównaj z Maca (`macref.sh`
4. Niepowodzenie → uruchom agenta diagnostycznego (`--trace`, `-v`, lldb na Macu jako orakul, dyld_info, porównanie kolejności wywołań). Napraw PRZYCZYNĘ, nie objaw. Nie wyłączaj testów i nie stubuj na „return 0”, jeśli to ukrywa błąd
(stub dozwolony tylko gdy Mac potwierdza, że wynik nie ma wpływu, i oznacz go w kodzie `// HLE:`).
5. Sukces kroku → commit (zgodnie z zasadami), odhacz w planie, krótka notatka w `docs/HANDOFF.md`.
6. Co ~3 iteracje przeglądnij plan: jeśli ścieżka stoi (ten sam błąd po 3 różnych próbach lub brak postgentów `Plan` z opisem, co próbowano i dlaczego nie wyszło, i zmień strategię (np. P1 → P2, innykandydat aplikacji). Nigdy nie powtarzaj tej samej nieudanej metody.
7. Jeśli kandydat okaże się nieosiągalny (np. wymaga Metal bez bazy OSS), przejdź do następnego kandydaEK działająca aplikacja 3D, nie konkretna.
Nie przerywaj pętli, dopóki: kryterium sukcesu spełnione, albo nie masz realnego ruchu bez decyzji użytkownika. Wtedy opisz dokładnie blokadę i jedno konkretne pytanie.

# KONTROLA JAKOŚCI I KONTEKSTU
- Po każdym scaleniu: `tests/darwin/run_tests.sh` + `tests/guest/run.sh` (krótkie). Regresja w istniejąalszymi krokami.
- Zadbaj o to, żeby `docs/MACOS_3D_PLAN.md` zawsze odzwierciedlał stan (zrobione / w toku / zablokowane / następne). Gdy kontekst się skompresuje, to stamtąd wznowisz pracę.
- Raportuj użytkownikowi krótko na końcu każdej fazy (2–4 zdania), bez zalewania logami.

# ZAKOŃCZENIE
Gdy kryteria 1–5 są spełnione, podaj: nazwę aplikacji, komendę uruchomienia, ścieżkę zrzutu ekranu,
listę dodanych komponentów (frameworki/HLE/thunki), hash commitu, oraz 3 następne najlepsze kroki
(kolejne aplikacje 3D do uruchomienia).

Zrobiłem tu trzy założenia:
- Pierwszy cel to OpenGL, nie Metal. Metal→Vulkan nie ma gotowej bazy open source na Linuksie, więc to ż thunki --host-gl, więc OpenGL jest najkrótszą drogą do pierwszej klatki.
- Agenty konkurują planami. W fazie planowania trzy agenty Plan projektują różne strategie, a Ty wybierasz najlepszą. Dzięki temu pętla nie utknie na pierwszym pomyśle.
- Plan jest zapisany w pliku. docs/MACOS_3D_PLAN.md służy jako pamięć trwała. Po kompresji kontekstu senie od zera.
