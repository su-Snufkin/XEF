#!/bin/bash
# Third-party dylibs that macOS ships in /usr/lib (zlib, bzip2, xz, libiconv, expat, libxml2, sqlite3, ncurses, libffi),
# built from upstream sources on the remote Mac with the same install names/sonames -> ./darwin-rootfs/usr/lib.
set -e
cd "$(dirname "$0")/.."
ssh mac 'bash -s' <<'REMOTE'
set +e
W=$HOME/xef-remote/src/deps; O=$HOME/xef-remote/out/rootfs/usr/lib; mkdir -p $W $O; cd $W
export MACOSX_DEPLOYMENT_TARGET=12.0
CF="-arch arm64 -mmacosx-version-min=12.0 -O2"
get() { # url file
  test -f "$2" || curl -fsSL -o "$2" "$1" || { rm -f "$2"; echo "download failed: $1"; return 1; }; }
build_ac() { # name tarball url dir extra-configure
  get "$3" "$2"; test -d "$4" || tar xf "$2"
  (cd "$4" && test -f config.status || ./configure --prefix=$W/inst/$1 --disable-static --enable-shared CFLAGS="$CF" LDFLAGS="-arch arm64" $5 >/dev/null 2>&1; make -j8 >/dev/null 2>&1; make install >/dev/null 2>&1)
}
# zlib
get https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz zlib.tgz; test -d zlib-1.3.1 || tar xzf zlib.tgz
(cd zlib-1.3.1 && CFLAGS="$CF" ./configure --prefix=$W/inst/zlib >/dev/null && make -j8 libz.1.3.1.dylib >/dev/null 2>&1 || true)
clang $CF -dynamiclib -install_name /usr/lib/libz.1.dylib -compatibility_version 1.0.0 -current_version 1.3.1 zlib-1.3.1/*.c -o $O/libz.1.dylib 2>&1 | grep -E "error" | head -3 || true
ls zlib-1.3.1/*.c >/dev/null 2>&1 || true
# bzip2
get https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz bz2.tgz; test -d bzip2-1.0.8 || tar xzf bz2.tgz
(cd bzip2-1.0.8 && clang $CF -dynamiclib -install_name /usr/lib/libbz2.1.0.dylib -compatibility_version 1.0.0 -current_version 1.0.8 blocksort.c huffman.c crctable.c randtable.c compress.c decompress.c bzlib.c -o $O/libbz2.1.0.dylib 2>&1 | grep -E "error" | head -3 || true)
# xz / liblzma
get https://github.com/tukaani-project/xz/releases/download/v5.6.2/xz-5.6.2.tar.gz xz.tgz; test -d xz-5.6.2 || tar xzf xz.tgz
(cd xz-5.6.2 && test -f config.status || ./configure --prefix=$W/inst/xz --disable-static --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc CFLAGS="$CF" LDFLAGS="-arch arm64" >/dev/null 2>&1; make -j8 >/dev/null 2>&1; make install >/dev/null 2>&1)
cp $W/inst/xz/lib/liblzma.5.dylib $O/liblzma.5.dylib 2>/dev/null && install_name_tool -id /usr/lib/liblzma.5.dylib $O/liblzma.5.dylib || true
# libiconv
get https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz iconv.tgz; test -d libiconv-1.17 || tar xzf iconv.tgz
(cd libiconv-1.17 && test -f config.status || ./configure --prefix=$W/inst/iconv --disable-static CFLAGS="$CF" LDFLAGS="-arch arm64" >/dev/null 2>&1; make -j8 >/dev/null 2>&1; make install >/dev/null 2>&1)
cp $W/inst/iconv/lib/libiconv.2.dylib $O/libiconv.2.dylib 2>/dev/null && install_name_tool -id /usr/lib/libiconv.2.dylib $O/libiconv.2.dylib || true
cp $W/inst/iconv/lib/libcharset.1.dylib $O/libcharset.1.dylib 2>/dev/null && install_name_tool -id /usr/lib/libcharset.1.dylib $O/libcharset.1.dylib || true
# expat
get https://github.com/libexpat/libexpat/releases/download/R_2_6_2/expat-2.6.2.tar.gz expat.tgz; test -d expat-2.6.2 || tar xzf expat.tgz
(cd expat-2.6.2 && test -f config.status || ./configure --prefix=$W/inst/expat --disable-static CFLAGS="$CF" LDFLAGS="-arch arm64" >/dev/null 2>&1; make -j8 >/dev/null 2>&1; make install >/dev/null 2>&1)
cp $W/inst/expat/lib/libexpat.1.dylib $O/ 2>/dev/null && install_name_tool -id /usr/lib/libexpat.1.dylib $O/libexpat.1.dylib || true
# sqlite3 (amalgamation)
get https://www.sqlite.org/2024/sqlite-amalgamation-3460100.zip sqlite.zip; test -d sqlite-amalgamation-3460100 || unzip -q sqlite.zip
clang $CF -dynamiclib -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_RTREE -DSQLITE_THREADSAFE=1 -install_name /usr/lib/libsqlite3.dylib -compatibility_version 9.0.0 -current_version 9.6.0 sqlite-amalgamation-3460100/sqlite3.c -o $O/libsqlite3.dylib 2>&1 | grep -E "error" | head -3 || true
# libxml2
get https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.9.tar.xz xml2.txz; test -d libxml2-2.12.9 || tar xf xml2.txz
(cd libxml2-2.12.9 && test -f config.status || ./configure --prefix=$W/inst/xml2 --disable-static --without-python --without-lzma --with-zlib=$W/inst/zlib --with-iconv=$W/inst/iconv CFLAGS="$CF" LDFLAGS="-arch arm64" >/dev/null 2>&1; make -j8 >/dev/null 2>&1; make install >/dev/null 2>&1)
cp $W/inst/xml2/lib/libxml2.2.dylib $O/ 2>/dev/null && install_name_tool -id /usr/lib/libxml2.2.dylib $O/libxml2.2.dylib && install_name_tool -change $W/inst/zlib/lib/libz.1.dylib /usr/lib/libz.1.dylib -change $W/inst/iconv/lib/libiconv.2.dylib /usr/lib/libiconv.2.dylib $O/libxml2.2.dylib 2>/dev/null || true
# libffi
get https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz ffi.tgz; test -d libffi-3.4.6 || tar xzf ffi.tgz
(cd libffi-3.4.6 && test -f config.status || ./configure --prefix=$W/inst/ffi --disable-static CFLAGS="$CF" LDFLAGS="-arch arm64" >/dev/null 2>&1; make -j8 >/dev/null 2>&1; make install >/dev/null 2>&1)
cp $W/inst/ffi/lib/libffi.8.dylib $O/libffi.dylib 2>/dev/null && install_name_tool -id /usr/lib/libffi.dylib $O/libffi.dylib || true
# ncurses
get https://ftp.gnu.org/pub/gnu/ncurses/ncurses-6.4.tar.gz ncurses.tgz; test -d ncurses-6.4 || tar xzf ncurses.tgz
(cd ncurses-6.4 && test -f config.status || ./configure --prefix=$W/inst/ncurses --with-shared --without-debug --without-ada --without-cxx-binding --without-manpages --enable-widec=no --with-termlib CFLAGS="$CF" LDFLAGS="-arch arm64" >/dev/null 2>&1; make -j8 >/dev/null 2>&1; make install >/dev/null 2>&1)
for l in ncurses panel form menu; do f=$(ls $W/inst/ncurses/lib/lib$l.6.dylib 2>/dev/null | head -1); [ -n "$f" ] && cp $f $O/lib$l.5.4.dylib && install_name_tool -id /usr/lib/lib$l.5.4.dylib $O/lib$l.5.4.dylib || true; done
ln -sf libncurses.5.4.dylib $O/libcurses.dylib 2>/dev/null || true
ls -la $O | grep -E "libz|bz2|lzma|iconv|charset|expat|sqlite|xml2|ffi|ncurses|panel" 
REMOTE
mkdir -p darwin-rootfs/usr/lib
rsync -a --include='libz*' --include='libbz2*' --include='liblzma*' --include='libiconv*' --include='libcharset*' --include='libexpat*' --include='libsqlite3*' --include='libxml2*' --include='libffi*' --include='libncurses*' --include='libpanel*' --include='libform*' --include='libmenu*' --include='libcurses*' --exclude='*' mac:xef-remote/out/rootfs/usr/lib/ darwin-rootfs/usr/lib/
