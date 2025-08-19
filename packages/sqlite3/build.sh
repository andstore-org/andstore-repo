#!/bin/sh

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd $SCRIPT_DIR

download() {
    if [ ! -f "sqlite-autoconf-3500400.tar.gz" ]; then
        wget "https://www.sqlite.org/2025/sqlite-autoconf-3500400.tar.gz"
    fi
}

build_sqlite() {
    tar -xzf "$SCRIPT_DIR/sqlite-autoconf-3500400.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/sqlite-autoconf-3500400"
    mkdir -p "$PREFIX/bin"
    $CC_ABS $CFLAGS \
        -DSQLITE_ENABLE_FTS3 \
        -DSQLITE_ENABLE_FTS4 \
        -DSQLITE_ENABLE_FTS5 \
        -DSQLITE_ENABLE_JSON1 \
        -DSQLITE_ENABLE_RTREE \
        -DSQLITE_ENABLE_UPDATE_DELETE_LIMIT \
        -DSQLITE_ENABLE_MATH_FUNCTIONS \
        -static -lm -ldl \
        sqlite3.c shell.c -o "$PREFIX/bin/sqlite3"
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
    build_sqlite
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
      -cf - bin | zstd -19 > "$SCRIPT_DIR/$arch/sqlite3.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum sqlite3.tar.zst > sha256sum.txt )
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

rm -f "$SCRIPT_DIR/sqlite-autoconf-3500400.tar.gz"

cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=3500400
DESCRIPTION=SQLite is a C-language library that implements a small, fast, self-contained, high-reliability, full-featured, SQL database engine.
HOMEPAGE=https://sqlite.org/
MIN_API=21
DEPENDENCIES=
LICENSE=Public Domain
CONFLICTS=
EOF


echo "All builds complete"