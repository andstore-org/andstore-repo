#!/bin/sh
set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
setup_rust() {
    if ! rustup target list --installed | grep -q "^$RUST_TARGET$"; then
        rustup target add "$RUST_TARGET" || exit 1
    fi
}
download() {
    if [ ! -d "abx2xml-rs" ]; then
        git clone https://github.com/rhythmcache/abx2xml-rs.git --depth 1   
    fi
}

build_arch() {
    arch="$1"
    api="$2"
    mkdir -p "$SCRIPT_DIR/$arch"
    BUILD_DIR="$SCRIPT_DIR/build_$arch"
    PREFIX="$BUILD_DIR/install"
    rm -rf "$BUILD_DIR"
    mkdir -p "$PREFIX/bin"
    export PREFIX
    source "$SCRIPT_DIR/../build_env.sh" "$arch" "$api"
    export CFLAGS="$CFLAGS -static"
    export CXXFLAGS="$CXXFLAGS -static"
    export LDFLAGS="$LDFLAGS -static"
    setup_rust
    mkdir -p "$SCRIPT_DIR/abx2xml-rs/.cargo"
    cat > "$SCRIPT_DIR/abx2xml-rs/.cargo/config.toml" <<EOF
[target.$RUST_TARGET]
linker = "$CC_ABS"
ar = "$AR"

rustflags = [
  "-C", "link-arg=-static",
]
EOF

    cd "$SCRIPT_DIR/abx2xml-rs"
    cargo build --release --target "$RUST_TARGET"

    cp "target/$RUST_TARGET/release/abx2xml" "$PREFIX/bin/"
    if [ -f "$PREFIX/bin/abx2xml" ]; then
        "$STRIP" "$PREFIX/bin/abx2xml" 2>/dev/null || true
    fi

    cd "$PREFIX"
    tar \
  --owner=0 --group=2000 --numeric-owner \
  --mode=755 \
  --mtime="2020-01-01 00:00Z" \
  --sort=name \
  --pax-option=exthdr.name=/dev/null,delete=atime,delete=ctime \
  -cf - bin | zstd -19 > "$SCRIPT_DIR/$arch/abx2xml.tar.zst"
  ( cd "$SCRIPT_DIR/$arch" && sha256sum abx2xml.tar.zst > sha256sum.txt )
cd "$SCRIPT_DIR"


    rm -rf "$BUILD_DIR"
}


cd "$SCRIPT_DIR"
download

for arch in arm64-v8a armeabi-v7a x86 x86_64; do
    api=21
    build_arch "$arch" "$api"
done

cat > "$SCRIPT_DIR/INFO" <<EOF
VERSION=0.1.2
DESCRIPTION=Rust Library to decode android binary xml
HOMEPAGE=https://github.com/rhythmcache/abx2xml-rs
MIN_API=21
DEPENDENCIES=
LICENSE=Apache 2
CONFLICTS=
EOF


rm -rf "${SCRIPT_DIR}/abx2xml-rs"

echo "All builds complete"
