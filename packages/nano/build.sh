#!/bin/sh
set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
NCURSES_VERSION="6.5"
FILE_VERSION="5.46"  
NANO_VERSION="8.5" 

download() {
    if [ ! -f "ncurses-$NCURSES_VERSION.tar.gz" ]; then
        wget "https://ftp.gnu.org/gnu/ncurses/ncurses-$NCURSES_VERSION.tar.gz"
    fi
    if [ ! -f "file-$FILE_VERSION.tar.gz" ]; then
        wget "https://astron.com/pub/file/file-$FILE_VERSION.tar.gz"
    fi
    if [ ! -f "nano-$NANO_VERSION.tar.xz" ]; then
        wget "https://www.nano-editor.org/dist/v$(echo $NANO_VERSION | cut -d. -f1)/nano-$NANO_VERSION.tar.xz"
    fi
}

build_ncurses() {
    tar -xzf "$SCRIPT_DIR/ncurses-$NCURSES_VERSION.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/ncurses-$NCURSES_VERSION"
    
    ./configure \
        --prefix="$PREFIX" \
        --host="$HOST" \
        --enable-static \
        --disable-shared \
        --without-ada \
        --without-cxx \
        --with-termlib \
        --without-cxx-binding \
        --without-manpages \
        --without-progs \
        --without-tests \
        --with-fallbacks=linux,screen,screen-256color,tmux,tmux-256color,vt100,xterm,xterm-256color \
        --enable-widec \
        --disable-database \
        --with-default-terminfo-dir=/system/etc/terminfo
    
    make -j$(nproc)
    make install
    cd "$PREFIX/lib"
    ln -sf libtinfow.a libtinfo.a
    ln -sf libncursesw.a libncurses.a
    cd "$PREFIX/include" && ln -s ncursesw ncurses
    cd "$BUILD_DIR"
}


build_file() {
    tar -xzf "$SCRIPT_DIR/file-$FILE_VERSION.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/file-$FILE_VERSION"

    extra_conf=""
    case "$arch" in
        armeabi-v7a|x86)
            extra_conf="--disable-year2038"
            ;;
    esac

    ./configure \
        --prefix="$PREFIX" \
        --host="$HOST" \
        --enable-static \
        --disable-shared \
        --disable-libseccomp \
        --disable-zlib \
        $extra_conf

    make -j$(nproc) FILE_COMPILE=$(which file)
    make install
    cd "$BUILD_DIR"
}

build_nano() {
    tar -xJf "$SCRIPT_DIR/nano-$NANO_VERSION.tar.xz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/nano-$NANO_VERSION"
    
    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
    export CPPFLAGS="-I$PREFIX/include -I$PREFIX/include/ncursesw $CPPFLAGS"
    export LDFLAGS="-L$PREFIX/lib $LDFLAGS"
    
    ./configure \
        --prefix="$PREFIX" \
        --host="$HOST" \
        --enable-color \
        --enable-nanorc \
        --enable-multibuffer \
        --enable-utf8 \
        --disable-browser \
        --disable-help \
        --disable-nls \
        --disable-mouse \
        --disable-operatingdir \
        --disable-speller \
        --disable-justify \
        --disable-debug \
        LIBS="-lncursesw -ltinfo -lmagic"
    
    make -j$(nproc)
    make install
    cd "$BUILD_DIR"
}

build_arch() {
    arch="$1"
    api="$2"
    mkdir -p "$SCRIPT_DIR/$arch"
    BUILD_DIR="$SCRIPT_DIR/build_$arch"
    PREFIX="$BUILD_DIR/install"
    rm -rf "$BUILD_DIR"
    mkdir -p "$PREFIX"
    export PREFIX
    export BUILD_DIR
    source "$SCRIPT_DIR/../build_env.sh" "$arch" "$api"
    cd "$BUILD_DIR"
    export CFLAGS="$CFLAGS -static"
    export LDFLAGS="$LDFLAGS -static"
    export CXXFLAGS="$CXXFLAGS -static"
    build_ncurses
    build_file
    build_nano
    "$STRIP" "$PREFIX/bin/nano" 2>/dev/null || true
    cd "$PREFIX"
    tar \
      --owner=0 --group=2000 --numeric-owner \
      --mode=755 \
      --mtime="2020-01-01 00:00Z" \
      --sort=name \
      --pax-option=exthdr.name=/dev/null,delete=atime,delete=ctime \
      -cf - bin/nano | zstd -19 > "$SCRIPT_DIR/$arch/nano.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum nano.tar.zst > sha256sum.txt )
    
    cd "$SCRIPT_DIR"
    rm -rf "$BUILD_DIR"
}

cd "$SCRIPT_DIR"

download

for arch in arm64-v8a armeabi-v7a x86 x86_64 riscv64; do
    api=28
    [ "$arch" = "riscv64" ] && api=35
    build_arch "$arch" "$api"
done

rm -f "$SCRIPT_DIR/ncurses-$NCURSES_VERSION.tar.gz"
rm -f "$SCRIPT_DIR/file-$FILE_VERSION.tar.gz"
rm -f "$SCRIPT_DIR/nano-$NANO_VERSION.tar.xz"

cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=$NANO_VERSION
DESCRIPTION=GNU nano is a small editor for on the terminal.
HOMEPAGE=https://www.nano-editor.org/
MIN_API=$api
DEPENDENCIES=
LICENSE=GPLv3
CONFLICTS=
EOF
