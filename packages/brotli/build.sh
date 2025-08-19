#!/bin/sh

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd $SCRIPT_DIR
BROTLI_VERSION="1.1.0"
BROTLI_URL="https://github.com/google/brotli/archive/refs/tags/v${BROTLI_VERSION}.tar.gz"

download() {
    if [ ! -f "v${BROTLI_VERSION}.tar.gz" ]; then
        wget "$BROTLI_URL"
    fi
}

build_brotli() {
    tar -xzf "$SCRIPT_DIR/v${BROTLI_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/brotli-${BROTLI_VERSION}"
    mkdir -p "$PREFIX/bin"
    rm -rf out
    mkdir -p out && cd out
    cmake .. \
        -G "Unix Makefiles" \
        -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake \
        -DANDROID_ABI=$ARCH \
        -DANDROID_PLATFORM=android-$api \
        -DCMAKE_INSTALL_PREFIX=$PREFIX \
        -DBUILD_SHARED_LIBS=OFF \
        -DBROTLI_BUNDLED_MODE=OFF \
        -DBROTLI_DISABLE_TESTS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS -static" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS -static" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS -static"
    make -j"$(nproc)"
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
    build_brotli
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
      -cf - bin | zstd -19 > "$SCRIPT_DIR/$arch/brotli.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum brotli.tar.zst > sha256sum.txt )
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

rm -f "$SCRIPT_DIR/v${BROTLI_VERSION}.tar.gz"

cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=${BROTLI_VERSION}
DESCRIPTION=Brotli is a generic-purpose lossless compression algorithm
HOMEPAGE=https://github.com/google/brotli
MIN_API=21
DEPENDENCIES=
LICENSE=MIT
CONFLICTS=
EOF


echo "All builds complete"
