#!/usr/bin/env bash
set -euo pipefail

JOBS="${JOBS:-$(nproc)}"
OUT_DIR="${OUT_DIR:-/out}"
SRC_DIR="${SRC_DIR:-/work/fastfetch}"
NDK_DIR="${ANDROID_NDK_HOME:-/opt/android-ndk}"
BUILD_ROOT="${BUILD_ROOT:-/work/build}"
BUILD_TARGETS="${BUILD_TARGETS:-}"

TOOLCHAIN="${NDK_DIR}/build/cmake/android.toolchain.cmake"
STRIP="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"

if [[ ! -f "${TOOLCHAIN}" ]]; then
    echo "NDK toolchain not found at ${TOOLCHAIN}" >&2
    exit 1
fi

mkdir -p "${OUT_DIR}" "${BUILD_ROOT}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUB_SRC="${SCRIPT_DIR}/src/android-stubs"
STUB_DIR="${BUILD_ROOT}/android-include-stub"

cp -r "${STUB_SRC}/." "${STUB_DIR}/"

DISABLE_FLAGS=(
    -DENABLE_VULKAN=OFF
    -DENABLE_WAYLAND=OFF
    -DENABLE_XCB_RANDR=OFF
    -DENABLE_XRANDR=OFF
    -DENABLE_DRM=OFF
    -DENABLE_VA=OFF
    -DENABLE_VDPAU=OFF
    -DENABLE_DRM_AMDGPU=OFF
    -DENABLE_GIO=OFF
    -DENABLE_DCONF=OFF
    -DENABLE_EET=OFF
    -DENABLE_DBUS=OFF
    -DENABLE_SQLITE3=OFF
    -DENABLE_RPM=OFF
    -DENABLE_IMAGEMAGICK7=OFF
    -DENABLE_IMAGEMAGICK6=OFF
    -DENABLE_CHAFA=OFF
    -DENABLE_EGL=OFF
    -DENABLE_GLX=OFF
    -DENABLE_OPENCL=OFF
    -DENABLE_FREETYPE=OFF
    -DENABLE_PULSE=OFF
    -DENABLE_DDCUTIL=OFF
    -DENABLE_LUA=OFF
    -DENABLE_QUICKJS=OFF
    -DENABLE_LIBZFS=OFF
    -DENABLE_SYSTEM_YYJSON=OFF
    -DENABLE_WORDEXP=OFF
    -DENABLE_ELF=OFF
    -DENABLE_ZLIB=OFF
    -DBUILD_TESTS=OFF
    -DFASTFETCH_BUILD_TESTS=OFF
)

build_one() {
    local name="$1"
    local abi="$2"
    local api="$3"
    local bdir="${BUILD_ROOT}/${name}"

    echo "==> Building ${name} (ABI=${abi} API=${api})"

    rm -rf "${bdir}"
    mkdir -p "${bdir}"

    if ! cmake -S "${SRC_DIR}" -B "${bdir}" \
            -G Ninja \
            -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
            -DANDROID_ABI="${abi}" \
            -DANDROID_PLATFORM="android-${api}" \
            -DANDROID_STL="c++_static" \
            -DCMAKE_BUILD_TYPE=Release \
            "-DCMAKE_C_FLAGS=-I${STUB_DIR} -include glob.h" \
            "${DISABLE_FLAGS[@]}"; then
        echo "cmake configure failed for ${name}" >&2
        exit 1
    fi

    if ! cmake --build "${bdir}" --target fastfetch -j"${JOBS}"; then
        echo "cmake build failed for ${name}" >&2
        exit 1
    fi

    cp -f "${bdir}/fastfetch" "${OUT_DIR}/fastfetch-${name}"
    "${STRIP}" "${OUT_DIR}/fastfetch-${name}" || true
    python3 "${SCRIPT_DIR}/src/patch-dtflags.py" "${OUT_DIR}/fastfetch-${name}"

    echo "==> Done: $(file "${OUT_DIR}/fastfetch-${name}")"
}

_build_one() {
    local name="$1"
    if [[ -n "${BUILD_TARGETS}" ]]; then
        local t
        for t in ${BUILD_TARGETS//,/ }; do
            [[ "${t}" == "${name}" ]] && { build_one "$@"; return; }
        done
        echo "==> Skipping ${name} (not in BUILD_TARGETS=${BUILD_TARGETS})"
        return
    fi
    build_one "$@"
}

_build_one "aarch64" "arm64-v8a" "24"
_build_one "x86"     "x86"       "21"

echo ""
echo "Artifacts in ${OUT_DIR}:"
ls -lh "${OUT_DIR}"/fastfetch-*
