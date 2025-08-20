#!/bin/sh

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd $SCRIPT_DIR

TREE_VERSION="2.2.1"
TREE_URL="https://gitlab.com/OldManProgrammer/unix-tree/-/archive/2.2.1/unix-tree-${TREE_VERSION}.tar.bz2"

download() {
    if [ ! -f "unix-tree-${TREE_VERSION}.tar.bz2" ]; then
        wget "$TREE_URL"
    fi
}

build_tree() {
    tar -xvf "$SCRIPT_DIR/unix-tree-${TREE_VERSION}.tar.bz2" -C "$BUILD_DIR"
    cd "$BUILD_DIR/unix-tree-${TREE_VERSION}"
    export CFLAGS="$CFLAGS -static"
    export LDFLAGS="$LDFLAGS -static"
    make -j$(nproc) CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
    mkdir -p "$PREFIX/bin"
    cp tree "$PREFIX/bin/"
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
    build_tree
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
      -cf - bin | zstd -19 > "$SCRIPT_DIR/$arch/tree.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum tree.tar.zst > sha256sum.txt )
    cd "$SCRIPT_DIR"
    rm -rf "$BUILD_DIR"
}

cd "$SCRIPT_DIR"

download

for arch in arm64-v8a armeabi-v7a x86 x86_64 riscv64; do
    api=26
    [ "$arch" = "riscv64" ] && api=35
    build_arch "$arch" "$api"
done

rm -f "$SCRIPT_DIR/unix-tree-${TREE_VERSION}.tar.bz2"

cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=${TREE_VERSION}
DESCRIPTION=The tree application is useful to display a dictionary tree's contents, including files, directories, and links.
HOMEPAGE=
MIN_API=26
DEPENDENCIES=
LICENSE=GPLv2+
CONFLICTS=
EOF
