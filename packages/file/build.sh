#!/bin/sh
set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FILE_VERSION="5.46" 
download() {
    if [ ! -f "file-$FILE_VERSION.tar.gz" ]; then
        wget "https://astron.com/pub/file/file-$FILE_VERSION.tar.gz"
    fi
}

build_file() {
    tar -xzf "$SCRIPT_DIR/file-$FILE_VERSION.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/file-$FILE_VERSION"
     sed -i 's/LT_INIT(\[disable-static pic-only\])/LT_INIT([static])/g' configure.ac
     autoreconf -fi
    ./configure \
    --prefix="$PREFIX" \
    --host="$HOST" \
    --enable-static \
    --disable-shared \
    --disable-libseccomp \
    --disable-zlib 

    make -j$(nproc) FILE_COMPILE=$(which file) LDFLAGS="-all-static"

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
    build_file
    "$STRIP" "$PREFIX/bin/file" 2>/dev/null || true
    cd "$PREFIX"
    tar \
      --owner=0 --group=2000 --numeric-owner \
      --mode=755 \
      --mtime="2020-01-01 00:00Z" \
      --sort=name \
      --pax-option=exthdr.name=/dev/null,delete=atime,delete=ctime \
      -cf - bin/file | zstd -19 > "$SCRIPT_DIR/$arch/file.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum file.tar.zst > sha256sum.txt )
    
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

rm -f "$SCRIPT_DIR/file-$FILE_VERSION.tar.gz"
cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=$FILE_VERSION
DESCRIPTION=file is a shell command for reporting the type of data contained in a file.
HOMEPAGE=https://www.darwinsys.com/file/
MIN_API=$api
DEPENDENCIES=
LICENSE=BSD Clause 2
CONFLICTS=
EOF

