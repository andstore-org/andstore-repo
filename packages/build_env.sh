#!/bin/sh

set -e

ARCH="${1:-${ARCH}}"
API_LEVEL="${2:-${API_LEVEL:-21}}"

export ANDROID_API=$API_LEVEL
if [ "$ARCH" = "riscv64" ]; then
	if [ "$API_LEVEL" -lt 35 ]; then
		echo "INFO: RISC-V requires minimum API level 35, adjusting from $API_LEVEL to 35"
		API_LEVEL=35
	fi
fi

VALID_ARCHES="armeabi-v7a arm64-v8a x86 x86_64 riscv64"

arch_valid=0
if [ -n "$ARCH" ]; then
	for valid_arch in $VALID_ARCHES; do
		if [ "$ARCH" = "$valid_arch" ]; then
			arch_valid=1
			break
		fi
	done
fi

if [ $arch_valid -eq 0 ]; then
	echo "Usage: $0 <armeabi-v7a|arm64-v8a|x86|x86_64|riscv64> [API_LEVEL] (or set ARCH/API_LEVEL env variables)"
	echo "Default API_LEVEL is 21"
	exit 1
fi

if [ -z "$ANDROID_NDK_ROOT" ] && [ -z "$NDK_ROOT" ] && [ -z "$ANDROID_NDK_HOME" ]; then
	echo "ERROR: Please set ANDROID_NDK_ROOT, NDK_ROOT, or ANDROID_NDK_HOME environment variable"
	exit 1
fi


if [ -n "$ANDROID_NDK_ROOT" ]; then
	NDK_ROOT="$ANDROID_NDK_ROOT"
elif [ -n "$NDK_ROOT" ]; then
	NDK_ROOT="$NDK_ROOT"
else
	NDK_ROOT="$ANDROID_NDK_HOME"
fi

if [ ! -d "$NDK_ROOT" ]; then
	echo "ERROR: NDK directory not found: $NDK_ROOT"
	exit 1
fi

case "$ARCH" in
	armeabi-v7a)
		HOST=arm-linux-androideabi
		ANDROID_ABI=armeabi-v7a
		RUST_TARGET=armv7-linux-androideabi
		CLANG_TARGET=armv7a-linux-androideabi${API_LEVEL}
		;;
	arm64-v8a)
		HOST=aarch64-linux-android
		ANDROID_ABI=arm64-v8a
		RUST_TARGET=aarch64-linux-android
		CLANG_TARGET=aarch64-linux-android${API_LEVEL}
		;;
	x86)
		HOST=i686-linux-android
		ANDROID_ABI=x86
		RUST_TARGET=i686-linux-android
		CLANG_TARGET=i686-linux-android${API_LEVEL}
		;;
	x86_64)
		HOST=x86_64-linux-android
		ANDROID_ABI=x86_64
		RUST_TARGET=x86_64-linux-android
		CLANG_TARGET=x86_64-linux-android${API_LEVEL}
		;;
	riscv64)
		HOST=riscv64-linux-android
		ANDROID_ABI=riscv64
		RUST_TARGET=riscv64-linux-android
		CLANG_TARGET=riscv64-linux-android${API_LEVEL}
		;;
	*)
		echo "Unsupported architecture: $ARCH"
		exit 1
		;;
esac

TOOLCHAIN_PREFIX=""
for host_arch in linux-x86_64 darwin-x86_64 darwin-arm64 windows-x86_64; do
	candidate="$NDK_ROOT/toolchains/llvm/prebuilt/$host_arch"
	if [ -d "$candidate" ]; then
		TOOLCHAIN_PREFIX="$candidate"
		break
	fi
done

if [ -z "$TOOLCHAIN_PREFIX" ]; then
	echo "ERROR: Could not find NDK toolchain directory in $NDK_ROOT/toolchains/llvm/prebuilt/"
	exit 1
fi


CC="${TOOLCHAIN_PREFIX}/bin/${CLANG_TARGET}-clang"
CXX="${TOOLCHAIN_PREFIX}/bin/${CLANG_TARGET}-clang++"
AR="${TOOLCHAIN_PREFIX}/bin/llvm-ar"
RANLIB="${TOOLCHAIN_PREFIX}/bin/llvm-ranlib"
STRIP="${TOOLCHAIN_PREFIX}/bin/llvm-strip"
NM="${TOOLCHAIN_PREFIX}/bin/llvm-nm"
STRINGS="${TOOLCHAIN_PREFIX}/bin/llvm-strings"
AS="${TOOLCHAIN_PREFIX}/bin/llvm-as"
PROFDATA="${TOOLCHAIN_PREFIX}/bin/llvm-profdata"

full_path() {
	tool_name="$1"
	if command -v "$tool_name" >/dev/null 2>&1; then
		command -v "$tool_name"
	elif [ -x "$tool_name" ]; then
		echo "$tool_name"
	else
		echo "ERROR: Tool '$tool_name' not found or not executable" >&2
		exit 1
	fi
}

CC_ABS=$(full_path "$CC")
CXX_ABS=$(full_path "$CXX")
AR_ABS=$(full_path "$AR")
RANLIB_ABS=$(full_path "$RANLIB")
STRIP_ABS=$(full_path "$STRIP")
NM_ABS=$(full_path "$NM")


SIZE_CFLAGS="-Os -ffunction-sections -fdata-sections"
SIZE_CXXFLAGS="-Os -ffunction-sections -fdata-sections"
SIZE_LDFLAGS="-Wl,--gc-sections"


CFLAGS="$SIZE_CFLAGS -DNDEBUG -fPIC"
CXXFLAGS="$SIZE_CXXFLAGS -DNDEBUG -fPIC"
CPPFLAGS="-I$PREFIX/include -DNDEBUG"
LDFLAGS="$SIZE_LDFLAGS -fPIC"
SYSROOT="$TOOLCHAIN_PREFIX/sysroot"
RUSTFLAGS="-C target-feature=+crt-static -C relocation-model=pic"


export CC CXX AR RANLIB STRIP NM STRINGS AS PROFDATA
export CFLAGS CXXFLAGS CPPFLAGS LDFLAGS SYSROOT RUSTFLAGS
export ANDROID_ABI HOST RUST_TARGET API_LEVEL PREFIX
export PATH=${TOOLCHAIN_PREFIX}/bin:$PATH

echo "Build environment configured for:"
echo "  Architecture: $ARCH ($ANDROID_ABI)"
echo "  API Level: $API_LEVEL"
echo "  NDK Root: $NDK_ROOT"
echo "  Toolchain: $TOOLCHAIN_PREFIX"
echo "  Install Prefix: $PREFIX"
