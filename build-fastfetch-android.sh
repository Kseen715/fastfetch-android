#!/usr/bin/env bash
set -euo pipefail

JOBS="${JOBS:-$(nproc)}"
OUT_DIR="${OUT_DIR:-/out}"
SRC_DIR="${SRC_DIR:-/work/fastfetch}"
BUILD_ROOT="${BUILD_ROOT:-/work/build}"
BUILD_TARGETS="${BUILD_TARGETS:-}"
TARGET_SET="${TARGET_SET:-modern}"

# Two NDKs, picked per target by API level (see pick_ndk):
#   modern (API >= 21): r27c — arm64-v8a, x86, x86_64, armeabi-v7a (PIE)
#   legacy (API <  21): r16b — armeabi (armv5/v6), low-API armv7 (PIE & noPIE)
# A single-NDK image can still drive one tier by pointing both at the same path.
NDK_MODERN="${NDK_MODERN:-${ANDROID_NDK_HOME:-/opt/android-ndk}}"
NDK_LEGACY="${NDK_LEGACY:-${NDK_MODERN}}"

# pick_ndk <api> -> sets NDK_DIR, TOOLCHAIN, STRIP for the current target
pick_ndk() {
    local api="$1"
    if [[ "${api}" -lt 21 ]]; then
        NDK_DIR="${NDK_LEGACY}"
        STRIP="${STRIP_OVERRIDE:-${NDK_DIR}/toolchains/arm-linux-androideabi-4.9/prebuilt/linux-x86_64/bin/arm-linux-androideabi-strip}"
    else
        NDK_DIR="${NDK_MODERN}"
        STRIP="${STRIP_OVERRIDE:-${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip}"
    fi
    TOOLCHAIN="${NDK_DIR}/build/cmake/android.toolchain.cmake"
    if [[ ! -f "${TOOLCHAIN}" ]]; then
        echo "NDK toolchain not found at ${TOOLCHAIN}" >&2
        exit 1
    fi
}

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

# build_one <name> <abi> <api> <march> <pie>
#   name  : output suffix (fastfetch-<name>)
#   abi   : Android ABI (armeabi-v7a, arm64-v8a, x86, x86_64, armeabi)
#   api   : Android platform level
#   march : extra -march/-mtune flags (may be empty) for ARM sub-arch tuning
#   pie   : "on" (default) or "off" — off forces a non-PIE executable
build_one() {
    local name="$1"
    local abi="$2"
    local api="$3"
    local march="${4:-}"
    local pie="${5:-on}"
    local bdir="${BUILD_ROOT}/${name}"

    pick_ndk "${api}"

    echo "==> Building ${name} (ABI=${abi} API=${api} march='${march}' pie=${pie} ndk=${NDK_DIR##*/})"

    # Start from a pristine opengl source each target, then (for the legacy tier)
    # neuter the FF_HAVE_EGL self-enable: old GL drivers crash inside
    # eglInitialize/eglQueryString, taking the whole run down. Modern targets
    # keep EGL-based GPU detection.
    local gl_src="src/detection/opengl/opengl_linux.c"
    git -C "${SRC_DIR}" checkout -- "${gl_src}" 2>/dev/null || true
    if [[ "${api}" -lt 21 ]]; then
        sed -i 's/#define FF_HAVE_EGL 1/\/\* FF_HAVE_EGL disabled: legacy GL drivers crash \*\//' \
            "${SRC_DIR}/${gl_src}"
    fi

    rm -rf "${bdir}"
    mkdir -p "${bdir}"

    local cflags="-I${STUB_DIR} -include glob.h"
    # Pre-API-21 Bionic lacks getline, statvfs, setmntent, faccessat, ...;
    # force-include inline shims (each guarded by its own API level).
    [[ "${api}" -lt 21 ]] && cflags="${cflags} -include legacy-compat.h"
    [[ -n "${march}" ]] && cflags="${cflags} ${march}"

    # r16b's gold linker rejects the LTO opt level clang passes for -Os; the
    # legacy (API < 21) tier builds without LTO. Modern tier keeps it on.
    local extra_args=()
    [[ "${api}" -lt 21 ]] && extra_args+=(-DENABLE_LTO=OFF)

    local pie_args=()
    if [[ "${pie}" == "off" ]]; then
        # Non-PIE executable (for pre-API-16 devices that can't load PIE).
        # Compile PIC code (-fPIC) so Thumb-2 MOVW/MOVT relocs go through the GOT
        # instead of emitting unsupported absolute text relocs, but link without
        # -pie (ANDROID_PIE=OFF + no CMake-injected -pie) to get an ET_EXEC.
        # Clang 5.0 (r16b) doesn't accept the -no-pie driver flag, hence this route.
        cflags="${cflags} -fPIC"
        pie_args=(
            -DANDROID_PIE=OFF
            -DCMAKE_POSITION_INDEPENDENT_CODE=OFF
        )
    fi

    if ! cmake -S "${SRC_DIR}" -B "${bdir}" \
            -G Ninja \
            -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
            -DANDROID_ABI="${abi}" \
            -DANDROID_PLATFORM="android-${api}" \
            -DANDROID_STL="c++_static" \
            -DCMAKE_BUILD_TYPE=Release \
            "-DCMAKE_C_FLAGS=${cflags}" \
            "${extra_args[@]}" \
            "${pie_args[@]}" \
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
    # PIE binaries: clear DF_1_PIE so old (<=7) linkers don't warn. Skip for non-PIE.
    if [[ "${pie}" != "off" ]]; then
        python3 "${SCRIPT_DIR}/src/patch-dtflags.py" "${OUT_DIR}/fastfetch-${name}"
    fi

    if command -v file >/dev/null 2>&1; then
        echo "==> Done: $(file "${OUT_DIR}/fastfetch-${name}")"
    else
        echo "==> Done: ${OUT_DIR}/fastfetch-${name}"
    fi
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

echo "==> TARGET_SET=${TARGET_SET}  NDK_MODERN=${NDK_MODERN}  NDK_LEGACY=${NDK_LEGACY}"

# Modern tier — NDK r27c (API floor 21, PIE mandatory)
build_modern() {
    #            name      abi          api  march  pie
    _build_one "armv8"    "arm64-v8a"   "24"  ""     "on"
    _build_one "x86"      "x86"         "21"  ""     "on"
    _build_one "x86-64"   "x86_64"      "21"  ""     "on"
}

# Legacy tier — NDK r16b (armeabi armv5/v6 + low-API armv7 PIE & noPIE)
build_legacy() {
    #            name          abi           api  march            pie
    _build_one "armv5"        "armeabi"     "14"  "-march=armv5te"  "off"
    _build_one "armv6"        "armeabi"     "14"  "-march=armv6"    "off"
    _build_one "armv7"        "armeabi-v7a" "16"  ""                "on"
    _build_one "armv7-nopie"  "armeabi-v7a" "14"  ""                "off"
}

case "${TARGET_SET}" in
  modern) build_modern ;;
  legacy) build_legacy ;;
  all)    build_legacy; build_modern ;;
  *)
    echo "Unknown TARGET_SET='${TARGET_SET}' (expected modern|legacy|all)" >&2
    exit 1
    ;;
esac

echo ""
echo "Artifacts in ${OUT_DIR}:"
ls -lh "${OUT_DIR}"/fastfetch-*
