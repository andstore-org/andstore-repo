#!/bin/sh

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd $SCRIPT_DIR

BZIP2_VERSION="1.0.8"
BZIP2_URL="https://sourceware.org/pub/bzip2/bzip2-${BZIP2_VERSION}.tar.gz"

download() {
    if [ ! -f "bzip2-${BZIP2_VERSION}.tar.gz" ]; then
        wget "$BZIP2_URL"
    fi
}

build_bzip2() {
    tar -xzf "$SCRIPT_DIR/bzip2-${BZIP2_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/bzip2-${BZIP2_VERSION}"
    export CFLAGS="$CFLAGS -static"
    export LDFLAGS="$LDFLAGS -static"
    make -j$(nproc) CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" bzip2 bzip2recover
    make install PREFIX="$PREFIX"
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
    build_bzip2
    
    if [ -d "$PREFIX/bin" ]; then
        for f in "$PREFIX/bin/"*; do
            if [ -f "$f" ] && [ -x "$f" ]; then
                "$STRIP" "$f" 2>/dev/null || true
            fi
        done
    fi
    cd "$PREFIX"
    tar \
      --owner=0 --group=2000 --numeric-owner \
      --mode=755 \
      --mtime="2020-01-01 00:00Z" \
      --sort=name \
      --pax-option=exthdr.name=/dev/null,delete=atime,delete=ctime \
      -cf - bin | zstd -19 > "$SCRIPT_DIR/$arch/bzip2.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum bzip2.tar.zst > sha256sum.txt )
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

rm -f "$SCRIPT_DIR/bzip2-${BZIP2_VERSION}.tar.gz"

cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=${BZIP2_VERSION}
DESCRIPTION=bzip2 is a free and open-source file compression program that uses the Burrows–Wheeler algorithm.
HOMEPAGE=https://sourceware.org/bzip2/
MIN_API=21
DEPENDENCIES=
LICENSE=
CONFLICTS=
EOF
