#!/bin/sh

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIBXML2_VERSION="master"
ZLIB_VERSION="1.3.1"
LIBICONV_VERSION="1.18"

download() {
    if [ ! -f "zlib-$ZLIB_VERSION.tar.gz" ]; then
        echo "Downloading zlib..."
        wget "https://zlib.net/zlib-$ZLIB_VERSION.tar.gz"
    fi
    if [ ! -f "libiconv-$LIBICONV_VERSION.tar.gz" ]; then
        echo "Downloading libiconv..."
        wget "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-$LIBICONV_VERSION.tar.gz"
    fi
    if [ ! -f "libxml2-$LIBXML2_VERSION.zip" ]; then
        echo "Downloading libxml2..."
        wget "https://github.com/GNOME/libxml2/archive/refs/heads/master.zip" -O "libxml2-$LIBXML2_VERSION.zip"
    fi
}

build_zlib() {
    tar -xzf "$SCRIPT_DIR/zlib-$ZLIB_VERSION.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/zlib-$ZLIB_VERSION"
    ./configure --prefix="$PREFIX" --static
    make -j$(nproc)
    make install
    cd "$BUILD_DIR"
}

build_libiconv() {
    tar -xzf "$SCRIPT_DIR/libiconv-$LIBICONV_VERSION.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/libiconv-$LIBICONV_VERSION"
    ./configure \
        --prefix="$PREFIX" \
        --enable-static \
        --disable-shared \
        --host="$HOST" \
        CC="$CC" \
        CXX="$CXX" \
        CFLAGS="$CFLAGS" \
        CXXFLAGS="$CXXFLAGS" \
        LDFLAGS="$LDFLAGS"
    make -j$(nproc)
    make install
    cd "$BUILD_DIR"
}

build_libxml2() {
    unzip -q "$SCRIPT_DIR/libxml2-$LIBXML2_VERSION.zip" -d "$BUILD_DIR"
    cd "$BUILD_DIR/libxml2-master"
    if [ ! -f configure ]; then
        ./autogen.sh --help >/dev/null 2>&1 || {
            autoreconf -fiv
        }
    fi
    ./configure \
        --prefix="$PREFIX" \
        --enable-static \
        --disable-shared \
        --with-zlib="$PREFIX" \
        --with-iconv="$PREFIX" \
        --without-python \
        --without-readline \
        --without-debug \
        --without-run-debug \
        --without-mem-debug \
        --without-lzma \
        --host="$HOST" \
        CC="$CC" \
        CXX="$CXX" \
        CFLAGS="$CFLAGS -static" \
        CXXFLAGS="$CXXFLAGS -static" \
        LDFLAGS="$LDFLAGS -static" \
        PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    
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
    source "$SCRIPT_DIR/../build_env.sh" "$arch" "$api"
    cd "$BUILD_DIR"
    export LDLFLAGS="LDFLAGS -static"
    export CFLAGS="$LDFLAGS -static"
    export CXXFLAGS="$CXXFLAGS -static"
    build_zlib
    build_libiconv
    build_libxml2
    "$STRIP" "$PREFIX/bin/xmllint" 2>/dev/null || true
    
    cd "$PREFIX"
    tar \
      --owner=0 --group=2000 --numeric-owner \
      --mode=755 \
      --mtime="2020-01-01 00:00Z" \
      --sort=name \
      --pax-option=exthdr.name=/dev/null,delete=atime,delete=ctime \
      -cf - bin/xmllint | zstd -19 > "$SCRIPT_DIR/$arch/xmllint.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum xmllint.tar.zst > sha256sum.txt )
    cd "$SCRIPT_DIR"
    rm -rf "$BUILD_DIR"
}

cd "$SCRIPT_DIR"
download

for arch in arm64-v8a armeabi-v7a x86 x86_64 riscv64; do
    api=21
    [ "$arch" = "riscv64" ] && api=35
    build_arch "$arch" "$api"
done

rm -f "$SCRIPT_DIR/libxml2-$LIBXML2_VERSION.zip"
rm -f "$SCRIPT_DIR/zlib-$ZLIB_VERSION.tar.gz"
rm -f "$SCRIPT_DIR/libiconv-$LIBICONV_VERSION.tar.gz"

cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=${LIBXML2_VERSION}
DESCRIPTION=libxml2 is an XML toolkit implemented in C, originally developed for the GNOME Project.
HOMEPAGE=https://github.com/GNOME/libxml2
MIN_API=21
DEPENDENCIES=
LICENSE=MIT
CONFLICTS=
EOF
