#!/bin/sh

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
OPENSSL_VERSION="3.5.2"
ZLIB_VERSION="1.3.1"

download() {
    if [ ! -f "zlib-$ZLIB_VERSION.tar.gz" ]; then
        echo "Downloading zlib..."
        wget "https://zlib.net/zlib-$ZLIB_VERSION.tar.gz"
    fi
    if [ ! -f "openssl-$OPENSSL_VERSION.tar.gz" ]; then
        echo "Downloading OpenSSL..."
        wget "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"
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

build_openssl() {
    tar -xzf "$SCRIPT_DIR/openssl-$OPENSSL_VERSION.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/openssl-$OPENSSL_VERSION"
    case "$arch" in
        arm64-v8a) openssl_target="android-arm64" ;;
        armeabi-v7a) openssl_target="android-arm" ;;
        x86) openssl_target="android-x86" ;;
        x86_64) openssl_target="android-x86_64" ;;
        riscv64) openssl_target="linux-generic64" ;;
    esac
    ./Configure "$openssl_target" \
        no-tests no-shared -static \
        --prefix="$PREFIX" \
        --with-zlib-include="$PREFIX/include" \
        --with-zlib-lib="$PREFIX/lib"
    make -j$(nproc)
    make install_sw
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
    build_zlib
    build_openssl
    "$STRIP" "$PREFIX/bin/openssl" 2>/dev/null || true
    cd "$PREFIX"
    tar \
      --owner=0 --group=2000 --numeric-owner \
      --mode=755 \
      --mtime="2020-01-01 00:00Z" \
      --sort=name \
      --pax-option=exthdr.name=/dev/null,delete=atime,delete=ctime \
      -cf - bin/openssl | zstd -19 > "$SCRIPT_DIR/$arch/openssl.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum openssl.tar.zst > sha256sum.txt )
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

rm -f "$SCRIPT_DIR/openssl-$OPENSSL_VERSION.tar.gz"
rm -f "$SCRIPT_DIR/zlib-$ZLIB_VERSION.tar.gz"

echo "All builds complete"