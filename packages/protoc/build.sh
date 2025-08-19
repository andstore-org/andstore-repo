#!/bin/sh

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd $SCRIPT_DIR
PROTOC_VERSION="32.0"
PROTOC_URL="https://github.com/protocolbuffers/protobuf/releases/download/v32.0/protobuf-32.0.tar.gz"
ZLIB_VERSION="1.3.1"

download() {
     if [ ! -f "zlib-$ZLIB_VERSION.tar.gz" ]; then
        wget "https://zlib.net/zlib-$ZLIB_VERSION.tar.gz"
    fi
    if [ ! -f "protobuf-32.0.tar.gz" ]; then
        wget "$PROTOC_URL"
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

build_protoc() {
    tar -xzf "$SCRIPT_DIR/protobuf-32.0.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/protobuf-32.0"
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
        -Dprotobuf_BUILD_TESTS=OFF \
        -Dprotobuf_BUILD_EXAMPLES=OFF \
        -Dprotobuf_BUILD_SHARED_LIBS=OFF \
        -Dprotobuf_WITH_ZLIB=ON \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
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
    build_zlib
     export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
    build_protoc
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
      -cf - bin | zstd -19 > "$SCRIPT_DIR/$arch/protoc.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum protoc.tar.zst > sha256sum.txt )
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

rm -f "$SCRIPT_DIR/protobuf-32.0.tar.gz"

cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=${PROTOC_VERSION}
DESCRIPTION=Protocol Buffers - Google's data interchange format
HOMEPAGE=https://github.com/protocolbuffers/protobuf
MIN_API=21
DEPENDENCIES=
LICENSE=BSD 3-Clause License
CONFLICTS=
EOF


echo "All builds complete"
