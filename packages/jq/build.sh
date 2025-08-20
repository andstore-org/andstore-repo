#!/bin/sh

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd $SCRIPT_DIR
JQ_V="1.8.1"
download() {
    if [ ! -f "jq-${JQ_V}.tar.gz" ]; then
        wget "https://github.com/jqlang/jq/releases/download/jq-${JQ_V}/jq-${JQ_V}.tar.gz"
    fi
}

build_jq() {
    tar -xzf "$SCRIPT_DIR/jq-${JQ_V}.tar.gz" -C "$BUILD_DIR"
    cd "$BUILD_DIR/jq-${JQ_V}"
    export CFLAGS="$CFLAGS -static"
    export LDFLAGS="$LDFLAGS -static"
   # [ -f "configure.ac" ] && autoreconf -i
    ./configure --with-oniguruma=builtin --prefix="${PREFIX}" --host="${HOST}" --enable-decnum --enable-static --enable-all-static --disable-docs
    make -j$(nproc)
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
    build_jq
    
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
      -cf - bin | zstd -19 > "$SCRIPT_DIR/$arch/jq.tar.zst"
    ( cd "$SCRIPT_DIR/$arch" && sha256sum jq.tar.zst > sha256sum.txt )
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

rm -f "$SCRIPT_DIR/jq-${JQ_V}.tar.gz"

cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=${JQ_V}
DESCRIPTION=Command-line JSON processor
HOMEPAGE=https://jqlang.org/
MIN_API=21
DEPENDENCIES=
LICENSE=MIT
CONFLICTS=
EOF

echo "All builds complete"
