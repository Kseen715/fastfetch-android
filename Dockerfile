# Single image that builds every fastfetch Android target.
#   modern targets (armv8, x86, x86-64, armv7)  -> NDK r27c
#   legacy targets (armv5, armv6, armv7-nopie)  -> NDK r16b
# The build script picks the NDK per target by API level.

# ---- fetch NDK r27c (modern: arm64-v8a, x86, x86_64, armeabi-v7a) ----
FROM debian:bookworm-slim AS ndk-modern
ARG NDK_MODERN_VERSION=r27c
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates unzip wget \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt
RUN wget -q https://dl.google.com/android/repository/android-ndk-${NDK_MODERN_VERSION}-linux.zip \
    && unzip -q android-ndk-${NDK_MODERN_VERSION}-linux.zip \
    && rm -f android-ndk-${NDK_MODERN_VERSION}-linux.zip
# unzip yields /opt/android-ndk-${NDK_MODERN_VERSION}; keep that name (== r27c)

# ---- fetch NDK r16b (legacy: armeabi armv5/v6, low-API armv7) ----
FROM debian:bookworm-slim AS ndk-legacy
ARG NDK_LEGACY_VERSION=r16b
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates unzip wget \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt
RUN wget -q https://dl.google.com/android/repository/android-ndk-${NDK_LEGACY_VERSION}-linux-x86_64.zip \
    && unzip -q android-ndk-${NDK_LEGACY_VERSION}-linux-x86_64.zip \
    && rm -f android-ndk-${NDK_LEGACY_VERSION}-linux-x86_64.zip
# unzip yields /opt/android-ndk-${NDK_LEGACY_VERSION}; keep that name (== r16b)

# ---- builder ----
FROM debian:bookworm-slim
ARG FASTFETCH_REF=dev

RUN apt-get update && apt-get install -y --no-install-recommends \
        cmake \
        ninja-build \
        git \
        ca-certificates \
        python3 \
        file \
        libncursesw6 \
        libtinfo6 \
    && rm -rf /var/lib/apt/lists/* \
    # r16b's Clang 5.0 links the legacy soname libncurses.so.5/libtinfo.so.5,
    # gone from bookworm. Point them at the v6 libs (ABI-compatible enough).
    && ln -sf "$(dirname "$(find / -name 'libncursesw.so.6' 2>/dev/null | head -1)")/libncursesw.so.6" \
              "$(dirname "$(find / -name 'libncursesw.so.6' 2>/dev/null | head -1)")/libncurses.so.5" \
    && ln -sf "$(dirname "$(find / -name 'libtinfo.so.6' 2>/dev/null | head -1)")/libtinfo.so.6" \
              "$(dirname "$(find / -name 'libtinfo.so.6' 2>/dev/null | head -1)")/libtinfo.so.5"

COPY --from=ndk-modern /opt/android-ndk-r27c /opt/android-ndk-r27c
COPY --from=ndk-legacy /opt/android-ndk-r16b /opt/android-ndk-r16b
ENV NDK_MODERN=/opt/android-ndk-r27c
ENV NDK_LEGACY=/opt/android-ndk-r16b
ENV ANDROID_NDK_HOME=/opt/android-ndk-r27c

WORKDIR /work
RUN git clone --depth=1 --branch ${FASTFETCH_REF} \
        https://github.com/fastfetch-cli/fastfetch.git

COPY src/ /work/src/

VOLUME ["/out"]
ENV TARGET_SET=all
CMD ["/bin/bash", "/work/build-fastfetch-android.sh"]
