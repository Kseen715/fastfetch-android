FROM debian:bookworm-slim AS ndk-fetch
ARG NDK_VERSION=r27c
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates unzip wget \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt
RUN wget -q https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip \
    && unzip -q android-ndk-${NDK_VERSION}-linux.zip \
    && mv android-ndk-${NDK_VERSION} android-ndk \
    && rm -f android-ndk-${NDK_VERSION}-linux.zip

FROM debian:bookworm-slim
ARG NDK_VERSION=r27c
ARG FASTFETCH_REF=dev

RUN apt-get update && apt-get install -y --no-install-recommends \
        cmake \
        ninja-build \
        git \
        ca-certificates \
        python3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ndk-fetch /opt/android-ndk /opt/android-ndk
ENV ANDROID_NDK_HOME=/opt/android-ndk

WORKDIR /work
RUN git clone --depth=1 --branch ${FASTFETCH_REF} \
        https://github.com/fastfetch-cli/fastfetch.git

COPY src/ /work/src/

VOLUME ["/out"]
CMD ["/bin/bash", "/work/build-fastfetch-android.sh"]
