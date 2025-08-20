#!/bin/sh

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd $SCRIPT_DIR

ZSTD_VERSION="1.5.7"
ZSTD_URL="https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz"

download() {
    if [ ! -f "zstd-${ZSTD_VERSION}.tar.gz" ]; then
        wget "$ZSTD_URL"
    fi
}

build_zstd() {
    tar -xzf "$SCRIPT_DIR/zstd-${ZSTD_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/zstd-${ZSTD_VERSION}"
    export CFLAGS="$CFLAGS -static"
    export LDFLAGS="$LDFLAGS -static"
    make -j$(nproc) CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" zstd-release
    mkdir -p "$PREFIX/bin"
    cp zstd "$PREFIX/bin/"
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
    build_zstd
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
      -cf - bin | zstd -19 > "$SCRIPT_DIR/$arch/zstd.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum zstd.tar.zst > sha256sum.txt )
    cd "$SCRIPT_DIR"
    rm -rf "$BUILD_DIR"
}

cd "$SCRIPT_DIR"

download

for arch in arm64-v8a armeabi-v7a x86 x86_64 riscv64; do
    api=24
    [ "$arch" = "riscv64" ] && api=35
    build_arch "$arch" "$api"
done

rm -f "$SCRIPT_DIR/zstd-${ZSTD_VERSION}.tar.gz"

cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=${ZSTD_VERSION}
DESCRIPTION=Zstandard is a real-time compression algorithm, providing high compression ratios.
HOMEPAGE=https://facebook.github.io/zstd/
MIN_API=24
DEPENDENCIES=
LICENSE=BSD-3-Clause
CONFLICTS=
EOF
