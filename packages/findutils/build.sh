#!/bin/sh

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd $SCRIPT_DIR

FIND_VERSION="4.10.0"
FIND_URL="https://ftp.gnu.org/gnu/findutils/findutils-${FIND_VERSION}.tar.xz"

download() {
    if [ ! -f "findutils-${FIND_VERSION}.tar.xz" ]; then
        wget "$FIND_URL"
    fi
}

build_find() {
    tar -xvf "$SCRIPT_DIR/findutils-${FIND_VERSION}.tar.xz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/findutils-${FIND_VERSION}"
    export CFLAGS="$CFLAGS -static"
    export LDFLAGS="$LDFLAGS -static"

      extra_conf=""
    case "$arch" in
        armeabi-v7a|x86)
            extra_conf="--disable-year2038"
            ;;
    esac

    ./configure \
    --host="$HOST" \
    --prefix="$PREFIX" \
      $extra_conf

    make -j$(nproc)
    mkdir -p "$PREFIX/bin"
    cp ./xargs/xargs "$PREFIX/bin"
    cp ./find/find "$PREFIX/bin"
    cp ./locate/updatedb "$PREFIX/bin"
    cp ./locate/locate "$PREFIX/bin"
    
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
    build_find
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
      -cf - bin | zstd -19 > "$SCRIPT_DIR/$arch/findutils.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum findutils.tar.zst > sha256sum.txt )
    cd "$SCRIPT_DIR"
    rm -rf "$BUILD_DIR"
}

cd "$SCRIPT_DIR"

download

for arch in arm64-v8a armeabi-v7a x86 x86_64 riscv64; do
    api=35
    [ "$arch" = "riscv64" ] && api=35
    build_arch "$arch" "$api"
done

rm -f "$SCRIPT_DIR/findutils-${FIND_VERSION}.tar.xz"

cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=${FIND_VERSION}
DESCRIPTION=The GNU Find Utilities are the basic directory searching utilities of the GNU operating system.
HOMEPAGE=
MIN_API=35
DEPENDENCIES=
LICENSE=GPLv2+
CONFLICTS=
EOF
