# fastfetch-android

Cross-compiles [fastfetch](https://github.com/fastfetch-cli/fastfetch) for Android
using Docker. A single image bundles two NDKs and builds **seven** targets,
from ancient ARMv5 (Android 4.0) up to modern arm64-v8a.

<img src="./image/README/Honor_6X.png" alt="fastfetch-android" width="600"/>

<img src="./image/README/ASUS_Fonepad_8.png" alt="fastfetch-android" width="600"/>

## Targets

| Output | ABI | Min API | PIE | NDK | Verified on |
|--------|-----|:------:|:---:|-----|-------------|
| `fastfetch-armv5`       | `armeabi`     | 14 | no  | r16b | U8815 / Honor 3 (back-compat) |
| `fastfetch-armv6`       | `armeabi`     | 14 | no  | r16b | U8815 / Honor 3 (back-compat) |
| `fastfetch-armv7`       | `armeabi-v7a` | 16 | yes | r16b | Huawei Honor 3 (A4.2.2) |
| `fastfetch-armv7-nopie` | `armeabi-v7a` | 14 | no  | r16b | Huawei U8815 (A4.0.3) |
| `fastfetch-armv8`       | `arm64-v8a`   | 24 | yes | r27c | Honor 6X (A7.0) |
| `fastfetch-x86`         | `x86`         | 21 | yes | r27c | ASUS Fonepad 8 (A5.0) |
| `fastfetch-x86-64`      | `x86_64`      | 21 | yes | r27c | build-only (no 64-bit x86 device) |

Why two NDKs: r27c dropped the `armeabi` ABI (armv5/armv6) and raised the API
floor to 21 with mandatory PIE, so it can't target the pre-Android-4.1 devices.
NDK **r16b** (the last with `armeabi`) handles the legacy ARM tier; **r27c**
handles everything API 21+. `build-fastfetch-android.sh` picks the NDK per target
by API level automatically.

## Requirements

- Docker + Docker Compose
- `adb` in PATH (for device testing)

## Build

```bash
docker compose up --build       # builds all 7 targets into ./out
```

Pick a tier or specific targets:

```bash
TARGET_SET=modern docker compose run --rm fastfetch-android-build   # armv8, x86, x86-64
TARGET_SET=legacy docker compose run --rm fastfetch-android-build   # armv5/6/7, armv7-nopie
BUILD_TARGETS=armv7,armv8 docker compose run --rm fastfetch-android-build
```

Control parallelism with `JOBS=4`.

## Deploy and run

```bash
adb push out/fastfetch-armv8 /data/local/tmp/fastfetch
adb shell "chmod +x /data/local/tmp/fastfetch && /data/local/tmp/fastfetch"

# pipe mode (no colors/logo, easier to parse)
adb shell /data/local/tmp/fastfetch --pipe
```

`./test.sh` pushes the matching binary to each device in [ADB.md](ADB.md) and runs it.

## Rebuilding after source changes

The build script and stubs are bind-mounted, so changes take effect without
rebuilding the image:

```bash
docker compose run --rm fastfetch-android-build
```

Force a full image rebuild (after changing `Dockerfile` or bumping `FASTFETCH_REF`):

```bash
docker compose up --build
```

## Android compatibility patches

Bionic — especially the old r16b sysroot — is missing glibc headers and
functions fastfetch expects on Linux. Stubs live in `src/android-stubs/` and are
injected via `-I` / `-include` at compile time. All are `static inline` or
forward to the real header, so there are no extra runtime symbol dependencies.

| File | Why |
|------|-----|
| `glob.h` | Bionic has no `glob.h`; fastfetch falls back from `wordexp` to `glob` |
| `GL/gl.h` | Android auto-detects EGL, then includes desktop `GL/gl.h`; redirected to `GLES/gl.h` |
| `sys/sysinfo.h` | Forwards to real header; adds `get_nprocs`/`get_nprocs_conf` for API < 23 |
| `ifaddrs.h` | `getifaddrs`/`freeifaddrs` added in API 24; stub returns `ENOSYS` below that |
| `legacy-compat.h` | Force-included for API < 21: inline `getline`/`getdelim` (API 18), `statvfs`/`fstatvfs` (API 19), `setmntent`/`endmntent` (API 21), `faccessat` (API 16) |
| `utmpx.h` | Bionic gained `<utmpx.h>` at API 23; shim provides the type + no-op accessors so `users` detection compiles |
| `media/NdkMediaCodec.h` | r16b predates the `AMediaCodec` API; shim supplies declarations (loaded at runtime via `dlopen`), forwards to the real header on API 21+ |

Legacy tier (API < 21) extras handled by the build script:

- **LTO off** — r16b's gold linker rejects the LTO opt level Clang passes for `-Os`.
- **Non-PIE via `-fPIC`** — Clang 5.0 has no `-no-pie`; PIC code + `ANDROID_PIE=OFF`
  yields an `ET_EXEC` without unsupported absolute Thumb-2 relocations.
- **GL GPU detection disabled** — old GL drivers segfault inside
  `eglInitialize`/`eglQueryString`; the `FF_HAVE_EGL` self-enable is patched out
  for this tier (GPU name is simply omitted on those devices).

`src/patch-dtflags.py` clears the `DF_1_PIE` bit from `DT_FLAGS_1` after linking
PIE binaries. NDK r27c's lld sets this bit; Android ≤ 7's linker doesn't recognise
it and prints a harmless warning. The patch silences it.
