#!/bin/sh

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
XZ_VERSION="5.8.1"

download() {
    if [ ! -f "xz-${XZ_VERSION}.tar.gz" ]; then
        wget "https://github.com/tukaani-project/xz/releases/download/v5.8.1/xz-${XZ_VERSION}.tar.gz"
    fi
}

build_xz() {
    tar -xzf "$SCRIPT_DIR/xz-${XZ_VERSION}.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/xz-$XZ_VERSION"
    ./configure \
		--host="$HOST" \
		--prefix="$PREFIX" \
		--enable-static \
		--disable-shared \
		CC="$CC_ABS" \
		CFLAGS="$CFLAGS -static" \
		CXXFLAGS="$CXXFLAGS -static" \
		LDFLAGS="$LDFLAGS -static"
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
    build_xz
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
      -cf - bin | zstd -19 > "$SCRIPT_DIR/$arch/xz.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum xz.tar.zst > sha256sum.txt )
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

rm -f "$SCRIPT_DIR/xz-$XZ_VERSION.tar.gz"

cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=$XZ_VERSION
DESCRIPTION=XZ-Utils
HOMEPAGE=https://tukaani.org/xz/
MIN_API=21
DEPENDENCIES=
LICENSE=BSD Zero Clause License
CONFLICTS=
EOF


echo "All builds complete"